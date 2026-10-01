# An install disconnecting its account from the platform, proving it holds the token.
module StripeBilling
  module Broker
    class DeauthorizationsController < BaseController
      def create
        StripeBilling::Broker.deauthorize!(account_id: params[:account_id].to_s, access_token: params[:access_token].to_s)
        render json: { status: "ok" }
      rescue StripeBilling::Broker::Error => error
        render json: { error: error.message }, status: :unprocessable_entity
      end
    end
  end
end
