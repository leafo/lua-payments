import types from require "tableshape"
import extract_params, make_http, assert_shape from require "spec.helpers"

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
      spec_name = assert opts.name or opts.path, "missing spec name"
      it spec_name, ->
        response = { fn! }

        assert.same {
          opts.response_object or {hello: "world"}
          200
        }, response

        req = assert http_requests[#http_requests], "expected http request"

        assert_shape req, types.shape {
          method: opts.method or "GET"
          url: "https://api.stripe.com/v1#{assert opts.path, "missing path"}"

          sink: types.function

          headers: types.shape {
            "Host": "api.stripe.com"
            "Content-Type": "application/x-www-form-urlencoded"
            "Authorization": "Basic Y2xpZW50X3NlY3JldDo="
          }
        }

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

