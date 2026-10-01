module StripeBilling
  # A Runwell plugin: Stripe payment links for what a client approved. When a client approves an
  # agreement, the approval page (and an email) offers a Stripe payment link for its amount: a
  # subscription on the agreement's cadence for a service, a one-time payment for fixed work
  # (the initial price, then each change order's difference). Stripe's webhooks mark each
  # version paid; an admin can mark it paid another way. A service is billed once: a single
  # subscription per engagement, kept at the approved amount and cancelled when it closes.
  #
  # Stripe connects with OAuth (Stripe Connect) through a broker: the install that holds the
  # platform's keys (STRIPE_CONNECT_CLIENT_ID, STRIPE_CONNECT_SECRET_KEY) exchanges the code and
  # hands the agency's token to its install server to server (StripeBilling::Broker). Every
  # other install only needs to reach the broker while it connects (STRIPE_CONNECT_BROKER_URL).
  class Engine < ::Rails::Engine
    initializer "stripe_billing.routes" do |app|
      app.routes.append do
        scope "stripe", module: "stripe_billing", as: "stripe" do
          resource :settings, only: %i[show destroy]
          resource :authorization, only: %i[create show]
          resource :webhooks, only: :create
          resources :engagements, param: :ref, only: [] do
            resources :charges, only: :index
          end
          resources :charges, only: [] do
            scope module: :charges do
              resource :payment, only: %i[create destroy]
              resource :delivery, only: :create
              resource :link, only: :create
            end
          end
          namespace :broker do
            resource :authorization, only: %i[new show]
            resource :token, only: :create
            resource :deauthorization, only: :create
          end
        end
      end
    end

    initializer "stripe_billing.events" do
      ActiveSupport::Notifications.subscribe("event.runwell") { |*, payload| StripeBilling::Events.handle(payload[:event]) }
    end

    initializer "stripe_billing.models" do
      ActiveSupport.on_load(:runwell_engagement) do
        has_many :stripe_billing_charges, class_name: "StripeBilling::Charge", dependent: :destroy
        has_one :stripe_subscription, class_name: "StripeBilling::Subscription", dependent: :destroy
      end
    end

    config.to_prepare do
      Runwell::Plugins.register :stripe_billing, name: "Stripe", version: StripeBilling::VERSION, author: "Runwell",
        requires: ">= 2.1.3", homepage: "https://github.com/Martin-Business-Consultants/runwell-stripe-billing",
        description: "Payment links for approved agreements: a subscription for a service, a one-time payment for fixed work, offered on the approval page and by email. Stripe marks each paid, or an admin records payment another way."
      Runwell::Plugins.settings :stripe_billing, "Stripe", -> { stripe_settings_path }
      Runwell::Plugins.permission :stripe_billing, :manage_billing, name: "Invoice clients and link recurring billing", roles: %w[owner manager]
      Runwell::Plugins.slot :engagement_panel, :stripe_billing, "stripe_billing/slots/engagement_panel"
      Runwell::Plugins.slot :portal_engagement_panel, :stripe_billing, "stripe_billing/slots/portal_engagement_panel"
      Runwell::Plugins.slot :approval_page, :stripe_billing, "stripe_billing/slots/approval_page"
      Runwell::Plugins.briefing :stripe_billing, "Payments to follow up", partial: "stripe_billing/briefing/item",
        items: ->(user) { user.can?(:manage_billing) ? StripeBilling::Attention.items : [] }
    end
  end
end
