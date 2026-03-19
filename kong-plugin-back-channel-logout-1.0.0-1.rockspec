package = "kong-plugin-back-channel-logout"
version = "1.0.0-1"
supported_platforms = {"linux", "macosx"}
source = {
  url = "https://github.com/mohitjain-kong/kong-plugin-back-channel-logout/archive/refs/tags/v1.0.0.tar.gz",
  dir = "kong-plugin-back-channel-logout-1.0.0",
}
description = {
  summary = "Kong plugin implementing OpenID Connect Back-Channel Logout 1.0 specification.",
  homepage = "https://github.com/mohitjain-kong/kong-plugin-back-channel-logout",
  license = "MIT"
}
dependencies = {
  "lua-resty-jwt >= 0.2.3",
  "lua-resty-openidc >= 1.8.0",
  "lua-yajl >= 2.1.0",
  "lua-resty-redis >= 0.29",
  "kong >= 2.0"
}
build = {
  type = "builtin",
  modules = {
    ["kong.plugins.back-channel-logout.handler"] = "kong/plugins/back-channel-logout/handler.lua",
    ["kong.plugins.back-channel-logout.schema"] = "kong/plugins/back-channel-logout/schema.lua",
  }
}