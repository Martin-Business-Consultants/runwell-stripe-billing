# Settings > Stripe: connecting the agency's Stripe account, whether Stripe can reach this
# install, and disconnecting.
module StripeBilling
  class SettingsController < ApplicationController
    require_permission :manage_settings
    agent_tool :show_stripe_settings, on: :show, title: "Show the Stripe connection"
    agent_tool :disconnect_stripe, on: :destroy, title: "Disconnect Stripe",
      description: "Stops new payment links. Links already sent and running subscriptions carry on in Stripe."

    before_action { @connection = Connection.for_settings }

    def show
      @open = Charge.open.count
      @subscriptions = Subscription.where(status: Subscription::LIVE).count
    end

    def destroy
      remove_webhook_endpoint
      Oauth.new(@connection).deauthorize!
      @connection.disconnect!
      redirect_to stripe_settings_path, notice: "Disconnected from Stripe. Links already sent and running subscriptions carry on in Stripe."
    end

    private
      # Best effort: Stripe refusing must not stop someone disconnecting here.
      def remove_webhook_endpoint
        Api.new(@connection).delete_webhook_endpoint(@connection.webhook_endpoint_id) if @connection.webhook_endpoint_id.present?
      rescue Api::Error => error
        Rails.logger.warn("[Stripe] removing the webhook endpoint failed: #{error.message}")
      end
  end
end
