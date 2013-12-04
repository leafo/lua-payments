local http = require("lapis.nginx.http")
local ltn12 = require("ltn12")
local json = require("cjson")
local encode_query_string, parse_query_string
do
  local _obj_0 = require("lapis.util")
  encode_query_string, parse_query_string = _obj_0.encode_query_string, _obj_0.parse_query_string
end
local encode_base64
do
  local _obj_0 = require("lapis.util.encoding")
  encode_base64 = _obj_0.encode_base64
end
local Stripe
do
  local _base_0 = {
    api_url = "https://api.stripe.com/v1/",
    connect_url = function(self)
      return "https://connect.stripe.com/oauth/authorize?response_type=code&scope=read_write&client_id=" .. tostring(self.client_id)
    end,
    oauth_token = function(self, code)
      local out = { }
      http.request({
        url = "https://connect.stripe.com/oauth/token",
        method = "POST",
        sink = ltn12.sink.table(out),
        source = ltn12.source.string(encode_query_string({
          code = code,
          client_secret = self.client_secret,
          grant_type = "authorization_code"
        }))
      })
      out = table.concat(out)
      return json.decode(out)
    end,
    charge = function(self, opts)
      local access_token, card, amount, currency, description, fee
      access_token, card, amount, currency, description, fee = opts.access_token, opts.card, opts.amount, opts.currency, opts.description, opts.fee
      assert(tonumber(amount))
      local application_fee
      if fee and fee > 0 then
        application_fee = amount * fee
      end
      local out = { }
      local headers = {
        ["Authorization"] = "Basic " .. encode_base64(access_token .. ":"),
        ["Content-Type"] = "application/x-www-form-urlencoded"
      }
      local status = http.request({
        url = self.api_url .. "charges",
        method = "POST",
        headers = headers,
        sink = ltn12.sink.table(out),
        source = ltn12.source.string(encode_query_string({
          card = card,
          amount = amount,
          description = description,
          currency = currency,
          application_fee = application_fee
        }))
      })
      return json.decode(table.concat(out))
    end
  }
  _base_0.__index = _base_0
  local _class_0 = setmetatable({
    __init = function(self, client_id, client_secret)
      self.client_id, self.client_secret = client_id, client_secret
    end,
    __base = _base_0,
    __name = "Stripe"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  Stripe = _class_0
end
return {
  Stripe = Stripe
}
