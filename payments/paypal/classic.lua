local PayPalClassic
do
  local _class_0
  local _parent_0 = require("payments.base_client")
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
        local moon = require("moon")
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
    refund = function(self, transaction_id, opts)
      return self:_method("RefundTransaction", extend({
        TRANSACTIONID = transaction_id
      }, upper_keys(opts)))
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
    end,
    calculate_fee = function(self, ...)
      return assert(calculate_fee(...))
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
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
    __name = "PayPalClassic",
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
  PayPalClassic = _class_0
  return _class_0
end
