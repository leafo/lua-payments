import types from require "tableshape"
import make_http, assert_shape, url_shape, query_string_shape from require "spec.helpers"

import parse_query_string, to_json from require "lapis.util"

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

    -- create a test case where whatver is called in fn creates a single http
    -- request that matches what is described in opts
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
        ltn12 = require "ltn12"

        -- if api_response is a function then it call it once per http request
        -- using pump.step. Use a coroutine.wrap to output multiple responses
        switch type(api_response)
          when "function"
            ltn12.pump.step api_response, req.sink
          else
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

      -- creates basic charge
      api_request {
        method: "POST"
        path: "/charges"
        body: {
          card: "x_card"
          amount: "500"
          currency: "USD"
          application_fee: "200"
          description: "test charge"
          "metadata[purchase_id]": "hello world"
        }
      }, ->
        stripe\create_charge {
          card: "x_card"
          amount: 500
          currency: "USD"
          application_fee: 200
          description: "test charge"
          "metadata[purchase_id]": "hello world"
        }

      -- creates charge with custom access token
      api_request {
        method: "POST"
        path: "/charges"
        headers: {
          Authorization: "Basic eF9zZWxsZXJfdG9rOg=="
        }
        body: {
          card: "x_card"
          amount: "500"
          currency: "USD"
          application_fee: "200"
          description: "test charge"
        }
      }, ->
        stripe\create_charge {
          card: "x_card"
          amount: 500
          currency: "USD"
          application_fee: 200
          description: "test charge"
        }, "x_seller_tok"

      -- creates charge with deprecated charge method
      -- note: application_fee is passed as fee
      -- note: access_token can be passed in to the opts, instead of argument
      api_request {
        method: "POST"
        path: "/charges"
        headers: {
          Authorization: "Basic eF9zZWxsZXJfdG9rOg=="
        }
        body: {
          card: "x_card"
          amount: "500"
          currency: "USD"
          application_fee: "200"
          description: "test charge"
        }
      }, ->
        stripe\charge {
          access_token: "x_seller_tok"
          card: "x_card"
          amount: 500
          currency: "USD"
          fee: 200
          description: "test charge"
        }

      describe "each_charge", ->
        it "iterates through empty result", ->
          api_response = coroutine.wrap ->
            coroutine.yield to_json {
              has_more: false
              data: {}
            }

          count = 0
          for charge in stripe\each_charge!
            count += 1

          assert.same 0, count

          assert_shape http_requests, types.shape {
            types.partial {
              method: "GET"
              url: url_shape {
                scheme: "https"
                query: query_string_shape {
                  limit: "50"
                }
              }
            }
          }

        it "iterates through result with one page with initial params", ->
          api_response = coroutine.wrap ->
            coroutine.yield to_json {
              has_more: false
              data: {
                { id: "ch_one" }
                { id: "ch_two" }
              }
            }

          results = [charge for charge in stripe\each_charge limit: 5]

          assert.same {
            { id: "ch_one" }
            { id: "ch_two" }
          }, results

          assert_shape http_requests, types.shape {
            types.partial {
              method: "GET"
              url: url_shape {
                scheme: "https"
                query: query_string_shape {
                  limit: "5"
                }
              }
            }
          }

        it "iterates through multiple pages", ->
          api_response = coroutine.wrap ->
            coroutine.yield to_json {
              has_more: true
              data: {
                { id: "ch_one" }
                { id: "ch_two" }
              }
            }

            coroutine.yield to_json {
              has_more: false
              data: {
                { id: "ch_three" }
                { id: "ch_four" }
              }
            }

          results = [charge for charge in stripe\each_charge limit: 100]
          assert.same {
            { id: "ch_one" }
            { id: "ch_two" }
            { id: "ch_three" }
            { id: "ch_four" }
          }, results

          assert_shape http_requests, types.shape {
            types.partial {
              method: "GET"
              url: url_shape {
                scheme: "https"
                query: query_string_shape {
                  limit: "100"
                }
              }
            }

            types.partial {
              method: "GET"
              url: url_shape {
                scheme: "https"
                query: query_string_shape {
                  limit: "100"
                  starting_after: "ch_two"
                }
              }
            }

          }

        it "iterates through multiple pages with initial starting_after", ->
          api_response = coroutine.wrap ->
            coroutine.yield to_json {
              has_more: true
              data: {
                { id: "ch_one" }
                { id: "ch_two" }
              }
            }

            coroutine.yield to_json {
              has_more: false
              data: {
                { id: "ch_three" }
                { id: "ch_four" }
              }
            }

          results = [charge for charge in stripe\each_charge starting_after: "ch_zero"]
          assert.same {
            { id: "ch_one" }
            { id: "ch_two" }
            { id: "ch_three" }
            { id: "ch_four" }
          }, results

          assert_shape http_requests, types.shape {
            types.partial {
              method: "GET"
              url: url_shape {
                scheme: "https"
                query: query_string_shape {
                  limit: "50"
                  starting_after: "ch_zero"
                }
              }
            }

            types.partial {
              method: "GET"
              url: url_shape {
                scheme: "https"
                query: query_string_shape {
                  limit: "50"
                  starting_after: "ch_two"
                }
              }
            }

          }


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



