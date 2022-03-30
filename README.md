# Lua Payments

![test](https://github.com/leafo/lua-payments/workflows/test/badge.svg)

Bindings to various payment provider APIs for use in Lua (with OpenResty via
Lapis or anything that supports LuaSocket or
[cqueues](http://www.25thandclement.com/~william/projects/cqueues.html) with
[lua-http](https://github.com/daurnimator/lua-http))

The following APIs are supported:

* [Stripe](#stripe)
* [PayPal Express Checkout](#paypal-express-checkout)
* [PayPal REST](#paypal-rest-api)
* [PayPal Adaptive Payments](#paypal-adaptive-payments)

## Install

    luarocks install payments

## Examples


### PayPal Rest API

Create the API client:

```lua
local paypal = require("payments.paypal")

local client = paypal.PayPalRest({
  sandbox = true,
  client_id = "AVP_0123445",
  secret = "EFAAAAEFE-HELLO-WORLD",
})
```

Fetch some data:

```lua
local payments = client:payment_resources()
```

Create a new payment:


```lua
local res, status = client:create_payment({
  intent = "sale",
  payer = {
    payment_method: "paypal"
  },
  transactions = {
    {
      description = "My thinger",
      invoice_number = "P-1291829281",

      amount = {
        total = "5.99"
        currency = "USD"
      }
    }
  },
  redirect_urls = {
    return_url = "http://example.com/confirm-payment",
    cancel_url = "http://example.com/cancel-payment"
  }
})
```


**Note:** This currently uses the PayPal V1 REST API. You can force calls to go
to V2 by adjusting the following field on your client instance:

```lua
client.api_version = "v2"
client:create_checkout_order({...})
```


### Stripe

Create the API client:

```lua

local Stripe = require("payments.stripe").Stripe

local client = Stripe({
  client_id = "ca_12345",
  client_secret = "sk_test_helloworld",
  publishable_key = "pk_test_blahblahblahb"
})
```

Fetch some data:

```lua

-- each resource exposed by Stripe API has a respective list_, get_, and each_
-- method in this library:

local result = client:list_charges()
local result = client:list_accounts({ limit = "100 "})
local result = client:list_disputes({ starting_after = "dsp_12343" })

-- get a single item
local result = client:get_customer("cust_12o323480")

-- iterate through every refund, fetching each page as needed
for refund in client:each_refund() do
  print(refund.id)
end
```

Create a charge:

```lua
local result, err = client:charge({
  card = "tok_232u302"
  amount = "5.99",
  currency = "USD",
  description = "indie games"
})
```

Resouces can be created, updated, and deleted:

```lua

local customer = client:create_customer({
  email = "loaf@itch.zone"
})

client:update_customer(customer.id, {
  account_balance = 23023
})

client:delete_customer(customer.id)

```

### PayPal Express Checkout

Create the API client:

```lua
local paypal = require("payments.paypal")

local client = paypal.PayPalExpressCheckout({
  sandbox = true,
  auth = {
    USER = "me_1212121.leafo.net",
    PWD = "123456789",
    SIGNATURE = "AABBBC_CCZZZXXX"
  }
})
```

Create a new purchase page:

```lua
local res = assert(client:set_express_checkout({
  returnurl = "http://leafo.net/success",
  cancelurl = "http://leafo.net/cancel",
  brandname = "Purchase something",
  paymentrequest_0_amt = "$5.99"
}))


-- redirect the buyer to the payment page:
print(client:checkout_url(res.TOKEN))
```


### PayPal Adaptive Payments

> **Note:** This is a legacy API now deprecated by PayPal. You probably don't want to be using this.

Create the API client:

```lua
local paypal = require("payments.paypal")

local client = paypal.PayPalAdaptive({
  sandbox = true,
  application_id = "APP-1234HELLOWORLD",
  auth = {
    USER = "me_1212121.leafo.net",
    PWD = "123456789",
    SIGNATURE = "AABBBC_CCZZZXXX"
  }
})
```

Create a new purchase page:


```lua
local res = assert(client:pay({
  cancelUrl = "http://leafo.net/cancel",
  returnUrl = "http://leafo.net/return",
  currencyCode = "EUR",
  receivers = {
    {
      email = "me@example.com",
      amount = "5.50",
      primary = true,
    },
    {
      email = "you@example.com",
      amount = "1.50",
    }
  }
}))

-- configure the checkout page
assert(client:set_payment_options(res.payKey, {
  ["displayOptions.businessName"] = "My adaptive store front"
}))

-- redirect the buyer to the payment page:
print(client:checkout_url(res.payKey))

-- after completion, you can check the payment status
local details = assert(client:payment_details(res.payKey))

```


## HTTP Client

All of the APIs exposed here are powered by HTTP. This client supports using
different HTTP client libraries depending on the environment.

If `ngx` is available in the global scope then Lapis' HTTP library is used by
default.  This will give you non-blocking requests within nginx. Otherwise,
LuaSec and LuaSocket are used.

You can manually set the client by passing a `http_provider` parameter to any
of the client constructors. For example, to use cqueues pass
`"http.compat.socket"` as the provider:

```lua
local Stripe = require("payments.stripe").Stripe

local client = Stripe({
  http_provider = "http.compat.socket",
  -- ...
})
```

## License

MIT, Copyright (C) 2022 by Leaf Corcoran
