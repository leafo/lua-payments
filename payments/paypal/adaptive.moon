-- Paypal Adaptive Payments (Classic API):
-- https://developer.paypal.com/docs/classic/api/#ap
class PayPalAdaptive extends require "payments.base_client"
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
