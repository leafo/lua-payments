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
    api_version = "v1",
    url_with_version = function(self, v)
      if v == nil then
        v = self.api_version
      end
      return tostring(self.url) .. tostring(v) .. "/"
    end,
    format_price = function(self, ...)
      return format_price(...)
    end,
    log_in_url = function(self, opts)
      if opts == nil then
        opts = { }
      end
      local url
      if self.sandbox then
        url = self.__class.urls.login_sandbox
      else
        url = self.__class.urls.login_default
      end
      local params = encode_query_string({
        client_id = assert(self.client_id, "missing client id"),
        response_type = opts.response_type or "code",
        scope = opts.scope or "openid",
        redirect_uri = assert(opts.redirect_uri, "missing redirect uri"),
        nonce = opts.nonce,
        state = opts.state
      })
      return tostring(url) .. "?" .. tostring(params)
    end,
    identity_token = function(self, opts)
      if opts == nil then
        opts = { }
      end
      local parse_url = require("socket.url").parse
      local url = tostring(self:url_with_version("v1")) .. "identity/openidconnect/tokenservice"
      local host = assert(parse_url(url).host)
      local body
      if opts.refresh_token then
        body = encode_query_string({
          grant_type = "refresh_token",
          refresh_token = opts.refresh_token
        })
      elseif opts.code then
        body = encode_query_string({
          grant_type = "authorization_code",
          code = opts.code
        })
      else
        body = error("unknown method for identity token (expecting code or refresh_token)")
      end
      local encode_base64
      encode_base64 = require("lapis.util.encoding").encode_base64
      local headers = {
        ["Host"] = host,
        ["Content-length"] = tostring(#body),
        ["Authorization"] = "Basic " .. tostring(encode_base64(tostring(self.client_id) .. ":" .. tostring(self.secret))),
        ["Content-Type"] = "application/x-www-form-urlencoded",
        ["Accept"] = "application/json",
        ["Accept-Language"] = "en_US"
      }
      local out = { }
      local res, status = assert(self:http().request({
        method = "POST",
        url = url,
        headers = headers,
        sink = ltn12.sink.table(out),
        source = body and ltn12.source.string(body) or nil,
        protocol = self.http_provider == "ssl.https" and "sslv23" or nil
      }))
      out = table.concat(out, "")
      if out:match("^{") then
        out = json.decode(out)
      end
      if not (status == 200) then
        return nil, out
      end
      return out
    end,
    identity_userinfo = function(self, opts)
      if opts == nil then
        opts = { }
      end
      assert(opts.access_token, "missing access token")
      local res, status = self:_request({
        method = "GET",
        path = "oauth2/token/userinfo",
        url_params = {
          schema = "openid"
        },
        access_token = opts.access_token
      })
      if not (status == 200) then
        return nil, res
      end
      return res
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
      local url = tostring(self:url_with_version("v1")) .. "oauth2/token"
      local host = assert(parse_url(url).host)
      local res, status = assert(self:http().request({
        url = url,
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
      assert(self.access_token, "failed to get token from refresh (" .. tostring(status) .. ")")
      return true
    end,
    _request = function(self, opts)
      if opts == nil then
        opts = { }
      end
      assert(opts.method, "missing method")
      assert(opts.path, "missing path")
      local method, path, params, url_params
      method, path, params, url_params = opts.method, opts.path, opts.params, opts.url_params
      local authorization
      if opts.access_token then
        authorization = "Bearer " .. tostring(opts.access_token)
      else
        self:refresh_token()
        authorization = "Bearer " .. tostring(self.access_token)
      end
      local out = { }
      local body
      if params then
        body = json.encode(params)
      end
      local url = tostring(self:url_with_version()) .. tostring(path)
      if url_params then
        url = url .. ("?" .. encode_query_string(url_params))
      end
      local parse_url = require("socket.url").parse
      local host = assert(parse_url(self:url_with_version()).host)
      local res, status = assert(self:http().request({
        url = url,
        method = method,
        headers = {
          ["Host"] = host,
          ["Content-length"] = body and tostring(#body) or nil,
          ["Authorization"] = authorization,
          ["Content-Type"] = body and "application/json",
          ["Accept"] = "application/json",
          ["Accept-Language"] = "en_US"
        },
        sink = ltn12.sink.table(out),
        source = body and ltn12.source.string(body) or nil,
        protocol = self.http_provider == "ssl.https" and "sslv23" or nil
      }))
      out = concat(out)
      return json.decode(out), status
    end,
    get_payments = function(self, opts)
      return self:_request({
        method = "GET",
        path = "payments/payment",
        params = opts
      })
    end,
    payout = function(self, opts)
      local email = assert(opts.email, "missing email")
      local amount = assert(opts.amount, "missing amount")
      local currency = assert(opts.currency, "missing currency")
      assert(type(amount) == "string", "amount should be formatted as string (0.00)")
      local note = opts.note or "Payout"
      local email_subject = opts.email_subject or "You got a payout"
      return self:_request({
        method = "POST",
        path = "payments/payouts",
        url_params = {
          sync_mode = "true"
        },
        params = {
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
        }
      })
    end,
    get_payout = function(self, batch_id)
      return self:_request({
        method = "GET",
        path = "payments/payouts/" .. tostring(batch_id)
      })
    end,
    get_sale_transaction = function(self, transaction_id)
      return self:_request({
        method = "GET",
        path = "payments/sale/" .. tostring(transaction_id)
      })
    end,
    sale_transaction = function(self, ...)
      return self:get_sale_transaction(...)
    end,
    create_payment = function(self, opts)
      return self:_request({
        method = "POST",
        path = "payments/payment",
        params = opts
      })
    end,
    execute_payment = function(self, payment_id, opts)
      return self:_request({
        method = "POST",
        path = "payments/payment/" .. tostring(payment_id) .. "/execute",
        params = opts
      })
    end,
    refund_sale = function(self, sale_id, opts)
      if opts == nil then
        opts = { }
      end
      return self:_request({
        method = "POST",
        path = "payments/sale/" .. tostring(sale_id) .. "/refund",
        params = opts
      })
    end,
    get_payment = function(self, payment_id)
      return self:_request({
        method = "GET",
        path = "payments/payment/" .. tostring(payment_id)
      })
    end,
    get_customer_partner_referral = function(self, partner_referral_id, opts)
      assert(partner_referral_id, "missing partner referral id")
      return self:_request({
        method = "GET",
        path = "customer/partner-referrals/" .. tostring(partner_referral_id),
        url_params = opts
      })
    end,
    get_customer_partner_merchant_integration = function(self, partner_id, merchant_id, opts)
      assert(partner_id, "missing partner id")
      assert(merchant_id, "missing merchant id")
      return self:_request({
        method = "GET",
        path = "customer/partners/" .. tostring(partner_id) .. "/merchant-integrations/" .. tostring(merchant_id),
        url_params = opts
      })
    end,
    create_customer_partner_referral = function(self, opts)
      return self:_request({
        method = "POST",
        path = "customer/partner-referrals",
        params = opts
      })
    end,
    get_customer_disputes = function(self, opts)
      return self:_request({
        method = "GET",
        path = "customer/disputes",
        url_params = opts
      })
    end,
    get_customer_dispute = function(self, dispute_id, opts)
      assert(dispute_id, "missing dispute id")
      return self:_request({
        method = "GET",
        path = "customer/disputes/" .. tostring(dispute_id),
        url_params = opts
      })
    end,
    dispute_accept_claim = function(self, dispute_id, opts)
      assert(dispute_id, "missing dispute id")
      return self:_request({
        method = "GET",
        path = "customer/disputes/" .. tostring(dispute_id) .. "/accept-claim",
        params = opts
      })
    end,
    dispute_escalate = function(self, dispute_id, opts)
      assert(dispute_id, "missing dispute id")
      return self:_request({
        method = "GET",
        path = "customer/disputes/" .. tostring(dispute_id) .. "/escalate",
        params = opts
      })
    end,
    create_checkout_order = function(self, opts)
      return self:_request({
        method = "POST",
        path = "checkout/orders",
        params = opts
      })
    end
  }
  _base_0.__index = _base_0
  setmetatable(_base_0, _parent_0.__base)
  _class_0 = setmetatable({
    __init = function(self, opts)
      if opts == nil then
        opts = { }
      end
      self.sandbox = opts.sandbox or false
      self.url = self.sandbox and self.__class.urls.sandbox or self.__class.urls.default
      self.client_id = assert(opts.client_id, "missing client id")
      self.secret = assert(opts.secret, "missing secret")
      if opts.api_version then
        self.api_version = opts.api_version
      end
      self.partner_id = opts.partner_id
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
    default = "https://api.paypal.com/",
    sandbox = "https://api.sandbox.paypal.com/",
    login_default = "https://www.paypal.com/signin/authorize",
    login_sandbox = "https://www.sandbox.paypal.com/signin/authorize"
  }
  if _parent_0.__inherited then
    _parent_0.__inherited(_parent_0, _class_0)
  end
  PayPalRest = _class_0
  return _class_0
end
