local reg_utils = require("spec-ops.reg-utils")

--- @alias SpecOpsRegHandlerOpt "default"|"target_only"|"ring"|fun( ctx: reg_handler_ctx): string[]

local M = {}

local operators = {
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

function M.setup()
    local g_spec_ops = vim.g.spec_ops or {}
    local reg_handler = g_spec_ops.reg_handler or "ring" --- @type SpecOpsRegHandlerOpt

    if type(reg_handler) == "string" then
        reg_handler = reg_utils.get_handler(reg_handler)
    elseif type(reg_handler) ~= "function" then
        reg_handler = reg_utils.get_handler("default")
    end

    -- NOTE: Each operator should take the same config class
    for _, o in pairs(operators) do
        o.setup_fun({ reg_handler = reg_handler })
    end
end

return M
