import types from require "tableshape"
import extract_params, make_http, assert_shape from require "spec.helpers"

import parse_query_string from require "lapis.util"

assert_shape = (obj, shape) ->
  assert shape obj

describe "stripe", ->
  it "creates a stripe object", ->
    import Stripe from require "payments.stripe"
    stripe = assert Stripe {
      client_id: "client_id"
      client_secret: "client_secret"
      publishable_key: "publishable_key"
    }

  describe "with client", ->
    local stripe, http_requests, http_fn
    local api_response

    api_request = (opts={}, fn) ->
      method = opts.method or "GET"
      spec_name = opts.name or "#{method} #{opts.path}"

      it spec_name, ->
        response = { fn! }

        assert.same {
          opts.response_object or {hello: "world"}
          200
        }, response

        req = assert http_requests[#http_requests], "expected http request"

        headers = {
          "Host": "api.stripe.com"
          "Content-Type": "application/x-www-form-urlencoded"
          "Content-length": opts.body and types.pattern "%d+"
          "Authorization": "Basic Y2xpZW50X3NlY3JldDo="
        }

        if opts.headers
          for k,v in pairs opts.headers
            headers[k] = v

        assert_shape req, types.shape {
          :method
          url: "https://api.stripe.com/v1#{assert opts.path, "missing path"}"

          sink: types.function
          source: opts.body and types.function

          headers: types.shape headers
        }

        if opts.body
          source = req.source!
          source_data = parse_query_string source
          expected = {k,v for k,v in pairs source_data when type(k) == "string"}
          assert.same opts.body, expected

    before_each ->
      api_response = nil -- reset to default
      import Stripe from require "payments.stripe"
      http_fn, http_requests = make_http (req) ->
        req.sink api_response or '{"hello": "world"}'

      stripe = assert Stripe {
        client_id: "client_id"
        client_secret: "client_secret"
      }
      stripe.http = http_fn

    describe "with account", ->
      api_request {
        path: "/charges/hello_world"
        headers: {
          "Stripe-Account": "acct_one"
        }
      }, ->
        stripe\for_account_id("acct_one")\get_charge "hello_world"

    describe "disputes", ->
      api_request {
        path: "/disputes?limit=20"
      }, ->
        stripe\list_disputes {
          limit: 20
        }

    describe "charges", ->
      api_request {
        path: "/accounts"
      }, ->
        stripe\list_accounts!

      api_request {
        path: "/charges/cr_cool"
      }, ->
        stripe\get_charge "cr_cool"

    describe "accounts", ->
      api_request {
        path: "/accounts"
      }, ->
        stripe\list_accounts!

      api_request {
        path: "/accounts/act_leafo"
      }, ->
        stripe\get_account "act_leafo"

      api_request {
        method: "POST"
        path: "/accounts/act_leafo"
        body: {
          name: "boot zone"
        }
      }, ->
        stripe\update_account "act_leafo", {
          name: "boot zone"
        }

      api_request {
        method: "DELETE"
        path: "/accounts/act_cool"
      }, ->
        stripe\delete_account "act_cool"

      api_request {
        method: "POST"
        path: "/accounts"
        body: {
          email: "leafo@itch.zone"
          country: "ARCTIC"
          managed: "true"
        }
      }, ->
        stripe\create_account {
          email: "leafo@itch.zone"
          country: "ARCTIC"
        }

    describe "balance_transactions", ->
      api_request {
        method: "GET"
        path: "/balance/history/txn_hello"
      }, ->
        stripe\get_balance_transaction "txn_hello"

      api_request {
        method: "GET"
        path: "/balance/history"
      }, ->
        stripe\list_balance_transactions!



