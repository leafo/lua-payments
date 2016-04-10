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
  local resource
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
    oauth_token = function(self, code)
      local out = { }
      local parse_url = require("socket.url").parse
      local body = encode_query_string({
        code = code,
        client_secret = self.client_secret,
        grant_type = "authorization_code"
      })
      local connect_url = "https://connect.stripe.com/oauth/token"
      assert(self:http().request({
        url = connect_url,
        method = "POST",
        sink = ltn12.sink.table(out),
        headers = {
          ["Host"] = assert(parse_url(connect_url).host, "failed to get host"),
          ["Content-Type"] = "application/x-www-form-urlencoded",
          ["Content-length"] = body and #body or nil
        },
        source = ltn12.source.string(body),
        protocol = self.http_provider == "ssl.https" and "sslv23" or nil
      }))
      out = table.concat(out)
      return json.decode(out)
    end,
    _request = function(self, method, path, params, access_token)
      if access_token == nil then
        access_token = self.client_secret
      end
      local out = { }
      if params then
        for k, v in pairs(params) do
          params[k] = tostring(v)
        end
      end
      local body
      if method ~= "GET" then
        body = params and encode_query_string(params)
      end
      local parse_url = require("socket.url").parse
      local headers = {
        ["Host"] = assert(parse_url(self.api_url).host, "failed to get host"),
        ["Authorization"] = "Basic " .. encode_base64(access_token .. ":"),
        ["Content-Type"] = "application/x-www-form-urlencoded",
        ["Content-length"] = body and #body or nil
      }
      local url = self.api_url .. path
      if method == "GET" and params then
        url = url .. "?" .. tostring(encode_query_string(params))
      end
      local _, status = self:http().request({
        url = url,
        method = method,
        headers = headers,
        sink = ltn12.sink.table(out),
        source = body and ltn12.source.string(body) or nil,
        protocol = self.http_provider == "ssl.https" and "sslv23" or nil
      })
      return self:_format_response(json.decode(table.concat(out)), status)
    end,
    _format_response = function(self, res, status)
      if res.error then
        return nil, res.error.message, res, status
      else
        return res, status
      end
    end,
    _iterate_resource = function(self, method, per_page)
      if per_page == nil then
        per_page = 50
      end
      local last_id
      return coroutine.wrap(function()
        while true do
          local items = assert(method(self, {
            limit = per_page,
            starting_after = last_id
          }))
          local _list_0 = items.data
          for _index_0 = 1, #_list_0 do
            local a = _list_0[_index_0]
            last_id = a.id
            coroutine.yield(a)
          end
          if not (items.has_more) then
            break
          end
          if not (last_id) then
            break
          end
        end
      end)
    end,
    charge = function(self, opts)
      local access_token, card, amount, currency, description, fee
      access_token, card, amount, currency, description, fee = opts.access_token, opts.card, opts.amount, opts.currency, opts.description, opts.fee
      assert(tonumber(amount), "missing amount")
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
    create_card = function(self, customer_id, opts)
      return self:_request("POST", "customers/" .. tostring(customer_id) .. "/sources", opts)
    end,
    delete_customer_card = function(self, customer_id, card_id, opts)
      return self:_request("DELETE", "customers/" .. tostring(customer_id) .. "/sources/" .. tostring(card_id), opts)
    end,
    get_token = function(self, token_id)
      return self:_request("GET", "tokens/" .. tostring(token_id))
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
      assert(self.client_secret:match("^sk_test_"), "can only fill account in test")
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
    __init = function(self, opts)
      self.client_id = assert(opts.client_id, "missing client id")
      self.client_secret = assert(opts.client_secret, "missing client secret")
      self.publishable_key = opts.publishable_key
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
  local self = _class_0
  resource = function(name, resource_opts)
    if resource_opts == nil then
      resource_opts = { }
    end
    local singular = resource_opts.singular or name:gsub("s$", "")
    local list_method = "list_" .. tostring(name)
    if not (resource_opts.get == false) then
      self.__base[list_method] = self.__base[list_method] or function(self, opts)
        return self:_request("GET", name, opts)
      end
      self.__base["each_" .. tostring(singular)] = self.__base["each_"] or function(self)
        return self:_iterate_resource(self[list_method])
      end
      self.__base["get_" .. tostring(singular)] = self.__base["get_"] or function(self, id)
        return self:_request("GET", tostring(name) .. "/" .. tostring(id))
      end
    end
    if not (resource_opts.edit == false) then
      self.__base["update_" .. tostring(singular)] = self.__base["update_"] or function(self, id, opts)
        if resource_opts.update then
          opts = resource_opts.update(self, opts)
        end
        return self:_request("POST", tostring(name) .. "/" .. tostring(id), opts)
      end
      self.__base["delete_" .. tostring(singular)] = self.__base["delete_"] or function(self, id)
        return self:_request("DELETE", tostring(name) .. "/" .. tostring(id), opts)
      end
      self.__base["create_" .. tostring(singular)] = self.__base["create_"] or function(self, opts)
        if resource_opts.create then
          opts = resource_opts.create(self, opts)
        end
        return self:_request("POST", name, opts)
      end
    end
  end
  resource("accounts", {
    create = function(self, opts)
      if opts.managed == nil then
        opts.managed = true
      end
      assert(opts.country, "missing country")
      assert(opts.email, "missing country")
      return opts
    end
  })
  resource("customers")
  resource("charges", {
    edit = false
  })
  resource("disputes", {
    edit = false
  })
  resource("refunds", {
    edit = false
  })
  resource("products", {
    edit = false
  })
  resource("transfers", {
    edit = false
  })
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  Stripe = _class_0
end
return {
  Stripe = Stripe
}
