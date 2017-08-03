local cjson = require "cjson"
local helpers = require "spec.helpers"

describe("URI encoding", function()
  local client

  setup(function()
    helpers.run_migrations()
    assert(helpers.dao.apis:insert {
      name         = "api-1",
      hosts        = { "mock_upstream" },
      upstream_url = helpers.mock_upstream_url,
    })

    assert(helpers.dao.apis:insert {
      name         = "api-2",
      hosts        = { "mock_upstream" },
      upstream_url = helpers.mock_upstream_url,
    })

    assert(helpers.dao.apis:insert {
      name         = "api-3",
      uris         = "/request",
      strip_uri    = false,
      upstream_url = helpers.mock_upstream_url,
    })

    assert(helpers.dao.apis:insert {
      name         = "api-4",
      uris         = "/stripped-path",
      strip_uri    = true,
      upstream_url = helpers.mock_upstream_url,
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
    client = helpers.proxy_client()
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("issue #1975 does not double percent-encode proxied args", function()
    -- https://github.com/Mashape/kong/pull/1975

    local res = assert(client:send {
      method  = "GET",
      path    = "/get?limit=25&where=%7B%22or%22:%5B%7B%22name%22:%7B%22like%22:%22%25bac%25%22%7D%7D%5D%7D",
      headers = {
        ["Host"] = "mock_upstream",
      },
    })

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.equal("25", json.uri_args.limit)
    assert.equal([[{"or":[{"name":{"like":"%bac%"}}]}]], json.uri_args.where)
  end)

  it("issue #1480 does not percent-encode args unecessarily", function()
    -- behavior might not be correct, but we assert it anyways until
    -- a change is planned and documented.
    -- https://github.com/Mashape/kong/issues/1480

    local res = assert(client:send {
      method  = "GET",
      path    = "/request?param=1.2.3",
      headers = {
        ["Host"] = "mock_upstream",
      },
    })

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.equal(helpers.mock_upstream_protocol .. "://" ..
                 helpers.mock_upstream_host .. "/request?param=1.2.3", json.url)
  end)

  it("issue #749 does not decode percent-encoded args", function()
    -- https://github.com/Mashape/kong/issues/749

    local res = assert(client:send {
      method  = "GET",
      path    = "/request?param=abc%7Cdef",
      headers = {
        ["Host"] = "mock_upstream",
      },
    })

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.equal(helpers.mock_upstream_protocol .. "://" ..
                 helpers.mock_upstream_host .. "/request?param=abc%7Cdef", json.url)
  end)

  it("issue #688 does not percent-decode proxied URLs", function()
    -- https://github.com/Mashape/kong/issues/688

    local res = assert(client:send {
      method  = "GET",
      path    = "/request/foo%2Fbar",
      headers = {
        ["Host"] = "mock_upstream",
      },
    })

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.equal(helpers.mock_upstream_protocol .. "://" ..
                 helpers.mock_upstream_host .. "/request/foo%2Fbar", json.url)
  end)

  it("issue #2512 does not double percent-encode upstream URLs", function()
    -- https://github.com/Mashape/kong/issues/2512

    -- with `hosts` matching
    local res    = assert(client:send {
      method     = "GET",
      path       = "/request/auth%7C123",
      headers    = {
        ["Host"] = "mock_upstream",
      },
    })

    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    assert.matches("/request/auth%7C123", json.url, nil, true)

    -- with `uris` matching
    local res2 = assert(client:send {
      method   = "GET",
      path     = "/request/auth%7C123",
    })

    local body2 = assert.res_status(200, res2)
    local json2 = cjson.decode(body2)

    assert.matches("/request/auth%7C123", json2.url, nil, true)

    -- with `uris` matching + `strip_uri`
    local res3 = assert(client:send {
      method   = "GET",
      path     = "/stripped-path/request/auth%7C123",
    })

    local body3 = assert.res_status(200, res3)
    local json3 = cjson.decode(body3)

    assert.matches("/request/auth%7C123", json3.url, nil, true)
  end)
end)
