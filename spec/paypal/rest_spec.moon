import types from require "tableshape"
import extract_params, make_http, assert_shape from require "spec.helpers"

describe "paypal", ->
  describe "rest", ->
    describe "with client", ->
      local paypal, http_requests, http_fn

      before_each ->
        import PayPalRest from require "payments.paypal"
        http_fn, http_requests = make_http (req) ->
          json = require "cjson"
          req.sink json.encode {
            access_token: "ACCESS_TOKEN"
            expires_in: 100
          }

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
        }) req

        assert.same {
          grant_type: "client_credentials"
        }, extract_params req.source!

      assert_api_requrest = (req, opts) ->
        assert (types.shape {
          method: opts.method
          sink: types.function
          url: opts.url
          headers: types.shape {
            Host: "api.paypal.com"
            Accept: "application/json"
            Authorization: "Bearer ACCESS_TOKEN"
            "Content-Type": "application/json"
            "Accept-Language": "en_US"
          }
        }) http_requests[2]

      it "makes request", ->
        paypal\get_payments!

        -- auth request, request for api call
        assert.same 2, #http_requests
        assert_oauth_token_request http_requests[1]

        assert_api_requrest http_requests[2], {
          method: "GET"
          url: "https://api.paypal.com/v1/payments/payment"
        }

      it "makes doesn't request oauth token twice", ->
        paypal\get_payments!
        paypal\get_payments!

        assert.same 3, #http_requests
        assert_oauth_token_request http_requests[1]

        for i=2,3
          assert_api_requrest http_requests[i], {
            method: "GET"
            url: "https://api.paypal.com/v1/payments/payment"
          }

      it "fetches new oauth token when expired", ->
        paypal\get_payments!
        paypal.last_token_time -= 200
        paypal\get_payments!

        assert.same 4, #http_requests
        assert_oauth_token_request http_requests[1]
        assert_oauth_token_request http_requests[3]
