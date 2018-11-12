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
    for_account_id = function(self, account_id)
      local out = Stripe({
        client_id = self.client_id,
        client_secret = self.client_secret,
        publishable_key = self.publishable_key,
        stripe_account_id = account_id,
        stripe_version = self.stripe_version,
        http_provider = self.http_provider
      })
      out.http = self.http
      return out
    end,
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
      local _, status = assert(self:http().request({
        url = connect_url,
        method = "POST",
        sink = ltn12.sink.table(out),
        headers = {
          ["Host"] = assert(parse_url(connect_url).host, "failed to get host"),
          ["Content-Type"] = "application/x-www-form-urlencoded",
          ["Content-length"] = body and tostring(#body) or nil
        },
        source = ltn12.source.string(body),
        protocol = self.http_provider == "ssl.https" and "sslv23" or nil
      }))
      out = table.concat(out)
      if not (status == 200) then
        return nil, "got status " .. tostring(status) .. ": " .. tostring(out)
      end
      return json.decode(out)
    end,
    _request = function(self, method, path, params, access_token, more_headers)
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
        ["Content-length"] = body and tostring(#body) or nil,
        ["Stripe-Account"] = self.stripe_account_id,
        ["Stripe-Version"] = self.stripe_version
      }
      if more_headers then
        for k, v in pairs(more_headers) do
          headers[k] = v
        end
      end
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
    _iterate_resource = function(self, method, opts)
      local last_id
      return coroutine.wrap(function()
        while true do
          local iteration_opts = {
            limit = 50,
            starting_after = last_id
          }
          if opts then
            for k, v in pairs(opts) do
              iteration_opts[k] = v
            end
          end
          local items = assert(method(self, iteration_opts))
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
      local access_token, card, customer, source, amount, currency, description, fee
      access_token, card, customer, source, amount, currency, description, fee = opts.access_token, opts.card, opts.customer, opts.source, opts.amount, opts.currency, opts.description, opts.fee
      assert(tonumber(amount), "missing amount")
      local application_fee
      if fee and fee > 0 then
        application_fee = fee
      end
      return self:_request("POST", "charges", {
        card = card,
        customer = customer,
        source = source,
        amount = amount,
        description = description,
        currency = currency,
        application_fee = application_fee
      }, access_token)
    end,
    create_card = function(self, customer_id, opts)
      return self:_request("POST", "customers/" .. tostring(customer_id) .. "/sources", opts)
    end,
    update_card = function(self, customer_id, card_id, opts)
      return self:_request("POST", "customers/" .. tostring(customer_id) .. "/sources/" .. tostring(card_id), opts)
    end,
    get_card = function(self, customer_id, card_id, opts)
      return self:_request("GET", "customers/" .. tostring(customer_id) .. "/sources/" .. tostring(card_id), opts)
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
      self.stripe_account_id = opts.stripe_account_id
      self.stripe_version = opts.stripe_version
      return _class_0.__parent.__init(self, opts)
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
    local api_path = resource_opts.path or name
    local list_method = "list_" .. tostring(name)
    if not (resource_opts.get == false) then
      local _update_0 = list_method
      self.__base[_update_0] = self.__base[_update_0] or function(self, opts)
        return self:_request("GET", api_path, opts)
      end
      local _update_1 = "each_" .. tostring(singular)
      self.__base[_update_1] = self.__base[_update_1] or function(self, opts)
        return self:_iterate_resource(self[list_method], opts)
      end
      local _update_2 = "get_" .. tostring(singular)
      self.__base[_update_2] = self.__base[_update_2] or function(self, id, opts)
        return self:_request("GET", tostring(api_path) .. "/" .. tostring(id), opts)
      end
    end
    if not (resource_opts.edit == false) then
      local _update_0 = "update_" .. tostring(singular)
      self.__base[_update_0] = self.__base[_update_0] or function(self, id, opts)
        if resource_opts.update then
          opts = resource_opts.update(self, opts)
        end
        return self:_request("POST", tostring(api_path) .. "/" .. tostring(id), opts)
      end
      local _update_1 = "delete_" .. tostring(singular)
      self.__base[_update_1] = self.__base[_update_1] or function(self, id)
        return self:_request("DELETE", tostring(api_path) .. "/" .. tostring(id))
      end
      local _update_2 = "create_" .. tostring(singular)
      self.__base[_update_2] = self.__base[_update_2] or function(self, opts)
        if resource_opts.create then
          opts = resource_opts.create(self, opts)
        end
        return self:_request("POST", api_path, opts)
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
  resource("transfers", {
    edit = false
  })
  resource("balance_transactions", {
    edit = false,
    path = "balance/history"
  })
  resource("application_fees", {
    edit = false
  })
  resource("events", {
    edit = false
  })
  resource("bitcoin_receivers", {
    edit = false,
    path = "bitcoin/receivers"
  })
  resource("products")
  resource("plans")
  resource("subscriptions")
  resource("invoices", {
    edit = false
  })
  resource("upcoming_invoices", {
    edit = false,
    path = "invoices/upcoming"
  })
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  Stripe = _class_0
end
return {
  Stripe = Stripe
}
