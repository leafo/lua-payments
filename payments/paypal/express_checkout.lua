local concat
concat = table.concat
local types
types = require("tableshape").types
local extend, format_price, upper_keys, strip_numeric, valid_amount
do
  local _obj_0 = require("payments.paypal.helpers")
  extend, format_price, upper_keys, strip_numeric, valid_amount = _obj_0.extend, _obj_0.format_price, _obj_0.upper_keys, _obj_0.strip_numeric, _obj_0.valid_amount
end
local encode_query_string, parse_query_string
do
  local _obj_0 = require("lapis.util")
  encode_query_string, parse_query_string = _obj_0.encode_query_string, _obj_0.parse_query_string
end
local ltn12 = require("ltn12")
local PayPalExpressCheckout
do
  local _class_0
  local _parent_0 = require("payments.base_client")
  local _base_0 = {
    _method = function(self, name, params)
      params.METHOD = name
      local out = { }
      for k, v in pairs(self.auth) do
        if not (params[k]) then
          params[k] = v
        end
      end
      local body = encode_query_string(params)
      local parse_url = require("socket.url").parse
      local success, code, res_headers = self:http().request({
        url = self.api_url,
        headers = {
          ["Host"] = assert(parse_url(self.api_url).host, "failed to get host"),
          ["Content-type"] = "application/x-www-form-urlencoded",
          ["Content-length"] = #body
        },
        source = ltn12.source.string(body),
        method = "POST",
        sink = ltn12.sink.table(out),
        protocol = self.http_provider == "ssl.https" and "sslv23" or nil
      })
      assert(success, code)
      local text = concat(out)
      local res = parse_query_string(text) or text
      if type(res) == "table" then
        strip_numeric(res)
      end
      return self:_extract_error(res, res_headers)
    end,
    _extract_error = function(self, res, headers)
      if res.ACK ~= "Success" and res.ACK ~= "SuccessWithWarning" then
        return nil, res.L_LONGMESSAGE0, res, headers
      end
      return res, headers
    end,
    refund = function(self, transaction_id, opts)
      return self:_method("RefundTransaction", extend({
        TRANSACTIONID = transaction_id
      }, upper_keys(opts)))
    end,
    _format_transaction_results = function(self, res)
      local warning_fields = {
        longmessage = true,
        shortmessage = true,
        severitycode = true,
        errorcode = true
      }
      local other_messages = { }
      local out = { }
      for k, val in pairs(res) do
        local field, id = k:match("L_(.-)(%d+)$")
        if field then
          field = field:lower()
          if warning_fields[field] then
            other_messages[k] = val
          else
            id = tonumber(id) + 1
            out[id] = out[id] or { }
            out[id][field] = val
          end
        else
          other_messages[k] = val
        end
      end
      return out, other_messages
    end,
    transaction_search = function(self, opts)
      local res, rest = self:_method("TransactionSearch", upper_keys(opts or { }))
      return self:_format_transaction_results(res), rest
    end,
    get_transaction_details = function(self, opts)
      return self:_method("GetTransactionDetails", upper_keys(opts or { }))
    end,
    set_express_checkout = function(self, opts)
      opts = upper_keys(opts)
      return self:_method("SetExpressCheckout", opts)
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
    checkout_url = function(self, token)
      return tostring(self.checkout_url_prefix) .. "?cmd=_express-checkout&token=" .. tostring(token) .. "&useraction=commit"
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
      self.auth.VERSION = self.auth.VERSION or "98"
      assert(self.__class.auth_shape(self.auth))
      local urls = self.opts.sandbox and self.__class.urls.sandbox or self.__class.urls.live
      self.api_url = self.opts.api_url or urls.signature
      self.checkout_url_prefix = self.opts.checkout_url or urls.checkout
    end,
    __base = _base_0,
    __name = "PayPalExpressCheckout",
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
      checkout = "https://www.paypal.com/cgi-bin/webscr",
      certificate = "https://api.paypal.com/nvp",
      signature = "https://api-3t.paypal.com/nvp"
    },
    sandbox = {
      checkout = "https://www.sandbox.paypal.com/cgi-bin/webscr",
      certificate = "https://api.sandbox.paypal.com/nvp",
      signature = "https://api-3t.sandbox.paypal.com/nvp"
    }
  }
  self.auth_shape = types.shape({
    USER = types.string,
    PWD = types.string,
    SIGNATURE = types.string,
    VERSION = types.string:is_optional()
  })
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  PayPalExpressCheckout = _class_0
  return _class_0
end
