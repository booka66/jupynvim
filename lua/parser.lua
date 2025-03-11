-- jupynvim/lua/jupynvim/parser.lua
local M = {}

-- Config storage
local config = {}

function M.setup(cfg)
	config = cfg
end

-- Parse a notebook file into a Lua table
function M.parse_notebook(filename)
	-- Check if file exists
	local file = io.open(filename, "r")
	if not file then
		vim.notify("Failed to open file: " .. filename, vim.log.levels.ERROR)
		return nil
	end

	-- Read the file content
	local content = file:read("*all")
	file:close()

	-- Parse JSON content
	local status, notebook = pcall(vim.fn.json_decode, content)
	if not status then
		vim.notify("Failed to parse notebook JSON: " .. notebook, vim.log.levels.ERROR)
		return nil
	end

	return notebook
end

-- Convert a notebook table back to JSON
function M.notebook_to_json(notebook)
	local status, json = pcall(vim.fn.json_encode, notebook)
	if not status then
		vim.notify("Failed to encode notebook to JSON: " .. json, vim.log.levels.ERROR)
		return nil
	end

	return json
end

-- Save notebook to file
function M.save_notebook(notebook, filename)
	local json = M.notebook_to_json(notebook)
	if not json then
		return false
	end

	local file = io.open(filename, "w")
	if not file then
		vim.notify("Failed to open file for writing: " .. filename, vim.log.levels.ERROR)
		return false
	end

	file:write(json)
	file:close()
	return true
end

-- Extract cell content from a cell
function M.get_cell_content(cell)
	if cell.cell_type == "code" then
		-- Join source lines for code cells
		return table.concat(cell.source, "")
	elseif cell.cell_type == "markdown" then
		-- Join source lines for markdown cells
		return table.concat(cell.source, "")
	end
	return ""
end

-- Create a new cell
function M.create_cell(cell_type, content)
	local cell = {
		cell_type = cell_type,
		source = {},
		metadata = {},
	}

	-- Add content as source lines
	if content then
		-- Split content into lines
		for line in content:gmatch("[^\r\n]+") do
			table.insert(cell.source, line .. "\n")
		end
	end

	-- Add outputs array for code cells
	if cell_type == "code" then
		cell.outputs = {}
		cell.execution_count = nil
	end

	return cell
end

return M
