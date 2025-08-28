local reg_utils = require("spec-ops.reg-utils")

--- @alias SpecOpsRegHandlerOpt "default"|"target_only"|"ring"|fun( ctx: reg_handler_ctx): string[]

--- @class (exact) SpecOpsGlobalConfig
--- @field reg_handler? SpecOpsRegHandlerOpt

--- @class (exact) SpecOpsOpConfig
--- @field enabled? boolean

--- @class (exact) SpecOpsOpsConfigs
--- @field change? SpecOpsOpConfig
--- @field delete? SpecOpsOpConfig
--- @field paste? SpecOpsOpConfig
--- @field substitute? SpecOpsOpConfig
--- @field yank? SpecOpsOpConfig

--- @class (exact) SpecOpsConfig
--- @field global? SpecOpsGlobalConfig
--- @field ops? SpecOpsOpsConfigs

local M = {}

-- TODO: Each op should store its own config in an OpConfig table and be able to report its config
-- TODO: Make sure that re-initialization is possible

local ops = {
    change = {
        setup_fun = require("spec-ops.change").setup,
    },
    delete = {
        setup_fun = require("spec-ops.delete").setup,
    },
    paste = {
        setup_fun = require("spec-ops.paste").setup,
    },
    substitute = {
        setup_fun = require("spec-ops.substitute").setup,
    },
    yank = {
        setup_fun = require("spec-ops.yank").setup,
    },
}

--- @param reg_handler SpecOpsRegHandlerOpt
--- @return fun( ctx: reg_handler_ctx): string[]
local function validate_reg_hander(reg_handler)
    if type(reg_handler) == "function" then
        return reg_handler
    elseif type(reg_handler) == "string" then
        return reg_utils.get_handler(reg_handler)
    else
        return reg_utils.get_handler("default")
    end
end

function M.setup()
    local g_spec_ops = vim.g.spec_ops or {}

    local global = g_spec_ops.global or {}

    local reg_handler = validate_reg_hander(global.reg_handler) --- @type SpecOpsRegHandlerOpt

    local ops_cfg = g_spec_ops.ops or {} --- @type SpecOpsOpsConfigs
    for k, v in pairs(ops) do
        local ops_cfg_k = ops_cfg[k] or {}
        if ops_cfg_k.enabled or ops_cfg_k.enabled == nil then
            local op_reg_handler = (function()
                if ops_cfg_k.reg_handler then
                    return validate_reg_hander(ops_cfg_k.reg_handler)
                else
                    return reg_handler
                end
            end)()

            v.setup_fun({ reg_handler = op_reg_handler })
        end
    end
end

return M
