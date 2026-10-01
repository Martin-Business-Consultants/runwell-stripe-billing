# An engagement's payments: what each approved version asks the client to pay, and whether
# they have.
module StripeBilling
  class ChargesController < ApplicationController
    require_permission :manage_billing
    agent_tool :list_stripe_payments, on: :index, title: "List an engagement's Stripe payments",
      description: "Each approved version's amount, its payment link, and whether it's paid (by Stripe, or recorded by hand)."

    def index
      @engagement = ::Engagement.find_by_ref!(params[:engagement_ref])
      @charges = @engagement.stripe_billing_charges.recent.includes(:agreement_version, :marked_paid_by)
    end
  end
end
