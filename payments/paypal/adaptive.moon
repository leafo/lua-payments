import concat from table
import types from require "tableshape"
import extend, strip_numeric, format_price from require "payments.paypal.helpers"

import encode_query_string, parse_query_string from require "lapis.util"

ltn12 = require "ltn12"

-- Paypal Adaptive Payments (Classic API):
-- https://developer.paypal.com/docs/classic/api/#ap
class PayPalAdaptive extends require "payments.base_client"
  @urls: {
    live: {
      base: "https://www.paypal.com"
      api: "https://svcs.paypal.com"
    }

    sandbox: {
      base: "https://www.sandbox.paypal.com"
      api: "https://svcs.sandbox.paypal.com"
    }
  }

  @auth_shape: types.shape {
    USER: types.string
    PWD: types.string
    SIGNATURE: types.string
  }

  new: (@opts) =>
    @auth = assert @opts.auth, "missing auth"
    assert @@.auth_shape @auth

    @application_id = assert @opts.application_id, "missing application id"

    urls = @opts.sandbox and @@urls.sandbox or @@urls.live
    @api_url = @opts.api_url or urls.api
    @base_url = @opts.base_url or urls.base
    super @opts

  _method: (action, params) =>
    headers = {
      "X-PAYPAL-SECURITY-USERID": @auth.USER
      "X-PAYPAL-SECURITY-PASSWORD": @auth.PWD
      "X-PAYPAL-SECURITY-SIGNATURE": @auth.SIGNATURE
      "X-PAYPAL-REQUEST-DATA-FORMAT": "NV" -- Name-Value pair (rather than SOAP)
      "X-PAYPAL-RESPONSE-DATA-FORMAT": "NV"
      "X-PAYPAL-APPLICATION-ID": @application_id
    }

    params = extend {
      "clientDetails.applicationId": @application_id
    }, params

    body = encode_query_string params

    parse_url = require("socket.url").parse
    host = assert parse_url(@api_url).host
    headers["Host"] = host
    headers["Content-length"] = tostring #body

    out = {}
    _, code, res_headers = assert @http!.request {
      :headers
      url: "#{@api_url}/#{action}"
      source: ltn12.source.string body
      method: "POST"
      sink: ltn12.sink.table out

      protocol: @http_provider == "ssl.https" and "sslv23" or nil
    }

    text = concat out
    res = parse_query_string(text) or text
    strip_numeric(res) if type(res) == "table"

    @_extract_error res, res_headers

  _extract_error: (res={}, msg="paypal failed") =>
    if (res["responseEnvelope.ack"] or "")\lower! == "success"
      res
    else
      nil, res["error(0).message"], res

  pay: (params={}) =>
    assert params.receivers and #params.receivers > 0,
      "there must be at least one receiver"

    params_shape = types.shape {
      cancelUrl: types.string
      returnUrl: types.string

      receivers: types.array_of types.shape {
        email: types.string
        amount: types.string
      }, open: true

    }, open: true

    assert params_shape params

    receivers = params.receivers
    params.receivers = nil

    params = extend {
      actionType: "PAY"
      currencyCode: "USD"
      feesPayer: if #receivers > 1 then "PRIMARYRECEIVER"
      "requestEnvelope.errorLanguage": "en_US"

      cancelUrl: params.returnUrl
      returnUrl: params.cancelUrl
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

  payment_details: (params) =>
    assert params.payKey or params.transactionId or params.trackingId,
      "Missing one of payKey, transactionId or trackingId"

    @_method "AdaptivePayments/PaymentDetails", extend {
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

  checkout_url: (pay_key) =>
    -- "https://www.paypal.com/webapps/adaptivepayment/flow/pay?paykey=#{pay_key}"
    "#{@base_url}/webscr?cmd=_ap-payment&paykey=#{pay_key}"

  format_price: (...) => format_price ...

