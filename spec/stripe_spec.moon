import types from require "tableshape"
import extract_params, make_http, assert_shape from require "spec.helpers"

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

    before_each ->
      import Stripe from require "payments.stripe"
      http_fn, http_requests = make_http (req) ->
        req.sink '{"hello": "world"}'

      stripe = assert Stripe {
        client_id: "client_id"
        client_secret: "client_secret"
      }
      stripe.http = http_fn

    it "get_charges", ->
      assert.same {
        {hello: "world"}
        200
      }, {
        stripe\get_charges!
      }

      req = assert http_requests[1]

      req_shape = types.shape {
        method: "GET"
        url: "https://api.stripe.com/v1/charges"
        sink: types.function

        headers: types.shape {
          "Host": "api.stripe.com"
          "Content-Type": "application/x-www-form-urlencoded"
          "Authorization": "Basic Y2xpZW50X3NlY3JldDo="
        }
      }

      assert req_shape req


