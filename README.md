# Lua Payments

Bindings to various payment provider APIs for use in Lua (with OpenResty or
anything that supports LuaSocket)


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



