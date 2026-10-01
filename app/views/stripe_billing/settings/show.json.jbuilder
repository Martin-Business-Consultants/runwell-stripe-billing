json.summary(@connection.connected? ? "Stripe connected to #{@connection.account_name || @connection.account_id}#{" (test mode)" unless @connection.livemode?}; #{@open} payments waiting" : "Stripe isn't connected")
json.connected @connection.connected?
json.account_id @connection.account_id
json.account_name @connection.account_name
json.livemode @connection.livemode
json.receiving_events @connection.webhook_endpoint_id.present?
json.last_event_at @connection.last_event_at
json.error @connection.last_error
json.payments_waiting @open
json.services_billed @subscriptions
json.broker StripeBilling::Oauth.broker_url
