subscription = @engagement.stripe_subscription
json.summary "#{@engagement.ref}: #{pluralize(@charges.size, "payment")}, #{@charges.count { !it.paid? && !it.withdrawn? }} waiting#{subscription ? "; billed #{subscription.external? ? "another way" : "by Stripe (#{subscription.status})"} at #{subscription.amount_label}" : ""}"
json.engagement agent_ref(@engagement)
json.subscription do
  if subscription
    json.status subscription.status
    json.billed_by subscription.external? ? "another way" : "stripe"
    json.amount subscription.amount_label
    json.amount_cents subscription.amount_cents
    json.cancel_at_period_end subscription.cancel_at_period_end
    json.last_payment_failed_at subscription.last_payment_failed_at
  else
    json.nil!
  end
end
json.payments @charges do |charge|
  json.id charge.id
  json.version charge.agreement_version.label
  json.kind charge.kind
  json.amount charge.amount_label
  json.amount_cents charge.amount_cents
  json.state charge.state
  json.paid charge.paid
  json.paid_via charge.paid_via
  json.paid_at charge.paid_at
  json.paid_note charge.paid_note
  json.payment_link charge.payment_link_url
  json.emailed_at charge.emailed_at
  json.error charge.last_error
end
