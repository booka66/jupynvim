-- jupynvim/lua/jupynvim/executor.lua
local M = {}

-- Config storage
local config = {}
local python_cmd = nil

function M.setup(cfg)
	config = cfg
	python_cmd = config.python_path
end

-- Function to start a Jupyter kernel
function M.start_kernel(kernel_name)
	kernel_name = kernel_name or "python3"

	-- Create a temporary file to store kernel connection info
	local connection_file = os.tmpname()

	-- Execute python to start kernel and get connection info
	local cmd = python_cmd
		.. ' -c "'
		.. "import json; "
		.. "from jupyter_client.manager import start_new_kernel; "
		.. "km, kc = start_new_kernel(kernel_name='"
		.. kernel_name
		.. "'); "
		.. "with open('"
		.. connection_file
		.. "', 'w') as f: "
		.. "    json.dump({'connection_file': km.connection_file}, f); "
		.. "print('Kernel started')"
		.. '"'

	-- Run the command
	local handle = io.popen(cmd)
	local result = handle:read("*a")
	handle:close()

	-- Read the connection file
	local file = io.open(connection_file, "r")
	if not file then
		vim.notify("Failed to start Jupyter kernel", vim.log.levels.ERROR)
		return nil
	end

	local connection_info = file:read("*all")
	file:close()
	os.remove(connection_file)

	-- Parse the connection info
	local status, info = pcall(vim.fn.json_decode, connection_info)
	if not status then
		vim.notify("Failed to parse kernel connection info", vim.log.levels.ERROR)
		return nil
	end

	return info.connection_file
end

-- Execute a code cell
function M.execute_cell(cell_content, connection_file)
	if not connection_file then
		vim.notify("No active kernel connection", vim.log.levels.ERROR)
		return nil
	end

	-- Create a temporary file for the code
	local code_file = os.tmpname()
	local output_file = os.tmpname()

	-- Write the code to the file
	local file = io.open(code_file, "w")
	file:write(cell_content)
	file:close()

	-- Execute the code
	local cmd = python_cmd
		.. ' -c "'
		.. "import json; "
		.. "from jupyter_client import BlockingKernelClient; "
		.. "kc = BlockingKernelClient(); "
		.. "kc.load_connection_file('"
		.. connection_file
		.. "'); "
		.. "kc.start_channels(); "
		.. "with open('"
		.. code_file
		.. "', 'r') as f: "
		.. "    code = f.read(); "
		.. "msg_id = kc.execute(code); "
		.. "outputs = []; "
		.. "while True: "
		.. "    try: "
		.. "        msg = kc.get_iopub_msg(timeout=1); "
		.. "        if 'content' in msg: "
		.. "            outputs.append(msg); "
		.. "    except: "
		.. "        break; "
		.. "kc.stop_channels(); "
		.. "with open('"
		.. output_file
		.. "', 'w') as f: "
		.. "    json.dump(outputs, f); "
		.. '"'

	-- Run the command
	local handle = io.popen(cmd)
	local result = handle:read("*a")
	handle:close()

	-- Read the output file
	local out_file = io.open(output_file, "r")
	if not out_file then
		vim.notify("Failed to execute cell", vim.log.levels.ERROR)
		os.remove(code_file)
		return nil
	end

	local output_content = out_file:read("*all")
	out_file:close()

	-- Clean up temporary files
	os.remove(code_file)
	os.remove(output_file)

	-- Parse the output
	local status, outputs = pcall(vim.fn.json_decode, output_content)
	if not status then
		vim.notify("Failed to parse execution output", vim.log.levels.ERROR)
		return nil
	end

	-- Process the outputs
	local processed_outputs = {}
	for _, output in ipairs(outputs) do
		if output.msg_type == "execute_result" or output.msg_type == "display_data" then
			table.insert(processed_outputs, {
				output_type = output.msg_type,
				data = output.content.data,
				metadata = output.content.metadata,
			})
		elseif output.msg_type == "stream" then
			table.insert(processed_outputs, {
				output_type = "stream",
				name = output.content.name,
				text = output.content.text,
			})
		elseif output.msg_type == "error" then
			table.insert(processed_outputs, {
				output_type = "error",
				ename = output.content.ename,
				evalue = output.content.evalue,
				traceback = output.content.traceback,
			})
		end
	end

	return processed_outputs
end

return M
