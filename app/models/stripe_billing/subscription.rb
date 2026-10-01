module StripeBilling
  # How a service is billed: one row per engagement, so it can never be billed twice. Either a
  # Stripe subscription started from a payment link, or `external`: an admin recorded that the
  # client pays another way. A cancelled subscription keeps its row, and a later approval's
  # payment link starts the service's next one in it.
  class Subscription < ::ApplicationRecord
    self.table_name = "stripe_billing_subscriptions"

    LIVE = %w[active trialing past_due unpaid incomplete external].freeze

    belongs_to :engagement, class_name: "::Engagement"
    belongs_to :charge, class_name: "StripeBilling::Charge"

    scope :troubled, -> { where(status: %w[past_due unpaid]).or(where.not(last_error: nil)) }

    def live? = LIVE.include?(status) && canceled_at.nil?
    def external? = status == "external"
    def stripe? = stripe_subscription_id.present?

    def amount_label = Charge.amount_label(amount_cents, interval, interval_count)

    # The service closed: Stripe stops at the end of the period already paid for.
    def end_with_engagement!
      return unless stripe? && live? && !cancel_at_period_end?

      Api.new.cancel_subscription_at_period_end(stripe_subscription_id)
      update!(cancel_at_period_end: true)
      engagement.record_event!("stripe.subscription_ending", actor: nil, payload: { amount: amount_label })
    rescue Api::Error => error
      update!(last_error: "The service closed but its Stripe subscription couldn’t be stopped: #{error.message}")
    end
  end
end
