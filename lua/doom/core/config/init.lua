---[[---------------------------------------]]---
--          config - Core of Doom Nvim         --
--              Author: NTBBloodbath           --
--              License: MIT                   --
---[[---------------------------------------]]---

local log = require('doom.core.logging')
local rc = require('doom.core.config.doomrc')
local default = require('doom.core.default')
local functions = require('doom.core.functions')

log.debug('Loading Doom core config module ...')

-- Doom Nvim version
Doom_version = '2.3.2'

-- Check if running Neovim or Vim and fails if:
--  1. Running Vim instead of Neovim
--  2. Running Neovim 0.4 or below
if vim.fn.has('nvim') == 1 then
	if vim.fn.has('nvim-0.5') ~= 1 then
		log.fatal('Doom Nvim requires Neovim 0.5.0')
	end
else
	log.fatal('Doom Nvim does not have support for Vim, please use it with Neovim instead')
end

-- Set some configs on load
if vim.fn.has('vim_starting') then
	-- Set encoding
	vim.opt.encoding = 'utf-8'
	-- Required to use some colorschemes and improve colors
	vim.opt.termguicolors = true
end

----- Start Doom and run packer.nvim
-- Search for a configuration file (doomrc)
local doomrc_exists = rc.check_doomrc()
if doomrc_exists then
	rc.load_doomrc()
end

-- Set which separator should be used for paths, unused at the moment
-- Which_os()

-- Load the default Neovim settings, e.g. tabs width
default.load_default_options()

-- Load packer.nvim and load plugins settings
require('doom.modules')

-- Load the user-defined settings (global variables, autocmds, mappings)
default.custom_options()

if Doom.check_updates then
	functions.check_updates()
end
