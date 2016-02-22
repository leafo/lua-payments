-- Paypal Express Checkout (Basic Classic API):
-- https://developer.paypal.com/docs/classic/api/#ec
-- Guess we're not using this
class PayPalClassic extends require "payments.base_client"
  api_url: "https://api-3t.sandbox.paypal.com/nvp"
  checkout_url: "https://www.sandbox.paypal.com/cgi-bin/webscr"

  new: (auth, @api_url) =>
    @auth = { k,v for k,v in pairs sandbox }

    if auth
      @auth[k] = v for k,v in pairs auth

  _method: (name, params) =>
    params.METHOD = name
    out = {}
    for k,v in pairs @auth
      params[k] = v unless params[k]

    if debug
      moon = require "moon"
      io.stdout\write "#{name}:\n"
      io.stdout\write moon.dump params

    _, code, res_headers = http.request {
      url: @api_url
      source: ltn12.source.string encode_query_string params
      method: "POST"
      sink: ltn12.sink.table out
    }

    text = concat(out)
    res = parse_query_string(text) or text
    strip_numeric(res) if type(res) == "table"
    res, res_headers

  refund: (transaction_id, opts) =>
    @_method "RefundTransaction", extend {
      TRANSACTIONID: transaction_id
    }, upper_keys opts

  -- amount: 0.00
  set_express_checkout: (return_url, cancel_url, opts) =>
    @_method "SetExpressCheckout", extend {
      RETURNURL: return_url
      CANCELURL: cancel_url
    }, upper_keys opts

  get_express_checkout_details: (token) =>
    @_method "GetExpressCheckoutDetails", TOKEN: token

  do_express_checkout: (token, payerid, amount, opts) =>
    assert valid_amount amount

    @_method "DoExpressCheckoutPayment", extend {
      TOKEN: token
      PAYERID: payerid
      PAYMENTREQUEST_0_AMT: amount
    }, upper_keys opts

  pay_url: (token) =>
    "#{@checkout_url}?cmd=_express-checkout&token=#{token}&useraction=commit"

  format_price: (...) => format_price ...

  calculate_fee: (...) => assert calculate_fee ...
