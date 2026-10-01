require_relative "lib/stripe_billing/version"

Gem::Specification.new do |spec|
  spec.name = "stripe_billing"
  spec.version = StripeBilling::VERSION
  spec.summary = "Stripe payment links for approved agreements in Runwell, as a plugin"
  spec.authors = [ "Runwell" ]
  spec.homepage = "https://github.com/Martin-Business-Consultants/runwell-stripe-billing"
  spec.license = "FSL-1.1-MIT"
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
