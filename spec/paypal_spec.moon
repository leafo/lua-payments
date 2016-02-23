
import types from require "tableshape"
import parse_query_string from require "lapis.util"

assert_shape = (obj, shape) ->
  assert shape obj

extract_params = (str) ->
  params = assert parse_query_string str
  {k,v for k,v in pairs params when type(k) == "string"}

make_http = ->
  http_requests = {}
  fn = =>
    @http_provider = "test"
    {
      request: (req) ->
        table.insert http_requests, req
        1, 200, {}
    }

  fn, http_requests

describe "paypal", ->
  describe "adaptive payments", ->
    local http_requests, http_fn

    before_each ->
      http_fn, http_requests = make_http!

    describe "with client", ->
      local paypal

      assert_request = (request, req_shape, params_shape) ->
        assert request, "missing request"

        test_req_shape = {
          headers: types.shape {
            Host: "svcs.sandbox.paypal.com"
            "X-PAYPAL-RESPONSE-DATA-FORMAT": "NV"
            "X-PAYPAL-APPLICATION-ID": "APP-1234HELLOWORLD"
            "X-PAYPAL-SECURITY-USERID": "me_1212121.leafo.net"
            "X-PAYPAL-SECURITY-SIGNATURE": "AABBBC_CCZZZXXX"
            "X-PAYPAL-SECURITY-PASSWORD": "123456789"
            "Content-length": types.number
            "X-PAYPAL-REQUEST-DATA-FORMAT": "NV"
          }
        }

        if req_shape
          for k,v in pairs req_shape
            test_req_shape[k] = v

        assert_shape request, types.shape test_req_shape, open: true

        if params_shape
          params = extract_params request.source!
          assert_shape params, params_shape

      before_each ->
        import PayPalAdaptive from require "payments.paypal"
        paypal = PayPalAdaptive {
          sandbox: true
          application_id: "APP-1234HELLOWORLD"
          auth: {
            USER: "me_1212121.leafo.net"
            PWD: "123456789"
            SIGNATURE: "AABBBC_CCZZZXXX"
          }
        }
        paypal.http = http_fn

      it "makes pay request", ->
        paypal\pay {
          cancelUrl: "http://leafo.net/cancel"
          returnUrl: "http://leafo.net/return"
          currencyCode: "EUR"
          receivers: {
            {
              email: "me@example.com"
              amount: "5.50"
              primary: true
            },
            {
              email: "you@example.com"
              amount: "1.50"
            }
          }
        }

        assert.same 1, #http_requests
        request = http_requests[1]

        assert_request request, {
          method: "POST"
          url: "https://svcs.sandbox.paypal.com/AdaptivePayments/Pay"
        }, types.shape {
          actionType: "PAY"
          feesPayer: "PRIMARYRECEIVER"
          currencyCode: "EUR"
          cancelUrl: "http://leafo.net/cancel"
          returnUrl: "http://leafo.net/return"

          "requestEnvelope.errorLanguage": "en_US"
          "clientDetails.applicationId": "APP-1234HELLOWORLD"
          "receiverList.receiver(0).amount": "5.50"
          "receiverList.receiver(0).email": "me@example.com"
          "receiverList.receiver(0).primary": "true"
          "receiverList.receiver(1).amount": "1.50"
          "receiverList.receiver(1).email": "you@example.com"
        }

      it "makes convert currency request", ->
        paypal\convert_currency "5.00", "USD", "EUR"
        assert_request http_requests[1], {
          method: "POST"
          url: "https://svcs.sandbox.paypal.com/AdaptivePayments/ConvertCurrency"
        }, types.shape {
          "requestEnvelope.errorLanguage": "en_US"
          "clientDetails.applicationId": "APP-1234HELLOWORLD"

          "baseAmountList.currency(0).code": "USD"
          "baseAmountList.currency(0).amount": "5.00"
          "convertToCurrencyList.currencyCode": "EUR"
        }

      it "makes refund request", ->
        paypal\refund "my-key-1000"

        assert_request http_requests[1], {
          method: "POST"
          url: "https://svcs.sandbox.paypal.com/AdaptivePayments/Refund"
        }, types.shape {
          "requestEnvelope.errorLanguage": "en_US"
          "clientDetails.applicationId": "APP-1234HELLOWORLD"
          payKey: "my-key-1000"
        }



      it "creates checkout url", ->
        assert.same "https://www.sandbox.paypal.com/webscr?cmd=_ap-payment&paykey=hello-world", paypal\checkout_url "hello-world"


