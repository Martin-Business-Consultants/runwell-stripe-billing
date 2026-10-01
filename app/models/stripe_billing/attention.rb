module StripeBilling
  # The home page's payments: approved work the client hasn't paid for, links that couldn't be
  # made, and subscriptions whose payments are failing.
  module Attention
    def self.items
      Charge.open.includes(:agreement_version, engagement: :client).order(:created_at).to_a +
        Subscription.troubled.includes(engagement: :client).to_a
    end
  end
end
