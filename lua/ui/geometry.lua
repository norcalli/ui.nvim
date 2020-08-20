local vim = vim
local api = vim.api

-- Calculates the minimum of all attached windows because that is the
-- typical valid region you care about.
local function ui_size()
  local uis = api.nvim_list_uis()
  local ui_min_width = math.huge
  local ui_min_height = math.huge
  for _, ui in ipairs(uis) do
    ui_min_width = math.min(ui.width, ui_min_width)
    ui_min_height = math.min(ui.height, ui_min_height)
  end
  return { width = ui_min_width, height = ui_min_height }
end

local function window_size(winnr)
  winnr = winnr or 0
  return {
    width = api.nvim_win_get_width(winnr),
    height = api.nvim_win_get_height(winnr),
  }
end

local function rect(w, h, x, y)
  return {
    w = assert(w);
    h = assert(h);
    x = x or 0;
    y = y or 0;
  }
end

local function fixed_or_ratio(v, span)
  assert(type(v) == 'number')
  if v == 0 then return 0 end
  -- TODO(ashkan, 2020-08-19 02:37:00+0900) <= or <?
  if v > 0 and v <= 1 then return span * v end
  return v
end

local positioning_strategies = {}

local function window_context(winnr)
  winnr = winnr or 0
  return {
    pos = api.nvim_win_get_cursor(winnr);
    size = geometry.window_size(winnr);
    ui_size = geometry.ui_size();
  }
end

function positioning_strategies.cursor(rect, context)
  context = context or window_context()
  return context.pos
end

function positioning_strategies.ui_center(rect, context)
  context = context or window_context()
  return {
    floor((context.ui_size.width - rect.w) / 2);
    floor((context.ui_size.height - rect.h) / 2);
  }
end

function positioning_strategies.window_center(rect, context)
  context = context or window_context()
  return {
    floor((context.size.width - rect.w) / 2);
    floor((context.size.height - rect.h) / 2);
  }
end

return {
  ui_size = ui_size;
  fixed_or_ratio = fixed_or_ratio;
  rect = rect;
  window_size = window_size;
  positioning = positioning_strategies;
  window_context = window_context;
}
