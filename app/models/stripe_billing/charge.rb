module StripeBilling
  # What one approved agreement version asks the client to pay, and whether they have (`paid`).
  #
  #   subscription         a service's first approval (or the first since its subscription
  #                        ended): a payment link that starts a subscription on the cadence
  #   subscription_change  a later approved revision or add-on: the running subscription moves
  #                        to the new amount, so the service is still billed once
  #   one_time             fixed work: the initial price, then each change order's difference
  #
  # Stripe marks a charge paid when its link is paid (Webhook); an admin can mark it paid another
  # way, which switches the link off so the client can't pay twice.
  class Charge < ::ApplicationRecord
    self.table_name = "stripe_billing_charges"

    KINDS = %w[subscription subscription_change one_time].freeze
    INTERVALS = { "weekly" => [ "week", 1 ], "monthly" => [ "month", 1 ], "quarterly" => [ "month", 3 ] }.freeze

    belongs_to :engagement, class_name: "::Engagement"
    belongs_to :agreement_version, class_name: "::AgreementVersion"
    belongs_to :contact, class_name: "::Contact", optional: true
    belongs_to :marked_paid_by, class_name: "::User", optional: true
    has_one :subscription, class_name: "StripeBilling::Subscription", inverse_of: :charge

    validates :kind, inclusion: { in: KINDS }
    validates :amount_cents, numericality: { greater_than: 0 }

    scope :open, -> { where(paid: false, withdrawn_at: nil) }
    scope :recent, -> { order(created_at: :desc) }

    # What an approved version asks the client to pay, made ready: a payment link, or the
    # running subscription moved to the new amount. Nil when there is nothing to pay, or the
    # service is billed by QuickBooks.
    def self.for_approval!(version, contact: nil)
      return find_by(agreement_version: version) if exists?(agreement_version: version)

      plan = plan_for(version) or return
      charge = transaction do
        if plan[:kind] == "subscription"
          open.where(engagement: version.engagement, kind: "subscription").find_each { it.withdraw!("replaced by #{version.label}") }
        end
        create!(engagement: version.engagement, agreement_version: version, contact: contact, **plan)
      end
      charge.prepare!
      charge
    end

    def self.plan_for(version)
      engagement = version.engagement
      if engagement.recurring?
        return if billed_by_quickbooks?(engagement)

        amount = recurring_total(version)
        return unless amount.positive?

        interval, count = INTERVALS.fetch(version.cadence.to_s, INTERVALS["monthly"])
        { kind: engagement.stripe_subscription&.live? ? "subscription_change" : "subscription", amount_cents: amount, interval: interval, interval_count: count }
      else
        amount = version.initial? ? version.amount_cents.to_i : version.price_delta_cents.to_i
        { kind: "one_time", amount_cents: amount } if amount.positive?
      end
    end

    # A service's price per period once this version is approved: an initial agreement or a
    # revision states the whole amount; an add-on adds its items to what was already agreed.
    def self.recurring_total(version)
      approved = version.engagement.agreement_versions.select { it.approved? && it.number < version.number }
      (approved + [ version ]).reduce(0) { |total, v| v.kind == "add_on" ? total + v.price_delta_cents.to_i : v.amount_cents.to_i }
    end

    # QuickBooks keeps its own recurring invoice for a service; Stripe never bills one too.
    def self.billed_by_quickbooks?(engagement)
      Runwell::Plugins.enabled?(:quickbooks) && engagement.respond_to?(:quickbooks_recurring_link) && engagement.quickbooks_recurring_link.present?
    end

    def subscription? = kind == "subscription"
    def change? = kind == "subscription_change"
    def withdrawn? = withdrawn_at.present?
    def payable? = !paid? && !withdrawn? && payment_link_url.present?

    def state
      if paid? then paid_via == "manual" ? "paid another way" : (change? ? "applied" : "paid")
      elsif withdrawn? then "withdrawn"
      elsif last_error.present? then "needs attention"
      elsif change? then "billed outside Stripe"
      elsif payment_link_url.blank? then "preparing"
      else "awaiting payment"
      end
    end

    # "$1,200.00", or "$400.00 every 3 months".
    def self.amount_label(cents, interval = nil, count = nil)
      return Money.format(cents) unless interval

      "#{Money.format(cents)} every #{count.to_i > 1 ? "#{count} #{interval.pluralize}" : interval}"
    end

    def amount_label = self.class.amount_label(amount_cents, interval, interval_count)

    def recipient = contact || agreement_version.approval&.contact

    # The link with the client's email filled in on Stripe's page.
    def pay_url(email = recipient&.email)
      return unless payment_link_url

      email.present? ? "#{payment_link_url}?#{{ prefilled_email: email }.to_query}" : payment_link_url
    end

    def prepare!
      case kind
      when "subscription", "one_time" then create_link!
      when "subscription_change" then apply_change!
      end
    rescue Api::Error => error
      update!(last_error: error.message)
    end

    # Emails the client the payment link, once it exists and they have an address.
    def deliver!
      return false unless payable? && recipient&.email.present?

      PaymentMailer.with(charge: self).link.deliver_later
      update!(emailed_at: Time.current)
    end

    def mark_paid!(by:, note:)
      raise ArgumentError, "This is already marked paid." if paid?
      raise ArgumentError, "Say how they paid, so the record shows it." if note.blank?

      transaction do
        update!(paid: true, paid_via: "manual", paid_at: Time.current, paid_note: note, marked_paid_by: by, last_error: nil)
        bill_outside_stripe! if subscription? || change?
        engagement.record_event!("stripe.marked_paid", actor: by, payload: { version: agreement_version.number, amount: amount_label, note: note })
      end
      switch_link(false)
    end

    def unmark_paid!(by:)
      raise ArgumentError, "Only a payment recorded by hand can be undone here." unless paid_via == "manual"

      transaction do
        update!(paid: false, paid_via: nil, paid_at: nil, paid_note: nil, marked_paid_by: nil)
        engagement.stripe_subscription.destroy! if subscription? && engagement.stripe_subscription&.external? && engagement.stripe_subscription.charge_id == id
        engagement.record_event!("stripe.unmarked_paid", actor: by, payload: { version: agreement_version.number, amount: amount_label })
      end
      switch_link(true)
    end

    # Stripe says the link was paid (Webhook). A subscription becomes the service's one
    # subscription; if it already has a live one, the new one is cancelled at once.
    def paid_by_stripe!(session)
      return if paid? && paid_via == "stripe"
      if paid?
        return update!(last_error: "Paid in Stripe after it was marked paid another way: refund one of the two in Stripe.")
      end

      duplicate = nil
      transaction do
        update!(paid: true, paid_via: "stripe", paid_at: Time.current, checkout_session_id: session["id"],
          stripe_customer_id: session["customer"], last_error: nil)
        if subscription?
          existing = Subscription.lock.find_by(engagement_id: engagement_id)
          if existing&.live?
            duplicate = session["subscription"]
          else
            (existing || Subscription.new(engagement: engagement)).update!(charge: self, stripe_subscription_id: session["subscription"],
              stripe_customer_id: session["customer"], status: "active", amount_cents: amount_cents, interval: interval,
              interval_count: interval_count, cancel_at_period_end: false, canceled_at: nil, last_payment_at: Time.current, last_error: nil)
          end
        end
        engagement.record_event!("stripe.paid", actor: nil, source: "stripe", payload: { version: agreement_version.number, amount: amount_label })
      end
      cancel_duplicate(duplicate) if duplicate
    end

    def withdraw!(reason)
      return if withdrawn? || paid?

      update!(withdrawn_at: Time.current, withdrawn_reason: reason)
      switch_link(false)
    end

    private
      def api = Api.new

      def product_name = "#{engagement.ref} #{engagement.title}: #{agreement_version.label}"

      def metadata
        { runwell_charge_id: id, engagement: engagement.ref, agreement_version: agreement_version.number, install: ENV.fetch("APP_HOST", "localhost") }
      end

      def create_link!
        return if payment_link_url.present? || withdrawn? || paid?

        price = api.create_price(amount_cents: amount_cents, name: product_name, interval: interval, interval_count: interval_count)
        link = api.create_payment_link(price_id: price["id"], metadata: metadata, recurring: subscription?,
          message: "Thank you. #{engagement.client.name}’s payment for #{engagement.title} is set up.")
        update!(price_id: price["id"], payment_link_id: link["id"], payment_link_url: link["url"], last_error: nil)
        engagement.record_event!("stripe.link_created", actor: nil, payload: { version: agreement_version.number, amount: amount_label })
      end

      # A running Stripe subscription moves to the new amount from its next period. A service
      # billed outside Stripe waits for an admin to change it there and mark this done.
      def apply_change!
        subscription = engagement.stripe_subscription
        return unless subscription&.stripe?

        price = api.create_price(amount_cents: amount_cents, name: product_name, interval: interval, interval_count: interval_count)
        api.change_subscription_price(subscription.stripe_subscription_id, price["id"])
        transaction do
          update!(price_id: price["id"], paid: true, paid_via: "stripe", paid_at: Time.current, last_error: nil)
          subscription.update!(amount_cents: amount_cents, interval: interval, interval_count: interval_count)
          engagement.record_event!("stripe.subscription_changed", actor: nil, payload: { version: agreement_version.number, amount: amount_label })
        end
      end

      # Recorded as billed another way: the service's one billing is outside Stripe now.
      def bill_outside_stripe!
        subscription = engagement.stripe_subscription
        if subscription&.live? && subscription.stripe?
          raise ArgumentError, "This service already has a Stripe subscription. Cancel it in Stripe first."
        end

        (subscription || Subscription.new(engagement: engagement)).update!(charge: self, status: "external", stripe_subscription_id: nil,
          amount_cents: amount_cents, interval: interval, interval_count: interval_count, canceled_at: nil)
      end

      def switch_link(active)
        return if payment_link_id.blank? || (active && withdrawn?)

        api.set_payment_link_active(payment_link_id, active)
      rescue Api::Error => error
        update_columns(last_error: "Couldn’t #{active ? "switch the payment link back on" : "switch off the payment link"}: #{error.message}")
      end

      def cancel_duplicate(stripe_subscription_id)
        api.cancel_subscription_now(stripe_subscription_id)
        update_columns(last_error: "A second subscription (#{stripe_subscription_id}) was started and cancelled at once. Refund its first payment in Stripe.")
      rescue Api::Error => error
        update_columns(last_error: "A second subscription (#{stripe_subscription_id}) was started and couldn’t be cancelled: #{error.message}. Cancel it in Stripe.")
      end
  end
end
