# The broker's public endpoints (StripeBilling::Broker), on the install holding the Stripe
# Connect platform's keys; everywhere else they don't exist. They don't depend on the plugin
# being switched on here.
module StripeBilling
  module Broker
    class BaseController < ::ApplicationController
      allow_unauthenticated_access
      skip_forgery_protection

      before_action { head :not_found unless StripeBilling::Broker.configured? }
    end
  end
end
