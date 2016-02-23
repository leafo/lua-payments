
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

    it "makes pay request", ->
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

      assert_shape request, types.shape {
        method: "POST"
        url: "https://svcs.sandbox.paypal.com/AdaptivePayments/Pay"
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
      }, open: true

      params = extract_params request.source!

      assert_shape params, types.shape {
        actionType: "PAY"
        feesPayer: "PRIMARYRECEIVER"
        currencyCode: "EUR"
        cancelUrl: "http://leafo.net/cancel"
        returnUrl: "http://leafo.net/return"

        "requestEnvelope.errorLanguage": "en_US"
        "clientDetails.applicationId": "APP-1234HELLOWORLD",
        "receiverList.receiver(0).amount": "5.50",
        "receiverList.receiver(0).email": "me@example.com",
        "receiverList.receiver(0).primary": "true",
        "receiverList.receiver(1).amount": "1.50"
        "receiverList.receiver(1).email": "you@example.com",
      }

