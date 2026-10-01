module StripeBilling
  # The calls this plugin makes to Stripe's REST API, each a named method, with the connected
  # account's token. Stripe takes form-encoded bodies with bracketed keys
  # (line_items[0][price]=…), and answers JSON.
  class Api
    require "net/http"

    BASE = "https://api.stripe.com/v1"

    # The events this install's endpoint is subscribed to (Webhook handles each).
    EVENTS = %w[checkout.session.completed checkout.session.async_payment_succeeded checkout.session.async_payment_failed
      invoice.paid invoice.payment_failed customer.subscription.updated customer.subscription.deleted].freeze

    class Error < StandardError; end

    def self.encode(params) = pairs(params).join("&")

    def self.pairs(params, prefix = nil)
      params.flat_map do |key, value|
        name = prefix ? "#{prefix}[#{key}]" : key.to_s
        case value
        when Hash then pairs(value, name)
        when Array then pairs(value.each_with_index.to_h { |item, index| [ index, item ] }, name)
        when nil then []
        else [ "#{CGI.escape(name)}=#{CGI.escape(value.to_s)}" ]
        end
      end
    end

    def initialize(connection = Connection.current)
      @connection = connection
    end

    def account = get("account")

    def create_webhook_endpoint(url)
      post("webhook_endpoints", url: url, enabled_events: EVENTS, description: "Runwell")
    end

    def delete_webhook_endpoint(id) = delete("webhook_endpoints/#{id}")

    # A price for one agreement version: one-time, or recurring every `interval_count` intervals.
    def create_price(amount_cents:, name:, interval: nil, interval_count: nil)
      post("prices", currency: Connection::CURRENCY, unit_amount: amount_cents, product_data: { name: name.truncate(250) },
        recurring: (interval ? { interval: interval, interval_count: interval_count || 1 } : nil))
    end

    # A link that can be paid once, carrying the charge's ids so its payment finds its way back.
    def create_payment_link(price_id:, metadata:, recurring:, message:)
      post("payment_links", line_items: [ { price: price_id, quantity: 1 } ], metadata: metadata,
        restrictions: { completed_sessions: { limit: 1 } },
        after_completion: { type: "hosted_confirmation", hosted_confirmation: { custom_message: message.truncate(500) } },
        subscription_data: (recurring ? { metadata: metadata } : nil),
        payment_intent_data: (recurring ? nil : { metadata: metadata }),
        customer_creation: (recurring ? nil : "always"))
    end

    def set_payment_link_active(id, active) = post("payment_links/#{id}", active: active)

    def subscription(id) = get("subscriptions/#{id}")

    # Moves the subscription to a new price from the next period, without prorating.
    def change_subscription_price(id, price_id)
      item = subscription(id).dig("items", "data", 0, "id") or raise Error, "Stripe subscription #{id} has no item to change."
      post("subscriptions/#{id}", items: [ { id: item, price: price_id } ], proration_behavior: "none")
    end

    def cancel_subscription_at_period_end(id) = post("subscriptions/#{id}", cancel_at_period_end: true)
    def cancel_subscription_now(id) = delete("subscriptions/#{id}")

    private
      def get(path) = request(Net::HTTP::Get.new(URI("#{BASE}/#{path}")))
      def delete(path) = request(Net::HTTP::Delete.new(URI("#{BASE}/#{path}")))

      def post(path, params)
        request(Net::HTTP::Post.new(URI("#{BASE}/#{path}")).tap { it.body = self.class.encode(params.compact) })
      end

      def request(request)
        raise Error, "Stripe isn’t connected." unless @connection&.connected?

        request["Authorization"] = "Bearer #{@connection.access_token}"
        request["Content-Type"] = "application/x-www-form-urlencoded"
        response = Net::HTTP.start(request.uri.host, request.uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { it.request(request) }
        body = JSON.parse(response.body.to_s) rescue {}
        return body if response.is_a?(Net::HTTPSuccess)

        message = body.dig("error", "message") || response.body.to_s.truncate(200)
        raise Error, response.code == "401" ? "Stripe refused the connection (#{message}). Reconnect Stripe in Settings." : "Stripe: #{message}"
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => error
        raise Error, "Couldn’t reach Stripe (#{error.message})."
      end
  end
end
