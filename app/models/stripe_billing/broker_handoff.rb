module StripeBilling
  # A sign-in in flight on the broker (StripeBilling::Broker): where to send the person back,
  # and for a few minutes the agency's token, until its install collects it.
  class BrokerHandoff < ::ApplicationRecord
    self.table_name = "stripe_billing_broker_handoffs"

    encrypts :access_token

    scope :live, -> { where(expires_at: Time.current..) }
    scope :expired, -> { where(expires_at: ...Time.current) }
  end
end
