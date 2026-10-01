module StripeBilling
  # Brokers "Connect with Stripe" for every install, on the one install that holds the Stripe
  # Connect platform's keys:
  #
  #   STRIPE_CONNECT_CLIENT_ID   the platform's client id (ca_…)
  #   STRIPE_CONNECT_SECRET_KEY  the platform's secret key, which never leaves this install
  #
  # An install sends the person here with its callback, a state and a code challenge (start!);
  # Stripe sends them back with a code, which is exchanged for the agency's token and held for
  # HANDOFF_TTL against a one-time code (callback!); the install redeems that code with its
  # verifier, server to server, and the token is forgotten here (redeem!).
  module Broker
    require "net/http"

    class Error < StandardError; end

    HANDOFF_TTL = 10.minutes
    AUTHORIZE_URL = "https://connect.stripe.com/oauth/authorize"
    TOKEN_URL = "https://connect.stripe.com/oauth/token"
    DEAUTHORIZE_URL = "https://connect.stripe.com/oauth/deauthorize"

    module_function

    def client_id = ENV["STRIPE_CONNECT_CLIENT_ID"].presence
    def secret_key = ENV["STRIPE_CONNECT_SECRET_KEY"].presence
    def configured? = client_id.present? && secret_key.present?

    def start!(install:, state:, challenge:, redirect_uri:)
      raise Error, "This install doesn’t broker Stripe sign-ins." unless configured?
      raise Error, "The install’s address must be https." unless callback_allowed?(install)
      raise Error, "The sign-in is missing its state or challenge." if state.blank? || challenge.blank?

      BrokerHandoff.expired.delete_all
      handoff = BrokerHandoff.create!(token: SecureRandom.urlsafe_base64(24), install_callback: install, install_state: state,
        code_challenge: challenge, expires_at: HANDOFF_TTL.from_now)
      "#{AUTHORIZE_URL}?#{{ response_type: "code", client_id: client_id, scope: "read_write", redirect_uri: redirect_uri, state: handoff.token }.to_query}"
    end

    # Where the person goes next: back to their install with a one-time code, or an error.
    def callback!(token:, code:, error: nil)
      handoff = BrokerHandoff.live.find_by(token: token.to_s) or raise Error, "That sign-in has expired. Start again from Runwell."
      return back_to(handoff, error: error) if error.present?

      payload = stripe_post(TOKEN_URL, grant_type: "authorization_code", code: code)
      handoff_code = SecureRandom.urlsafe_base64(32)
      handoff.update!(access_token: payload["access_token"], stripe_user_id: payload["stripe_user_id"], livemode: payload["livemode"] == true,
        handoff_digest: digest(handoff_code))
      back_to(handoff, code: handoff_code)
    end

    def redeem!(code:, verifier:)
      handoff = BrokerHandoff.live.where.not(access_token: nil).find_by(handoff_digest: digest(code.to_s)) or raise Error, "invalid_code"
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier.to_s), padding: false)
      raise Error, "invalid_verifier" unless ActiveSupport::SecurityUtils.secure_compare(challenge, handoff.code_challenge)

      { "access_token" => handoff.access_token, "stripe_user_id" => handoff.stripe_user_id, "livemode" => handoff.livemode }
    ensure
      handoff&.destroy! if handoff&.persisted?
    end

    # Disconnects an account from the platform, for an install that proves it holds its token.
    def deauthorize!(account_id:, access_token:)
      raise Error, "This install doesn’t broker Stripe sign-ins." unless configured?

      account = stripe_get("https://api.stripe.com/v1/account", access_token)
      raise Error, "token_mismatch" unless account["id"].present? && account["id"] == account_id

      stripe_post(DEAUTHORIZE_URL, client_id: client_id, stripe_user_id: account_id)
    end

    def callback_allowed?(url)
      uri = URI.parse(url.to_s)
      uri.host.present? && (uri.scheme == "https" || (uri.scheme == "http" && %w[localhost 127.0.0.1].include?(uri.host)))
    rescue URI::InvalidURIError
      false
    end

    def back_to(handoff, **params)
      uri = URI.parse(handoff.install_callback)
      uri.query = [ uri.query.presence, { state: handoff.install_state, **params }.to_query ].compact.join("&")
      uri.to_s
    end

    def digest(value) = Digest::SHA256.hexdigest(value)

    def stripe_post(url, params)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(secret_key, "")
      request.set_form_data(params)
      parse(Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { it.request(request) })
    end

    def stripe_get(url, token)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"
      parse(Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { it.request(request) })
    end

    def parse(response)
      body = JSON.parse(response.body.to_s) rescue {}
      return body if response.is_a?(Net::HTTPSuccess)

      raise Error, body["error_description"] || body.dig("error", "message") || body["error"] || "Stripe answered #{response.code}"
    end
  end
end
