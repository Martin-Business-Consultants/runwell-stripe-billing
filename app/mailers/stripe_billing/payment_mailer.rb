module StripeBilling
  # The payment link for what the client just approved, sent as they approve (and again on
  # request), in the client's time zone.
  class PaymentMailer < ::ApplicationMailer
    def link
      @charge = params[:charge]
      @engagement = @charge.engagement
      @contact = @charge.recipient
      @engagement.client.in_time_zone do
        mail to: @contact.email, subject: "#{@engagement.title}: #{@charge.subscription? ? "set up your payment" : "your payment"}"
      end
    end
  end
end
