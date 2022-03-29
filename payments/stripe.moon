
ltn12 = require "ltn12"
json = require "cjson"

import encode_query_string, parse_query_string from require "lapis.util"

import encode_base64 from require "lapis.util.encoding"

class Stripe extends require "payments.base_client"
  api_url: "https://api.stripe.com/v1/"

  resource = (name, resource_opts={}) ->
    singular = resource_opts.singular or name\gsub "s$", ""
    api_path = resource_opts.path or name

    list_method = "list_#{name}"

    unless resource_opts.get == false
      @__base[list_method] or= (...) =>
        @_request "GET", api_path, ...

      @__base["each_#{singular}"] or= (...) =>
        @_iterate_resource @[list_method], ...

      @__base["get_#{singular}"] or= (id, ...) =>
        @_request "GET", "#{api_path}/#{id}", ...

    unless resource_opts.edit == false
      @__base["update_#{singular}"] or= (id, opts, ...) =>
        if resource_opts.update
          opts = resource_opts.update @, opts

        @_request "POST", "#{api_path}/#{id}", opts, ...

      @__base["delete_#{singular}"] or= (id) =>
        @_request "DELETE", "#{api_path}/#{id}"

      @__base["create_#{singular}"] or= (opts, ...) =>
        if resource_opts.create
          opts = resource_opts.create @, opts

        @_request "POST", api_path, opts, ...

  new: (opts) =>
    @client_id = assert opts.client_id, "missing client id"
    @client_secret = assert opts.client_secret, "missing client secret"
    @publishable_key = opts.publishable_key
    @stripe_account_id = opts.stripe_account_id
    @stripe_version = opts.stripe_version
    super opts

  for_account_id: (account_id) =>
    out = Stripe {
      client_id: @client_id
      client_secret: @client_secret
      publishable_key: @publishable_key
      stripe_account_id: account_id
      stripe_version: @stripe_version
      http_provider: @http_provider
    }

    out.http = @http

    out

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

    parse_url = require("socket.url").parse

    body = encode_query_string {
      :code
      client_secret: @client_secret
      grant_type: "authorization_code"
    }

    connect_url = "https://connect.stripe.com/oauth/token"

    _, status = assert @http!.request {
      url: connect_url
      method: "POST"
      sink: ltn12.sink.table out
      headers: {
        "Host": assert parse_url(connect_url).host, "failed to get host"
        "Content-Type": "application/x-www-form-urlencoded"
        "Content-length": body and tostring(#body) or nil
      }

      source: ltn12.source.string body
      protocol: @http_provider == "ssl.https" and "sslv23" or nil
    }

    out = table.concat out

    unless status == 200
      return nil, "got status #{status}: #{out}"

    json.decode out

  _request: (method, path, params, access_token=@client_secret, more_headers) =>
    out = {}

    if params
      for k,v in pairs params
        params[k] = tostring v

    body = if method != "GET"
      params and encode_query_string params

    parse_url = require("socket.url").parse

    headers = {
      "Host": assert parse_url(@api_url).host, "failed to get host"
      "Authorization": "Basic " .. encode_base64 access_token .. ":"
      "Content-Type": "application/x-www-form-urlencoded"
      "Content-length": body and tostring(#body) or nil
      "Stripe-Account": @stripe_account_id
      "Stripe-Version": @stripe_version
    }

    if more_headers
      for k,v in pairs more_headers
        headers[k] = v

    url = @api_url .. path
    if method == "GET" and params
      url ..= "?#{encode_query_string params}"

    _, status = @http!.request {
      :url
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

  _iterate_resource: (method, opts) =>
    last_id = opts and opts.starting_after

    coroutine.wrap ->
      while true
        iteration_opts = {
          limit: 50
          starting_after: last_id
        }

        if opts
          for k, v in pairs opts
            continue if k == "starting_after" -- don't copy over initial starting point
            iteration_opts[k] = v

        items = assert method @, iteration_opts

        for a in *items.data
          last_id = a.id
          coroutine.yield a

        break unless items.has_more
        break unless last_id

  resource "accounts", {
    create: (opts) =>
      opts.managed = true if opts.managed == nil
      assert opts.country, "missing country"
      assert opts.email, "missing country"

      opts
  }

  resource "customers"

  resource "charges"
  resource "disputes", edit: false
  resource "refunds", edit: false
  resource "transfers", edit: false
  resource "balance_transactions", edit: false, path: "balance/history"
  resource "application_fees", edit: false
  resource "events", edit: false
  resource "bitcoin_receivers", edit: false, path: "bitcoin/receivers"

  resource "products"
  resource "plans"
  resource "subscriptions"
  resource "invoices", edit: false
  resource "upcoming_invoices", edit: false, path: "invoices/upcoming"
  resource "coupons"

  -- NOTE: this is deprecated method, use the create_charge method part of the charges resource
  -- NOTE: how fee is renamed to application_fee
  -- NOTE: how access_token is extracted
  -- charge a card with amount cents
  charge: (opts) =>
    {
      :access_token, :card, :customer, :source, :amount, :currency,
      :description, :fee
    } = opts

    assert tonumber(amount), "missing amount"

    application_fee = if fee and fee > 0 then fee

    @_request "POST", "charges", {
      :card, :customer, :source, :amount, :description, :currency,
      :application_fee
    }, access_token

  create_card: (customer_id, opts) =>
    @_request "POST", "customers/#{customer_id}/sources", opts

  update_card: (customer_id, card_id, opts) =>
    @_request "POST", "customers/#{customer_id}/sources/#{card_id}", opts

  get_card: (customer_id, card_id, opts) =>
    @_request "GET", "customers/#{customer_id}/sources/#{card_id}", opts

  delete_customer_card: (customer_id, card_id, opts) =>
    @_request "DELETE", "customers/#{customer_id}/sources/#{card_id}", opts

  get_token: (token_id) =>
    @_request "GET", "tokens/#{token_id}"

  refund_charge: (charge_id) =>
    @_request "POST", "refunds", {
      charge: charge_id
    }

  mark_fraud: (charge_id) =>
    @_request "POST", "charges/#{charge_id}", {
      "fraud_details[user_report]": "fraudulent"
    }

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
    assert @client_secret\match("^sk_test_"), "can only fill account in test"

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

  create_checkout_session: (opts) =>
    @_request "POST", "checkout/sessions", opts


{ :Stripe }
