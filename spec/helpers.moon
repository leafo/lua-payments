
import parse_query_string from require "lapis.util"

assert_shape = (obj, shape) ->
  assert shape obj

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

{:extract_params, :make_http, :assert_shape}
