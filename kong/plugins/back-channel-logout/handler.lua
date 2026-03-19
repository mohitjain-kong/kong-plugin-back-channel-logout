local plugin = {}; plugin.VERSION = "1.0.0"; plugin.PRIORITY = 1000

plugin.access = function(conf)
  local body = kong.request.get_body()
  if not body or not body.logout_token then
    kong.log.err("Missing logout_token in request body")
    kong.response.exit(400, { message = "Missing logout_token" })
    return
  end

  local logout_token = body.logout_token

  -- Store necessary data in kong.ctx for later use
  kong.ctx.plugin.logout_token = logout_token
  kong.ctx.plugin.conf = conf

  local jwks_url = conf.jwks_url
  if not jwks_url then
    kong.log.err("Missing jwks_url in configuration")
    kong.response.exit(500, { message = "Missing jwks_url in configuration" })
    return
  end

  local res = kong.service.request(jwks_url, {
    method = "GET",
    headers = {
      ["Content-Type"] = "application/json"
    }
  })

  if not res then
    kong.log.err("Failed to fetch JWKS from ", jwks_url)
    kong.response.exit(500, { message = "Failed to fetch JWKS" })
    return
  end

  if res.status ~= 200 then
    kong.log.err("Failed to fetch JWKS from ", jwks_url, ": ", res.status)
    kong.response.exit(500, { message = "Failed to fetch JWKS" })
    return
  end

  local body = res.body
  local jwks, err = cjson.decode(body)

  if err then
    kong.log.err("Failed to decode JWKS: ", err)
    kong.response.exit(500, { message = "Failed to decode JWKS" })
    return
  end

  if not jwks or not jwks.keys or #jwks.keys == 0 then
    kong.log.err("No usable keys found in JWKS")
    kong.response.exit(500, { message = "No usable keys found in JWKS" })
    return
  end

  kong.ctx.plugin.jwks = jwks.keys
end

plugin.header_filter = function()
  if not kong.ctx.plugin.jwks or not kong.ctx.plugin.logout_token or not kong.ctx.plugin.conf then
    return -- Already handled error in access phase
  end

  local jwks = kong.ctx.plugin.jwks
  local logout_token = kong.ctx.plugin.logout_token
  local conf = kong.ctx.plugin.conf

  local jwt_header_b64, jwt_payload_b64, jwt_signature_b64 = string.match(logout_token, "([^.]*).([^.]*).([^.]*)")
  if not jwt_header_b64 or not jwt_payload_b64 or not jwt_signature_b64 then
    kong.log.err("Invalid JWT format")
    kong.response.exit(400, { message = "Invalid JWT format" })
    return
  end

  local jwt_header_json = ngx.decode_base64(jwt_header_b64)
  if not jwt_header_json then
      kong.log.err("Failed to decode JWT header")
      kong.response.exit(400, { message = "Failed to decode JWT header" })
      return
  end
  local jwt_header, err = cjson.decode(jwt_header_json)

  if err then
      kong.log.err("Failed to decode JWT header JSON: ", err)
      kong.response.exit(400, { message = "Failed to decode JWT header JSON" })
      return
  end

  local jwt_payload_json = ngx.decode_base64(jwt_payload_b64)
   if not jwt_payload_json then
      kong.log.err("Failed to decode JWT payload")
      kong.response.exit(400, { message = "Failed to decode JWT payload" })
      return
  end
  local jwt_payload, err = cjson.decode(jwt_payload_json)
  if err then
      kong.log.err("Failed to decode JWT payload JSON: ", err)
      kong.response.exit(400, { message = "Failed to decode JWT payload JSON" })
      return
  end

  -- Find the appropriate key for the JWT
  local found_key = false
  local key = nil
  if jwt_header.kid then
    for i,k in ipairs(jwks) do
      if k.kid == jwt_header.kid then
        key = k
        found_key = true
        break
      end
    end
  else
    -- If no kid in header, try all keys (not recommended in production)
    if #jwks > 0 then
      key = jwks[1] -- Just use the first key.
      found_key = true
    else
      kong.log.err("No key found with kid: ", jwt_header.kid)
      kong.response.exit(500, {message = "No matching key found"})
      return
    end
  end


  if not found_key then
      kong.log.err("No key found with kid: ", jwt_header.kid)
      kong.response.exit(500, {message = "No matching key found"})
      return
  end

  -- Verify JWT signature
  local jwt = require "resty.jwt"
  local verified, err = jwt:verify(key, logout_token)
  if not verified then
      kong.log.err("JWT verification failed: ", err)
      kong.response.exit(401, {message = "Invalid JWT signature"})
      return
  end

  -- Check exp claim
  local exp = jwt_payload.exp
  if not exp then
      kong.log.err("Missing 'exp' claim in JWT")
      kong.response.exit(400, {message = "Missing 'exp' claim"})
      return
  end

  local now = ngx.time()
  if now > exp then
      kong.log.err("JWT has expired")
      kong.response.exit(400, {message = "JWT has expired"})
      return
  end

  -- Subject extraction
  local credential_claim = conf.credential_claim or "sub"
  local subject = jwt_payload[credential_claim]

  if not subject then
      kong.log.err("Missing subject claim: ", credential_claim)
      kong.response.exit(400, {message = "Missing subject claim"})
      return
  end

  kong.ctx.plugin.subject = subject
  kong.ctx.plugin.jwt_payload = jwt_payload
end

plugin.body_filter = function()
  if not kong.ctx.plugin.subject or not kong.ctx.plugin.conf then
    return
  end

  local subject = kong.ctx.plugin.subject
  local conf = kong.ctx.plugin.conf

  -- Redis setup
  local redis = require "resty.redis"
  local red = redis:new()
  red:set_timeout(1000) -- 1 sec

  local ok, err = red:connect(conf.redis_host, conf.redis_port)
  if not ok then
      kong.log.err("Failed to connect to Redis: ", err)
      kong.response.exit(503, {message = "Failed to connect to Redis"})
      return
  end

  local prefix = conf.redis_prefix or "kong"
  local cookie = conf.cookie_name or "sessionid"
  local audience = conf.audience or "default"

  local anchor_key = prefix .. ":" .. cookie .. ":" .. audience .. ":" .. subject
  local sessions, err = red:zrange(anchor_key, 0, -1)
  if err then
      kong.log.err("Failed to fetch session IDs from Redis: ", err)
      red:close()
      kong.response.exit(500, {message = "Failed to fetch session IDs from Redis"})
      return
  end

  local terminated_sessions = {}
  if sessions then
    for i, session_id in ipairs(sessions) do
      local session_key = prefix .. ":" .. cookie .. ":" .. session_id
      local ok, err = red:del(session_key)
      if err then
          kong.log.err("Failed to delete session key: ", session_key, " error: ", err)
      else
          table.insert(terminated_sessions, session_id)
      end
    end
  end

  local ok, err = red:del(anchor_key)
  if err then
      kong.log.err("Failed to delete anchor key: ", anchor_key, " error: ", err)
  end

  red:close()

  kong.response.set_header("Content-Type", "application/json")
  kong.response.exit(200, cjson.encode({ success = true, terminated_sessions = terminated_sessions }))
end

return plugin