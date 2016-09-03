# Lua Payments

[![Build Status](https://travis-ci.org/leafo/lua-payments.svg?branch=master)](https://travis-ci.org/leafo/lua-payments)

Bindings to various payment provider APIs for use in Lua (with OpenResty or
anything that supports LuaSocket)

The following APIs are supported:

* Stripe
* PayPal Express Checkout
* PayPal Adaptive Payments
* PayPal REST

## Examples

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
  returnurl: "http://leafo.net/success"
  cancelurl: "http://leafo.net/cancel"
  brandname: "Purchase something"
  paymentrequest_0_amt: "$5.99"
}))


-- redirect the buyer to the payment page:
print(client:checkout_url(res.TOKEN))
```


### PayPal Adaptive Payments

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


