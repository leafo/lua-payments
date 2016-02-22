local debug = false
local http
if ngx then
  http = require("lapis.nginx.http")
else
  http = require("ssl.https")
end
local ltn12 = require("ltn12")
local json = require("cjson")
local encode_query_string, parse_query_string
do
  local _obj_0 = require("lapis.util")
  encode_query_string, parse_query_string = _obj_0.encode_query_string, _obj_0.parse_query_string
end
local assert_error
assert_error = require("lapis.application").assert_error
local concat
concat = table.concat
local sandbox = {
  USER = "sdk-three_api1.sdk.com",
  PWD = nil,
  SIGNATURE = nil,
  VERSION = "98"
}
local extend
extend = function(a, ...)
  local _list_0 = {
    ...
  }
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    if t then
      for k, v in pairs(t) do
        a[k] = v
      end
    end
  end
  return a
end
local upper_keys
upper_keys = function(t)
  if t then
    local _tbl_0 = { }
    for k, v in pairs(t) do
      _tbl_0[type(k) == "string" and k:upper() or k] = v
    end
    return _tbl_0
  end
end
local strip_numeric
strip_numeric = function(t)
  for k, v in ipairs(t) do
    t[k] = nil
  end
  return t
end
local valid_amount
valid_amount = function(str)
  if str:match("%d+%.%d%d") then
    return true
  end
  return nil, "invalid amount (" .. tostring(str) .. ")"
end
local format_price
format_price = function(cents, currency)
  if currency == nil then
    currency = "USD"
  end
  if currency == "JPY" then
    return tostring(math.floor(cents))
  else
    local dollars = math.floor(cents / 100)
    local change = ("%02d"):format(cents % 100)
    return tostring(dollars) .. "." .. tostring(change)
  end
end
local calculate_fee
calculate_fee = function(currency, transactions_count, amount, medium)
  if not (medium == "default") then
    error("don't know how to calculate paypal fee for medium " .. tostring(medium))
  end
  local _exp_0 = currency
  if "USD" == _exp_0 or "CAD" == _exp_0 or "AUD" == _exp_0 then
    return transactions_count * 30 + math.floor(amount * 0.029)
  elseif "GBP" == _exp_0 then
    return transactions_count * 20 + math.floor(amount * 0.034)
  elseif "EUR" == _exp_0 then
    return transactions_count * 35 + math.floor(amount * 0.019)
  elseif "JPY" == _exp_0 then
    return transactions_count * 40 + math.floor(amount * 0.036)
  else
    return nil, "don't know how to calculate Paypal fee for currency " .. tostring(currency)
  end
end
return {
  PayPalAdaptive = require("payments.paypal.adaptive"),
  PayPalRest = require("payments.paypal.rest"),
  PayPalClassic = require("payments.paypal.classic")
}
