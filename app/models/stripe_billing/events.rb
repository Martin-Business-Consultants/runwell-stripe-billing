module StripeBilling
  # What the core's events set off here ("event.runwell"). An approved agreement version gets
  # its charge made ready, and the client is emailed its payment link, in the request, so the
  # approval page can offer the link straight away. A closed engagement stops its subscription
  # at the end of the paid period and withdraws any link still waiting.
  module Events
    def self.handle(event)
      return unless Runwell::Plugins.enabled?(:stripe_billing) && Connection.ready?

      case event.kind
      when "agreement.approved"
        version = event.subject
        return unless version.is_a?(::AgreementVersion)

        Charge.for_approval!(version, contact: version.approval&.contact)&.deliver!
      when "engagement.closed"
        engagement = event.subject
        return unless engagement.is_a?(::Engagement)

        engagement.stripe_subscription&.end_with_engagement!
        engagement.stripe_billing_charges.open.find_each { it.withdraw!("the engagement closed") }
      end
    rescue StandardError => error
      Rails.error.report(error, context: { plugin: :stripe_billing, event: event.kind })
    end
  end
end
