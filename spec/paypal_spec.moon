
import types from require "tableshape"
import parse_query_string from require "lapis.util"
import extract_params, make_http, assert_shape from require "spec.helpers"

describe "paypal", ->
  describe "express checkout", ->
    local http_requests, http_fn

    before_each ->
      http_fn, http_requests = make_http!

    describe "with client", ->
      local paypal

      assert_request = ->
        assert.same 1, #http_requests

        assert_shape http_requests[1], types.shape {
          method: "POST"
          url: "https://api-3t.sandbox.paypal.com/nvp"
          source: types.function
          sink: types.function
          headers: types.shape {
            Host: "api-3t.sandbox.paypal.com"
            "Content-type": "application/x-www-form-urlencoded"
            "Content-length": types.number
          }
        }

        http_requests[1]

      assert_params = (request, shape) ->
        assert request.source, "missing source"
        params = {k,v for k,v in pairs parse_query_string request.source! when type(k) == "string"}
        assert_shape params, shape

      before_each ->
        import PayPalExpressCheckout from require "payments.paypal"
        paypal = PayPalExpressCheckout {
          sandbox: true

          auth: {
            USER: "me_1212121.leafo.net"
            PWD: "123456789"
            SIGNATURE: "AABBBC_CCZZZXXX"
          }
        }

        paypal.http = http_fn

      it "call sets_express_checkout", ->
        paypal\set_express_checkout {
          returnurl: "http://leafo.net/success"
          cancelurl: "http://leafo.net/cancel"
          brandname: "Purchase something"
          paymentrequest_0_amt: "$5.99"
        }

        request = assert_request!
        assert_params request, types.shape {
          PAYMENTREQUEST_0_AMT: "$5.99"
          CANCELURL: "http://leafo.net/cancel"
          RETURNURL: "http://leafo.net/success"
          BRANDNAME: "Purchase something"
          PWD: "123456789"
          SIGNATURE: "AABBBC_CCZZZXXX"
          USER: "me_1212121.leafo.net"
          VERSION: "98"
          METHOD: "SetExpressCheckout"
        }

      it "gets checkout url", ->
        out = paypal\checkout_url "toekn-abc123"


