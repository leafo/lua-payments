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
            "Content-length": "29"
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
          source: opts.body and types.function
          url: opts.url
          headers: types.shape {
            Host: "api.paypal.com"
            Accept: "application/json"
            Authorization: "Bearer ACCESS_TOKEN"
            "Content-Type": if req.method == "POST"
              "application/json"
            "Accept-Language": "en_US"
            "Content-length": types.pattern("%d+")\is_optional!
          }
        }) req

        if opts.body
          source = req.source!
          import from_json from require "lapis.util"
          assert.same opts.body, from_json(source)

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

      describe "api calls", ->
        -- stub oauth request
        before_each ->
          paypal.last_token = {
            access_token: "ACCESS_TOKEN"
            expires_in: 5000
          }
          paypal.last_token_time = os.time!
          paypal.access_token = paypal.last_token.access_token

        it "sale_transaction", ->
          paypal\sale_transaction "TRANSACTION_ID"

          assert.same 1, #http_requests
          assert_api_requrest http_requests[1], {
            method: "GET"
            url: "https://api.paypal.com/v1/payments/sale/TRANSACTION_ID"
          }

        it "payout", ->
          paypal\payout {
            email: "leafo@example.com"
            amount: paypal\format_price 100, "USD"
            currency: "USD"
          }

          assert.same 1, #http_requests
          assert_api_requrest http_requests[1], {
            method: "POST"
            url: "https://api.paypal.com/v1/payments/payouts?sync_mode=true"
            body: {
              sender_batch_header: {
                email_subject: "You got a payout"
              }
              items: {
                {
                  amount: {
                    currency: "USD",
                    value: "1.00"
                  }
                  receiver: "leafo@example.com",
                  recipient_type: "EMAIL",
                  note: "Payout"
                }
              }
            }
          }

