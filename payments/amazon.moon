
debug = false

http = require "lapis.nginx.http"
ltn12 = require "ltn12"

import encode_query_string, parse_query_string from require "lapis.util"
import hmac_sha1, encode_base64, decode_base64 from require "lapis.util.encoding"

import sort, concat from table

parse_url = require"socket.url".parse

extend = (a, ...) ->
  for t in *{...}
    if t
      a[k] = v for k,v in pairs t
  a

format_price = (cents) ->
  dollars = math.floor cents / 100
  change = "%02d"\format cents % 100
  "#{dollars}.#{change}"

valid_amount = (str) ->
  return true if str\match "%d+%.%d%d"
  nil, "invalid amount (#{str})"

-- url encoding as defined by amazon
url_encode = (str) ->
  (str\gsub "[^a-zA-Z0-9_.~%-]", (chr) ->
    byte = chr\byte!
    hex = "%02x"\format(byte)\upper!
    "%#{hex}")

class AmazonFPS
  @sandbox_endpoint: {
    api_url: "https://fps.sandbox.amazonaws.com/"
    cobranded_url: "https://authorize.payments-sandbox.amazon.com/cobranded-ui/actions/start"
  }

  @production_endpoint: {
    api_url: "https://fps.amazonaws.com/"
    cobranded_url: "https://authorize.payments.amazon.com/cobranded-ui/actions/start"
  }

  override_ipn: nil

  find_node = (nodes, tag) ->
    return unless nodes
    for node in *nodes
      if node.tag == tag
        return node

  filter_nodes = (node, tag) ->
    return unless node
    return for child in *node
      continue unless child.tag == tag
      child

  node_value = (nodes, tag) ->
    if found = find_node nodes, tag
      found[1]

  extract_errors = (nodes) ->
    errors = filter_nodes find_node(nodes, "Errors"), "Error"
    return nil if not errors or #errors == 0
    return for e in *errors
      {
        code: node_value e, "Code"
        message: node_value e, "Message"
      }

  new: (@access_key, @secret, opts) =>
    @endpoint = @@sandbox_endpoint
    for k,v in pairs opts
      @[k] = v

  format_price: (...) => format_price ...

  -- StringToSign = HTTPVerb + "\n" +
  --   ValueOfHostHeaderInLowercase + "\n" +
  --   HTTPRequestURI + "\n" +
  --   CanonicalizedQueryString <from the preceding step>
  sign_params: (params, verb="GET", host=error"missing host", path=error"missing path") =>
    query = if type(params) == "table"
      tuples = [{k, v} for k,v in pairs params]
      sort tuples, (left, right) -> left[1] < right[1]
      concat [url_encode(t[1]) .. "=" .. url_encode(t[2]) for t in *tuples], "&"
    else
      params

    to_sign = concat { verb\upper!, host\lower!, path, query }, "\n"
    encode_base64 hmac_sha1 @secret, to_sign

  _action: (name, opts, method="GET") =>
    opts = extend {
      Action: name
      AWSAccessKeyId: @access_key
      SignatureVersion: "2"
      SignatureMethod: "HmacSHA1"
      Timestamp: os.date "!%FT%TZ"
      Version: "2010-08-28"
    }, opts

    if debug
      moon = require "moon"
      io.stdout\write "Amazon API:\n"
      io.stdout\write moon.dump opts

    parsed_api_url = parse_url @endpoint.api_url
    opts.Signature = @sign_params opts, method,
      parsed_api_url.host, parsed_api_url.path or "/"

    out = {}
    _, code, res_headers = http.request {
      url: @endpoint.api_url .. "?" .. encode_query_string opts
      method: method
      sink: ltn12.sink.table out
    }

    lom = require "lxp.lom"

    out = table.concat out

    if debug
      io.stdout\write out
      io.stdout\write "\n\n"

    res, err = lom.parse out
    return nil, err, code, out unless res

    if code == 200
      res, code, out
    else
      nil, extract_errors(res), code, out

  -- verify the signature of the current request
  verify_request: (req) =>
    uri = ngx.var.request_uri
    path, params = uri\match "^([^?]*)%?(.*)$"

    unless path
      path = uri
      params = ""

    if ngx.var.request_method == "POST"
      params = ngx.req.get_body_data!

    @verify_signature req\build_url(path), params

  verify_signature: (endpoint, param_str) =>
    res, code, err_code = @_action "VerifySignature", {
      UrlEndPoint: endpoint
      HttpParameters: param_str
    }

    return nil, code, err_code unless res
    status = node_value(find_node(res, "VerifySignatureResult"), "VerificationStatus")
    (status and status\lower!) == "success", code

  pay: (opts) => -- amount, sender_token_id, recipient_token_id, opts={}) =>
    {:amount, :sender, :recipient, :fee} = opts

    assert valid_amount amount
    res, code, err_code, err_raw = @_action "Pay", {
      "TransactionAmount.CurrencyCode": "USD"
      "TransactionAmount.Value": amount
      ChargeFeeTo: "Recipient"
      MarketplaceVariableFee: fee or nil
      CallerReference: @gen_reference "dopay"
      CallerDescription: "TEST"
      OverrideIPNURL: @override_ipn

      RecipientTokenId: recipient
      SenderTokenId: sender
    }

    return nil, code, err_code, err_raw unless res
    transaction_id = node_value find_node(res, "PayResult"), "TransactionId"
    transaction_id, code, err_code, err_raw

  get_trasaction_status: (transaction_id) =>
    @_action "GetTransactionStatus", {
      TransactionId: transaction_id
    }

  cobranded_url: (opts) =>
    opts = extend {
      callerKey: @access_key
      signatureVersion: "2"
      signatureMethod: "HmacSHA1"
    }, opts

    parsed_cobranded = parse_url @endpoint.cobranded_url
    opts.signature = @sign_params opts, "GET",
      parsed_cobranded.host, parsed_cobranded.path or "/"

    @endpoint.cobranded_url .. "?" .. encode_query_string opts

  -- https://authorize.payments.amazon.com/cobranded-ui/actions/start?
  --   callerKey=[The caller's AWS Access Key ID]
  --   &callerReference=DigitalDownload1183401134541
  --   &pipelineName=SingleUse
  --   &returnURL=http%3A%2F%2Fwww.digitaldownload.com%2FpaymentDetails.jsp%3FPaymentAmount%3
  --   D0.10%26Download%3DCandle%2BIn%2Bthe%2BWind%2B-%2BElton%2BJohn%26uniqueId%3D1183401134535
  --   &paymentReason=To download Candle In the Wind - Elton John
  --   &signature=[URL-encoded value you generate]
  --   &transactionAmount=0.10
  cobranded_pay_url: (amount, return_url, opts) =>
    assert valid_amount amount
    @cobranded_url extend {
      pipelineName: "SingleUse"
      transactionAmount: amount
      returnURL: return_url
      callerReference: @gen_reference "pay"
    }, opts

  cobranded_register_url: (return_url, opts) =>
    max_fee = opts.max_fee
    opts.max_fee = nil

    @cobranded_url extend {
      pipelineName: "Recipient"
      callerReference: @gen_reference "link"
      recipientPaysFee: "True"
      paymentMethod: "CC,ACH,ABT"
      maxVariableFee: max_fee or nil
      returnURL: return_url
    }, opts

  gen_reference: (prefix="ref") =>
    "#{prefix}_#{os.time!}_#{math.random 1, 10000}"

{ :AmazonFPS, :url_encode }
