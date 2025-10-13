--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

-- This plugin is based on the official APISIX response-rewrite plugin.
-- The core logic for response header and body modification is reused from the original implementation.
-- Additional functionality has been added to support dynamic appending of an API key to URLs in the response body.
-- Specifically, the plugin:
--   - Extracts the API key from the request query string in the access phase.
--   - Rewrites matched URLs in the response body to append the API key as a query parameter,
--     ensuring no duplicate apikey parameters are present.
-- All other response-rewrite features (headers, body, status code, filters) remain unchanged.
-- Original source: https://github.com/apache/apisix/blob/master/apisix/plugins/response-rewrite.lua
-- License: Apache License, Version 2.0
local core        = require("apisix.core")
local expr        = require("resty.expr.v1")
local re_compile  = require("resty.core.regex").re_match_compile
local plugin_name = "dynamic-response-rewrite"
local ngx         = ngx
local ngx_header  = ngx.header
local re_sub      = ngx.re.sub
local re_gsub     = ngx.re.gsub
local pairs       = pairs
local ipairs      = ipairs
local type        = type
local pcall       = pcall
local content_decode = require("apisix.utils.content-decode")

local lrucache = core.lrucache.new({
    type = "plugin",
})

local schema = {
    type = "object",
    properties = {
        headers = {
            description = "new headers for response",
            anyOf = {
                {
                    type = "object",
                    minProperties = 1,
                    patternProperties = {
                        ["^[^:]+$"] = {
                            oneOf = {
                                {type = "string"},
                                {type = "number"},
                            }
                        }
                    },
                },
                {
                    properties = {
                        add = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "string",
                                -- "Set-Cookie: <cookie-name>=<cookie-value>; Max-Age=<number>"
                                pattern = "^[^:]+:[^:]*[^/]$"
                            }
                        },
                        set = {
                            type = "object",
                            minProperties = 1,
                            patternProperties = {
                                ["^[^:]+$"] = {
                                    oneOf = {
                                        {type = "string"},
                                        {type = "number"},
                                    }
                                }
                            },
                        },
                        remove = {
                            type = "array",
                            minItems = 1,
                            items = {
                                type = "string",
                                -- "Set-Cookie"
                                pattern = "^[^:]+$"
                            }
                        },
                    },
                }
            }
        },
        body = {
            description = "new body for response",
            type = "string",
        },
        body_base64 = {
            description = "whether new body for response need base64 decode before return",
            type = "boolean",
            default = false,
        },
        status_code = {
            description = "new status code for response",
            type = "integer",
            minimum = 200,
            maximum = 598,
        },
        vars = {
            type = "array",
        },
        filters = {
            description = "a group of filters that modify response body" ..
                          "by replacing one specified string by another",
            type = "array",
            minItems = 1,
            items = {
                description = "filter that modifies response body",
                type = "object",
                required = {"regex", "replace"},
                properties = {
                    regex = {
                        description = "match pattern on response body",
                        type = "string",
                        minLength = 1,
                    },
                    scope = {
                        description = "regex substitution range",
                        type = "string",
                        enum = {"once", "global"},
                        default = "once",
                    },
                    replace = {
                        description = "regex substitution content",
                        type = "string",
                    },
                    options = {
                        description = "regex options",
                        type = "string",
                        default = "jo",
                    }
                },
            },
        },
    },
    dependencies = {
        body = {
            ["not"] = {required = {"filters"}}
        },
        filters = {
            ["not"] = {required = {"body"}}
        }
    }
}

local _M = {
    version  = 0.1,
    priority = 901, -- higher than default response-rewrite plugin
    name     = plugin_name,
    schema   = schema,
}

local function vars_matched(conf, ctx)
    if not conf.vars then
        return true
    end

    if not conf.response_expr then
        local response_expr, _ = expr.new(conf.vars)
        conf.response_expr = response_expr
    end

    local match_result = conf.response_expr:eval(ctx.var)

    return match_result
end

-- Extract apikey query param in access phase (before proxied to upstream)
function _M.access(conf, ctx)
    local args = ngx.req.get_uri_args()
    ctx.apikey = args.apikey or ""
end

function _M.header_filter(conf, ctx)
    ctx.response_rewrite_matched = vars_matched(conf, ctx)
    if not ctx.response_rewrite_matched then
        return
    end

    if conf.status_code then
        ngx.status = conf.status_code
    end

    if conf.filters or conf.body then
        local response_encoding = ngx_header["Content-Encoding"]
        core.response.clear_header_as_body_modified()
        ctx.response_encoding = response_encoding
    end

    if not conf.headers then
        return
    end

    -- Original header operations (unchanged)
    local function create_header_operation(hdr_conf)
        local set = {}
        local add = {}
        if
            (hdr_conf.add and type(hdr_conf.add) == "table")
            or (hdr_conf.set and type(hdr_conf.set) == "table")
        then
            if hdr_conf.add then
                for _, value in ipairs(hdr_conf.add) do
                    local m, err = ngx.re.match(value, [[^([^:\s]+)\s*:\s*([^:]+)$]], "jo")
                    if not m then
                        return nil, err
                    end
                    core.table.insert_tail(add, m[1], m[2])
                end
            end

            if hdr_conf.set then
                for field, value in pairs(hdr_conf.set) do
                    core.table.insert_tail(set, field, value)
                end
            end
        else
            for field, value in pairs(hdr_conf) do
                core.table.insert_tail(set, field, value)
            end
        end

        return {
            add = add,
            set = set,
            remove = hdr_conf.remove or {},
        }
    end

    local hdr_op, err = core.lrucache.plugin_ctx(lrucache, ctx, nil, create_header_operation, conf.headers)
    if not hdr_op then
        core.log.error("failed to create header operation: ", err)
        return
    end

    for i = 1, #hdr_op.add, 2 do
        local val = core.utils.resolve_var(hdr_op.add[i + 1], ctx.var)
        core.response.add_header(hdr_op.add[i], val)
    end

    for i = 1, #hdr_op.set, 2 do
        local val = core.utils.resolve_var(hdr_op.set[i + 1], ctx.var)
        core.response.set_header(hdr_op.set[i], val)
    end

    for i = 1, #hdr_op.remove do
        core.response.set_header(hdr_op.remove[i], nil)
    end
end


function _M.body_filter(conf, ctx)
    if not ctx.response_rewrite_matched then
        return
    end

    if conf.filters then
        local body = core.response.hold_body_chunk(ctx)
        if not body then
            return
        end

        local err
        if ctx.response_encoding ~= nil then
            local decoder = content_decode.dispatch_decoder(ctx.response_encoding)
            if not decoder then
                core.log.error("filters may not work as expected due to unsupported encoding: ", ctx.response_encoding)
                return
            end
            body, err = decoder(body)
            if err then
                core.log.error("filters may not work as expected: ", err)
                return
            end
        end

        for _, filter in ipairs(conf.filters) do
            -- Rewrite domain, preserve path/query/fragment, and append apikey
            local function rewrite_url(m)
                -- m[0] is the full match, m[1] is the captured path/query/fragment
                local rest = m[1] or ""
                -- Remove any existing apikey from query string
                rest = rest:gsub("([?&])apikey=[^&#]*(&?)", function(sep, nextsep)
                    if sep == "?" and nextsep == "&" then
                        return "?"
                    elseif sep == "&" and nextsep == "&" then
                        return "&"
                    else
                        return sep == "?" and "?" or ""
                    end
                end)
                -- Remove trailing ? or & if left after removal
                rest = rest:gsub("[?&]$", "")

                -- Split rest at # to handle fragment
                local main_part, fragment = rest:match("^(.-)(#.*)$")
                if not main_part then
                    main_part = rest
                    fragment = ""
                end

                local new_url = filter.replace .. main_part
                if ctx.apikey and ctx.apikey ~= "" then
                    if new_url:find("?", 1, true) then
                        new_url = new_url .. "&apikey=" .. ctx.apikey
                    else
                        new_url = new_url .. "?apikey=" .. ctx.apikey
                    end
                end
                new_url = new_url .. fragment
                return new_url
            end

            local new_body, n, err
            if filter.scope == "once" then
                new_body, n, err = re_sub(body, filter.regex, rewrite_url, filter.options)
            else
                new_body, n, err = re_gsub(body, filter.regex, rewrite_url, filter.options)
            end

            if err then
                core.log.error("regex \"" .. filter.regex .. "\" substitution failed: " .. err)
                goto continue_filter -- skip appending apikey for this filter due to error
            end

            body = new_body

            ::continue_filter::
        end

        ngx.arg[1] = body
        return
    end

    if conf.body then
        ngx.arg[2] = true
        if conf.body_base64 then
            ngx.arg[1] = ngx.decode_base64(conf.body)
        else
            ngx.arg[1] = conf.body
        end
    end
end


return _M
