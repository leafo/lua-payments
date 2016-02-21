package = "payments"
version = "dev-1"

source = {
  url = "git://github.com/leafo/lua-payments.git",
}

description = {
  summary = "Payment APIs for Lua",
  homepage = "https://github.com/leafo/lua-payments",
  license = "MIT"
}

dependencies = {
  "lua >= 5.1"
}

build = {
  type = "builtin",
  modules = {
  }
}

