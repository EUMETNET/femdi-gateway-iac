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
    -- your original schema here, unchanged for brevity
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

-- Extract apikey query param in access phase
function _M.access(conf, ctx)
    local args = ngx.req.get_uri_args()
    core.log.warn("dynamic-response-rewrite: ngx.req.get_uri_args() table: ", core.json.encode(args))
    ctx.apikey = args.apikey or ""
    core.log.warn("dynamic-response-rewrite: extracted apikey from query in access phase: ", ctx.apikey)

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

    core.log.warn("dynamic-response-rewrite: ctx.apikey in body_filter: ", ctx.apikey)

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
            -- Only append apikey to URLs matched by the regex
            local function append_apikey_to_url(url)
                if ctx.apikey and ctx.apikey ~= "" then
                    if url:find("?", 1, true) then
                        return url .. "&apikey=" .. ctx.apikey
                    else
                        return url .. "?apikey=" .. ctx.apikey
                    end
                end
                return url
            end

            local new_body, n, err
            if filter.scope == "once" then
                new_body, n, err = re_sub(body, filter.regex, function(m)
                    return append_apikey_to_url(m[0])
                end, filter.options)
            else
                new_body, n, err = re_gsub(body, filter.regex, function(m)
                    return append_apikey_to_url(m[0])
                end, filter.options)
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
