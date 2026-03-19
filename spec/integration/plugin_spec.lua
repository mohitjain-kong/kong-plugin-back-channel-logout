local helpers = require "spec.helpers"

local PLUGIN_NAME = "back-channel-logout"

-- ──────────────────────────────────────────────────────────────────────────
-- TODO: fill in required config fields, then set READY = true
-- ──────────────────────────────────────────────────────────────────────────
local READY = false
local plugin_config = {
  -- e.g. jwks_url = "https://your-idp.com/.well-known/jwks.json",
}
-- ──────────────────────────────────────────────────────────────────────────

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. " integration tests [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      if not READY then return end

      local bp = helpers.get_db_utils(strategy, {
        "routes", "services", "plugins",
      }, { PLUGIN_NAME })

      local service = bp.services:insert({ url = "http://httpbin.konghq.com/get" })
      local route   = bp.routes:insert({ paths = { "/" }, service = service })

      bp.plugins:insert({ route = route, name = PLUGIN_NAME, config = plugin_config })

      assert(helpers.start_kong({
        database = strategy,
        plugins  = "bundled," .. PLUGIN_NAME,
      }))
    end)

    lazy_teardown(function()
      if not READY then return end
      helpers.stop_kong()
    end)

    before_each(function()
      if not READY then return end
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    it("returns 200 on proxied request", function()
      if not READY then
        pending("Set READY = true and fill in plugin_config to run integration tests")
        return
      end
      local res = assert(client:send({ method = "GET", path = "/" }))
      assert.res_status(200, res)
    end)

    -- TODO: add more assertions specific to plugin behaviour
  end)
end
