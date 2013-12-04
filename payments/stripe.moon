
http = require "lapis.nginx.http"
ltn12 = require "ltn12"
json = require "cjson"

import encode_query_string, parse_query_string from require "lapis.util"

import encode_base64 from require "lapis.util.encoding"

class Stripe
  api_url: "https://api.stripe.com/v1/"

  new: (@client_id, @client_secret) =>

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

    http.request {
      url: "https://connect.stripe.com/oauth/token"
      method: "POST"
      sink: ltn12.sink.table out
      source: ltn12.source.string encode_query_string {
        :code
        client_secret: @client_secret
        grant_type: "authorization_code"
      }
    }

    out = table.concat out
    json.decode out

  -- charge a card with amount cents
  charge: (opts) =>
    { :access_token, :card, :amount, :currency, :description, :fee } = opts

    assert tonumber amount

    -- fee in cents
    application_fee = if fee and fee > 0
      amount * fee

    out = {}

    headers = {
      "Authorization": "Basic " .. encode_base64 access_token .. ":"
      "Content-Type": "application/x-www-form-urlencoded"
    }

    status = http.request {
      url: @api_url .. "charges"
      method: "POST"
      :headers
      sink: ltn12.sink.table out
      source: ltn12.source.string encode_query_string {
        :card, :amount, :description, :currency, :application_fee
      }
    }

    json.decode table.concat out

{ :Stripe }
