module StripeBilling
  class ApplicationController < ::ApplicationController
    layout "application"

    before_action { head :not_found unless Runwell::Plugins.enabled?(:stripe_billing) }

    private
      def set_charge = @charge = Charge.find(params[:charge_id])
  end
end
