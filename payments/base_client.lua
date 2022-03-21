local BaseClient
do
  local _class_0
  local _base_0 = {
    http = function(self)
      if not (self._http) then
        self.http_provider = self.http_provider or (function()
          if ngx and ngx.socket then
            return "lapis.nginx.http"
          else
            return "ssl.https"
          end
        end)()
        if type(self.http_provider) == "function" then
          self._http = self:http_provider()
        else
          self._http = require(self.http_provider)
        end
      end
      return self._http
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self, opts)
      if opts then
        self.http_provider = opts.http_provider
      end
    end,
    __base = _base_0,
    __name = "BaseClient"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  BaseClient = _class_0
  return _class_0
end
