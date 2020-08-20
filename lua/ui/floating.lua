local geometry = require 'ui.geometry'
local vim = vim
local api = vim.api
local floor = math.floor

local positioning_strategy_lookup = {
  cursor = geometry.positioning.cursor;
  ui_center = geometry.positioning.ui_center;
  window_center = geometry.positioning.window_center;
}

local positioning_strategy_reverse = {}

for k, v in pairs(POSITIONING_STRATEGY) do
  positioning_strategy_reverse[k:lower()] = k
  positioning_strategy_reverse[v] = v
end

local function fuzzy_popup(opts)
  opts = opts or {}
	local buf = api.nvim_create_buf(false, true)

	api.nvim_buf_set_option(buf, 'bufhidden', 'delete')

	local win

  local ui_size = geometry.ui_size()

  local width = geometry.fixed_or_ratio(opts.width or 0.5, ui_size.width)
  local height = geometry.fixed_or_ratio(opts.height or 0.5, ui_size.height)

	local O = {
		relative = 'editor';
		width = width;
		height = height;
		anchor = 'NW';
		style = 'minimal';
		focusable = false;
	}

  -- Positioning
  -- If col is specified, then use that.
  -- If col isn't specified, then use a strategy for positioning.
  local positioning_strategy = positioning_strategy_reverse[opts.position or -1] or POSITIONING_STRATEGY.CENTER
	O.col = opts.col or floor((ui_min_width - O.width) / 2)


  -- By default, center it.
	O.col = opts.col or floor((ui_min_width - O.width) / 2)
	O.row = opts.row or floor((ui_min_height - O.height) / 2)

	O.row = floor((ui_min_height - opts.height) / 2)
	win = api.nvim_open_win(buf, 0, opts)

	api.nvim_win_set_option(win, 'wrap', false)
	api.nvim_buf_set_option(buf, 'ul', -1)
	api.nvim_win_set_option(win, 'concealcursor', 'nc')
	-- nvim.buf_set_option(buf, 'modifiable', false)
	return buf, win
end


return floating
