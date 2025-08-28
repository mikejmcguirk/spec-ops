local blk_utils = require("spec-ops.block-utils")

---------------
-- Behaviors --
---------------

local utils = require("spec-ops.utils")

local M = {}

--- @class RegHandlerCtx
--- @field lines? string[]
--- @field op string "y"|"p"|"d"
--- @field reg string
--- @field vmode boolean

--- @class SpecOpsRegInfo
--- @field lines? string[]
--- @field reg string
--- @field text string
--- @field type string
--- @field vtype string

--- @alias RegHandlerStrs "target_only"|"base"|"ring"

-- TODO: Weird question - Do we handle reg validity here or in the ops? If you do it here, anyone
-- who wants to make a custom handler has to do it themselves. But if you don't, then you're
-- firing and forgetting the register. You're relying on spooky action at a distance

-- PERF: I have table extends here for clarity, but they are unnecessary heap allocations
-- Same with inlining the delete_cmds table instead of storing it persistently
-- Same with creating locals for every part of ctx

-- PERF: Right now I'm trying to cover the 'if op_type == "p" then only return vreg' case as
-- thoroughly as possible. But this checking is redundant and should be pared back

--- @param ctx RegHandlerCtx
--- @return string[]
---  See :h registers
---  If ctx.op is "p", will return ctx.reg or a fallback
---  For op values of "y" or "d", will calculate a combination of registers to write to
---  in line with Neovim's defaults
---  If ctx.reg is the black hole, simply returns that value
function M.base_handler(ctx)
    ctx = ctx or {}

    local default_reg = utils.get_default_reg() --- @type string
    local reg = (function()
        if utils.is_valid_register(ctx.reg) then
            return ctx.reg
        else
            return default_reg
        end
    end)() --- @type string

    ctx.op = ctx.op or "p"
    if reg == "_" or ctx.op == "p" then
        return { reg }
    end

    ctx.lines = ctx.lines or { "" } -- Fallback should not trigger a ring movement on delete

    local reges = { '"' }
    if reg ~= '"' then
        table.insert(reges, reg)
    end

    if ctx.op == "d" and not ctx.vmode then
        if #ctx.lines == 1 and reg ~= default_reg then
            -- Known issue: When certain motions are used, the 1 register is written in addition
            -- to the small delete register. That behavior is omitted
            -- CORE: Would be useful to see the last omode text object/motion
            return vim.tbl_extend("force", reges, { "-" })
        else
            -- NOTE: The possibility of the calling function erroring after this is run is
            -- accepted in order to keep register behavior centralized
            for i = 9, 2, -1 do
                local old_reg = vim.fn.getreginfo(tostring(i - 1)) --- @type table
                vim.fn.setreg(tostring(i), old_reg.regcontents, old_reg.regtype)
            end

            table.insert(reges, "1")
            return reges
        end
    end

    if reg == default_reg then
        table.insert(reges, "0")
        return reges
    else
        return reges
    end
end

--- @param ctx RegHandlerCtx
--- @return string[]
--- Validates ctx.reg, returning either it or a fallback to the default reg
--- TODO: Does not quite work, because unnamed is still pointend at zero
function M.target_only_handler(ctx)
    ctx = ctx or {}

    if utils.is_valid_register(ctx.reg) then
        return { ctx.reg }
    else
        return { utils.get_default_reg() }
    end
end

--- @param ctx RegHandlerCtx
--- @return string[]
--- If yanking, changing, or deleting (ctx.op "y", "c", or "d"), write a copy to reg 0,
--- incrementing the other numbered registers to store history
--- If the op is paste (ctx.op = "p"), a numbered register is passed, or the black hole register
--- is passed, only the input register will be returned and the history will not be incremented
function M.ring_handler(ctx)
    ctx = ctx or {}

    local reg = (function()
        if utils.is_valid_register(ctx.reg) then
            return ctx.reg
        else
            return utils.get_default_reg()
        end
    end)() --- @type string

    if reg == "_" or reg:match("^%d$") or ctx.op == "p" then
        return { reg }
    end

    for i = 9, 1, -1 do
        local old_reg = vim.fn.getreginfo(tostring(i - 1)) --- @type table
        vim.fn.setreg(tostring(i), old_reg.regcontents, old_reg.regtype)
    end

    return { reg, "0" }
end

--- @param handler_str? RegHandlerStrs
--- @return fun( ctx: RegHandlerCtx): string[]
function M.get_handler(handler_str)
    handler_str = handler_str or "ring"

    if handler_str == "target_only" then
        return M.target_only_handler
    elseif handler_str == "base" then
        return M.base_handler
    else
        return M.ring_handler
    end
end

local function regtype_from_vtype(vtype)
    local short_vtype = string.sub(vtype, 1, 1)
    if short_vtype == "\22" then
        local width = string.sub(vtype, 2, #vtype)
        return "b" .. width
    elseif short_vtype == "V" then
        return "l"
    else
        return "c"
    end
end

-- TODO: Need to clamp paste returns to one here
-- TODO: If we do it this way, try to stay out of doing it as text entirely

--- @param op_state OpState
--- @return nil
--- Edit op_state.reg_info in place
--- An empty table will be set if the black hole register is passed in
function M.get_reginfo(op_state)
    op_state = op_state or {}
    -- NOTE: op_state.reg_info should be nil'd when a new vreg_pre is set
    if op_state.reginfo then
        return
    end

    local reg_handler_ctx = {
        lines = op_state.lines,
        op = op_state.op_type,
        reg = op_state.vreg,
        vmode = op_state.vmode,
    } --- @type RegHandlerCtx

    local reges = (function()
        if op_state.op_type == "p" then
            return M.target_only_handler(reg_handler_ctx)
        else
            return op_state.reg_handler(reg_handler_ctx)
        end
    end)() --- @type string[]

    local r = {} --- @type SpecOpsRegInfo[]

    if vim.tbl_contains(reges, "_") then
        op_state.reginfo = {}
        return
    end

    -- TODO: Put both lines and text in here, then let the repeat function use the data it wants
    -- TODO: Imply regtype based on trailing \n when necessary
    -- PERF: Adding both lines and text is cumbersome
    for _, reg in pairs(reges) do
        local reginfo = vim.fn.getreginfo(reg)
        local text = vim.fn.getreg(reg) or ""
        local vtype = reginfo.regtype or "v"
        local type = regtype_from_vtype(vtype)

        table.insert(r, { reg = reg, text = text, type = type, vtype = vtype })
    end

    op_state.reginfo = r
end

-- MAYBE: You could scan the lines to check them against some condition, but that would potentially
-- cause more performance lag then occasionally letting a "bad" paste through, whatever that means
-- Potential user hook

--- @param op_state OpState
--- @return boolean
function M.can_set_reginfo(op_state)
    if #op_state.reginfo < 1 then
        return false --- Black hole register
    end

    if not op_state.reginfo[1].text or #op_state.reginfo[1].text < 1 then
        return false
    end

    return true
end

--- @param op_state OpState
--- @return boolean
--- This function assumes that, if the black hole register was specified, it will receive an
--- empty op_state.reg_info table
function M.set_reges(op_state)
    local reg_info = op_state.reginfo or {} --- @type SpecOpsRegInfo[]
    if (not reg_info) or #reg_info < 1 then
        return false
    end

    local lines = op_state.lines or { "" }
    local motion = op_state.motion or "char"

    local text = table.concat(lines, "\n") .. (motion == "line" and "\n" or "") --- @type string
    local regtype = (function()
        if motion == "block" then
            return "b" .. blk_utils.get_block_reg_width(lines) or nil
        elseif motion == "line" then
            return "l"
        else
            return "c"
        end
    end)()

    for _, reg in pairs(reg_info) do
        vim.fn.setreg(reg.reg, text, regtype)
    end

    -- TODO: op_state needs to contain a fire TextYankPost flag
    vim.api.nvim_exec_autocmds("TextYankPost", {
        buffer = vim.api.nvim_get_current_buf(),
        data = {
            inclusive = true,
            operator = op_state.op_type,
            regcontents = op_state.lines,
            regname = op_state.vreg,
            regtype = utils.regtype_from_motion(op_state.motion),
            visual = op_state.vmode,
        },
    })

    return true
end
return M
