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
