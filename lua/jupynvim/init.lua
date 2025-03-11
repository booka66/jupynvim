-- jupynvim/lua/jupynvim/init.lua
local M = {}

-- Store active notebook buffers and data
local notebooks = {}

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

-- Find current cell under cursor (exported to M for use in diagnostics)
function M.find_current_cell(bufnr)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1] - 1
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Track cell boundaries
	local cells = {}
	local current_cell = nil
	local current_start = -1
	local current_type = nil

	-- First pass: identify all cells and their boundaries
	for i, line in ipairs(lines) do
		local idx = i - 1

		-- Cell header detection
		local type_match = line:match("^%-%-[%s]*([%w]+)[%s]*CELL[%s]*%-%-$")
		if type_match then
			-- Start of a new cell
			if current_start ~= -1 then
				-- End the previous cell if we haven't already
				if current_type then
					table.insert(cells, {
						start = current_start,
						end_line = idx - 1,
						type = current_type,
					})
				end
			end

			-- Start a new cell
			current_start = idx
			current_type = type_match:lower()
		elseif line:match("^%-%-[%s]*END[%s]*CELL[%s]*%-%-$") then
			-- End of the current cell
			if current_start ~= -1 and current_type then
				table.insert(cells, {
					start = current_start,
					end_line = idx,
					type = current_type,
				})
				current_start = -1
				current_type = nil
			end
		end
	end

	-- If we have an unclosed cell at the end of the file
	if current_start ~= -1 and current_type then
		table.insert(cells, {
			start = current_start,
			end_line = #lines - 1,
			type = current_type,
		})
	end

	-- Second pass: find which cell contains the cursor
	for _, cell in ipairs(cells) do
		if cursor_line >= cell.start and cursor_line <= cell.end_line then
			return cell
		end
	end

	return nil
end

-- Diagnostic function to help debug issues
function M.diagnose_current_cell()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1] - 1
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Print the current line and a few lines around it
	local start_line = math.max(0, cursor_line - 3)
	local end_line = math.min(#lines, cursor_line + 3)

	vim.notify("Current position: Line " .. cursor_line, vim.log.levels.INFO)
	vim.notify("Context:", vim.log.levels.INFO)

	for i = start_line, end_line do
		local prefix = i == cursor_line and "-> " or "   "
		vim.notify(prefix .. i .. ": " .. lines[i + 1], vim.log.levels.INFO)

		-- If this is a cell header, show what it matches
		local match = lines[i + 1]:match("^%-%-[%s]*([%w]+)[%s]*CELL[%s]*%-%-$")
		if match then
			vim.notify("   Detected cell type: " .. match, vim.log.levels.INFO)
		end
	end

	-- Try to find the current cell using our function
	local cell_info = M.find_current_cell(bufnr)
	if cell_info then
		vim.notify(
			"Found cell: start="
				.. cell_info.start
				.. ", end="
				.. (cell_info.end_line or "?")
				.. ", type="
				.. (cell_info.type or "unknown"),
			vim.log.levels.INFO
		)
	else
		vim.notify("No cell detected at cursor position", vim.log.levels.WARN)
	end
end

-- Extract the content of the current cell
local function get_cell_content(bufnr, cell_info)
	if not cell_info then
		return nil
	end

	-- Get the content lines (excluding the header and footer)
	local content_start = cell_info.start + 1 -- Skip the header
	local content_end = cell_info.end_line or vim.api.nvim_buf_line_count(bufnr) - 1

	local lines = vim.api.nvim_buf_get_lines(bufnr, content_start, content_end, false)
	return table.concat(lines, "\n")
end

-- Add this function to your plugin
function M.check_python_environment()
	local bufnr = vim.api.nvim_get_current_buf()
	local notebook_info = notebooks[bufnr]

	if not notebook_info then
		vim.notify("Not a Jupyter notebook buffer", vim.log.levels.ERROR)
		return
	end

	local python_path = notebook_info.python_path or "python"

	-- Simple test code to check numpy and matplotlib
	local test_code = [[
import sys
print("Python version: " + sys.version.replace("\n", ""))
print("Checking for required packages...")
try:
    import numpy
    print("numpy ✓ " + numpy.__version__)
except ImportError:
    print("numpy ✗ (not installed)")
try:
    import matplotlib
    print("matplotlib ✓ " + matplotlib.__version__)
except ImportError:
    print("matplotlib ✗ (not installed)")
]]

	vim.notify("Checking Python environment...", vim.log.levels.INFO)
	local result = execute_cell(test_code, python_path)
	vim.notify("Python environment check:\n" .. result, vim.log.levels.INFO)
end

-- Then add this to your setup function where you define commands
vim.api.nvim_create_user_command("JupyCheckEnv", function()
	M.check_python_environment()
end, {})

-- Execute cell using Python with improved error handling
local function execute_cell(code, python_path)
	-- Create temporary files
	local code_file = os.tmpname()
	local result_file = os.tmpname()

	-- Write code to temporary file
	local f = io.open(code_file, "w")
	if not f then
		return "Error: Could not create temporary file"
	end
	f:write(code)
	f:close()

	-- Create a more robust Python execution script with better error handling
	local exec_cmd = python_path
		.. ' -c "'
		.. "import sys, json, traceback;"
		.. "try:"
		.. "    code = open('"
		.. code_file
		.. "', 'r').read();"
		.. "    # Add matplotlib configuration for non-interactive environments"
		.. '    if "matplotlib" in code:'
		.. '        setup_code = "import matplotlib\\nmatplotlib.use(\\"Agg\\")\\n";'
		.. "        code = setup_code + code;"
		.. '    result = {"output": "", "error": ""};'
		.. "    try:"
		.. "        from io import StringIO;"
		.. "        old_stdout, old_stderr = sys.stdout, sys.stderr;"
		.. "        captured_out = StringIO();"
		.. "        captured_err = StringIO();"
		.. "        sys.stdout = captured_out;"
		.. "        sys.stderr = captured_err;"
		.. "        exec(code);"
		.. "        sys.stdout = old_stdout;"
		.. "        sys.stderr = old_stderr;"
		.. '        result["output"] = captured_out.getvalue();'
		.. "        err = captured_err.getvalue();"
		.. '        if err: result["error"] = err;'
		.. "    except Exception as e:"
		.. '        result["error"] = "Exception: " + str(e) + "\\n" + traceback.format_exc();'
		.. "    with open('"
		.. result_file
		.. "', 'w') as f:"
		.. "        f.write(json.dumps(result));"
		.. "except Exception as outer_error:"
		.. "    with open('"
		.. result_file
		.. "', 'w') as f:"
		.. '        f.write(json.dumps({"output": "", "error": "Internal execution error: " + str(outer_error)}))"'

	-- Run the command, capturing its output in case of shell errors
	local handle = io.popen(exec_cmd .. " 2>&1")
	local cmd_result = handle:read("*all")
	local _, _, cmd_exit = handle:close()

	-- Read result
	local result = ""
	local rf = io.open(result_file, "r")
	if rf then
		result = rf:read("*all")
		rf:close()
	else
		return "Failed to read execution result. Shell output: " .. cmd_result
	end

	-- Clean up temporary files
	os.remove(code_file)
	os.remove(result_file)

	-- Parse result JSON
	local ok, parsed = pcall(vim.fn.json_decode, result)
	if not ok then
		return "Error parsing execution result: " .. result
	end

	-- Return both output and error if present
	local output = ""
	if parsed.output and parsed.output ~= "" then
		output = parsed.output
	end

	if parsed.error and parsed.error ~= "" then
		if output ~= "" then
			output = output .. "\n\n"
		end
		output = output .. "Error:\n" .. parsed.error
	end

	return output or "No output"
end

-- Execute the current cell
function M.execute_current_cell()
	local bufnr = vim.api.nvim_get_current_buf()
	local notebook_info = notebooks[bufnr]

	if not notebook_info then
		vim.notify("Not a Jupyter notebook buffer", vim.log.levels.ERROR)
		return
	end

	local cell_info = M.find_current_cell(bufnr)
	if not cell_info then
		vim.notify("No cell found at cursor position", vim.log.levels.ERROR)
		return
	end

	-- Extra debug output
	vim.notify("Found cell of type: " .. (cell_info.type or "unknown"), vim.log.levels.INFO)

	-- Compare case-insensitively and more flexibly
	if not cell_info.type or not string.find(string.lower(cell_info.type), "code") then
		vim.notify("Cannot execute non-code cell (type: " .. (cell_info.type or "unknown") .. ")", vim.log.levels.WARN)
		return
	end

	local code = get_cell_content(bufnr, cell_info)
	if not code or code == "" then
		vim.notify("Cell is empty", vim.log.levels.WARN)
		return
	end

	vim.notify("Executing cell...", vim.log.levels.INFO)

	local result = execute_cell(code, notebook_info.python_path or "python")

	-- Display output after the cell
	local output_start = cell_info.end_line + 1
	local next_cell_start = output_start + 1

	-- Find next cell or end of buffer
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i = output_start + 1, #lines do
		if lines[i]:match("^%-%-[%s]*[%w]+[%s]*CELL[%s]*%-%-$") then
			next_cell_start = i
			break
		end
	end

	-- If there's existing output, clear it
	if output_start < next_cell_start - 1 then
		vim.api.nvim_buf_set_lines(bufnr, output_start, next_cell_start - 1, false, {})
	end

	-- Add output
	local output_lines = {}
	table.insert(output_lines, "-- OUTPUT --")

	for line in result:gmatch("[^\r\n]+") do
		table.insert(output_lines, line)
	end

	vim.api.nvim_buf_set_lines(bufnr, output_start, output_start, false, output_lines)

	vim.notify("Cell executed", vim.log.levels.INFO)
end

-- Parse buffer content back into notebook structure
local function buffer_to_notebook(bufnr, notebook_data)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local updated_notebook = vim.deepcopy(notebook_data)
	local cells = {}

	local current_cell = nil
	local cell_content = {}
	local in_cell = false

	for _, line in ipairs(lines) do
		local type_match = line:match("^%-%-[%s]*([%w]+)[%s]*CELL[%s]*%-%-$")
		if type_match then
			-- Start of a new cell
			local cell_type = type_match:lower()
			current_cell = {
				cell_type = cell_type,
				source = {},
				metadata = {},
			}
			if cell_type == "code" then
				current_cell.outputs = {}
				current_cell.execution_count = nil
			end
			in_cell = true
			cell_content = {}
		elseif line:match("^%-%-[%s]*END[%s]*CELL[%s]*%-%-$") then
			-- End of a cell
			if current_cell then
				-- Convert cell_content to source format
				for _, content_line in ipairs(cell_content) do
					table.insert(current_cell.source, content_line .. "\n")
				end
				table.insert(cells, current_cell)
			end
			in_cell = false
		elseif line:match("^%-%-[%s]*OUTPUT[%s]*%-%-$") then
		-- Output marker - skip
		elseif in_cell then
			-- Cell content
			table.insert(cell_content, line)
		end
	end

	updated_notebook.cells = cells
	return updated_notebook
end

-- Save the notebook
function M.save_notebook()
	local bufnr = vim.api.nvim_get_current_buf()
	local notebook_info = notebooks[bufnr]

	if not notebook_info then
		vim.notify("Not a Jupyter notebook buffer", vim.log.levels.ERROR)
		return
	end

	-- Parse buffer content back into notebook structure
	local updated_notebook = buffer_to_notebook(bufnr, notebook_info.data)

	-- Convert to JSON
	local json = vim.fn.json_encode(updated_notebook)

	-- Write to file
	local f = io.open(notebook_info.filename, "w")
	if not f then
		vim.notify("Failed to open file for writing: " .. notebook_info.filename, vim.log.levels.ERROR)
		return
	end

	f:write(json)
	f:close()

	vim.notify("Notebook saved: " .. notebook_info.filename, vim.log.levels.INFO)

	-- Update stored notebook data
	notebook_info.data = updated_notebook
end

-- Add a new cell after the current cell
function M.add_cell(cell_type)
	cell_type = string.upper(cell_type or "CODE")

	local bufnr = vim.api.nvim_get_current_buf()
	if not notebooks[bufnr] then
		vim.notify("Not a Jupyter notebook buffer", vim.log.levels.ERROR)
		return
	end

	local cell_info = M.find_current_cell(bufnr)
	local insert_line

	if cell_info then
		-- Find end of the current cell
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		insert_line = cell_info.end_line + 1

		-- Skip any output
		while insert_line < #lines and lines[insert_line + 1]:match("^%-%-[%s]*OUTPUT[%s]*%-%-$") do
			insert_line = insert_line + 1
		end

		-- Skip until next cell or end
		while insert_line < #lines and not lines[insert_line + 1]:match("^%-%-[%s]*[%w]+[%s]*CELL[%s]*%-%-$") do
			insert_line = insert_line + 1
		end
	else
		-- Add at the end
		insert_line = vim.api.nvim_buf_line_count(bufnr)
	end

	-- Create new cell content
	local new_cell = {
		"-- " .. cell_type .. " CELL --",
		"",
		"-- END CELL --",
		"",
	}

	-- Insert the new cell
	vim.api.nvim_buf_set_lines(bufnr, insert_line, insert_line, false, new_cell)

	-- Move cursor to the empty line in the new cell
	vim.api.nvim_win_set_cursor(0, { insert_line + 2, 0 })
end

-- Navigate to the next cell
function M.goto_next_cell()
	local bufnr = vim.api.nvim_get_current_buf()
	if not notebooks[bufnr] then
		vim.notify("Not a Jupyter notebook buffer", vim.log.levels.ERROR)
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1] - 1
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Find the next cell header
	for i = cursor_line + 1, #lines do
		if lines[i]:match("^%-%-[%s]*[%w]+[%s]*CELL[%s]*%-%-$") then
			-- Move to the line after the header
			vim.api.nvim_win_set_cursor(0, { i + 2, 0 })
			return
		end
	end

	vim.notify("No next cell found", vim.log.levels.INFO)
end

-- Navigate to the previous cell
function M.goto_prev_cell()
	local bufnr = vim.api.nvim_get_current_buf()
	if not notebooks[bufnr] then
		vim.notify("Not a Jupyter notebook buffer", vim.log.levels.ERROR)
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1] - 1
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	-- Find the current cell's header
	local current_cell_start = 0
	for i = 0, cursor_line do
		if lines[i + 1]:match("^%-%-[%s]*[%w]+[%s]*CELL[%s]*%-%-$") then
			current_cell_start = i
		end
	end

	-- Find the previous cell's header
	local prev_cell_start = nil
	for i = 0, current_cell_start - 1 do
		if lines[i + 1]:match("^%-%-[%s]*[%w]+[%s]*CELL[%s]*%-%-$") then
			prev_cell_start = i
		end
	end

	if prev_cell_start then
		-- Move to the line after the header
		vim.api.nvim_win_set_cursor(0, { prev_cell_start + 2, 0 })
	else
		vim.notify("No previous cell found", vim.log.levels.INFO)
	end
end

function M.setup(opts)
	-- Default options
	local options = {
		python_path = opts.python_path or "python",
		keymaps = {
			execute_cell = opts.keymaps and opts.keymaps.execute_cell or "<leader>je",
			add_code_cell = opts.keymaps and opts.keymaps.add_code_cell or "<leader>jc",
			add_markdown_cell = opts.keymaps and opts.keymaps.add_markdown_cell or "<leader>jm",
			save_notebook = opts.keymaps and opts.keymaps.save_notebook or "<leader>js",
			next_cell = opts.keymaps and opts.keymaps.next_cell or "<leader>j]",
			prev_cell = opts.keymaps and opts.keymaps.prev_cell or "<leader>j[",
		},
	}

	-- Set up commands
	vim.api.nvim_create_user_command("JupyExecute", function()
		M.execute_current_cell()
	end, {})
	vim.api.nvim_create_user_command("JupySave", function()
		M.save_notebook()
	end, {})
	vim.api.nvim_create_user_command("JupyAddCode", function()
		M.add_cell("CODE")
	end, {})
	vim.api.nvim_create_user_command("JupyAddMarkdown", function()
		M.add_cell("MARKDOWN")
	end, {})
	vim.api.nvim_create_user_command("JupyNextCell", function()
		M.goto_next_cell()
	end, {})
	vim.api.nvim_create_user_command("JupyPrevCell", function()
		M.goto_prev_cell()
	end, {})
	vim.api.nvim_create_user_command("JupyDiagnose", function()
		M.diagnose_current_cell()
	end, {})

	-- Set up keymaps
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "jupynvim",
		callback = function()
			local bufnr = vim.api.nvim_get_current_buf()

			-- Map keybindings
			vim.api.nvim_buf_set_keymap(
				bufnr,
				"n",
				options.keymaps.execute_cell,
				":JupyExecute<CR>",
				{ noremap = true, silent = true }
			)
			vim.api.nvim_buf_set_keymap(
				bufnr,
				"n",
				options.keymaps.save_notebook,
				":JupySave<CR>",
				{ noremap = true, silent = true }
			)
			vim.api.nvim_buf_set_keymap(
				bufnr,
				"n",
				options.keymaps.add_code_cell,
				":JupyAddCode<CR>",
				{ noremap = true, silent = true }
			)
			vim.api.nvim_buf_set_keymap(
				bufnr,
				"n",
				options.keymaps.add_markdown_cell,
				":JupyAddMarkdown<CR>",
				{ noremap = true, silent = true }
			)
			vim.api.nvim_buf_set_keymap(
				bufnr,
				"n",
				options.keymaps.next_cell,
				":JupyNextCell<CR>",
				{ noremap = true, silent = true }
			)
			vim.api.nvim_buf_set_keymap(
				bufnr,
				"n",
				options.keymaps.prev_cell,
				":JupyPrevCell<CR>",
				{ noremap = true, silent = true }
			)

			-- Display information about keymaps
			vim.notify(
				"Jupyter notebook opened. Keybindings:\n"
					.. "  "
					.. options.keymaps.execute_cell
					.. ": Execute current cell\n"
					.. "  "
					.. options.keymaps.save_notebook
					.. ": Save notebook\n"
					.. "  "
					.. options.keymaps.add_code_cell
					.. ": Add code cell\n"
					.. "  "
					.. options.keymaps.add_markdown_cell
					.. ": Add markdown cell\n"
					.. "  "
					.. options.keymaps.next_cell
					.. ": Go to next cell\n"
					.. "  "
					.. options.keymaps.prev_cell
					.. ": Go to previous cell\n"
					.. "  :JupyDiagnose: Show cell diagnostics",
				vim.log.levels.INFO
			)
		end,
	})

	-- Set up file type detection for .ipynb files
	vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
		pattern = "*.ipynb",
		callback = function(args)
			M.open_notebook(args.match, options.python_path)
		end,
	})
end

function M.open_notebook(filename, python_path)
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
	vim.api.nvim_buf_set_option(buf, "buftype", "") -- Regular file

	-- Store notebook info
	notebooks[buf] = {
		filename = filename,
		data = notebook,
		python_path = python_path,
	}

	-- Switch to the buffer
	vim.api.nvim_set_current_buf(buf)

	-- Set up basic syntax highlighting
	vim.cmd([[
    syntax clear
    syntax match JupyCell /^-- \w\+ CELL --$/
    syntax match JupyEnd /^-- END CELL --$/
    syntax match JupyOutput /^-- OUTPUT --$/
    highlight JupyCell ctermfg=Green guifg=Green
    highlight JupyEnd ctermfg=Gray guifg=Gray
    highlight JupyOutput ctermfg=Yellow guifg=Yellow
  ]])

	vim.notify("Opened Jupyter notebook", vim.log.levels.INFO)
end

return M
