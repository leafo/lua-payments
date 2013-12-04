
debug = false

http = require "lapis.nginx.http"
ltn12 = require "ltn12"

import encode_query_string, parse_query_string  from require "lapis.util"
import assert_error from require "lapis.application"
import concat from table

sandbox = {
  USER: "sdk-three_api1.sdk.com"
	PWD: nil
	SIGNATURE: nil

  VERSION: "98" -- 2013-Feb-01
}

extend = (a, ...) ->
  for t in *{...}
    if t
      a[k] = v for k,v in pairs t
  a

upper_keys = (t) ->
  if t
    { type(k) == "string" and k\upper! or k, v for k,v in pairs t }

strip_numeric = (t) ->
  for k,v in ipairs t
    t[k] = nil
  t

valid_amount = (str) ->
  return true if str\match "%d+%.%d%d"
  nil, "invalid amount (#{str})"

format_price = (cents, currency="USD") ->
  if currency == "JPY"
    tostring math.floor cents
  else
    dollars = math.floor cents / 100
    change = "%02d"\format cents % 100
    "#{dollars}.#{change}"

-- basic paypal, guess I'm not using this
class PayPal
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
      require "moon"
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

class Adaptive
  application_id: "APP-XXX" -- sandbox
  api_url: "https://svcs.sandbox.paypal.com" -- sandbox
  base_url: "www.sandbox.paypal.com"

  new: (auth) =>
    params = extend {}, sandbox, auth
    @user = params.USER
    @password = params.PWD
    @signature = params.SIGNATURE

    for k in *{"api_url", "application_id", "base_url"}
      @[k] = params[k]

  _method: (action, params) =>
    headers = {
      "X-PAYPAL-SECURITY-USERID": @user
      "X-PAYPAL-SECURITY-PASSWORD": @password
      "X-PAYPAL-SECURITY-SIGNATURE": @signature
      "X-PAYPAL-REQUEST-DATA-FORMAT": "NV"
      "X-PAYPAL-RESPONSE-DATA-FORMAT": "NV"
      "X-PAYPAL-APPLICATION-ID": @application_id
    }

    params = extend {
      "clientDetails.applicationId": @application_id
    }, params

    if debug
      require "moon"
      io.stdout\write "#{action}:\n"
      -- io.stdout\write "Headers:\n"
      -- io.stdout\write moon.dump headers
      io.stdout\write "Params:\n"
      io.stdout\write moon.dump params

    out = {}
    _, code, res_headers = http.request {
      :headers
      url: "#{@api_url}/#{action}"
      source: ltn12.source.string encode_query_string params
      method: "POST"
      sink: ltn12.sink.table out
    }

    text = concat(out)
    res = parse_query_string(text) or text
    strip_numeric(res) if type(res) == "table"
    res, res_headers

  pay: (return_url, cancel_url, receivers={}, params) =>
    assert #receivers > 0, "there must be at least one receiver"

    params = extend {
      actionType: "PAY"
      currencyCode: "USD"
      feesPayer: if #receivers > 1 then "PRIMARYRECEIVER"
      "requestEnvelope.errorLanguage": "en_US"

      cancelUrl: cancel_url
      returnUrl: return_url
    }, params

    for i, r in ipairs receivers
      i -= 1
      for rk, rv in pairs r
        params["receiverList.receiver(#{i}).#{rk}"] = tostring rv

    @_method "AdaptivePayments/Pay", params

  payment_details: (pay_key, params) =>
    @_method "AdaptivePayments/PaymentDetails", extend {
      payKey: pay_key
      "requestEnvelope.errorLanguage": "en_US"
    }, params

  get_shipping_addresses: (pay_key, params) =>
    @_method "AdaptivePayments/GetShippingAddresses", extend {
      key: pay_key
      "requestEnvelope.errorLanguage": "en_US"
    }, params

  set_payment_options: (pay_key, params) =>
    @_method "AdaptivePayments/SetPaymentOptions", extend {
      payKey: pay_key
      "requestEnvelope.errorLanguage": "en_US"
    }, params

  pay_url: (pay_key) =>
    -- "https://www.paypal.com/webapps/adaptivepayment/flow/pay?paykey=#{pay_key}"
    "https://#{@base_url}/webscr?cmd=_ap-payment&paykey=#{pay_key}"

  format_price: (...) => format_price ...

  check_success: (res={}, msg="paypal failed") =>
    if (res["responseEnvelope.ack"] or "")\lower! == "success"
      res
    else
      nil, msg

  assert_success: (...) =>
    assert_error @check_success ...

{ :PayPal, :Adaptive }
