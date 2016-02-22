
extend = (a, ...) ->
  for t in *{...}
    if t
      a[k] = v for k,v in pairs t
  a

upper_keys = (t) ->
  if t
    { type(k) == "string" and k\upper! or k, v for k,v in pairs t }

strip_numeric = (t) ->
  for k,v in ipairs t
    t[k] = nil
  t

valid_amount = (str) ->
  return true if str\match "%d+%.%d%d"
  nil, "invalid amount (#{str})"

format_price = (cents, currency="USD") ->
  if currency == "JPY"
    tostring math.floor cents
  else
    dollars = math.floor cents / 100
    change = "%02d"\format cents % 100
    "#{dollars}.#{change}"

{ :extend, :upper_keys, :strip_numeric, :valid_amount, :format_price }
