
import types from require "tableshape"
import parse_query_string from require "lapis.util"

url = require "socket.url"

assert_shape = (obj, shape) ->
  assert shape obj

-- returns shape that matches against parsed url
url_shape = (obj, _t=types.partial) ->
  format_error = (value, err) =>
    import to_json from require "lapis.util"
    "got #{to_json value}: #{err}"

  annotated = {k, types.annotate(v, :format_error) for k,v in pairs obj}
  types.string / url.parse * _t annotated

query_string_shape = (obj, _t=types.shape) ->
  -- since query string returns parsed result in two ways, we strip it out
  -- into plain hash table

  types.string /
    parse_query_string /
    ((o) -> { k,v for k,v in pairs o when type(k) == "string"}) *
    _t obj

extract_params = (str) ->
  params = assert parse_query_string str
  {k,v for k,v in pairs params when type(k) == "string"}

make_http = (handle) ->

  http_requests = {}
  fn = =>
    @http_provider = "test"
    {
      request: (req) ->
        table.insert http_requests, req
        handle req if handle
        1, 200, {}
    }

  fn, http_requests

{:extract_params, :make_http, :assert_shape, :url_shape, :query_string_shape}
