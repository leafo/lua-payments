
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

    login_default: "https://www.paypal.com/signin/authorize"
    login_sandbox: "https://www.sandbox.paypal.com/signin/authorize"
  }

  new: (opts) =>
    @sandbox = opts.sandbox or false
    @url = @sandbox and @@urls.sandbox or @@urls.default
    @client_id = assert opts.client_id, "missing client id"
    @secret = assert opts.secret, "missing secret"
    super opts

  format_price: (...) => format_price ...

  log_in_url: (opts={}) =>
    url = if @sandbox
      @@urls.login_sandbox
    else
      @@urls.login_default

    params = encode_query_string {
      client_id: assert @client_id, "missing client id"
      response_type: opts.response_type or "code"
      scope: opts.scope or "openid"
      redirect_uri: assert opts.redirect_uri, "missing redirect uri"
      nonce: opts.nonce
      state: opts.state
    }

    "#{url}?#{params}"

  identity_token: (opts={}) =>
    return unless @need_refresh!

    parse_url = require("socket.url").parse
    host = assert parse_url(@url).host

    body = if opts.refresh_token
      encode_query_string {
        grant_type: "refresh_token"
        refresh_token: opts.refresh_token
      }
    elseif opts.code
      encode_query_string {
        grant_type: "authorization_code"
        code: opts.code
      }
    else
      error "unknown method for identity token (expecting code or refresh_token)"

    import encode_base64 from require "lapis.util.encoding"

    headers = {
      "Host": host
      "Content-length":tostring(#body)
      "Authorization": "Basic #{encode_base64 "#{@client_id}:#{@secret}"}"
      "Content-Type": "application/x-www-form-urlencoded"
      "Accept": "application/json"
      "Accept-Language": "en_US"
    }

    out = {}

    res, status = assert @http!.request {
      method: "POST"
      url: "#{@url}identity/openidconnect/tokenservice"
      :headers

      sink: ltn12.sink.table out
      source: body and ltn12.source.string(body) or nil

      protocol: @http_provider == "ssl.https" and "sslv23" or nil
    }

    out = table.concat out, ""

    if out\match "^{"
      out = json.decode out

    unless status == 200
      return nil, out

    out

  identity_userinfo: (opts={}) =>
    assert opts.access_token, "missing access token"

    res, status = @_request {
      method: "GET"
      path: "oauth2/token/userinfo"
      url_params: {
        schema: "openid"
      }
      access_token: opts.access_token
    }

    unless status == 200
      return nil, res

    res

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

  _request: (opts={}) =>
    assert opts.method, "missing method"
    assert opts.path, "missing path"

    {:method, :path, :params, :url_params} = opts

    authorization = if opts.access_token
      "Bearer #{opts.access_token}"
    else
      @refresh_token!
      "Bearer #{@access_token}"

    out = {}

    body = if params then json.encode params

    url = "#{@url}#{path}"

    if url_params
      url ..= "?" .. encode_query_string url_params

    parse_url = require("socket.url").parse
    host = assert parse_url(@url).host

    res, status = assert @http!.request {
      :url
      :method

      headers: {
        "Host": host
        "Content-length": body and tostring(#body) or nil
        "Authorization": authorization
        "Content-Type": body and "application/json"
        "Accept": "application/json"
        "Accept-Language": "en_US"
      }

      sink: ltn12.sink.table out
      source: body and ltn12.source.string(body) or nil

      protocol: @http_provider == "ssl.https" and "sslv23" or nil
    }

    json.decode(concat out), status

  get_payments: (opts) =>
    @_request {
      method: "GET"
      path: "payments/payment"
      params: opts
    }

  payout: (opts) =>
    email = assert opts.email, "missing email"
    amount = assert opts.amount, "missing amount"
    currency = assert opts.currency, "missing currency"

    assert type(amount) == "string", "amount should be formatted as string (0.00)"

    note = opts.note or "Payout"
    email_subject = opts.email_subject or "You got a payout"


    @_request {
      method: "POST"
      path: "payments/payouts"
      url_params: {
        sync_mode: "true"
      }
      params: {
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
      }
    }

  get_payout: (batch_id) =>
    -- GET /v1/payments/payouts/<payout_batch_id>
    @_request {
      method: "GET"
      path: "payments/payouts/#{batch_id}"
    }

  sale_transaction: (transaction_id) =>
    -- GET /v1/payments/sale/<Transaction-Id>
    @_request {
      method: "GET"
      path: "payments/sale/#{transaction_id}"
    }

  payment: (payment_id) =>
    -- GET /v1/payments/payment/<Payment-Id>
    @_request {
      method: "GET"
      path: "payments/payment/#{payment_id}"
    }

