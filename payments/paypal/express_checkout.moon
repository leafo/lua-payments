
import concat from table
import types from require "tableshape"
import extend, format_price, upper_keys, strip_numeric, valid_amount from require "payments.paypal.helpers"

import encode_query_string, parse_query_string from require "lapis.util"

ltn12 = require "ltn12"

-- Paypal Express Checkout (Basic Classic API):
-- https://developer.paypal.com/docs/classic/api/#ec
class PayPalExpressCheckout extends require "payments.base_client"
  @urls: {

    live: {
      checkout: "https://www.paypal.com/cgi-bin/webscr"
      certificate: "https://api.paypal.com/nvp"
      signature: "https://api-3t.paypal.com/nvp"
    }

    sandbox: {
      checkout: "https://www.sandbox.paypal.com/cgi-bin/webscr"
      certificate: "https://api.sandbox.paypal.com/nvp"
      signature: "https://api-3t.sandbox.paypal.com/nvp"
    }
  }

  @auth_shape: types.shape {
    USER: types.string
    PWD: types.string
    SIGNATURE: types.string
    VERSION: types.string\is_optional!
  }

  new: (@opts) =>
    assert @opts.auth, "missing auth"
    @auth = assert @opts.auth, "missing auth"
    @auth.VERSION or= "98"

    assert @@.auth_shape @auth

    urls = @opts.sandbox and @@urls.sandbox or @@urls.live
    @api_url = @opts.api_url or urls.signature
    @checkout_url = @opts.checkout_url or urls.checkout

  _method: (name, params) =>
    params.METHOD = name
    out = {}

    for k,v in pairs @auth
      params[k] = v unless params[k]

    body = encode_query_string params

    success, code, res_headers = @http!.request {
      url: @api_url

      headers: {
        "Host": assert @api_url\match("//([^/]+)"), "failed to parse host"
        "Content-type": "application/x-www-form-urlencoded"
        "Content-length": #body
      }

      source: ltn12.source.string body
      method: "POST"
      sink: ltn12.sink.table out
      protocol: @http_provider == "ssl.https" and "sslv23" or nil
    }

    assert success, code

    text = concat out
    res = parse_query_string(text) or text
    strip_numeric(res) if type(res) == "table"
    @_extract_error res, res_headers

  _extract_error: (res, headers) =>
    if res.ACK != "Success"
      return nil, res.L_LONGMESSAGE0, res, headers

    res, headers

  refund: (transaction_id, opts) =>
    @_method "RefundTransaction", extend {
      TRANSACTIONID: transaction_id
    }, upper_keys opts

  transaction_search: (opts) =>
    @_method "TransactionSearch", upper_keys opts or {}

  -- amount: 0.00
  set_express_checkout: (opts) =>
    opts = upper_keys opts
    @_method "SetExpressCheckout", opts

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

