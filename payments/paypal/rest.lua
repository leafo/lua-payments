local json = require("cjson")
local ltn12 = require("ltn12")
local format_price
format_price = require("payments.paypal.helpers").format_price
local encode_query_string
encode_query_string = require("lapis.util").encode_query_string
local concat
concat = table.concat
local PayPalRest
do
  local _class_0
  local _parent_0 = require("payments.base_client")
  local _base_0 = {
    format_price = function(self, ...)
      return format_price(...)
    end,
    need_refresh = function(self)
      if not (self.last_token) then
        return true
      end
      return os.time() > self.last_token_time + self.last_token.expires_in - 100
    end,
    refresh_token = function(self)
      if not (self:need_refresh()) then
        return 
      end
      local encode_base64
      encode_base64 = require("lapis.util.encoding").encode_base64
      local out = { }
      local body = encode_query_string({
        grant_type = "client_credentials"
      })
      local parse_url = require("socket.url").parse
      local host = assert(parse_url(self.url).host)
      local res, status = assert(self:http().request({
        url = tostring(self.url) .. "oauth2/token",
        method = "POST",
        sink = ltn12.sink.table(out),
        source = ltn12.source.string(body),
        headers = {
          ["Host"] = host,
          ["Content-length"] = tostring(#body),
          ["Authorization"] = "Basic " .. tostring(encode_base64(tostring(self.client_id) .. ":" .. tostring(self.secret))),
          ["Content-Type"] = "application/x-www-form-urlencoded",
          ["Accept"] = "application/json",
          ["Accept-Language"] = "en_US"
        },
        protocol = self.http_provider == "ssl.https" and "sslv23" or nil
      }))
      self.last_token_time = os.time()
      self.last_token = json.decode(concat(out))
      self.access_token = self.last_token.access_token
      assert(self.access_token, "failed to get token from refresh")
      return true
    end,
    _request = function(self, method, path, body, url_params)
      self:refresh_token()
      local out = { }
      if body then
        body = json.encode(body)
      end
      local url = tostring(self.url) .. tostring(path)
      if url_params then
        url = url .. ("?" .. encode_query_string(url_params))
      end
      local parse_url = require("socket.url").parse
      local host = assert(parse_url(self.url).host)
      local headers = {
        ["Host"] = host,
        ["Content-length"] = body and tostring(#body) or nil,
        ["Authorization"] = "Bearer " .. tostring(self.access_token),
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json",
        ["Accept-Language"] = "en_US"
      }
      local res, status = assert(self:http().request({
        url = url,
        method = method,
        headers = headers,
        sink = ltn12.sink.table(out),
        source = body and ltn12.source.string(body) or nil,
        protocol = self.http_provider == "ssl.https" and "sslv23" or nil
      }))
      return json.decode(concat(out)), status
    end,
    get_payments = function(self, opts)
      return self:_request("GET", "payments/payment", opts)
    end,
    payout = function(self, opts)
      local email = assert(opts.email, "missing email")
      local amount = assert(opts.amount, "missing amount")
      local currency = assert(opts.currency, "missing currency")
      assert(type(amount) == "string", "amount should be formatted as string (0.00)")
      local note = opts.note or "Payout"
      local email_subject = opts.email_subject or "You got a payout"
      return self:_request("POST", "payments/payouts", {
        sender_batch_header = {
          email_subject = email_subject
        },
        items = {
          {
            recipient_type = "EMAIL",
            amount = {
              value = amount,
              currency = currency
            },
            receiver = email,
            note = note
          }
        }
      }, {
        sync_mode = "true"
      })
    end,
    sale_transaction = function(self, transaction_id)
      return self:_request("GET", "payments/sale/" .. tostring(transaction_id))
    end,
    payment = function(self, payment_id)
      return self:_request("GET", "payments/payment/" .. tostring(payment_id))
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, opts)
      self.url = opts.sandbox and self.__class.urls.sandbox or self.__class.urls.default
      self.client_id = assert(opts.client_id, "missing client id")
      self.secret = assert(opts.secret, "missing secret")
      return _class_0.__parent.__init(self, opts)
    end,
    __base = _base_0,
    __name = "PayPalRest",
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
    default = "https://api.paypal.com/v1/",
    sandbox = "https://api.sandbox.paypal.com/v1/"
  }
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  PayPalRest = _class_0
  return _class_0
end
