# JupyNvim

A Neovim plugin for editing and running Jupyter notebooks (.ipynb files) directly within Neovim.

## Features

- Open and edit .ipynb files directly in Neovim
- Execute code cells using Jupyter kernels
- Display cell outputs including text, errors, and basic data
- Navigate between cells with simple keybindings
- Add and delete cells

## Requirements

- Neovim 0.5.0+
- Python 3.6+ with the following packages:
  - jupyter_client
  - nbformat
  - ipykernel

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "yourusername/jupynvim",
  dependencies = {},
  config = function()
    require("jupynvim").setup({
      -- Optional: override defaults
      python_path = "python3",  -- Path to your Python executable
      -- Customize keymappings
      keymaps = {
        execute_cell = "<leader>je",
        next_cell = "<leader>j]",
        prev_cell = "<leader>j[",
        add_cell = "<leader>ja",
        delete_cell = "<leader>jd",
      },
    })
  end,
}
```

## Usage

### Opening a Notebook

Simply open a .ipynb file in Neovim, and JupyNvim will automatically parse and display it:

```
nvim my_notebook.ipynb
```

### Cell Navigation

- `<leader>j]`: Move to the next cell
- `<leader>j[`: Move to the previous cell

### Cell Operations

- `<leader>je`: Execute the current cell
- `<leader>ja`: Add a new cell after the current cell
- `<leader>jd`: Delete the current cell

### Commands

- `:JupyExecute`: Execute the current cell
- `:JupyNext`: Navigate to the next cell
- `:JupyPrev`: Navigate to the previous cell
- `:JupyAddCell [type]`: Add a new cell (optional type: "code" or "markdown")
- `:JupyDeleteCell`: Delete the current cell
- `:JupyStartKernel [name]`: Start a Jupyter kernel (optional kernel name)

## How It Works

JupyNvim parses .ipynb files (which are JSON) and displays them in a structured format in Neovim. It connects to Jupyter kernels using Python's jupyter_client library to execute code cells and capture their outputs.

## Known Limitations

- Limited support for rich outputs (images, HTML, etc.)
- No automatic kernel selection based on notebook metadata
- Basic error handling

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT
