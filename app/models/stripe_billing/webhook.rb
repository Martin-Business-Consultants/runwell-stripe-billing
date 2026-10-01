module StripeBilling
  # One event from the connected Stripe account, already verified (WebhooksController): a
  # payment link paid, a subscription's invoice paid or failed, a subscription changed or
  # cancelled in Stripe.
  class Webhook
    def initialize(payload)
      @type = payload["type"]
      @object = payload.dig("data", "object") || {}
    end

    def process!
      case @type
      when "checkout.session.completed"
        charge&.paid_by_stripe!(@object) if %w[paid no_payment_required].include?(@object["payment_status"])
      when "checkout.session.async_payment_succeeded"
        charge&.paid_by_stripe!(@object)
      when "checkout.session.async_payment_failed"
        charge&.update!(last_error: "The client’s bank payment failed. They can pay with the link again.")
      when "invoice.paid"
        subscription&.update!(last_payment_at: Time.current, last_payment_failed_at: nil, status: "active", last_error: nil)
      when "invoice.payment_failed"
        subscription&.update!(last_payment_failed_at: Time.current, status: "past_due")
      when "customer.subscription.updated"
        subscription&.update!(status: @object["status"], cancel_at_period_end: @object["cancel_at_period_end"] == true)
      when "customer.subscription.deleted"
        subscription&.update!(status: "canceled", canceled_at: Time.current)
      end
    end

    private
      def charge
        Charge.find_by(id: @object.dig("metadata", "runwell_charge_id")) || Charge.find_by(payment_link_id: @object["payment_link"].presence || "none")
      end

      # Invoices name their subscription at the top level, or under parent in newer API versions.
      def subscription
        id = @type.start_with?("customer.subscription") ? @object["id"] : (@object["subscription"] || @object.dig("parent", "subscription_details", "subscription"))
        Subscription.find_by(stripe_subscription_id: id) if id.present?
      end
  end
end
