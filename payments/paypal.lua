local debug = false
local http = require("lapis.nginx.http")
local ltn12 = require("ltn12")
local encode_query_string, parse_query_string
do
  local _obj_0 = require("lapis.util")
  encode_query_string, parse_query_string = _obj_0.encode_query_string, _obj_0.parse_query_string
end
local assert_error
do
  local _obj_0 = require("lapis.application")
  assert_error = _obj_0.assert_error
end
local concat
do
  local _obj_0 = table
  concat = _obj_0.concat
end
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
local PayPal
do
  local _base_0 = {
    api_url = "https://api-3t.sandbox.paypal.com/nvp",
    checkout_url = "https://www.sandbox.paypal.com/cgi-bin/webscr",
    _method = function(self, name, params)
      params.METHOD = name
      local out = { }
      for k, v in pairs(self.auth) do
        if not (params[k]) then
          params[k] = v
        end
      end
      if debug then
        require("moon")
        io.stdout:write(tostring(name) .. ":\n")
        io.stdout:write(moon.dump(params))
      end
      local _, code, res_headers = http.request({
        url = self.api_url,
        source = ltn12.source.string(encode_query_string(params)),
        method = "POST",
        sink = ltn12.sink.table(out)
      })
      local text = concat(out)
      local res = parse_query_string(text) or text
      if type(res) == "table" then
        strip_numeric(res)
      end
      return res, res_headers
    end,
    set_express_checkout = function(self, return_url, cancel_url, opts)
      return self:_method("SetExpressCheckout", extend({
        RETURNURL = return_url,
        CANCELURL = cancel_url
      }, upper_keys(opts)))
    end,
    get_express_checkout_details = function(self, token)
      return self:_method("GetExpressCheckoutDetails", {
        TOKEN = token
      })
    end,
    do_express_checkout = function(self, token, payerid, amount, opts)
      assert(valid_amount(amount))
      return self:_method("DoExpressCheckoutPayment", extend({
        TOKEN = token,
        PAYERID = payerid,
        PAYMENTREQUEST_0_AMT = amount
      }, upper_keys(opts)))
    end,
    pay_url = function(self, token)
      return tostring(self.checkout_url) .. "?cmd=_express-checkout&token=" .. tostring(token) .. "&useraction=commit"
    end,
    format_price = function(self, ...)
      return format_price(...)
    end
  }
  _base_0.__index = _base_0
  local _class_0 = setmetatable({
    __init = function(self, auth, api_url)
      self.api_url = api_url
      do
        local _tbl_0 = { }
        for k, v in pairs(sandbox) do
          _tbl_0[k] = v
        end
        self.auth = _tbl_0
      end
      if auth then
        for k, v in pairs(auth) do
          self.auth[k] = v
        end
      end
    end,
    __base = _base_0,
    __name = "PayPal"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  PayPal = _class_0
end
local Adaptive
do
  local _base_0 = {
    application_id = "APP-XXX",
    api_url = "https://svcs.sandbox.paypal.com",
    base_url = "www.sandbox.paypal.com",
    _method = function(self, action, params)
      local headers = {
        ["X-PAYPAL-SECURITY-USERID"] = self.user,
        ["X-PAYPAL-SECURITY-PASSWORD"] = self.password,
        ["X-PAYPAL-SECURITY-SIGNATURE"] = self.signature,
        ["X-PAYPAL-REQUEST-DATA-FORMAT"] = "NV",
        ["X-PAYPAL-RESPONSE-DATA-FORMAT"] = "NV",
        ["X-PAYPAL-APPLICATION-ID"] = self.application_id
      }
      params = extend({
        ["clientDetails.applicationId"] = self.application_id
      }, params)
      if debug then
        require("moon")
        io.stdout:write(tostring(action) .. ":\n")
        io.stdout:write("Params:\n")
        io.stdout:write(moon.dump(params))
      end
      local out = { }
      local _, code, res_headers = http.request({
        headers = headers,
        url = tostring(self.api_url) .. "/" .. tostring(action),
        source = ltn12.source.string(encode_query_string(params)),
        method = "POST",
        sink = ltn12.sink.table(out)
      })
      local text = concat(out)
      local res = parse_query_string(text) or text
      if type(res) == "table" then
        strip_numeric(res)
      end
      return res, res_headers
    end,
    pay = function(self, return_url, cancel_url, receivers, params)
      if receivers == nil then
        receivers = { }
      end
      assert(#receivers > 0, "there must be at least one receiver")
      params = extend({
        actionType = "PAY",
        currencyCode = "USD",
        feesPayer = (function()
          if #receivers > 1 then
            return "PRIMARYRECEIVER"
          end
        end)(),
        ["requestEnvelope.errorLanguage"] = "en_US",
        cancelUrl = cancel_url,
        returnUrl = return_url
      }, params)
      for i, r in ipairs(receivers) do
        i = i - 1
        for rk, rv in pairs(r) do
          params["receiverList.receiver(" .. tostring(i) .. ")." .. tostring(rk)] = tostring(rv)
        end
      end
      return self:_method("AdaptivePayments/Pay", params)
    end,
    payment_details = function(self, pay_key, params)
      return self:_method("AdaptivePayments/PaymentDetails", extend({
        payKey = pay_key,
        ["requestEnvelope.errorLanguage"] = "en_US"
      }, params))
    end,
    get_shipping_addresses = function(self, pay_key, params)
      return self:_method("AdaptivePayments/GetShippingAddresses", extend({
        key = pay_key,
        ["requestEnvelope.errorLanguage"] = "en_US"
      }, params))
    end,
    set_payment_options = function(self, pay_key, params)
      return self:_method("AdaptivePayments/SetPaymentOptions", extend({
        payKey = pay_key,
        ["requestEnvelope.errorLanguage"] = "en_US"
      }, params))
    end,
    pay_url = function(self, pay_key)
      return "https://" .. tostring(self.base_url) .. "/webscr?cmd=_ap-payment&paykey=" .. tostring(pay_key)
    end,
    format_price = function(self, ...)
      return format_price(...)
    end,
    check_success = function(self, res, msg)
      if res == nil then
        res = { }
      end
      if msg == nil then
        msg = "paypal failed"
      end
      if (res["responseEnvelope.ack"] or ""):lower() == "success" then
        return res
      else
        return nil, msg
      end
    end,
    assert_success = function(self, ...)
      return assert_error(self:check_success(...))
    end
  }
  _base_0.__index = _base_0
  local _class_0 = setmetatable({
    __init = function(self, auth)
      local params = extend({ }, sandbox, auth)
      self.user = params.USER
      self.password = params.PWD
      self.signature = params.SIGNATURE
      local _list_0 = {
        "api_url",
        "application_id",
        "base_url"
      }
      for _index_0 = 1, #_list_0 do
        local k = _list_0[_index_0]
        self[k] = params[k]
      end
    end,
    __base = _base_0,
    __name = "Adaptive"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Adaptive = _class_0
end
return {
  PayPal = PayPal,
  Adaptive = Adaptive
}
