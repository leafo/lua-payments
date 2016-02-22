local PayPalAdaptive
do
  local _class_0
  local _parent_0 = require("payments.base_client")
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
      local body = encode_query_string(params)
      if not (ngx) then
        local parse_url = require("socket.url").parse
        local host = assert(parse_url(self.api_url).host)
        headers["Host"] = host
        headers["Content-length"] = #body
      end
      if debug then
        local moon = require("moon")
        io.stdout:write(tostring(action) .. ":\n")
        io.stdout:write("Params:\n")
        io.stdout:write(moon.dump(params))
      end
      local out = { }
      local _, code, res_headers = assert(http.request({
        headers = headers,
        url = tostring(self.api_url) .. "/" .. tostring(action),
        source = ltn12.source.string(body),
        method = "POST",
        sink = ltn12.sink.table(out),
        protocol = not ngx and "sslv23" or nil
      }))
      local text = concat(out)
      local res = parse_query_string(text) or text
      if type(res) == "table" then
        strip_numeric(res)
      end
      if debug then
        local moon = require("moon")
        io.stdout:write("RESPONSE " .. tostring(action) .. ":\n")
        io.stdout:write(moon.dump({
          res = res,
          res_headers = res_headers
        }))
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
    convert_currency = function(self, amount, source, dest)
      if source == nil then
        source = "USD"
      end
      if dest == nil then
        dest = "AUD"
      end
      return self:_method("AdaptivePayments/ConvertCurrency", extend({
        ["requestEnvelope.errorLanguage"] = "en_US",
        ["baseAmountList.currency(0).code"] = source,
        ["baseAmountList.currency(0).amount"] = tostring(amount),
        ["convertToCurrencyList.currencyCode"] = dest
      }))
    end,
    refund = function(self, pay_key, params)
      return self:_method("AdaptivePayments/Refund", extend({
        payKey = pay_key,
        ["requestEnvelope.errorLanguage"] = "en_US"
      }, params))
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
    calculate_fee = function(self, ...)
      return calculate_fee(...)
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
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
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
    __name = "PayPalAdaptive",
    __parent = _parent_0
  }, {
    __index = function(cls, name)
      local val = rawget(_base_0, name)
      if val == nil then
        local parent = rawget(cls, "__parent")
        if parent then
          return parent[name]
        end
      else
        return val
      end
    end,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  PayPalAdaptive = _class_0
  return _class_0
end
