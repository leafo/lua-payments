local concat
concat = table.concat
local types
types = require("tableshape").types
local extend, strip_numeric, format_price
do
  local _obj_0 = require("payments.paypal.helpers")
  extend, strip_numeric, format_price = _obj_0.extend, _obj_0.strip_numeric, _obj_0.format_price
end
local encode_query_string, parse_query_string
do
  local _obj_0 = require("lapis.util")
  encode_query_string, parse_query_string = _obj_0.encode_query_string, _obj_0.parse_query_string
end
local ltn12 = require("ltn12")
local PayPalAdaptive
do
  local _class_0
  local _parent_0 = require("payments.base_client")
  local _base_0 = {
    _method = function(self, action, params)
      local headers = {
        ["X-PAYPAL-SECURITY-USERID"] = self.auth.USER,
        ["X-PAYPAL-SECURITY-PASSWORD"] = self.auth.PWD,
        ["X-PAYPAL-SECURITY-SIGNATURE"] = self.auth.SIGNATURE,
        ["X-PAYPAL-REQUEST-DATA-FORMAT"] = "NV",
        ["X-PAYPAL-RESPONSE-DATA-FORMAT"] = "NV",
        ["X-PAYPAL-APPLICATION-ID"] = self.application_id
      }
      params = extend({
        ["clientDetails.applicationId"] = self.application_id
      }, params)
      local body = encode_query_string(params)
      local parse_url = require("socket.url").parse
      local host = assert(parse_url(self.api_url).host)
      headers["Host"] = host
      headers["Content-length"] = tostring(#body)
      local out = { }
      local _, code, res_headers = assert(self:http().request({
        headers = headers,
        url = tostring(self.api_url) .. "/" .. tostring(action),
        source = ltn12.source.string(body),
        method = "POST",
        sink = ltn12.sink.table(out),
        protocol = self.http_provider == "ssl.https" and "sslv23" or nil
      }))
      local text = concat(out)
      local res = parse_query_string(text) or text
      if type(res) == "table" then
        strip_numeric(res)
      end
      return self:_extract_error(res, res_headers)
    end,
    _extract_error = function(self, res, msg)
      if res == nil then
        res = { }
      end
      if msg == nil then
        msg = "paypal failed"
      end
      if (res["responseEnvelope.ack"] or ""):lower() == "success" then
        return res
      else
        return nil, res["error(0).message"], res
      end
    end,
    pay = function(self, params)
      if params == nil then
        params = { }
      end
      assert(params.receivers and #params.receivers > 0, "there must be at least one receiver")
      local params_shape = types.shape({
        cancelUrl = types.string,
        returnUrl = types.string,
        receivers = types.array_of(types.shape({
          email = types.string,
          amount = types.string
        }, {
          open = true
        }))
      }, {
        open = true
      })
      assert(params_shape(params))
      local receivers = params.receivers
      params.receivers = nil
      params = extend({
        actionType = "PAY",
        currencyCode = "USD",
        feesPayer = (function()
          if #receivers > 1 then
            return "PRIMARYRECEIVER"
          end
        end)(),
        ["requestEnvelope.errorLanguage"] = "en_US",
        cancelUrl = params.returnUrl,
        returnUrl = params.cancelUrl
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
    payment_details = function(self, params)
      assert(params.payKey or params.transactionId, params.trackingId, "Missing one of payKey, transactionId or trackingId")
      return self:_method("AdaptivePayments/PaymentDetails", extend({
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
    checkout_url = function(self, pay_key)
      return tostring(self.base_url) .. "/webscr?cmd=_ap-payment&paykey=" .. tostring(pay_key)
    end,
    format_price = function(self, ...)
      return format_price(...)
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, opts)
      self.opts = opts
      self.auth = assert(self.opts.auth, "missing auth")
      assert(self.__class.auth_shape(self.auth))
      self.application_id = assert(self.opts.application_id, "missing application id")
      local urls = self.opts.sandbox and self.__class.urls.sandbox or self.__class.urls.live
      self.api_url = self.opts.api_url or urls.api
      self.base_url = self.opts.base_url or urls.base
      return _class_0.__parent.__init(self, self.opts)
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
  local self = _class_0
  self.urls = {
    live = {
      base = "https://www.paypal.com",
      api = "https://svcs.paypal.com"
    },
    sandbox = {
      base = "https://www.sandbox.paypal.com",
      api = "https://svcs.sandbox.paypal.com"
    }
  }
  self.auth_shape = types.shape({
    USER = types.string,
    PWD = types.string,
    SIGNATURE = types.string
  })
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  PayPalAdaptive = _class_0
  return _class_0
end
