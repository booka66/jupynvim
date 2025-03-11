-- jupynvim/lua/jupynvim/commands.lua
local M = {}
local display = require("jupynvim.display")
local parser = require("jupynvim.parser")
local executor = require("jupynvim.executor")

-- Config storage
local config = {}
local connection_file = nil

function M.setup(cfg)
	config = cfg

	-- Set up commands
	vim.api.nvim_create_user_command("JupyExecute", M.execute_current_cell, {})
	vim.api.nvim_create_user_command("JupyNext", M.next_cell, {})
	vim.api.nvim_create_user_command("JupyPrev", M.prev_cell, {})
	vim.api.nvim_create_user_command("JupyAddCell", function(opts)
		M.add_cell(opts.args)
	end, { nargs = "?" })
	vim.api.nvim_create_user_command("JupyDeleteCell", M.delete_cell, {})
	vim.api.nvim_create_user_command("JupyStartKernel", function(opts)
		M.start_kernel(opts.args)
	end, { nargs = "?" })

	-- Set up keymaps
	vim.api.nvim_set_keymap("n", config.keymaps.execute_cell, ":JupyExecute<CR>", { noremap = true, silent = true })
	vim.api.nvim_set_keymap("n", config.keymaps.next_cell, ":JupyNext<CR>", { noremap = true, silent = true })
	vim.api.nvim_set_keymap("n", config.keymaps.prev_cell, ":JupyPrev<CR>", { noremap = true, silent = true })
	vim.api.nvim_set_keymap("n", config.keymaps.add_cell, ":JupyAddCell<CR>", { noremap = true, silent = true })
	vim.api.nvim_set_keymap("n", config.keymaps.delete_cell, ":JupyDeleteCell<CR>", { noremap = true, silent = true })
end

-- Start Jupyter kernel
function M.start_kernel(kernel_name)
	vim.notify("Starting Jupyter kernel...", vim.log.levels.INFO)
	connection_file = executor.start_kernel(kernel_name)
	if connection_file then
		vim.notify("Jupyter kernel started successfully", vim.log.levels.INFO)
	end
end

-- Execute the current cell
function M.execute_current_cell()
	if not connection_file then
		vim.notify("Starting Jupyter kernel...", vim.log.levels.INFO)
		connection_file = executor.start_kernel()
		if not connection_file then
			vim.notify("Failed to start Jupyter kernel", vim.log.levels.ERROR)
			return
		end
	end

	-- Get current cell
	local cell_idx = display.find_current_cell()
	if not cell_idx then
		vim.notify("No cell found at cursor position", vim.log.levels.ERROR)
		return
	end

	-- Update cell content
	display.update_cell_content(cell_idx)

	-- Get cell content
	local cell = vim.g.current_notebook.cells[cell_idx]
	if cell.cell_type ~= "code" then
		vim.notify("Cannot execute non-code cell", vim.log.levels.WARN)
		return
	end

	local content = parser.get_cell_content(cell)

	-- Execute the cell
	vim.notify("Executing cell...", vim.log.levels.INFO)
	local outputs = executor.execute_cell(content, connection_file)

	if outputs then
		-- Update cell outputs
		cell.outputs = outputs
		cell.execution_count = (cell.execution_count or 0) + 1

		-- Re-render notebook
		display.render_notebook(vim.g.current_notebook)

		vim.notify("Cell executed successfully", vim.log.levels.INFO)
	else
		vim.notify("Failed to execute cell", vim.log.levels.ERROR)
	end
end

-- Navigate to next cell
function M.next_cell()
	display.goto_next_cell()
end

-- Navigate to previous cell
function M.prev_cell()
	display.goto_prev_cell()
end

-- Add a new cell
function M.add_cell(cell_type)
	cell_type = cell_type or "code"
	if cell_type ~= "code" and cell_type ~= "markdown" then
		vim.notify("Invalid cell type: " .. cell_type, vim.log.levels.ERROR)
		return
	end

	display.add_cell(cell_type)
end

-- Delete the current cell
function M.delete_cell()
	display.delete_cell()
end

return M
