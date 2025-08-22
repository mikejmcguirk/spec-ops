vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
    group = vim.api.nvim_create_augroup("load-spec-ops", { clear = true }),
    once = true,
    callback = function()
        require("spec-ops").setup({})
    end,
})
