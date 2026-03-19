local typedefs = require "kong.db.schema.typedefs"

return {
  name = "back-channel-logout",
  fields = {
    { consumer = typedefs.no_consumer },
    { config = {
      type = "record",
      fields = {
        { jwks_url = { type = "string", required = true, validate = typedefs.url } },
        { credential_claim = { type = "string", required = true } },
        { redis_host = { type = "string", required = true, default = "127.0.0.1" } },
        { redis_port = { type = "integer", required = true, default = 6379 } },
        { redis_password = { type = "string" } },
        { redis_prefix = { type = "string", default = "kong" } },
        { session_cookie_name = { type = "string", default = "kong_session" } },
      },
    }},
  }
}