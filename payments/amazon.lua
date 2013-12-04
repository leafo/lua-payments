local debug = false
local http = require("lapis.nginx.http")
local ltn12 = require("ltn12")
local encode_query_string, parse_query_string
do
  local _obj_0 = require("lapis.util")
  encode_query_string, parse_query_string = _obj_0.encode_query_string, _obj_0.parse_query_string
end
local hmac_sha1, encode_base64, decode_base64
do
  local _obj_0 = require("lapis.util.encoding")
  hmac_sha1, encode_base64, decode_base64 = _obj_0.hmac_sha1, _obj_0.encode_base64, _obj_0.decode_base64
end
local sort, concat
do
  local _obj_0 = table
  sort, concat = _obj_0.sort, _obj_0.concat
end
local parse_url = require("socket.url").parse
local extend
extend = function(a, ...)
  local _list_0 = {
    ...
  }
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    if t then
      for k, v in pairs(t) do
        a[k] = v
      end
    end
  end
  return a
end
local format_price
format_price = function(cents)
  local dollars = math.floor(cents / 100)
  local change = ("%02d"):format(cents % 100)
  return tostring(dollars) .. "." .. tostring(change)
end
local valid_amount
valid_amount = function(str)
  if str:match("%d+%.%d%d") then
    return true
  end
  return nil, "invalid amount (" .. tostring(str) .. ")"
end
local url_encode
url_encode = function(str)
  return (str:gsub("[^a-zA-Z0-9_.~%-]", function(chr)
    local byte = chr:byte()
    local hex = ("%02x"):format(byte):upper()
    return "%" .. tostring(hex)
  end))
end
local AmazonFPS
do
  local find_node, filter_nodes, node_value, extract_errors
  local _base_0 = {
    override_ipn = nil,
    format_price = function(self, ...)
      return format_price(...)
    end,
    sign_params = function(self, params, verb, host, path)
      if verb == nil then
        verb = "GET"
      end
      if host == nil then
        host = error("missing host")
      end
      if path == nil then
        path = error("missing path")
      end
      local query
      if type(params) == "table" then
        local tuples
        do
          local _accum_0 = { }
          local _len_0 = 1
          for k, v in pairs(params) do
            _accum_0[_len_0] = {
              k,
              v
            }
            _len_0 = _len_0 + 1
          end
          tuples = _accum_0
        end
        sort(tuples, function(left, right)
          return left[1] < right[1]
        end)
        query = concat((function()
          local _accum_0 = { }
          local _len_0 = 1
          for _index_0 = 1, #tuples do
            local t = tuples[_index_0]
            _accum_0[_len_0] = url_encode(t[1]) .. "=" .. url_encode(t[2])
            _len_0 = _len_0 + 1
          end
          return _accum_0
        end)(), "&")
      else
        query = params
      end
      local to_sign = concat({
        verb:upper(),
        host:lower(),
        path,
        query
      }, "\n")
      return encode_base64(hmac_sha1(self.secret, to_sign))
    end,
    _action = function(self, name, opts, method)
      if method == nil then
        method = "GET"
      end
      opts = extend({
        Action = name,
        AWSAccessKeyId = self.access_key,
        SignatureVersion = "2",
        SignatureMethod = "HmacSHA1",
        Timestamp = os.date("!%FT%TZ"),
        Version = "2010-08-28"
      }, opts)
      if debug then
        local moon = require("moon")
        io.stdout:write("Amazon API:\n")
        io.stdout:write(moon.dump(opts))
      end
      local parsed_api_url = parse_url(self.endpoint.api_url)
      opts.Signature = self:sign_params(opts, method, parsed_api_url.host, parsed_api_url.path or "/")
      local out = { }
      local _, code, res_headers = http.request({
        url = self.endpoint.api_url .. "?" .. encode_query_string(opts),
        method = method,
        sink = ltn12.sink.table(out)
      })
      local lom = require("lxp.lom")
      out = table.concat(out)
      if debug then
        io.stdout:write(out)
        io.stdout:write("\n\n")
      end
      local res, err = lom.parse(out)
      if not (res) then
        return nil, err, code, out
      end
      if code == 200 then
        return res, code, out
      else
        return nil, extract_errors(res), code, out
      end
    end,
    verify_request = function(self, req)
      local uri = ngx.var.request_uri
      local path, params = uri:match("^([^?]*)%?(.*)$")
      if not (path) then
        path = uri
        params = ""
      end
      if ngx.var.request_method == "POST" then
        params = ngx.req.get_body_data()
      end
      return self:verify_signature(req:build_url(path), params)
    end,
    verify_signature = function(self, endpoint, param_str)
      local res, code, err_code = self:_action("VerifySignature", {
        UrlEndPoint = endpoint,
        HttpParameters = param_str
      })
      if not (res) then
        return nil, code, err_code
      end
      local status = node_value(find_node(res, "VerifySignatureResult"), "VerificationStatus")
      return (status and status:lower()) == "success", code
    end,
    pay = function(self, opts)
      local amount, sender, recipient, fee
      amount, sender, recipient, fee = opts.amount, opts.sender, opts.recipient, opts.fee
      assert(valid_amount(amount))
      local res, code, err_code, err_raw = self:_action("Pay", {
        ["TransactionAmount.CurrencyCode"] = "USD",
        ["TransactionAmount.Value"] = amount,
        ChargeFeeTo = "Recipient",
        MarketplaceVariableFee = fee or nil,
        CallerReference = self:gen_reference("dopay"),
        CallerDescription = "TEST",
        OverrideIPNURL = self.override_ipn,
        RecipientTokenId = recipient,
        SenderTokenId = sender
      })
      if not (res) then
        return nil, code, err_code, err_raw
      end
      local transaction_id = node_value(find_node(res, "PayResult"), "TransactionId")
      return transaction_id, code, err_code, err_raw
    end,
    get_trasaction_status = function(self, transaction_id)
      return self:_action("GetTransactionStatus", {
        TransactionId = transaction_id
      })
    end,
    cobranded_url = function(self, opts)
      opts = extend({
        callerKey = self.access_key,
        signatureVersion = "2",
        signatureMethod = "HmacSHA1"
      }, opts)
      local parsed_cobranded = parse_url(self.endpoint.cobranded_url)
      opts.signature = self:sign_params(opts, "GET", parsed_cobranded.host, parsed_cobranded.path or "/")
      return self.endpoint.cobranded_url .. "?" .. encode_query_string(opts)
    end,
    cobranded_pay_url = function(self, amount, return_url, opts)
      assert(valid_amount(amount))
      return self:cobranded_url(extend({
        pipelineName = "SingleUse",
        transactionAmount = amount,
        returnURL = return_url,
        callerReference = self:gen_reference("pay")
      }, opts))
    end,
    cobranded_register_url = function(self, return_url, opts)
      local max_fee = opts.max_fee
      opts.max_fee = nil
      return self:cobranded_url(extend({
        pipelineName = "Recipient",
        callerReference = self:gen_reference("link"),
        recipientPaysFee = "True",
        paymentMethod = "CC,ACH,ABT",
        maxVariableFee = max_fee or nil,
        returnURL = return_url
      }, opts))
    end,
    gen_reference = function(self, prefix)
      if prefix == nil then
        prefix = "ref"
      end
      return tostring(prefix) .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1, 10000))
    end
  }
  _base_0.__index = _base_0
  local _class_0 = setmetatable({
    __init = function(self, access_key, secret, opts)
      self.access_key, self.secret = access_key, secret
      self.endpoint = self.__class.sandbox_endpoint
      for k, v in pairs(opts) do
        self[k] = v
      end
    end,
    __base = _base_0,
    __name = "AmazonFPS"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  local self = _class_0
  self.sandbox_endpoint = {
    api_url = "https://fps.sandbox.amazonaws.com/",
    cobranded_url = "https://authorize.payments-sandbox.amazon.com/cobranded-ui/actions/start"
  }
  self.production_endpoint = {
    api_url = "https://fps.amazonaws.com/",
    cobranded_url = "https://authorize.payments.amazon.com/cobranded-ui/actions/start"
  }
  find_node = function(nodes, tag)
    if not (nodes) then
      return 
    end
    for _index_0 = 1, #nodes do
      local node = nodes[_index_0]
      if node.tag == tag then
        return node
      end
    end
  end
  filter_nodes = function(node, tag)
    if not (node) then
      return 
    end
    return (function()
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #node do
        local _continue_0 = false
        repeat
          local child = node[_index_0]
          if not (child.tag == tag) then
            _continue_0 = true
            break
          end
          local _value_0 = child
          _accum_0[_len_0] = _value_0
          _len_0 = _len_0 + 1
          _continue_0 = true
        until true
        if not _continue_0 then
          break
        end
      end
      return _accum_0
    end)()
  end
  node_value = function(nodes, tag)
    do
      local found = find_node(nodes, tag)
      if found then
        return found[1]
      end
    end
  end
  extract_errors = function(nodes)
    local errors = filter_nodes(find_node(nodes, "Errors"), "Error")
    if not errors or #errors == 0 then
      return nil
    end
    return (function()
      local _accum_0 = { }
      local _len_0 = 1
      for _index_0 = 1, #errors do
        local e = errors[_index_0]
        _accum_0[_len_0] = {
          code = node_value(e, "Code"),
          message = node_value(e, "Message")
        }
        _len_0 = _len_0 + 1
      end
      return _accum_0
    end)()
  end
  AmazonFPS = _class_0
end
return {
  AmazonFPS = AmazonFPS,
  url_encode = url_encode
}
