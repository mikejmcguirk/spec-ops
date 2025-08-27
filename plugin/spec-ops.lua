-- TODO: The user should be able to set a vim.g variable to set custom load events, or simply
-- call the setup function manually
-- TODO: Figure out how lazy.nvim loads plugins and makes this work with that

vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
    group = vim.api.nvim_create_augroup("load-spec-ops", { clear = true }),
    once = true,
    callback = function()
        require("spec-ops").setup()
    end,
})
