-- jupynvim/lua/jupynvim/init.lua
local M = {}

-- Import our modules
M.parser = require("jupynvim.parser")
M.executor = require("jupynvim.executor")
M.display = require("jupynvim.display")
M.commands = require("jupynvim.commands")

-- Plugin configuration with defaults
M.config = {
	-- Default Python executable for Jupyter
	python_path = "python",
	-- Default template for new cells
	cell_template = "# %% [markdown]\n# \n\n# %% [code]\n\n",
	-- Keymappings
	keymaps = {
		execute_cell = "<leader>je",
		next_cell = "<leader>j]",
		prev_cell = "<leader>j[",
		add_cell = "<leader>ja",
		delete_cell = "<leader>jd",
	},
}

-- Setup function to initialize the plugin
function M.setup(opts)
	-- Merge user config with defaults
	if opts then
		for k, v in pairs(opts) do
			M.config[k] = v
		end
	end

	-- Initialize modules
	M.parser.setup(M.config)
	M.executor.setup(M.config)
	M.display.setup(M.config)
	M.commands.setup(M.config)

	-- Set up file type detection for .ipynb files
	vim.cmd([[
    augroup JupyNvim
      autocmd!
      autocmd BufRead,BufNewFile *.ipynb lua require('jupynvim').open_notebook()
    augroup END
  ]])
end

-- Function to open a notebook
function M.open_notebook()
	local filename = vim.api.nvim_buf_get_name(0)
	local notebook = M.parser.parse_notebook(filename)
	if notebook then
		M.display.render_notebook(notebook)
	end
end

return M
