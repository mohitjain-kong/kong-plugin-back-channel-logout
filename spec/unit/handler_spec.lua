local PLUGIN_NAME = "back-channel-logout"

describe(PLUGIN_NAME .. " unit tests", function()
  local handler
  local conf

  -- Kong PDK stub — extend as needed for your plugin
  local kong_stub = {
    request = {
      get_header   = function() return nil end,
      get_headers  = function() return {} end,
      get_body     = function() return nil, nil end,
      get_raw_body = function() return "" end,
      get_method   = function() return "GET" end,
      get_path     = function() return "/" end,
      get_query    = function() return {} end,
    },
    response = {
      set_header  = function() end,
      get_header  = function() return nil end,
      set_headers = function() end,
      get_status  = function() return 200 end,
      exit        = function() end,
    },
    service = {
      request = {
        set_header       = function() end,
        enable_buffering = function() end,
        set_body         = function() end,
        set_raw_body     = function() end,
      },
      response = {
        get_status  = function() return 200 end,
        get_header  = function() return nil end,
        get_headers = function() return {} end,
        get_body    = function() return nil, nil end,
      },
    },
    log = {
      debug  = function() end,
      info   = function() end,
      notice = function() end,
      warn   = function() end,
      err    = function() end,
    },
    ctx = {},
  }

  before_each(function()
    _G.kong = kong_stub
    handler = require("kong.plugins." .. PLUGIN_NAME .. ".handler")
    conf    = {}
  end)

  after_each(function()
    package.loaded["kong.plugins." .. PLUGIN_NAME .. ".handler"] = nil
  end)

  it("can be required", function()
    assert.not_nil(handler)
  end)

  it("calls a handler phase without error", function()
    -- detect whichever phase the plugin implements
    local phases = { "access", "header_filter", "body_filter", "rewrite", "log", "response" }
    local called = false
    for _, phase in ipairs(phases) do
      if type(handler[phase]) == "function" then
        assert.has_no.errors(function() handler[phase](handler, conf) end)
        called = true
        break
      end
    end
    assert.is_true(called, "handler has no recognised phase method")
  end)

  -- TODO: add assertions specific to plugin behaviour
end)
