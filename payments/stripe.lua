local ltn12 = require("ltn12")
local json = require("cjson")
local encode_query_string, parse_query_string
do
  local _obj_0 = require("lapis.util")
  encode_query_string, parse_query_string = _obj_0.encode_query_string, _obj_0.parse_query_string
end
local encode_base64
encode_base64 = require("lapis.util.encoding").encode_base64
local Stripe
do
  local _class_0
  local _parent_0 = require("payments.base_client")
  local _base_0 = {
    api_url = "https://api.stripe.com/v1/",
    calculate_fee = function(self, currency, transactions_count, amount, medium)
      local _exp_0 = medium
      if "default" == _exp_0 then
        return transactions_count * 30 + math.floor(amount * 0.029)
      elseif "bitcoin" == _exp_0 then
        return math.floor(amount * 0.005)
      else
        return error("don't know how to calculate stripe fee for medium " .. tostring(medium))
      end
    end,
    connect_url = function(self)
      return "https://connect.stripe.com/oauth/authorize?response_type=code&scope=read_write&client_id=" .. tostring(self.client_id)
    end,
    http = function(self)
      return require("lapis.nginx.http")
    end,
    oauth_token = function(self, code)
      local out = { }
      self:http().request({
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
    _request = function(self, method, path, params, access_token)
      if access_token == nil then
        access_token = self.client_secret
      end
      local out = { }
      local headers = {
        ["Authorization"] = "Basic " .. encode_base64(access_token .. ":"),
        ["Content-Type"] = "application/x-www-form-urlencoded"
      }
      if params then
        for k, v in pairs(params) do
          params[k] = tostring(v)
        end
      end
      local _, status = self:http().request({
        url = self.api_url .. path,
        method = method,
        headers = headers,
        sink = ltn12.sink.table(out),
        source = params and ltn12.source.string(encode_query_string(params)) or nil
      })
      return json.decode(table.concat(out)), status
    end,
    charge = function(self, opts)
      local access_token, card, amount, currency, description, fee
      access_token, card, amount, currency, description, fee = opts.access_token, opts.card, opts.amount, opts.currency, opts.description, opts.fee
      assert(tonumber(amount))
      local application_fee
      if fee and fee > 0 then
        application_fee = fee
      end
      return self:_request("POST", "charges", {
        card = card,
        amount = amount,
        description = description,
        currency = currency,
        application_fee = application_fee
      }, access_token)
    end,
    get_token = function(self, token_id)
      return self:_request("GET", "tokens/" .. tostring(token_id))
    end,
    get_charge = function(self, charge_id)
      return self:_request("GET", "charges/" .. tostring(charge_id))
    end,
    refund_charge = function(self, charge_id)
      return self:_request("POST", "refunds", {
        charge = charge_id
      })
    end,
    mark_fraud = function(self, charge_id)
      return self:_request("POST", "charges/" .. tostring(charge_id), {
        ["fraud_details[user_report]"] = "fraudulent"
      })
    end,
    create_account = function(self, opts)
      if opts == nil then
        opts = { }
      end
      if opts.managed == nil then
        opts.managed = true
      end
      assert(opts.country, "missing country")
      assert(opts.email, "missing country")
      return self:_request("POST", "accounts", opts)
    end,
    update_account = function(self, account_id, opts)
      return self:_request("POST", "accounts/" .. tostring(account_id), opts)
    end,
    list_accounts = function(self)
      return self:_request("GET", "accounts")
    end,
    list_products = function(self)
      return self:_request("GET", "products")
    end,
    get_account = function(self, account_id)
      return self:_request("GET", "accounts/" .. tostring(account_id))
    end,
    list_transfers = function(self)
      return self:_request("GET", "transfers")
    end,
    transfer = function(self, destination, currency, amount)
      assert("USD" == currency, "usd only for now")
      assert(tonumber(amount), "invalid amount")
      return self:_request("POST", "transfers", {
        destination = destination,
        currency = currency,
        amount = amount
      })
    end,
    fill_test_balance = function(self, amount)
      if amount == nil then
        amount = 50000
      end
      local config = require("lapis.config").get()
      assert(config._name == "development", "can only fill account in development")
      return self:_request("POST", "charges", {
        amount = amount,
        currency = "USD",
        ["source[object]"] = "card",
        ["source[number]"] = "4000000000000077",
        ["source[exp_month]"] = "2",
        ["source[exp_year]"] = "22"
      })
    end,
    get_balance = function(self)
      return self:_request("GET", "balance")
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, client_id, client_secret, publishable_key)
      self.client_id, self.client_secret, self.publishable_key = client_id, client_secret, publishable_key
    end,
    __base = _base_0,
    __name = "Stripe",
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
  Stripe = _class_0
end
return {
  Stripe = Stripe
}
