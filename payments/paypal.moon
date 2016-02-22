debug = false

http = if ngx
  require "lapis.nginx.http"
else
  require "ssl.https"


ltn12 = require "ltn12"
json = require "cjson"

import encode_query_string, parse_query_string  from require "lapis.util"
import assert_error from require "lapis.application"
import concat from table

sandbox = {
  USER: "sdk-three_api1.sdk.com"
  PWD: nil
  SIGNATURE: nil
  VERSION: "98" -- 2013-Feb-01
}

extend = (a, ...) ->
  for t in *{...}
    if t
      a[k] = v for k,v in pairs t
  a

upper_keys = (t) ->
  if t
    { type(k) == "string" and k\upper! or k, v for k,v in pairs t }

strip_numeric = (t) ->
  for k,v in ipairs t
    t[k] = nil
  t

valid_amount = (str) ->
  return true if str\match "%d+%.%d%d"
  nil, "invalid amount (#{str})"

format_price = (cents, currency="USD") ->
  if currency == "JPY"
    tostring math.floor cents
  else
    dollars = math.floor cents / 100
    change = "%02d"\format cents % 100
    "#{dollars}.#{change}"

calculate_fee = (currency, transactions_count, amount, medium) ->
  unless medium == "default"
    error "don't know how to calculate paypal fee for medium #{medium}"

  switch currency
    -- AUD is wrong, but it's too complicated so w/e
    when "USD", "CAD", "AUD"
      -- 2.9% + $0.30 per transaction
      -- https://www.paypal.com/us/webapps/mpp/merchant-fees
      transactions_count * 30 + math.floor(amount * 0.029)
    when "GBP"
      -- 3.4% + 20p per transaction
      -- https://www.paypal.com/gb/webapps/mpp/merchant-fees
      transactions_count * 20 + math.floor(amount * 0.034)
    when "EUR"
      -- FIXME: this is wrong - that info comes from the page for
      -- Germany. France for example is 3.4% + 0.25€, there's tons
      -- of edge cases, welcome to Europe. - amos

      -- 1.9% + 0.35€ per transaction
      -- https://www.paypal.com/de/webapps/mpp/merchant-fees
      transactions_count * 35 + math.floor(amount * 0.019)
    when "JPY"
      -- 3.6% + 40円 per transaction
      -- https://www.paypal.com/jp/webapps/mpp/merchant-fees
      transactions_count * 40 + math.floor(amount * 0.036)
    else
      nil, "don't know how to calculate Paypal fee for currency #{currency}"


{
  PayPalAdaptive: require "payments.paypal.adaptive"
  PayPalRest: require "payments.paypal.rest"
  PayPalClassic: require "payments.paypal.classic"
}
