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

	if not content or content == "" then
		vim.notify("File is empty: " .. filename, vim.log.levels.ERROR)
		return nil
	end

	-- Parse JSON content
	local status, notebook = pcall(vim.fn.json_decode, content)
	if not status then
		vim.notify("Failed to parse notebook JSON: " .. tostring(notebook), vim.log.levels.ERROR)
		return nil
	end

	-- Verify minimum notebook structure
	if not notebook.cells then
		vim.notify("Invalid notebook format: missing cells array", vim.log.levels.ERROR)
		notebook.cells = {}
	end

	return notebook
end

-- Convert a notebook table back to JSON
function M.notebook_to_json(notebook)
	if not notebook then
		vim.notify("Cannot encode nil notebook to JSON", vim.log.levels.ERROR)
		return nil
	end

	local status, json = pcall(vim.fn.json_encode, notebook)
	if not status then
		vim.notify("Failed to encode notebook to JSON: " .. tostring(json), vim.log.levels.ERROR)
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
	if not cell then
		vim.notify("Cannot extract content from nil cell", vim.log.levels.DEBUG)
		return ""
	end

	if not cell.source then
		vim.notify("Cell missing source property", vim.log.levels.DEBUG)
		return ""
	end

	if type(cell.source) == "string" then
		-- Handle case where source is directly a string
		return cell.source
	elseif type(cell.source) == "table" then
		-- Join source lines for cells
		return table.concat(cell.source, "")
	else
		vim.notify("Unexpected source type: " .. type(cell.source), vim.log.levels.DEBUG)
		return ""
	end
end

-- Create a new cell
function M.create_cell(cell_type, content)
	local cell = {
		cell_type = cell_type or "code",
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
	if cell.cell_type == "code" then
		cell.outputs = {}
		cell.execution_count = nil
	end

	return cell
end

return M
