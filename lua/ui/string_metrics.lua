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


