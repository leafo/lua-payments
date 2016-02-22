local extend
extend = function(a, ...)
  local _list_0 = {
    ...
  }
  for _index_0 = 1, #_list_0 do
    local t = _list_0[_index_0]
    if t then
      for k, v in pairs(t) do
        a[k] = v
      end
    end
  end
  return a
end
local upper_keys
upper_keys = function(t)
  if t then
    local _tbl_0 = { }
    for k, v in pairs(t) do
      _tbl_0[type(k) == "string" and k:upper() or k] = v
    end
    return _tbl_0
  end
end
local strip_numeric
strip_numeric = function(t)
  for k, v in ipairs(t) do
    t[k] = nil
  end
  return t
end
local valid_amount
valid_amount = function(str)
  if str:match("%d+%.%d%d") then
    return true
  end
  return nil, "invalid amount (" .. tostring(str) .. ")"
end
local format_price
format_price = function(cents, currency)
  if currency == nil then
    currency = "USD"
  end
  if currency == "JPY" then
    return tostring(math.floor(cents))
  else
    local dollars = math.floor(cents / 100)
    local change = ("%02d"):format(cents % 100)
    return tostring(dollars) .. "." .. tostring(change)
  end
end
return {
  extend = extend,
  upper_keys = upper_keys,
  strip_numeric = strip_numeric,
  valid_amount = valid_amount,
  format_price = format_price
}
