import types from require "tableshape"
import extract_params, make_http, assert_shape from require "spec.helpers"

describe "paypal", ->
  describe "rest", ->
    describe "with client", ->
      local paypal, http_requests, http_fn

      before_each ->
        import PayPalRest from require "payments.paypal"
        http_fn, http_requests = make_http (req) ->
          req.sink '{"access_token": "ACCESS_TOKEN"}'

        paypal = PayPalRest {
          client_id: "123"
          secret: "shh"
        }

        paypal.http = http_fn

      assert_oauth_token_request = (req) ->
        assert (types.shape {
          method: "POST"
          source: types.function
          sink: types.function
          url: "https://api.paypal.com/v1/oauth2/token"
          headers: types.shape {
            Host: "api.paypal.com"
            Accept: "application/json"
            Authorization: "Basic MTIzOnNoaA=="
            "Content-length": 29
            "Content-Type": "application/x-www-form-urlencoded"
            "Accept-Language": "en_US"
          }
        }) http_requests[1]

        assert.same {
          grant_type: "client_credentials"
        }, extract_params http_requests[1].source!

      it "makes request", ->
        paypal\payment_resources!

        -- auth request, request for api call
        assert.same 2, #http_requests
        assert_oauth_token_request http_requests[1]


        assert (types.shape {
          method: "GET"
          sink: types.function
          url: "https://api.paypal.com/v1/payments/payment/"
          headers: types.shape {
            Host: "api.paypal.com"
            Accept: "application/json"
            Authorization: "Bearer ACCESS_TOKEN"
            "Content-Type": "application/json"
            "Accept-Language": "en_US"
          }
        }) http_requests[2]


