package = "payments"
version = "dev-1"

source = {
  url = "git://github.com/leafo/lua-payments.git",
}

description = {
  summary = "Payment APIs for Lua, including Stripe & PayPal. Works with Openresty",
  homepage = "https://github.com/leafo/lua-payments",
  license = "MIT"
}

dependencies = {
  "lua >= 5.1",
  "lua-cjson",
  "luasocket",
  "luasec",
  "lapis", -- for encode_query_string
}

build = {
  type = "builtin",
  modules = {
    ["payments.amazon"] = "payments/amazon.lua",
    ["payments.base_client"] = "payments/base_client.lua",
    ["payments.paypal"] = "payments/paypal.lua",
    ["payments.paypal.adaptive"] = "payments/paypal/adaptive.lua",
    ["payments.paypal.express_checkout"] = "payments/paypal/express_checkout.lua",
    ["payments.paypal.helpers"] = "payments/paypal/helpers.lua",
    ["payments.paypal.rest"] = "payments/paypal/rest.lua",
    ["payments.stripe"] = "payments/stripe.lua",
  }
}

