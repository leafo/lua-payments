
json = require "cjson"
ltn12 = require "ltn12"


import format_price from require "payments.paypal.helpers"

import encode_query_string from require "lapis.util"

import concat from table

-- Paypal REST API:
-- https://developer.paypal.com/docs/api/
class PayPalRest extends require "payments.base_client"
  @urls: {
    default: "https://api.paypal.com/v1/"
    sandbox: "https://api.sandbox.paypal.com/v1/"
  }

  new: (opts) =>
    @url = opts.sandbox and @@urls.sandbox or @@urls.default
    @client_id = assert opts.client_id, "missing client id"
    @secret = assert opts.secret, "missing secret"
    super opts

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

    body = encode_query_string grant_type: "client_credentials"

    parse_url = require("socket.url").parse
    host = assert parse_url(@url).host

    res, status = assert @http!.request {
      url: "#{@url}oauth2/token"
      method: "POST"
      sink: ltn12.sink.table out
      source: ltn12.source.string(body)
      headers: {
        "Host": host
        "Content-length": tostring #body
        "Authorization": "Basic #{encode_base64 "#{@client_id}:#{@secret}"}"
        "Content-Type": "application/x-www-form-urlencoded"
        "Accept": "application/json"
        "Accept-Language": "en_US"
      }

      protocol: @http_provider == "ssl.https" and "sslv23" or nil
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


    parse_url = require("socket.url").parse
    host = assert parse_url(@url).host

    headers = {
      "Host": host
      "Content-length": body and tostring(#body) or nil
      "Authorization": "Bearer #{@access_token}"
      "Content-Type": "application/json"
      "Accept": "application/json"
      "Accept-Language": "en_US"
    }

    res, status = assert @http!.request {
      :url
      :method
      :headers

      sink: ltn12.sink.table out
      source: body and ltn12.source.string(body) or nil

      protocol: @http_provider == "ssl.https" and "sslv23" or nil
    }

    require("moon").p {
      headers
      concat out
    }

    json.decode(concat out), status

  get_payments: (opts) =>
    @_request "GET", "payments/payment", opts

  payout: (opts) =>
    email = assert opts.email, "missing email"
    amount = assert opts.amount, "missing amount"
    currency = assert opts.currency, "missing currency"

    note = opts.note or "Payout"
    email_subject = opts.email_subject or "You got a payout"


    @_request "POST", "payments/payouts", {
      sender_batch_header: {
        :email_subject
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

