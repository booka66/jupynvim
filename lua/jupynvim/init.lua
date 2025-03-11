-- jupynvim/lua/jupynvim/init.lua
local M = {}

-- Helper function for safe string handling
local function safe_string(value)
	if type(value) == "string" then
		return value
	elseif value == nil then
		return ""
	else
		return tostring(value)
	end
end

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
	local ok, notebook = pcall(vim.fn.json_decode, content)
	if not ok or type(notebook) ~= "table" then
		vim.notify("Failed to parse notebook JSON", vim.log.levels.ERROR)
		return
	end

	-- Create a new buffer for the notebook
	local buf = vim.api.nvim_create_buf(true, false)
	local lines = {}

	-- Add header
	table.insert(lines, "# Jupyter Notebook: " .. vim.fn.fnamemodify(filename, ":t"))
	table.insert(lines, "")

	-- Check for cells
	if type(notebook.cells) ~= "table" then
		table.insert(lines, "No cells found in notebook")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_set_current_buf(buf)
		return
	end

	-- Display cells
	for i, cell in ipairs(notebook.cells) do
		-- Check cell structure
		if type(cell) ~= "table" then
			table.insert(lines, "Cell #" .. i .. ": Invalid cell format")
			table.insert(lines, "")
			goto continue
		end

		-- Add cell header
		local cell_type = safe_string(cell.cell_type):upper()
		if cell_type == "" then
			cell_type = "UNKNOWN"
		end
		table.insert(lines, "-- " .. cell_type .. " CELL --")

		-- Process source content
		if cell.source == nil then
			table.insert(lines, "")
		elseif type(cell.source) == "string" then
			-- Split string by newlines
			for line in cell.source:gmatch("([^\r\n]*)[\r\n]?") do
				if line ~= "" then -- Skip empty lines that might come from splitting
					table.insert(lines, line)
				end
			end
		elseif type(cell.source) == "table" then
			-- Join source lines
			for _, src_line in ipairs(cell.source) do
				if type(src_line) == "string" then
					-- Remove trailing newlines
					local line = src_line:gsub("\n$", "")
					table.insert(lines, line)
				end
			end
		else
			table.insert(lines, "[Source in unsupported format: " .. type(cell.source) .. "]")
		end

		-- Add cell footer and separator
		table.insert(lines, "-- END CELL --")
		table.insert(lines, "")

		::continue::
	end

	-- Set buffer lines
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	-- Set buffer options
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	vim.api.nvim_buf_set_option(buf, "filetype", "jupynvim")

	-- Switch to the buffer
	vim.api.nvim_set_current_buf(buf)

	-- Set up basic syntax highlighting
	vim.cmd([[
    syntax clear
    syntax match JupyCell /^-- \w\+ CELL --$/
    syntax match JupyEnd /^-- END CELL --$/
    highlight JupyCell ctermfg=Green guifg=Green
    highlight JupyEnd ctermfg=Gray guifg=Gray
  ]])

	vim.notify("Opened Jupyter notebook in read-only mode", vim.log.levels.INFO)
end

return M
