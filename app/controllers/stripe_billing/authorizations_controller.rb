# The round trip to "Connect with Stripe": create sends the person to the broker, show is where
# the broker sends them back with a one-time code, which is redeemed server to server. Then this
# install subscribes to the account's events.
module StripeBilling
  class AuthorizationsController < ApplicationController
    require_permission :manage_settings
    agent_exempt :create, :show, reason: "connecting Stripe needs a person in a browser"

    before_action { @connection = Connection.for_settings }

    def create
      redirect_to Oauth.new(@connection).authorize_url(callback: stripe_authorization_url), allow_other_host: true
    end

    def show
      return redirect_to(stripe_settings_path, alert: "Stripe declined: #{params[:error_description] || params[:error]}") if params[:error].present?

      Oauth.new(@connection).complete!(code: params[:code], state: params[:state])
      account = Api.new(@connection).account
      @connection.update!(account_name: account.dig("settings", "dashboard", "display_name").presence || account.dig("business_profile", "name") || account["email"])
      subscribe_to_events
      redirect_to stripe_settings_path, notice: "Connected to #{@connection.account_name || "Stripe"}#{" (test mode)" unless @connection.livemode?}."
    rescue Oauth::Error, Api::Error => error
      redirect_to stripe_settings_path, alert: error.message
    end

    private
      def subscribe_to_events
        @connection.update!(webhook_endpoint_id: nil, webhook_secret: nil)
        endpoint = Api.new(@connection).create_webhook_endpoint(stripe_webhooks_url)
        @connection.update!(webhook_endpoint_id: endpoint["id"], webhook_secret: endpoint["secret"], last_error: nil)
      rescue Api::Error => error
        @connection.note_error!(error.message)
      end
  end
end
