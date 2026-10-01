# Stripe for Runwell

Payment links for approved agreements: when a client approves, the approval page and an email
offer a Stripe payment link for what they agreed.

A plugin for [Runwell](https://github.com/Martin-Business-Consultants/runwellv2), the core of an
agency's project management. It owns its tables (`stripe_billing_*`), points at core records by
id, and extends Runwell only through its plugin hooks, so removing it leaves Runwell as it was.

## What it does

- **A service** (recurring engagement): its first approval is a payment link that starts a
  subscription on the agreement's cadence (weekly, monthly, quarterly). A later revision moves
  that subscription to the new amount from its next period; an add-on adds its items to it.
- **Fixed work**: a one-time link for the initial price, then one for each change order's
  difference.
- **Paid or not**: each approved version has a paid flag. Stripe sets it when the link is paid;
  someone who can manage billing records a payment made another way, with a note, which switches
  the link off so the client can't pay twice. Unpaid ones are listed on Runwell's home page.
- **Billed once**: a service has one billing (a Stripe subscription, or billing recorded as
  outside Stripe), only one subscription link can be waiting, a second subscription paid anyway
  is cancelled at once, and closing the service stops its subscription at the end of the paid
  period. It won't bill a service the QuickBooks plugin bills.

Amounts are US dollars.

## Connecting Stripe

**Settings > Stripe > Connect with Stripe** signs in with Stripe Connect (OAuth) through a broker:
one Runwell install holding the Connect platform's keys exchanges Stripe's code and hands the
agency's token to its own install, server to server, keeping nothing. After that the install
talks to Stripe and receives its account's events directly, at `/stripe/webhooks`, so it must be
reachable from the internet.

- Every install: `STRIPE_CONNECT_BROKER_URL` (default `https://v2.runwell.business`).
- The broker only: `STRIPE_CONNECT_CLIENT_ID` (`ca_…`) and `STRIPE_CONNECT_SECRET_KEY` of a
  Stripe account with Connect enabled, whose redirect URI is
  `https://<broker>/stripe/broker/authorization`. The platform must be a Stripe account of its
  own: an account can't connect to itself.

## Install

In Runwell, **Settings > Plugins > Add a plugin**: enter
`Martin-Business-Consultants/runwell-stripe-billing`. Runwell downloads the latest release onto
the server, restarts and creates the plugin's tables. It starts off: switch it on in Settings >
Plugins.

From the command line on the server: `bin/rails "plugins:install[Martin-Business-Consultants/runwell-stripe-billing]"`,
then restart Runwell.

Needs Runwell 2.1.3 or later (the approval page's plugin slot). A plugin can use only the gems
Runwell bundles.

## Updating

Settings > Plugins shows an Update button on the plugin when a newer release is out (it checks
nightly, or with Check for updates). The plugin updates only when someone presses it; if the new
release won't load, the previous one comes back.

## Developing

Clone this repository beside a Runwell checkout and link it in, from Runwell's directory:

```sh
bin/rails "plugins:link[../runwell-stripe-billing]"
bin/rails db:migrate
bin/dev
```

## Releasing

Bump `VERSION` in `lib/stripe_billing/version.rb`, commit, then tag and publish a GitHub release:

```sh
git tag v0.2.0 && git push origin main v0.2.0
gh release create v0.2.0 --generate-notes
```

Installs see it in Settings > Plugins.

## License

[FSL-1.1-MIT](LICENSE.md), like Runwell.
