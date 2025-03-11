-- jupynvim/lua/jupynvim/display.lua
local M = {}
local parser = require("jupynvim.parser")

-- Config storage
local config = {}
local notebook_buffer = nil
local current_notebook = nil
local cell_markers = {}

function M.setup(cfg)
	config = cfg
end

-- Helper function to create syntax highlighting for cells
local function setup_syntax()
	vim.cmd([[
    syntax clear
    syntax region JupyNvimMarkdownCell start=/^-- MARKDOWN CELL --$/ end=/^-- END CELL --$/ contains=JupyNvimCellMarker
    syntax region JupyNvimCodeCell start=/^-- CODE CELL --$/ end=/^-- END CELL --$/ contains=JupyNvimCellMarker
    syntax match JupyNvimCellMarker /^-- \(MARKDOWN\|CODE\|END\) CELL --$/
    syntax match JupyNvimOutputMarker /^-- OUTPUT --$/
    
    highlight JupyNvimMarkdownCell ctermfg=Green guifg=Green
    highlight JupyNvimCodeCell ctermfg=Blue guifg=Blue
    highlight JupyNvimCellMarker ctermfg=Gray guifg=Gray
    highlight JupyNvimOutputMarker ctermfg=Gray guifg=Gray
  ]])
end

-- Render a notebook in a buffer
function M.render_notebook(notebook)
	current_notebook = notebook

	-- Create or get buffer
	if not notebook_buffer or not vim.api.nvim_buf_is_valid(notebook_buffer) then
		notebook_buffer = vim.api.nvim_create_buf(true, true)
		vim.api.nvim_buf_set_option(notebook_buffer, "filetype", "jupynvim")
	end

	-- Clear the buffer
	vim.api.nvim_buf_set_option(notebook_buffer, "modifiable", true)
	vim.api.nvim_buf_set_lines(notebook_buffer, 0, -1, false, {})

	-- Reset cell markers
	cell_markers = {}

	-- Add cells to buffer
	local line_idx = 0
	for i, cell in ipairs(notebook.cells) do
		table.insert(cell_markers, {
			cell_idx = i,
			start_line = line_idx,
			cell_type = cell.cell_type,
		})

		-- Add cell header
		local header = "-- " .. string.upper(cell.cell_type) .. " CELL --"
		vim.api.nvim_buf_set_lines(notebook_buffer, line_idx, line_idx + 1, false, { header })
		line_idx = line_idx + 1

		-- Add cell content
		local content = parser.get_cell_content(cell)
		local content_lines = {}
		for line in content:gmatch("[^\r\n]+") do
			table.insert(content_lines, line)
		end

		if #content_lines == 0 then
			table.insert(content_lines, "")
		end

		vim.api.nvim_buf_set_lines(notebook_buffer, line_idx, line_idx + #content_lines, false, content_lines)
		line_idx = line_idx + #content_lines

		-- Add outputs for code cells
		if cell.cell_type == "code" and cell.outputs and #cell.outputs > 0 then
			vim.api.nvim_buf_set_lines(notebook_buffer, line_idx, line_idx + 1, false, { "-- OUTPUT --" })
			line_idx = line_idx + 1

			for _, output in ipairs(cell.outputs) do
				local output_lines = {}

				if output.output_type == "stream" then
					-- Stream output (stdout/stderr)
					for line in output.text:gmatch("[^\r\n]+") do
						table.insert(output_lines, line)
					end
				elseif output.output_type == "execute_result" or output.output_type == "display_data" then
					-- Execution result
					if output.data["text/plain"] then
						local text = output.data["text/plain"]
						for line in text:gmatch("[^\r\n]+") do
							table.insert(output_lines, line)
						end
					end
				elseif output.output_type == "error" then
					-- Error output
					table.insert(output_lines, "Error: " .. output.ename .. ": " .. output.evalue)
					for _, line in ipairs(output.traceback) do
						table.insert(output_lines, line)
					end
				end

				if #output_lines > 0 then
					vim.api.nvim_buf_set_lines(notebook_buffer, line_idx, line_idx + #output_lines, false, output_lines)
					line_idx = line_idx + #output_lines
				end
			end
		end

		-- Add cell footer
		vim.api.nvim_buf_set_lines(notebook_buffer, line_idx, line_idx + 1, false, { "-- END CELL --" })
		line_idx = line_idx + 1

		-- Add empty line between cells
		vim.api.nvim_buf_set_lines(notebook_buffer, line_idx, line_idx + 1, false, { "" })
		line_idx = line_idx + 1
	end

	-- Set up syntax highlighting
	setup_syntax()

	-- Switch to the notebook buffer
	vim.api.nvim_set_current_buf(notebook_buffer)
	vim.api.nvim_buf_set_option(notebook_buffer, "modifiable", true)
end

-- Find the cell at the current cursor position
function M.find_current_cell()
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

	for i = #cell_markers, 1, -1 do
		if cursor_line >= cell_markers[i].start_line then
			return cell_markers[i].cell_idx
		end
	end

	return 1
end

-- Update the cell content in the notebook data structure
function M.update_cell_content(cell_idx)
	if not current_notebook or not cell_idx or cell_idx > #current_notebook.cells then
		return
	end

	local cell = current_notebook.cells[cell_idx]
	local cell_marker = nil

	-- Find the cell marker for this cell
	for _, marker in ipairs(cell_markers) do
		if marker.cell_idx == cell_idx then
			cell_marker = marker
			break
		end
	end

	if not cell_marker then
		return
	end

	-- Get content lines from the buffer
	local start_line = cell_marker.start_line + 1 -- Skip the header
	local end_line = start_line

	-- Find the end of the cell content
	while end_line < vim.api.nvim_buf_line_count(notebook_buffer) do
		local line = vim.api.nvim_buf_get_lines(notebook_buffer, end_line, end_line + 1, false)[1]
		if line == "-- OUTPUT --" or line == "-- END CELL --" then
			break
		end
		end_line = end_line + 1
	end

	-- Extract the content
	local content_lines = vim.api.nvim_buf_get_lines(notebook_buffer, start_line, end_line, false)

	-- Update cell source
	cell.source = {}
	for _, line in ipairs(content_lines) do
		table.insert(cell.source, line .. "\n")
	end
end

-- Navigate to the next cell
function M.goto_next_cell()
	local current_cell = M.find_current_cell()
	if current_cell < #current_notebook.cells then
		local next_marker
		for _, marker in ipairs(cell_markers) do
			if marker.cell_idx == current_cell + 1 then
				next_marker = marker
				break
			end
		end

		if next_marker then
			vim.api.nvim_win_set_cursor(0, { next_marker.start_line + 2, 0 })
		end
	end
end

-- Navigate to the previous cell
function M.goto_prev_cell()
	local current_cell = M.find_current_cell()
	if current_cell > 1 then
		local prev_marker
		for _, marker in ipairs(cell_markers) do
			if marker.cell_idx == current_cell - 1 then
				prev_marker = marker
				break
			end
		end

		if prev_marker then
			vim.api.nvim_win_set_cursor(0, { prev_marker.start_line + 2, 0 })
		end
	end
end

-- Add a new cell
function M.add_cell(cell_type)
	cell_type = cell_type or "code"

	-- Create new cell
	local new_cell = parser.create_cell(cell_type, "")

	-- Get current cell index
	local current_cell = M.find_current_cell()

	-- Update notebook structure
	table.insert(current_notebook.cells, current_cell + 1, new_cell)

	-- Re-render notebook
	M.render_notebook(current_notebook)

	-- Go to the new cell
	M.goto_next_cell()
end

-- Delete the current cell
function M.delete_cell()
	local current_cell = M.find_current_cell()
	if #current_notebook.cells > 1 then -- Don't delete if it's the only cell
		table.remove(current_notebook.cells, current_cell)
		M.render_notebook(current_notebook)
	end
end

return M
