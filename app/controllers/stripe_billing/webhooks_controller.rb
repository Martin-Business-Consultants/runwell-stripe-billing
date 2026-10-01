# Where Stripe delivers the connected account's events. Public, so every delivery must carry
# Stripe's signature over the body with this install's endpoint secret.
module StripeBilling
  class WebhooksController < ApplicationController
    allow_unauthenticated_access
    skip_forgery_protection

    def create
      connection = Connection.current
      return head(:unauthorized) unless connection&.verify_signature(request.raw_post, request.headers["Stripe-Signature"])

      Current.source = "stripe"
      Webhook.new(JSON.parse(request.raw_post)).process!
      connection.update_columns(last_event_at: Time.current)
      head :ok
    rescue JSON::ParserError
      head :bad_request
    end
  end
end
