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

-- TODO: Input config has to be one table because the ergonomics of splitting it up are terrible
-- It then follows that the config needs to have a monolithic type in order to reduce the amount of
-- boilerplate required form the user to get proper Lua_Ls hints. This is easy with global
-- I guess then what you would do is have the varoius fields be ? fields so the user doesn't get
-- missing-field diagnostics.
-- The final layer to this is what to do with config storage. I think, fortunately, this is an
-- easy problem. The vim.g variable sticks around. If the user wants to edit it later they can
-- If the user wants to re-run setup, I don't see why they shouldn't be able to do that. So in the
-- individual Ops, we would just make sure that a re-initialization clears state. The one gap is
-- that I don't know how you clear dot-repeat. There's also the keymap issue. Broadly, I don't
-- think that re-initializing should be advertised behavior, but there's no reason it shouldn't be
-- possible for someone who wants to
-- One note on config storage - right now it's pushed down to local variables in each of the op
-- modules. I think it would probably make sense for each module's config to store a copy based on
-- OpConfig. This would help with data consistency. But it should not be necessary, and I don't
-- think it's desirable, for there to be globally accesible state. The ops benefit from
-- module-level encapsulation here. I suppose, as a debug tool, you can have each op return a
-- copy of its cfg

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

-- Common logic between global and individual ops
local function validate_reg_hander(reg_handler)
    --
end

function M.setup()
    local g_spec_ops = vim.g.spec_ops or {}

    local global = g_spec_ops.global or {}

    local reg_handler = global.reg_handler or "ring" --- @type SpecOpsRegHandlerOpt
    if type(reg_handler) == "string" then
        reg_handler = reg_utils.get_handler(reg_handler)
    elseif type(reg_handler) ~= "function" then
        reg_handler = reg_utils.get_handler("default")
    end

    local ops_cfg = g_spec_ops.ops or {} --- @type SpecOpsOpsConfigs
    for k, v in pairs(ops) do
        local ops_cfg_k = ops_cfg[k] or {}
        if ops_cfg_k.enabled or ops_cfg_k.enabled == nil then
            v.setup_fun({ reg_handler = reg_handler })
        end
    end
end

return M
