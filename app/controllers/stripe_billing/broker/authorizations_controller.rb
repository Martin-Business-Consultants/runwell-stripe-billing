# new: an install sends the person here to connect Stripe; show: Stripe sends them back.
module StripeBilling
  module Broker
    class AuthorizationsController < BaseController
      def new
        redirect_to StripeBilling::Broker.start!(install: params[:install], state: params[:state], challenge: params[:challenge],
          redirect_uri: stripe_broker_authorization_url), allow_other_host: true
      rescue StripeBilling::Broker::Error => error
        render plain: error.message, status: :unprocessable_entity
      end

      def show
        redirect_to StripeBilling::Broker.callback!(token: params[:state], code: params[:code],
          error: params[:error_description].presence || params[:error]), allow_other_host: true
      rescue StripeBilling::Broker::Error => error
        render plain: error.message, status: :unprocessable_entity
      end
    end
  end
end
