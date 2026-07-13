class BaseClient
  new: (opts) =>
    if opts
      @http_provider = opts.http_provider

  http: =>
    unless @_http
      -- for cqeuues "http.compat.socket"
      @http_provider or= if ngx and ngx.socket
        "lapis.http"
      else
        "socket.http"

      @_http = if type(@http_provider) == "function"
        @http_provider!
      else
        require @http_provider

    @_http


