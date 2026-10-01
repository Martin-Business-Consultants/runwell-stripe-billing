# An install redeeming its one-time code, with its verifier, for the agency's token.
module StripeBilling
  module Broker
    class TokensController < BaseController
      def create
        render json: StripeBilling::Broker.redeem!(code: params[:code], verifier: params[:verifier])
      rescue StripeBilling::Broker::Error => error
        render json: { error: error.message }, status: :unprocessable_entity
      end
    end
  end
end
