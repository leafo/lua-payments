debug = false

http = if ngx
  require "lapis.nginx.http"
else
  require "ssl.https"


ltn12 = require "ltn12"
json = require "cjson"

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

calculate_fee = (currency, transactions_count, amount, medium) ->
  unless medium == "default"
    error "don't know how to calculate paypal fee for medium #{medium}"

  switch currency
    -- AUD is wrong, but it's too complicated so w/e
    when "USD", "CAD", "AUD"
      -- 2.9% + $0.30 per transaction
      -- https://www.paypal.com/us/webapps/mpp/merchant-fees
      transactions_count * 30 + math.floor(amount * 0.029)
    when "GBP"
      -- 3.4% + 20p per transaction
      -- https://www.paypal.com/gb/webapps/mpp/merchant-fees
      transactions_count * 20 + math.floor(amount * 0.034)
    when "EUR"
      -- FIXME: this is wrong - that info comes from the page for
      -- Germany. France for example is 3.4% + 0.25€, there's tons
      -- of edge cases, welcome to Europe. - amos

      -- 1.9% + 0.35€ per transaction
      -- https://www.paypal.com/de/webapps/mpp/merchant-fees
      transactions_count * 35 + math.floor(amount * 0.019)
    when "JPY"
      -- 3.6% + 40円 per transaction
      -- https://www.paypal.com/jp/webapps/mpp/merchant-fees
      transactions_count * 40 + math.floor(amount * 0.036)
    else
      nil, "don't know how to calculate Paypal fee for currency #{currency}"

-- Paypal Express Checkout (Basic Classic API):
-- https://developer.paypal.com/docs/classic/api/#ec
-- Guess we're not using this
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

-- Paypal Adaptive Payments (Classic API):
-- https://developer.paypal.com/docs/classic/api/#ap
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
      "X-PAYPAL-REQUEST-DATA-FORMAT": "NV" -- Name-Value pair (rather than SOAP)
      "X-PAYPAL-RESPONSE-DATA-FORMAT": "NV"
      "X-PAYPAL-APPLICATION-ID": @application_id
    }

    params = extend {
      "clientDetails.applicationId": @application_id
    }, params

    body = encode_query_string params

    unless ngx
      parse_url = require("socket.url").parse
      host = assert parse_url(@api_url).host
      headers["Host"] = host
      headers["Content-length"] = #body

    if debug
      moon = require "moon"
      io.stdout\write "#{action}:\n"
      -- io.stdout\write "Headers:\n"
      -- io.stdout\write moon.dump headers
      io.stdout\write "Params:\n"
      io.stdout\write moon.dump params

    out = {}
    _, code, res_headers = assert http.request {
      :headers
      url: "#{@api_url}/#{action}"
      source: ltn12.source.string body
      method: "POST"
      sink: ltn12.sink.table out
      protocol: not ngx and "sslv23" or nil -- for luasec
    }

    text = concat(out)
    res = parse_query_string(text) or text
    strip_numeric(res) if type(res) == "table"

    if debug
      moon = require "moon"
      io.stdout\write "RESPONSE #{action}:\n"
      io.stdout\write moon.dump {
        :res, :res_headers
      }

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

  convert_currency: (amount, source="USD", dest="AUD") =>
    @_method "AdaptivePayments/ConvertCurrency", extend {
      "requestEnvelope.errorLanguage": "en_US"
      "baseAmountList.currency(0).code": source
      "baseAmountList.currency(0).amount": tostring amount
      "convertToCurrencyList.currencyCode": dest
    }

  refund: (pay_key, params) =>
    -- https://developer.paypal.com/docs/classic/api/adaptive-payments/Refund_API_Operation/
    @_method "AdaptivePayments/Refund", extend {
      payKey: pay_key
      "requestEnvelope.errorLanguage": "en_US"
    }, params

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

  calculate_fee: (...) => calculate_fee ...

  check_success: (res={}, msg="paypal failed") =>
    if (res["responseEnvelope.ack"] or "")\lower! == "success"
      res
    else
      nil, msg

  assert_success: (...) =>
    assert_error @check_success ...

-- Paypal REST API:
-- https://developer.paypal.com/docs/api/
class Rest
  @urls: {
    default: "https://api.paypal.com/v1/"
    sandbox: "https://api.sandbox.paypal.com/v1/"
  }

  new: (opts) =>
    @url = opts.sandbox and @@urls.sandbox or @@urls.default
    @client_id = assert opts.client_id, "missing client id"
    @secret = assert opts.secret, "missing secret"

  http: =>
    require "lapis.nginx.http"

  format_price: (...) => format_price ...

  need_refresh: =>
    return true unless @last_token
    -- give it a 100 second buffer since who the h*ck knows what time paypal
    -- generated the expires for
    os.time! > @last_token_time + @last_token.expires_in - 100

  refresh_token: =>
    return unless @need_refresh!

    import encode_base64 from require "lapis.util.encoding"

    out = {}

    res, status = @http!.request {
      url: "#{@url}oauth2/token"
      method: "POST"
      sink: ltn12.sink.table out
      source: ltn12.source.string(encode_query_string grant_type: "client_credentials")
      headers: {
        "Authorization": "Basic #{encode_base64 "#{@client_id}:#{@secret}"}"
        "Content-Type": "application/x-www-form-urlencoded"
        "Accept": "application/json"
        "Accept-Language": "en_US"

      }
    }

    @last_token_time = os.time!
    @last_token = json.decode concat out
    @access_token = @last_token.access_token
    assert @access_token, "failed to get token from refresh"

    true

  _request: (method, path, body, url_params) =>
    @refresh_token!

    out = {}

    body = if body then json.encode body

    url = "#{@url}#{path}"

    if url_params
      url ..= "?" .. encode_query_string url_params

    headers = {
      "Authorization": "Bearer #{@access_token}"
      "Content-Type": "application/json"
      "Accept": "application/json"
      "Accept-Language": "en_US"
    }

    if debug
      moon = require "moon"
      io.stdout\write "\n\nPayPal REST:"
      io.stdout\write moon.dump {
        :url
        :body
        :method
        :headers
      }
      io.stdout\write "\n\n"

    res, status = @http!.request {
      :url
      :method
      :headers

      sink: ltn12.sink.table out
      source: body and ltn12.source.string(body) or nil
    }

    json.decode(concat out), status

  payout: (opts) =>
    email = assert opts.email, "missing email"
    amount = assert opts.amount, "missing amount"
    currency = assert opts.currency, "missing currency"
    note = opts.note or "A payout from itch.io"

    @_request "POST", "payments/payouts", {
      sender_batch_header: {
        email_subject: "You got a payout from itch.io"
      }
      items: {
        {
          recipient_type: "EMAIL"
          amount: {
            value: amount
            :currency
          }
          receiver: email
          :note
        }
      }
    }, {
      sync_mode: "true"
    }

  sale_transaction: (transaction_id) =>
    -- GET /v1/payments/sale/<Transaction-Id>
    @_request "GET", "payments/sale/#{transaction_id}"

  payment_resources: =>
    @_request "GET", "payments/payment/"

{ :PayPal, :Adaptive, :Rest }
