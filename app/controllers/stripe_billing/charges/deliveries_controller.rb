# Emailing the client the payment link again.
module StripeBilling
  module Charges
    class DeliveriesController < ApplicationController
      require_permission :manage_billing
      agent_tool :email_payment_link, on: :create, title: "Email the client the payment link again",
        confirm: "It emails the client the Stripe payment link."

      before_action :set_charge

      def create
        if @charge.deliver!
          redirect_back fallback_location: engagement_path(@charge.engagement), notice: "Payment link emailed to #{@charge.recipient.email}."
        else
          redirect_back fallback_location: engagement_path(@charge.engagement), alert: "There’s no payment link to send, or no contact with an email address."
        end
      end
    end
  end
end
