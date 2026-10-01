class CreateStripeBilling < ActiveRecord::Migration[8.1]
  def change
    # The agency's Stripe account, connected through the OAuth broker (one row).
    create_table :stripe_billing_connections do |t|
      t.string :account_id
      t.string :account_name
      t.text :access_token
      t.boolean :livemode, null: false, default: false
      t.string :webhook_endpoint_id
      t.text :webhook_secret
      t.string :oauth_state
      t.text :code_verifier
      t.datetime :connected_at
      t.datetime :last_event_at
      t.text :last_error
      t.timestamps
    end

    # What one approved agreement version asks the client to pay, and whether they have.
    create_table :stripe_billing_charges do |t|
      t.references :engagement, null: false, foreign_key: true
      t.references :agreement_version, null: false, foreign_key: true, index: { unique: true }
      t.references :contact, foreign_key: true
      t.string :kind, null: false
      t.integer :amount_cents, null: false
      t.string :interval
      t.integer :interval_count
      t.string :price_id
      t.string :payment_link_id
      t.string :payment_link_url
      t.datetime :emailed_at
      t.boolean :paid, null: false, default: false
      t.string :paid_via
      t.datetime :paid_at
      t.text :paid_note
      t.references :marked_paid_by, foreign_key: { to_table: :users }
      t.string :checkout_session_id
      t.string :stripe_customer_id
      t.datetime :withdrawn_at
      t.string :withdrawn_reason
      t.text :last_error
      t.timestamps
    end
    # A service has at most one payment link waiting to start its subscription.
    add_index :stripe_billing_charges, :engagement_id, unique: true, name: "index_stripe_billing_charges_one_open_subscription",
      where: "kind = 'subscription' AND paid = 0 AND withdrawn_at IS NULL"

    # How a service is billed, once: a Stripe subscription, or billing outside Stripe that an
    # admin recorded. One per engagement, so a service can't be billed twice.
    create_table :stripe_billing_subscriptions do |t|
      t.references :engagement, null: false, foreign_key: true, index: { unique: true }
      t.references :charge, null: false, foreign_key: { to_table: :stripe_billing_charges }
      t.string :stripe_subscription_id, index: { unique: true }
      t.string :stripe_customer_id
      t.string :status, null: false
      t.integer :amount_cents, null: false
      t.string :interval
      t.integer :interval_count
      t.boolean :cancel_at_period_end, null: false, default: false
      t.datetime :canceled_at
      t.datetime :last_payment_at
      t.datetime :last_payment_failed_at
      t.text :last_error
      t.timestamps
    end

    # The broker's half of a sign-in in flight (only on the install that brokers OAuth).
    create_table :stripe_billing_broker_handoffs do |t|
      t.string :token, null: false, index: { unique: true }
      t.string :install_callback, null: false
      t.string :install_state, null: false
      t.string :code_challenge, null: false
      t.string :handoff_digest, index: { unique: true }
      t.text :access_token
      t.string :stripe_user_id
      t.boolean :livemode
      t.datetime :expires_at, null: false
      t.timestamps
    end
  end
end
