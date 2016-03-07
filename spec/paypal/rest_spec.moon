import types from require "tableshape"
import extract_params, make_http, assert_shape from require "spec.helpers"

describe "paypal", ->
  describe "rest", ->
    describe "with client", ->
      local paypal, http_requests, http_fn

      before_each ->
        import PayPalRest from require "payments.paypal"
        http_fn, http_requests = make_http (req) ->
          req.sink '{"access_token": "1235"}'

        paypal = PayPalRest {
          client_id: "123"
          secret: "shh"
        }

        paypal.http = http_fn

      it "makes request", ->
        paypal\payment_resources!
        assert.same 2, #http_requests
