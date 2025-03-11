-- jupynvim/lua/jupynvim/init.lua
local M = {}

function M.setup(opts)
	-- Set up file type detection for .ipynb files
	vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
		pattern = "*.ipynb",
		callback = function(args)
			M.open_notebook(args.match)
		end,
	})
end

function M.open_notebook(filename)
	-- Read the file content
	local file = io.open(filename, "r")
	if not file then
		vim.notify("Failed to open file: " .. filename, vim.log.levels.ERROR)
		return
	end

	local content = file:read("*all")
	file:close()

	-- Parse JSON content
	local status, notebook = pcall(vim.fn.json_decode, content)
	if not status then
		vim.notify("Failed to parse notebook JSON", vim.log.levels.ERROR)
		return
	end

	-- Create a new buffer for the notebook
	local buf = vim.api.nvim_create_buf(true, false)
	local lines = {}

	-- Display cells
	for i, cell in ipairs(notebook.cells or {}) do
		-- Add cell header
		table.insert(lines, "-- " .. string.upper(cell.cell_type or "UNKNOWN") .. " CELL --")

		-- Add cell content
		if cell.source then
			if type(cell.source) == "table" then
				-- Join and add source lines
				for _, line in ipairs(cell.source) do
					table.insert(lines, line:gsub("\n$", ""))
				end
			elseif type(cell.source) == "string" then
				-- Add source as string
				for line in cell.source:gmatch("[^\r\n]+") do
					table.insert(lines, line)
				end
			end
		else
			table.insert(lines, "")
		end

		-- Add empty line between cells
		table.insert(lines, "")
	end

	-- Set buffer lines
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Set buffer options
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	vim.api.nvim_buf_set_option(buf, "filetype", "jupynvim")

	-- Switch to the buffer
	vim.api.nvim_set_current_buf(buf)
end

return M
