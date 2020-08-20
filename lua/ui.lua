local vim = vim
local api = vim.api
local min, max = math.min, math.max
local format = string.format
local concat = table.concat
local insert = table.insert
local remove = table.remove
local schedule = vim.schedule
local qsort = table.sort
local floor = math.floor
local ceil = math.ceil
local abs = math.abs
local qsort = require 'qsort'
local uv = require 'luv'

local function fuzzy_popup(opts)
  opts = opts or {}
	local buf = api.nvim_create_buf(false, true)

	api.nvim_buf_set_option(buf, 'bufhidden', 'delete')

	local win

  -- TODO(ashkan): use the minimum size or the actual window size.
	local uis = api.nvim_list_uis()

  local ui_min_width = math.huge
  local ui_min_height = math.huge
  for _, ui in ipairs(uis) do
    ui_min_width = math.min(ui.width, ui_min_width)
    ui_min_height = math.min(ui.height, ui_min_height)
  end

	local opts = {
		relative = 'editor';
		width = opts.width or floor(ui_min_width * 50 / 100);
		height = opts.height or floor(ui_min_height * 50 / 100);
--		width = 50;
--		height = 20;
		anchor = 'NW';
		style = 'minimal';
		focusable = false;
	}
	opts.col = floor((ui_min_width - opts.width) / 2)
	opts.row = floor((ui_min_height - opts.height) / 2)
	win = api.nvim_open_win(buf, 0, opts)

	api.nvim_win_set_option(win, 'wrap', false)
	api.nvim_buf_set_option(buf, 'ul', -1)
	api.nvim_win_set_option(win, 'concealcursor', 'nc')
	-- nvim.buf_set_option(buf, 'modifiable', false)
	return buf, win
end

local key_callbacks = {}

local function tohex(s)
  local R = {}
  for i = 1, #s do
    R[#R+1] = format("%02X", s:byte(i))
  end
  return concat(R)
end

local function apply_mappings(mappings)
  assert(type(mappings) == 'table')
  for k, v in pairs(mappings) do
    local mode = k:sub(1,1)
    local lhs = k:sub(2)
    local rhs = remove(v, 1)
    local opts = v
    if opts.buffer then
      local bufnr = opts.buffer
      assert(bufnr == tonumber(bufnr))
      opts.buffer = nil
      if not key_callbacks[bufnr] then
        key_callbacks[bufnr] = {}
        api.nvim_buf_attach(bufnr, false, {
          on_detach = function(bufnr)
            key_callbacks[bufnr] = nil
          end;
        })
      end
      local ekey = tohex(lhs:lower())
      key_callbacks[bufnr][ekey] = rhs
      opts.noremap = true
      rhs = format("<cmd>lua require'ui'.key_callbacks[%d][%q]()<cr>", bufnr, ekey)
      api.nvim_buf_set_keymap(bufnr, mode, lhs, rhs, opts)
    else
      local ekey = tohex(lhs:lower())
      key_callbacks[-1][ekey] = rhs
      opts.noremap = true
      rhs = format("<cmd>lua require'ui'.key_callbacks[-1][%q]()<cr>", ekey)
      api.nvim_set_keymap(mode, lhs, rhs, opts)
    end
  end
end

local function clamp(l, h, v)
  return min(h, max(l, v))
end

local function clamp2(l, h, v)
  local x = min(h, max(l, v))
  return x, v ~= x
end

local popup_internal
local function popup_callback(char)
  if type(popup_internal) == 'function' then
    local ok, err = pcall(popup_internal)
    if ok then
    else
      print(err)
    end
  end
end

local ffi = require 'ffi'

--- Levenshtein distance function.
local function levenshtein_distance(s1, s2)
  if s1 == s2 then return 0 end
  if s1:len() == 0 then return s2:len() end
  if s2:len() == 0 then return s1:len() end
  -- if s1:len() < s2:len() then s1, s2 = s2, s1 end
  -- print(s1:len(), s2:len())
  -- local column = ffi.new("int[?]", s1:len() + 1)
  local column = {}
  for y = 1, s1:len() do
    column[y] = y
  end
  local old_diag, last_diag
  for x = 1, s2:len() do
    column[0] = x
    last_diag = x - 1
    local delta
    for y = 1, #s1 do
      old_diag = column[y]
      delta = (s1:byte(y) == s2:byte(x)) and 0 or 1
      column[y] = min(column[y] + 1, column[y-1] + 1, last_diag + delta)
      last_diag = old_diag
    end
  end
  return column[#s1]
end

local function nonoverlapping_ngrams(s, n)
  local R = {}
  for m in s:gmatch(("."):rep(n)) do
    R[#R+1] = m
  end
  return R
end

local function overlapping_ngrams(s, n)
  local R = {}
  for i = 1, s:len() - n + 1 do
    R[#R+1] = s:sub(i, i+n-1)
  end
  return R
end

-- TODO(ashkan): try to use tries to make substring_finder?
-- local trie = require 'trie'
local function substring_finder(s, S)
  local n = #s
  local N = #S
  return function()
    for j = 1, N do
      local start = s:find(S[j], 1, true)
      if start then
        return start
      end
    end
    return 0
  end
end

local function make_ensemble_cost_fn(user_input)
  local N = user_input:len()
  -- if N <= 3 then
  --   return function(user_input, s)
  --     local n = s:len()
  --     local c1 = s:find(user_input, 1, true)
  --     if not c1 then
  --       return n
  --       -- return levenshtein_distance(user_input, s)
  --       -- return 0xFFFF
  --     end
  --     return min(n - c1 + 2, c1)
  --     -- return s:find(user_input, 1, true) or s:len()
  --   end
  -- end
  local ngramlen = 2
  -- if N > 5 then
  --   ngramlen = 3
  -- end
  local case_sensitive = 0 == 1
  local ul = user_input:lower()
  local ngram_input = case_sensitive and user_input or ul
  local overlapping = 1 == 1
  local ngrams = overlapping
    and overlapping_ngrams(ngram_input, ngramlen)
    or nonoverlapping_ngrams(ngram_input, ngramlen)
  if not ngrams[1] then
    ngrams[1] = ngram_input
  end
  return function(user_input, s)
    local sl = s:lower()
    local c1 = sl:find(ul, 1, true)
    -- local c1 = s:find(user_input, 1, true)
    local consecutive = 0
    local previous_index = 0
    local m = 0
    -- TODO(ashkan): not just total matches, but
    -- bias for consecutive matches somehow.
    for i = 1, #ngrams do
      local x1, x2 = sl:find(ngrams[i], 1, true)
      if x1 then
        m = m + 1
        if x1 > previous_index then
          consecutive = consecutive + 1
        end
        -- TODO(ashkan): or x2?
        previous_index = x1
      end
    end

    -- print((10*m/#ngrams)
    --   -- biases for shorter strings
    --   -- TODO(ashkan): this can bias towards repeated finds of the same
    --   -- subpattern with overlapping_ngrams
    --   , 3*m*ngramlen/#s
    --   , consecutive
    --   , N/(c1 or 2*#s))

    -- The multiplier controls precision since we round to integer.
    -- return -floor(1e2*(
    return ceil(1e2*(
      (10*m/#ngrams)
      -- biases for shorter strings
      -- TODO(ashkan): this can bias towards repeated finds of the same
      -- subpattern with overlapping_ngrams
      + 3*m*ngramlen/#s
      + consecutive
      + N/(c1 or (2*#s))
      -- + 30/(c1 or 2*N)
    ))

    -- return floor(-((m*20)/#ngrams) - (c1 and N or 0))
    -- return -m*5 - (c1 and N or 0)
    -- return levenshtein_distance(ul, s) - m*5 - (c1 and #s or 0)
    -- return levenshtein_distance(user_input, s) - m*5 - (c1 and #s or 0)

  end
  -- return levenshtein_distance
end

local function floating_fuzzy_menu(options)
  local inputs = assert(options.inputs or options[1], "Missing .inputs")
  assert(type(inputs) == 'table', "inputs must be a table")
  local entry_count = options.length or options.count or #inputs
  assert(type(entry_count) == 'number', "Input length is not a number")
  local callback = options.callback or options[2] or print
  assert(type(callback) == 'function')
  local ns = api.nvim_create_namespace('fuzzy_menu')
  local height = 40
  local width = 100
  local bufnr, winnr = fuzzy_popup {
    width = width;
    height = height;
  }

  local visible_entry_count = min(height - 1, entry_count)
  local visible_height = height - 1
  local wo = vim.wo[winnr]
  local bo = vim.bo[bufnr]
  wo.wrap = false

  local lazily_evalute = 1 == 1

  local highlighted_line = 1
  local horizontal_start = 1
  local visible_start = 1

  local prefix = "> "
  local PADDING = (" "):rep(width)

  -- for i, v in ipairs(entries) do
  --   entries[i] = tostring(v)
  -- end

  local K_BS = api.nvim_replace_termcodes("<BS>", true, true, true)
  local K_LEFT = api.nvim_replace_termcodes("<Left>", true, true, true)
  local K_CW = api.nvim_replace_termcodes("<c-w>", true, true, true)
  local K_RIGHT = api.nvim_replace_termcodes("<Right>", true, true, true)

  local user_input = options.user_input or ''
  local cost_fn = levenshtein_distance
  local last_index = entry_count

  local entries = {}
  -- local indices = ffi.new("int[?]", entry_count + 1)
  -- local costs = ffi.new("int[?]", entry_count + 1)
  local indices = {}
  local costs = {}

  for i = 0, entry_count do
    costs[i] = 0
    indices[i] = i
  end

  local longest_prefix = 0
  if lazily_evalute then
  else
    local first_index
    last_index = 0
    for i = 1, entry_count do
      local v = inputs[i]
      if v ~= nil then
        entries[i] = tostring(v)
        last_index = i
        first_index = first_index or i
      else
        entries[i] = ""
      end
    end
    if not first_index then
      return
    end
    assert(first_index == 1)
    if (last_index - first_index) >= 1 then
      longest_prefix = #entries[first_index]
      for i = first_index, last_index do
        if #entries[i] > 0 then
          longest_prefix = min(longest_prefix, #entries[i])
          for j = 1, longest_prefix do
            if entries[first_index]:byte(j) ~= entries[i]:byte(j) then
              longest_prefix = j
              break
            end
          end
        end
      end
    end
    print("LONGEST PREFIX:", longest_prefix, "index_range:", first_index, last_index)
    -- local indices = ffi.new("int[?]", last_index + 1)
    -- local costs = ffi.new("int[?]", last_index + 1)
    -- local indices = {}
    -- local costs = {}
    for i = 0, last_index do
      costs[i] = 0
      indices[i] = i
    end
  end

  local function get_entry(i)
    local e = entries[i]
    if e then
      return e
    end
    e = inputs[i]
    if e then
      e = tostring(e)
      entries[i] = e
      return e
    end
  end

  local function get_mapped_entry(idx)
    if idx >= 1 and idx <= entry_count then
      return get_entry(indices[idx])
    end
  end

  local function get_mapped_entry_display(idx)
    if idx >= 1 and idx <= entry_count then
      local i = indices[idx]
      local input = inputs[i]
      if input then
        return input.display or get_entry(i)
      end
    end
  end

  local calculation_budget = 100

  local hrtime = uv.hrtime
  local ms_time = function() return hrtime()/1e6 end
  -- local ms_time = uv.now
  local function update_filtered()
    print("longest_prefix:", longest_prefix)
    last_index = entry_count
  -- local function update_filtered(is_reduction)
    local N = user_input:len()
    print(os.time(), "filtered", N)
    local t0 = ms_time()
    local cost_fn = make_ensemble_cost_fn(user_input)
    if N == 0 then
      local new_longest_prefix = longest_prefix
      local first_entry
      for i = 1, last_index do
        local v = get_entry(i)
        if i > 1 and (ms_time() - t0) > calculation_budget then
          print("Breaking early", ms_time() - t0)
          v = nil
        end
        if not v then
          last_index = i - 1
          break
        end
        assert(type(v) == 'string', type(v))
        if longest_prefix == 0 and #v > 0 then
          if i == 1 then
            first_entry = v
            new_longest_prefix = #v
          else
            new_longest_prefix = min(new_longest_prefix, #v)
            for j = 1, new_longest_prefix do
              if first_entry:byte(j) ~= v:byte(j) then
                new_longest_prefix = j
                break
              end
            end
          end
        end
        -- TODO(ashkan): keep?
        costs[i] = 0
        indices[i] = i
      end
      if longest_prefix == 0 then
        longest_prefix = new_longest_prefix
      end
      return
    end
    local entry_check_count = last_index
    if is_reduction then
      entry_check_count = visible_entry_count
    end
    local new_longest_prefix = longest_prefix
    local first_entry
    -- TODO(ashkan): track the highest non-nil index to use as the length.
    for i = 1, entry_check_count do
      -- local j = indices[i]
      -- local v = entries[indices[i]]
      local v = get_entry(i)
      if i > 1 and (ms_time() - t0) > calculation_budget then
        print("Breaking early", ms_time() - t0)
        v = nil
      end
      if v then
        -- TODO(ashkan): only works if we're not limiting the entry_check_count
        if not is_reduction then
          last_index = i
        end
        if longest_prefix == 0 then
          if i == 1 then
            first_entry = v
            new_longest_prefix = #v
          end
          if i > 1 and #v > 0 then
            new_longest_prefix = min(new_longest_prefix, #v)
            for j = 1, new_longest_prefix do
              if first_entry:byte(j) ~= v:byte(j) then
                new_longest_prefix = j
                break
              end
            end
          end
        end

        -- if type(entries[i]) ~= 'string' then
        --   entries[i] = tostring(entries[i])
        -- end
        -- costs[i] = cost_fn(user_input, entries[i])
        -- costs[i] = cost_fn(user_input, tostring(entries[i]))

        -- costs[i] = cost_fn(user_input, v)
        costs[i] = cost_fn(user_input, v:sub(longest_prefix))
      else
        last_index = min(last_index, i-1)
        costs[i] = 0
        break
        -- costs[i] = N
      end
      -- costs[i] = cost_fn(user_input, entries[i])
      indices[i] = i
    end
    longest_prefix = new_longest_prefix
    entry_check_count = min(last_index, entry_check_count)
    local t1 = ms_time()
    qsort(indices, entry_check_count, function(a, b)
    -- qsort(indices, entry_count, function(a, b)
      return costs[a] > costs[b]
    end)
    print("entries:", entry_check_count, "Cost:", t1 - t0, "Sort:", ms_time() - t1)
  end

  local function focused_index()
    return visible_start + highlighted_line - 1
  end

  local function get_entry_string(idx)
    local entry = get_entry(idx)
    if entry then
      return tostring(entry)
    end
    return ""
  end

  local hscroll_all = 0 == 1

  local function redraw()
    local lines = {}
    local focused_entry = focused_index()
    for i = 1, visible_height do
    -- for i = 1, visible_entry_count do
      local idx = visible_start + i - 1
      i = height - i
      local v = get_mapped_entry_display(idx)
      if v then
        -- lines[i] = tostring(entries[indices[idx]] or "")
        -- lines[i] = get_entry_string(idx)
        -- lines[i] = format("%4d %s", costs[indices[idx]], lines[i])
        -- if idx == focused_entry then
        --   lines[i] = lines[i]:sub(horizontal_start)
        --   lines[i] = lines[i]..PADDING:sub(#lines[i])
        -- end
        local line_prefix
        do
          -- print(entry_count, last_index, idx, indices[idx])
          local cost = costs[indices[idx]] or error("You goofed up. Index "..idx)
          if cost < 0 then
            line_prefix = format("%4s ", "-"..format("%X", -cost))
          else
            line_prefix = format("%4X ", cost)
          end
        end
        -- IMPORTANT(ashkan): GET RID OF NEWLINES
        v = v:gsub("\n+", " ")
        if idx == focused_entry then
          lines[i] = line_prefix..v:sub(horizontal_start)
          -- lines[i] = line_prefix..get_entry_string(idx):sub(horizontal_start, width - #line_prefix - 1)
          lines[i] = lines[i]..PADDING:sub(#lines[i]+1)
        else
          if hscroll_all then
            -- local e = get_entry_string(idx)
            -- lines[i] = line_prefix..e:sub(vim.str_byteindex(e, horizontal_start, true))
            lines[i] = line_prefix..(v:sub(horizontal_start))
          else
            lines[i] = line_prefix..v
          end
          -- lines[i] = line_prefix..get_entry_string(idx):sub(1, width - #line_prefix - 1)
        end
      else
        lines[i] = ""
      end
      assert(lines[i], i)
    end
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    api.nvim_buf_set_lines(bufnr, 0, -2, false, lines)
    api.nvim_buf_add_highlight(bufnr, ns, 'Visual', height - highlighted_line - 1, 0, -1)
    api.nvim_buf_add_highlight(bufnr, ns, 'Question', height - highlighted_line - 1, 0, -1)
    -- nvu.nvim_highlight_region(buf, ns, highlight_name, l1, c1, l2, c2)
  end

  local function update_user_input()
    local prev = user_input
    user_input = api.nvim_get_current_line():sub(#prefix+1)
    if prev == user_input then
      return
    end
    if #user_input < #prev then
      for i = 1, last_index do
        costs[i] = 0
        indices[i] = i
      end
    end
    -- local is_reduction = #user_input > #prev
    local is_reduction = #user_input > 3 and #user_input > #prev
    update_filtered(is_reduction)
    redraw()
  end

  popup_internal = function()
    print(os.time(), "internal")
    update_user_input()
  end

  local function shift_view(offset)
    local prev = visible_start
    visible_start = clamp(1, max(last_index - visible_entry_count + 1, 1), visible_start + offset)
    return visible_start - prev
  end

  local function shift_highlight(offset)
    local prev = highlighted_line
    highlighted_line = clamp(1, min(visible_entry_count, last_index), highlighted_line + offset)
    return highlighted_line - prev
  end

  local function shift_cursor(offset)
    local x = shift_highlight(offset)
    x = x + shift_view(offset - x)
    if not hscroll_all and x ~= 0 then
      horizontal_start = 1
    end
    -- return shift_view(offset - shift_highlight(offset))
  end

  local function scroll_horizontally(offset)
    if hscroll_all then
      horizontal_start = max(1, horizontal_start + offset)
    else
      horizontal_start = clamp(1, #(get_mapped_entry(focused_index()) or ""), horizontal_start + offset)
    end
    -- horizontal_start = clamp(1, #(entries[focused_entry] or ""), horizontal_start + offset)
  end

  local function check_insert_cursor()
    return api.nvim_win_get_cursor(0)[2] > #prefix
  end

  local was_insert = vim.fn.mode() == 'i'

  local function close_window()
    if not was_insert then
      vim.cmd "stopinsert"
    end
    pcall(api.nvim_win_close, winnr, true)
    -- vim.cmd("silent! bwipe! "..bufnr)
    return true
  end

  -- TODO(ashkan): avoid redraws if the view doesn't change?
  local mappings = {
    ["i<down>"]      = function() shift_cursor(-1) end;
    ["i<up>"]        = function() shift_cursor(1) end;
    ["i<c-n>"]       = function() shift_cursor(-1) end;
    ["i<c-p>"]       = function() shift_cursor(1) end;
    ["i<esc>"]       = close_window;
    ["i<c-c>"]       = close_window;
    ["i<c-left>"]    = function() scroll_horizontally(-1) end;
    ["i<c-right>"]   = function() scroll_horizontally(1) end;
    ["i<c-s-left>"]  = function() scroll_horizontally(-5) end;
    ["i<c-s-right>"] = function() scroll_horizontally(5) end;
    ["i<c-d>"]       = function() shift_view(-visible_height) end;
    ["i<c-u>"]       = function() shift_view(visible_height) end;
    ["i<c-s-up>"]    = function() end;
    ["i<c-s-down>"]  = function() end;
    ["i<c-up>"]      = function() end;
    ["i<c-down>"]    = function() end;
    ["i<home>"]      = function() shift_cursor(entry_count) end;
    ["i<end>"]       = function() shift_cursor(-entry_count) end;
    ["i<pageup>"]    = function() shift_cursor(visible_height) end;
    ["i<pagedown>"]  = function() shift_cursor(-visible_height) end;
    ["i<left>"] = function()
      if check_insert_cursor() then
        api.nvim_feedkeys(K_LEFT, 'ni', false)
      end
    end;
    ["i<c-w>"] = function()
      if check_insert_cursor() then
        api.nvim_feedkeys(K_CW, 'ni', false)
      end
    end;
    ["i<bs>"] = function()
      if check_insert_cursor() then
        api.nvim_feedkeys(K_BS, 'ni', false)
      end
    end;
    ["i<CR>"] = function()
      local entry_index = indices[focused_index()]
      local ok, dont_close = pcall(callback, inputs[entry_index], entry_index, costs[entry_index])
      if ok then
        if not dont_close then
          return close_window()
        end
      else
        print(dont_close)
      end
    end;
  }
  for k, v in pairs(mappings) do
    assert(type(v) == 'function')
    local fn1 = v
    local fn = function()
      -- TODO(ashkan): check if you need to redraw by checking state difference.
      -- Can store a copy of the previous state here and then check it after the fn1()
      if not fn1() then redraw() end
    end
    mappings[k] = { fn; buffer = bufnr; }
  end
  update_filtered()
  if hscroll_all then
    horizontal_start = longest_prefix or 0
  end
  redraw()
  api.nvim_buf_set_lines(bufnr, -2, -1, false, {prefix})
  schedule(function()
    api.nvim_win_set_cursor(winnr, {height, #prefix})
    local line = api.nvim_get_current_line()
    api.nvim_set_current_line(line..user_input)
    api.nvim_win_set_cursor(winnr, {height, #prefix+#user_input})
  end)
  -- TODO(ashkan): make sure the window is focused.
  vim.cmd "startinsert"
  vim.cmd(format("autocmd BufEnter <buffer=%d> startinsert", bufnr))
  vim.cmd(format("autocmd BufLeave <buffer=%d> silent! bwipe! %d", bufnr, bufnr))
  -- vim.cmd(format("autocmd WinLeave <buffer=%d> stopinsert", bufnr))
  vim.cmd(format("autocmd InsertLeave <buffer=%d> startinsert", bufnr))
  vim.cmd(format("autocmd TextChangedI <buffer=%d> lua require'ui'.popup_callback()", bufnr))
  -- vim.cmd(format("autocmd InsertCharPre <buffer=%d> lua require'ui'.popup_callback()", bufnr))
  apply_mappings(mappings)
  -- nvu.nvim_apply_mappings(mappings, { buffer = bufnr; })
end


return {
  floating_fuzzy_menu = floating_fuzzy_menu;
  popup_callback = popup_callback;
  key_callbacks = key_callbacks;
}
