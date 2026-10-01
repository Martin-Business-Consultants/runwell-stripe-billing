module StripeBilling
  # The install's half of connecting Stripe. It sends the person to the broker with a state and
  # a code challenge, and on the way back redeems the broker's one-time code with the matching
  # verifier, server to server: the agency's token never passes through the browser, and only
  # the install that started the sign-in can collect it.
  class Oauth
    require "net/http"

    class Error < StandardError; end

    # The install holding the Stripe Connect platform's keys (StripeBilling::Broker).
    def self.broker_url = (ENV["STRIPE_CONNECT_BROKER_URL"].presence || "https://v2.runwell.business").chomp("/")

    def initialize(connection)
      @connection = connection
    end

    attr_reader :connection

    def authorize_url(callback:)
      verifier = SecureRandom.urlsafe_base64(48)
      connection.update!(oauth_state: SecureRandom.urlsafe_base64(24), code_verifier: verifier)
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      "#{self.class.broker_url}/stripe/broker/authorization/new?#{{ install: callback, state: connection.oauth_state, challenge: challenge }.to_query}"
    end

    def complete!(code:, state:)
      unless state.present? && connection.oauth_state.present? && ActiveSupport::SecurityUtils.secure_compare(state.to_s, connection.oauth_state)
        raise Error, "That sign-in didn’t start here. Try again."
      end

      payload = post("#{self.class.broker_url}/stripe/broker/token", code: code, verifier: connection.code_verifier)
      connection.store_account!(access_token: payload["access_token"], account_id: payload["stripe_user_id"], livemode: payload["livemode"] == true)
    end

    # Best effort: the broker or Stripe refusing must not stop someone disconnecting here.
    def deauthorize!
      return unless connection.connected?

      post("#{self.class.broker_url}/stripe/broker/deauthorization", account_id: connection.account_id, access_token: connection.access_token)
    rescue Error => error
      Rails.logger.warn("[Stripe] deauthorize failed: #{error.message}")
    end

    private
      def post(url, params)
        uri = URI(url)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = params.to_json
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 30) { it.request(request) }
        body = JSON.parse(response.body.to_s) rescue {}
        raise Error, "The Stripe sign-in service refused: #{body["error"] || response.code}" unless response.is_a?(Net::HTTPSuccess)

        body
      rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => error
        raise Error, "Couldn’t reach the Stripe sign-in service at #{self.class.broker_url} (#{error.message})."
      end
  end
end
