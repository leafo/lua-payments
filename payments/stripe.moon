
ltn12 = require "ltn12"
json = require "cjson"

import encode_query_string, parse_query_string from require "lapis.util"

import encode_base64 from require "lapis.util.encoding"

class Stripe extends require "payments.base_client"
  api_url: "https://api.stripe.com/v1/"

  new: (opts) =>
    @client_id = assert opts.client_id, "missing client id"
    @client_secret = assert opts.client_secret, "missing client secret"
    @publishable_key = opts.publishable_key

  calculate_fee: (currency, transactions_count, amount, medium) =>
    switch medium
      when "default"
        -- 2.9% + $0.30 per transaction
        -- https://stripe.com/us/pricing
        transactions_count * 30 + math.floor(amount * 0.029)
      when "bitcoin"
        -- 0.5% per transaction, no other fee
        -- https://stripe.com/bitcoin
        math.floor(amount * 0.005)
      else
        error "don't know how to calculate stripe fee for medium #{medium}"

  -- TODO: use csrf
  connect_url: =>
    "https://connect.stripe.com/oauth/authorize?response_type=code&scope=read_write&client_id=#{@client_id}"

  -- converts auth code into access token
  -- Returns:
  -- {
  --   "access_token": "sk_test_xxx",
  --   "livemode": false,
  --   "refresh_token": "rt_xxx",
  --   "token_type": "bearer",
  --   "stripe_publishable_key": "pk_test_xxx",
  --   "stripe_user_id": "acct_xxx",
  --   "scope": "read_only"
  -- }
  oauth_token: (code) =>
    out = {}

    @http!.request {
      url: "https://connect.stripe.com/oauth/token"
      method: "POST"
      sink: ltn12.sink.table out
      headers: {
        "Host": assert parse_url(@api_url).host, "failed to get host"
      }

      source: ltn12.source.string encode_query_string {
        :code
        client_secret: @client_secret
        grant_type: "authorization_code"
      }

      protocol: @http_provider == "ssl.https" and "sslv23" or nil
    }

    out = table.concat out
    json.decode out

  _request: (method, path, params, access_token=@client_secret) =>
    out = {}

    if params
      for k,v in pairs params
        params[k] = tostring v

    body = params and encode_query_string params

    parse_url = require("socket.url").parse

    headers = {
      "Host": assert parse_url(@api_url).host, "failed to get host"
      "Authorization": "Basic " .. encode_base64 access_token .. ":"
      "Content-Type": "application/x-www-form-urlencoded"
      "Content-length": body and #body or nil
    }

    _, status = @http!.request {
      url: @api_url .. path
      :method
      :headers
      sink: ltn12.sink.table out
      source: body and ltn12.source.string(body) or nil

      protocol: @http_provider == "ssl.https" and "sslv23" or nil
    }

    @_format_response json.decode(table.concat out), status

  _format_response: (res, status) =>
    if res.error
      nil, res.error.message, res, status
    else
      res, status

  -- charge a card with amount cents
  charge: (opts) =>
    { :access_token, :card, :amount, :currency, :description, :fee } = opts

    assert tonumber(amount), "missing amount"

    application_fee = if fee and fee > 0 then fee

    @_request "POST", "charges", {
      :card, :amount, :description, :currency, :application_fee
    }, access_token

  get_charges: =>
    @_request "GET", "charges"

  get_token: (token_id) =>
    @_request "GET", "tokens/#{token_id}"

  get_charge: (charge_id) =>
    @_request "GET", "charges/#{charge_id}"

  refund_charge: (charge_id) =>
    @_request "POST", "refunds", {
      charge: charge_id
    }

  mark_fraud: (charge_id) =>
    @_request "POST", "charges/#{charge_id}", {
      "fraud_details[user_report]": "fraudulent"
    }

  create_account: (opts={}) =>
    opts.managed = true if opts.managed == nil
    assert opts.country, "missing country"
    assert opts.email, "missing country"

    @_request "POST", "accounts", opts

  update_account: (account_id, opts) =>
    @_request "POST", "accounts/#{account_id}", opts

  list_accounts: =>
    @_request "GET", "accounts"

  list_products: =>
    @_request "GET", "products"

  get_account: (account_id) =>
    @_request "GET", "accounts/#{account_id}"

  list_transfers: =>
    @_request "GET", "transfers",

  transfer: (destination, currency, amount) =>
    assert "USD" == currency, "usd only for now"
    assert tonumber(amount), "invalid amount"

    @_request "POST", "transfers", {
      :destination
      :currency
      :amount
    }

  -- this is just for development to fill the test account
  fill_test_balance: (amount=50000) =>
    config = require("lapis.config").get!
    assert config._name == "development", "can only fill account in development"

    @_request "POST", "charges", {
      :amount
      currency: "USD"
      "source[object]": "card"
      "source[number]": "4000000000000077"
      "source[exp_month]": "2"
      "source[exp_year]": "22"
    }

  get_balance: =>
    @_request "GET", "balance"

{ :Stripe }
