# Recording that the client paid another way (or undoing that). It switches the Stripe link off,
# so they can't pay twice, and for a service records that it's billed outside Stripe.
module StripeBilling
  module Charges
    class PaymentsController < ApplicationController
      require_permission :manage_billing
      agent_tool :mark_payment_received, on: :create, title: "Record that the client paid another way",
        description: "note: how they paid (check, bank transfer, …). Switches off the Stripe link; for a service, records that it's billed outside Stripe.",
        params: { note: "string!" }
      agent_tool :undo_payment_received, on: :destroy, title: "Undo a payment recorded by hand", description: "Switches the Stripe link back on."

      before_action :set_charge

      def create
        @charge.mark_paid!(by: Current.user, note: params[:note].to_s.strip)
        redirect_back fallback_location: engagement_path(@charge.engagement), notice: "Marked paid: #{@charge.amount_label} for #{@charge.agreement_version.label}."
      rescue ArgumentError => error
        redirect_back fallback_location: engagement_path(@charge.engagement), alert: error.message
      end

      def destroy
        @charge.unmark_paid!(by: Current.user)
        redirect_back fallback_location: engagement_path(@charge.engagement), notice: "No longer marked paid. The payment link works again."
      rescue ArgumentError => error
        redirect_back fallback_location: engagement_path(@charge.engagement), alert: error.message
      end
    end
  end
end
