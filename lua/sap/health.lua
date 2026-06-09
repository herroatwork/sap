-- `:checkhealth sap` — validate the plugin's runtime requirements.

local M = {}

local function check_neovim()
	if vim.fn.has('nvim-0.11.4') == 1 then
		vim.health.ok('Neovim >= 0.11.4')
	else
		vim.health.error(
			'Neovim 0.11.4+ is required (uses vim.system and nvim_get_hl{ link = false })'
		)
	end
end

local function check_sl()
	if vim.fn.executable('sl') ~= 1 then
		vim.health.error(
			'`sl` not found on PATH',
			{ 'Install Sapling: https://sapling-scm.com/' }
		)
		return
	end
	local res = vim.system({ 'sl', '--version' }, { text = true }):wait()
	local ver = vim.trim((res.stdout or ''):gsub('\n.*$', ''))
	vim.health.ok('`sl` found' .. (ver ~= '' and (': ' .. ver) or ''))
end

local function check_telescope()
	if pcall(require, 'telescope') then
		vim.health.ok('telescope.nvim is installed')
	else
		vim.health.error(
			'telescope.nvim not found',
			{ 'Install nvim-telescope/telescope.nvim' }
		)
	end
end

local function check_repo()
	if vim.fn.executable('sl') ~= 1 then
		return
	end
	local res = vim.system({ 'sl', 'root' }, { text = true }):wait()
	if res.code == 0 then
		vim.health.info(
			'current directory is inside a Sapling repo: '
				.. vim.trim(res.stdout or '')
		)
	else
		vim.health.info(
			'current directory is not inside a Sapling repo (run the picker from within one)'
		)
	end
end

function M.check()
	vim.health.start('sap')
	check_neovim()
	check_sl()
	check_telescope()
	check_repo()
end

return M
