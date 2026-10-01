# Trying again when Stripe couldn't make a payment link, or move a subscription to a new amount.
module StripeBilling
  module Charges
    class LinksController < ApplicationController
      require_permission :manage_billing
      agent_tool :retry_payment_link, on: :create, title: "Try again to make a payment link (or apply a subscription change)"

      before_action :set_charge

      def create
        @charge.update!(last_error: nil)
        @charge.prepare!
        if @charge.reload.last_error.present?
          redirect_back fallback_location: engagement_path(@charge.engagement), alert: @charge.last_error
        else
          redirect_back fallback_location: engagement_path(@charge.engagement), notice: @charge.payable? ? "The payment link is ready." : "Done."
        end
      end
    end
  end
end
