local blk_utils = require("spec-ops.block-utils")
local cycle = require("spec-ops.cycle")
local get_utils = require("spec-ops.get-utils")
local op_utils = require("spec-ops.op-utils")
local paste_utils = require("spec-ops.paste-utils")
local reg_utils = require("spec-ops.reg-utils")
local set_utils = require("spec-ops.set-utils")
local shared = require("spec-ops.shared")
local utils = require("spec-ops.utils")

local M = {}

local hl_group = "SpecOpsPaste" --- @type string
vim.api.nvim_set_hl(0, hl_group, { link = "Boolean", default = true })
local hl_ns = vim.api.nvim_create_namespace("spec-ops.paste-highlight") --- @type integer
local hl_timeout = 175 --- @type integer

local op_state = nil --- @type OpState

local before = false --- @type boolean
local force_linewise = false --- @type boolean
local yank_old = false --- @type boolean

local function paste_norm(opts)
    opts = opts or {}
    before = opts.before
    force_linewise = opts.force_linewise

    op_utils.set_op_state_pre(op_state)

    vim.o.operatorfunc = "v:lua.require'spec-ops.paste'.paste_norm_callback"
    return "g@l"
end

local function paste_visual(opts)
    opts = opts or {}
    yank_old = opts.yank_old

    op_utils.set_op_state_pre(op_state)

    vim.o.operatorfunc = "v:lua.require'spec-ops.paste'.paste_visual_callback"
    return "g@"
end

-- TODO: Another to add to the setup hooks
local function should_reindent(ctx)
    ctx = ctx or {}
    return ctx.on_blank or ctx.regtype == "V" or ctx.motion == "line"
end

-- TODO: Should be able to pass a nil reg_handler to get_new_op_state and have it work so long
-- as op_type == "p"
-- TODO: Document that any reg-handler input for paste will be ignored

function M.setup(opts)
    opts = opts or {}

    local reg_handler = opts.reg_handler or reg_utils.get_handler()
    op_state = op_utils.get_new_op_state(hl_group, hl_ns, hl_timeout, reg_handler, "p")

    vim.keymap.set("n", "<Plug>(SpecOpsPasteNormalAfterCursor)", function()
        return paste_norm()
    end, { expr = true, silent = true })

    vim.keymap.set("n", "<Plug>(SpecOpsPasteNormalBeforeCursor)", function()
        return paste_norm({ before = true })
    end, { expr = true, silent = true })

    vim.keymap.set("n", "<Plug>(SpecOpsPasteLinewiseAfter)", function()
        return paste_norm({ force_linewise = true })
    end, { expr = true, silent = true })

    vim.keymap.set("n", "<Plug>(SpecOpsPasteLinewiseBefore)", function()
        return paste_norm({ force_linewise = true, before = true })
    end, { expr = true, silent = true })

    vim.keymap.set("x", "<Plug>(SpecOpsPasteVisual)", function()
        return paste_visual()
    end, { expr = true, silent = true })

    vim.keymap.set("x", "<Plug>(SpecOpsPasteVisualAndYank)", function()
        return paste_visual({ yank_old = true })
    end, { expr = true, silent = true })
end

--- @param cur_op_state OpState
--- Edit op_state in place
--- Adjust marks for paste after cursor
--- If you set text using row, col, row, col, the text is inserted before the col
--- If you set lines using row, row, it will set on the row and push pre-existing text down
--- In both cases, to paste after the end of a line or buffer boundary, the last 1 index is valid
local function adjust_after(cur_op_state)
    if not before then
        return
    end

    assert(
        cur_op_state.marks.start.row == cur_op_state.marks.fin.row,
        "Norm paste rows do not match"
    )
    assert(
        cur_op_state.marks.start.col == cur_op_state.marks.fin.col,
        "Norm paste cols do not match"
    )

    if cur_op_state.motion == "line" then
        cur_op_state.marks.start.row = cur_op_state.marks.start.row + 1

        -- PERF: Should not be necessary since strict indexing is not used, but will keep here
        -- for now
        local line_count = vim.api.nvim_buf_get_line_count(0)
        cur_op_state.marks.start.row = math.min(cur_op_state.marks.start.row, line_count)
        cur_op_state.marks.fin.row = cur_op_state.marks.start.row

        local row = cur_op_state.marks.start.row
        local new_start = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
        -- PERF: Not sure if this is necessary since we're setting lines
        cur_op_state.marks.start.col = math.min(cur_op_state.marks.start.col, #new_start)
        cur_op_state.marks.fin.col = cur_op_state.marks.start.col
    else
        local col = cur_op_state.marks.start.col --- @type integer
        local start_line = cur_op_state.start_line_pre --- @type string

        --- @type integer|nil, integer|nil, string|nil
        local _, fin_byte, _ = blk_utils.byte_bounds_from_col(start_line, col)
        assert(fin_byte) -- TODO: This is sloppy

        cur_op_state.marks.start.col = fin_byte + 1
        cur_op_state.marks.start.col = math.min(cur_op_state.marks.start.col, #start_line)
        cur_op_state.marks.fin.col = cur_op_state.marks.start.col
    end
end

--- @return nil
M.paste_norm_callback = function(motion)
    op_utils.set_op_state_cb(op_state, motion)

    reg_utils.get_reginfo(op_state)
    if not reg_utils.can_set_reginfo(op_state) then
        return
    end

    assert(#op_state.reginfo == 1) --- TODO: Dumb
    op_state.reginfo[1].type = force_linewise and "V" or op_state.reginfo[1].type
    op_utils.op_state_apply_count(op_state)
    adjust_after(op_state)

    local cur_pos = vim.api.nvim_win_get_cursor(0) --- @type {[1]: integer, [2]:integer}
    local on_blankline = op_state.start_line_pre:match("^%s*$") --- @type boolean

    local marks, err = paste_utils.do_paste({
        regtype = regtype,
        cur_pos = cur_pos,
        before = before,
        text = text,
        vcount = vcount,
    }) --- @type op_marks|nil, string|nil

    if (not marks) or err then
        return "paste_norm: " .. (err or ("Unknown error in " .. regtype .. " paste"))
    end

    if should_reindent({ on_blank = on_blankline, regtype = regtype, motion = motion }) then
        marks = utils.fix_indents(marks, cur_pos)
    end

    paste_utils.adj_paste_cursor_default({ marks = marks, regtype = regtype })

    shared.highlight_text(marks, hl_group, hl_ns, hl_timeout, regtype)
end

--- @param text string
--- @return boolean
local function should_yank(text)
    return string.match(text, "%S")
end

function M.paste_visual_callback(motion)
    op_utils.set_op_state_cb(op_state, motion)
    local post = op_state.post

    local marks = utils.get_marks(motion, post.vmode) --- @type op_marks

    local cur_pos = vim.api.nvim_win_get_cursor(0) --- @type {[1]: integer, [2]:integer}
    --- @type string
    local start_line = vim.api.nvim_buf_get_lines(0, cur_pos[1] - 1, cur_pos[1], false)[1]
    local on_blank = not start_line:match("%S") --- @type boolean

    -- TODO: This is silly right now, but the validation logic will be removed from the state
    -- update
    local reges = reg_handler({ op = "p", reg = post.reg, vmode = post.vmode })
    -- TODO: This technically works right now, but is a brittle assumption
    local reg = reges[1]

    --- @diagnostic disable: undefined-field
    local yanked, err_y = get_utils.do_get({
        marks = marks,
        curswant = post.view.curswant,
        motion = motion,
    }) --- @type string[]|nil, string|nil

    if (not yanked) or err_y then
        local err_msg = err_y or "Unknown error getting text to yank" --- @type string
        return vim.notify("paste_visual_callback: " .. err_msg, vim.log.levels.ERROR)
    end

    local regtype = vim.fn.getregtype(reg) --- @type string
    local text = vim.fn.getreg(reg) --- @type string
    if (not text) or text == "" then
        return vim.notify(reg .. " register is empty", vim.log.levels.INFO)
    end

    local curswant = post.view.curswant --- @type integer

    local vcount = vim.v.count1
    local lines = op_utils.setup_text_lines({
        text = text,
        motion = motion,
        regtype = regtype,
        vcount = vcount,
    })

    --- @type op_marks|nil, string|nil
    local post_marks, err_s = set_utils.do_set(lines, marks, regtype, motion, curswant)

    if (not post_marks) or err_s then
        local err_msg = err_s or "Unknown error in do_set"
        return vim.notify("paste_visual_callback: " .. err_msg, vim.log.levels.ERROR)
    end

    if should_reindent({ on_blank = on_blank, regtype = regtype, motion = motion }) then
        post_marks = utils.fix_indents(post_marks, cur_pos)
    end

    if #lines == 1 and regtype == "v" and motion == "block" then
        post_marks.fin.row = post_marks.start.row
        vim.api.nvim_buf_set_mark(0, "]", post_marks.fin.row, post_marks.fin.col, {})
    end

    if #lines == 1 and regtype == "v" then
        vim.api.nvim_win_set_cursor(0, { post_marks.fin.row, post_marks.fin.col })
    else
        vim.api.nvim_win_set_cursor(0, { post_marks.start.row, post_marks.start.col })
    end

    --- @type string
    if yank_old and reg ~= "_" then
        local yank_text = table.concat(yanked, "\n") .. (motion == "line" and "\n" or "")
        if should_yank(yank_text) then
            if motion == "block" then
                vim.fn.setreg(reg, yank_text, "b" .. blk_utils.get_block_reg_width(yanked))
            else
                vim.fn.setreg(reg, yank_text)
            end

            vim.api.nvim_exec_autocmds("TextYankPost", {
                buffer = vim.api.nvim_get_current_buf(),
                data = {
                    inclusive = true,
                    operator = "y",
                    regcontents = lines,
                    regname = reg,
                    regtype = utils.regtype_from_motion(motion),
                    visual = post.vmode,
                },
            })
        end
    end

    cycle.ingest_state(
        motion,
        reg,
        marks,
        post.vmode,
        -- text,
        vim.api.nvim_get_current_buf(),
        vim.api.nvim_get_current_win(),
        before,
        vcount,
        post.view.curswant
    )

    shared.highlight_text(post_marks, hl_group, hl_ns, hl_timeout, regtype)
end

return M
