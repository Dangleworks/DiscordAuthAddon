auth_port = 9006
verify_message = "Join the Discord server at http://discord.dangle.works and type ^verify %s"
unverified_join_message = "You are not verified!\nYou can only spawn 1 vehicle at a time\nTo raise this limit, please type ?verify"
unverified_popup = "You are not verified!\nYou can only spawn 1 vehicle at a time\nRun ?verify to link your Discord account and raise this limit!"
discord_auth = false
popup_id = nil
steam_ids = {}
peer_ids = {}
unverified_sent = {}
tick = 0

function onTick()
    tick = tick + 1
    if tick % 180 == 0 then
        for _, player in pairs(server.getPlayers()) do
            server.httpGet(auth_port, "/check?sid="..tostring(player.steam_id))
        end
    end
end

function onCreate(is_world_create)
  popup_id = server.getMapID()
	for _, player in pairs(server.getPlayers()) do
		steam_ids[player.id] = tostring(player.steam_id)
    peer_ids[tostring(player.steam_id)] = player.id
	end
end

function onPlayerJoin(steam_id, name, peer_id, admin, auth)
  server.httpGet(auth_port, "/check?v&sid="..tostring(steam_id))
	steam_ids[peer_id] = tostring(steam_id)
  peer_ids[tostring(steam_id)] = peer_id
end

function onPlayerLeave(steam_id, name, peer_id, is_admin, is_auth)
    steam_ids[peer_id] = nil
    peer_ids[tostring(steam_id)] = nil
end

function onCustomCommand(full_message, user_peer_id, is_admin, is_auth, command, ...)
    local args = {...}
    if command == "?verify" then
        server.httpGet(auth_port, "/getcode?sid="..steam_ids[user_peer_id])
    end
end

function httpReply(port, request, reply)
    if port == auth_port and string.sub(request, 1, 8) == "/getcode" then
        local data = json.parse(reply)
        if data.status then
            server.announce("[Verify]", string.format(verify_message, data.code), peer_ids[tostring(data.steam_id)])
        else
            server.announce("[Verify]", "You are already verified!", peer_ids[tostring(data.steam_id)])
        end
    elseif port == auth_port and string.sub(request, 1, 6) == "/check" then
        local data = json.parse(reply)
        if peer_ids[tostring(data.steam_id)] == 0 then return end
        if data.status then
          server.setPopupScreen(peer_ids[tostring(data.steam_id)], popup_id, "", false, "", -0.6, 0.88)
            for _, player in pairs(server.getPlayers()) do
                if discord_auth and tostring(player.steam_id) == tostring(data.steam_id) and not player.auth then
                    server.addAuth(peer_ids[tostring(data.steam_id)])
                end
            end
        else
          server.setPopupScreen(peer_ids[tostring(data.steam_id)], popup_id, "", true, unverified_popup, -0.88, 0.8)
            for _, player in pairs(server.getPlayers()) do
                if discord_auth and tostring(player.steam_id) == tostring(data.steam_id) and player.auth then
                    server.removeAuth(peer_ids[tostring(data.steam_id)])
                end
            end
        end
    elseif port == auth_port and string.sub(request, 1, 8) == "/check?v" then
      -- local data = json.parse(reply)
      -- if not data.status then
      --   server.announce("[Verify]", unverified_join_message, peer_ids[tostring(data.steam_id)])
      -- end
    end
end




json = {}


-- Internal functions.

local function kind_of(obj)
  if type(obj) ~= 'table' then return type(obj) end
  local i = 1
  for _ in pairs(obj) do
    if obj[i] ~= nil then i = i + 1 else return 'table' end
  end
  if i == 1 then return 'table' else return 'array' end
end

local function escape_str(s)
  local in_char  = {'\\', '"', '/', '\b', '\f', '\n', '\r', '\t'}
  local out_char = {'\\', '"', '/',  'b',  'f',  'n',  'r',  't'}
  for i, c in ipairs(in_char) do
    s = s:gsub(c, '\\' .. out_char[i])
  end
  return s
end

-- Returns pos, did_find; there are two cases:
-- 1. Delimiter found: pos = pos after leading space + delim; did_find = true.
-- 2. Delimiter not found: pos = pos after leading space;     did_find = false.
-- This throws an error if err_if_missing is true and the delim is not found.
local function skip_delim(str, pos, delim, err_if_missing)
  pos = pos + #str:match('^%s*', pos)
  if str:sub(pos, pos) ~= delim then
    if err_if_missing then
      return nil
    end
    return pos, false
  end
  return pos + 1, true
end

-- Expects the given pos to be the first character after the opening quote.
-- Returns val, pos; the returned pos is after the closing quote character.
local function parse_str_val(str, pos, val)
  val = val or ''
  local early_end_error = 'End of input found while parsing string.'
  if pos > #str then return nil end
  local c = str:sub(pos, pos)
  if c == '"'  then return val, pos + 1 end
  if c ~= '\\' then return parse_str_val(str, pos + 1, val .. c) end
  -- We must have a \ character.
  local esc_map = {b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
  local nextc = str:sub(pos + 1, pos + 1)
  if not nextc then return nil end
  return parse_str_val(str, pos + 2, val .. (esc_map[nextc] or nextc))
end

-- Returns val, pos; the returned pos is after the number's final character.
local function parse_num_val(str, pos)
  local num_str = str:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
  local val = tonumber(num_str)
  if not val then return nil end
  return val, pos + #num_str
end


-- Public values and functions.

function json.stringify(obj, as_key)
  local s = {}  -- We'll build the string as an array of strings to be concatenated.
  local kind = kind_of(obj)  -- This is 'array' if it's an array or type(obj) otherwise.
  if kind == 'array' then
    if as_key then return nil end
    s[#s + 1] = '['
    for i, val in ipairs(obj) do
      if i > 1 then s[#s + 1] = ', ' end
      s[#s + 1] = json.stringify(val)
    end
    s[#s + 1] = ']'
  elseif kind == 'table' then
    if as_key then return nil end
    s[#s + 1] = '{'
    for k, v in pairs(obj) do
      if #s > 1 then s[#s + 1] = ', ' end
      s[#s + 1] = json.stringify(k, true)
      s[#s + 1] = ':'
      s[#s + 1] = json.stringify(v)
    end
    s[#s + 1] = '}'
  elseif kind == 'string' then
    return '"' .. escape_str(obj) .. '"'
  elseif kind == 'number' then
    if as_key then return '"' .. tostring(obj) .. '"' end
    return tostring(obj)
  elseif kind == 'boolean' then
    return tostring(obj)
  elseif kind == 'nil' then
    return 'null'
  else
    return nil
  end
  return table.concat(s)
end

json.null = {}  -- This is a one-off table to represent the null value.

function json.parse(str, pos, end_delim)
  pos = pos or 1
  if pos > #str then return nil end
  local pos = pos + #str:match('^%s*', pos)  -- Skip whitespace.
  local first = str:sub(pos, pos)
  if first == '{' then  -- Parse an object.
    local obj, key, delim_found = {}, true, true
    pos = pos + 1
    while true do
      key, pos = json.parse(str, pos, '}')
      if key == nil then return obj, pos end
      if not delim_found then return nil end
      pos = skip_delim(str, pos, ':', true)  -- true -> error if missing.
      obj[key], pos = json.parse(str, pos)
      pos, delim_found = skip_delim(str, pos, ',')
    end
  elseif first == '[' then  -- Parse an array.
    local arr, val, delim_found = {}, true, true
    pos = pos + 1
    while true do
      val, pos = json.parse(str, pos, ']')
      if val == nil then return arr, pos end
      if not delim_found then return nil end
      arr[#arr + 1] = val
      pos, delim_found = skip_delim(str, pos, ',')
    end
  elseif first == '"' then  -- Parse a string.
    return parse_str_val(str, pos + 1)
  elseif first == '-' or first:match('%d') then  -- Parse a number.
    return parse_num_val(str, pos)
  elseif first == end_delim then  -- End of an object or array.
    return nil, pos + 1
  else  -- Parse true, false, or null.
    local literals = {['true'] = true, ['false'] = false, ['null'] = json.null}
    for lit_str, lit_val in pairs(literals) do
      local lit_end = pos + #lit_str - 1
      if str:sub(pos, lit_end) == lit_str then return lit_val, lit_end + 1 end
    end
    local pos_info_str = 'position ' .. pos .. ': ' .. str:sub(pos, pos + 10)
    return nil
  end
end

return json
