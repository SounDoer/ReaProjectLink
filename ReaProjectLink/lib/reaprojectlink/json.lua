local M = {}

local array_marker = {}
local null_marker = {}
M.null = null_marker

function M.array(values)
  return setmetatable(values or {}, array_marker)
end

local escapes = {
  ['"'] = '\\"',
  ["\\"] = "\\\\",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
}

local function encode_string(value)
  return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
    return escapes[character] or string.format("\\u%04x", character:byte())
  end) .. '"'
end

local function table_kind(value)
  if getmetatable(value) == array_marker then
    return "array", #value
  end

  local count = 0
  local maximum = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return "object"
    end
    count = count + 1
    maximum = math.max(maximum, key)
  end
  if count > 0 and count == maximum then
    return "array", maximum
  end
  return "object"
end

local encode_value

local function encode_table(value, stack)
  if stack[value] then
    error("cannot encode a circular table", 2)
  end
  stack[value] = true

  local kind, length = table_kind(value)
  local parts = {}
  if kind == "array" then
    for index = 1, length do
      parts[index] = encode_value(value[index], stack)
    end
    stack[value] = nil
    return "[" .. table.concat(parts, ",") .. "]"
  end

  local keys = {}
  for key in pairs(value) do
    if type(key) ~= "string" then
      error("JSON object keys must be strings", 2)
    end
    table.insert(keys, key)
  end
  table.sort(keys)
  for index, key in ipairs(keys) do
    parts[index] = encode_string(key) .. ":" .. encode_value(value[key], stack)
  end
  stack[value] = nil
  return "{" .. table.concat(parts, ",") .. "}"
end

encode_value = function(value, stack)
  if value == null_marker or value == nil then
    return "null"
  end

  local value_type = type(value)
  if value_type == "string" then
    return encode_string(value)
  elseif value_type == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      error("cannot encode a non-finite number", 2)
    end
    return string.format("%.17g", value)
  elseif value_type == "boolean" then
    return value and "true" or "false"
  elseif value_type == "table" then
    return encode_table(value, stack)
  end

  error("cannot encode value of type " .. value_type, 2)
end

function M.encode(value)
  return encode_value(value, {})
end

local function decode_error(text, position, message)
  error(string.format("invalid JSON at byte %d: %s", position, message), 3)
end

local function skip_space(text, position)
  local _, next_position = text:find("^[ \t\r\n]*", position)
  return (next_position or position - 1) + 1
end

local parse_value

local function parse_string(text, position)
  position = position + 1
  local parts = {}
  local start = position

  while position <= #text do
    local byte = text:byte(position)
    if byte == 34 then
      table.insert(parts, text:sub(start, position - 1))
      return table.concat(parts), position + 1
    elseif byte == 92 then
      table.insert(parts, text:sub(start, position - 1))
      local escape = text:sub(position + 1, position + 1)
      local simple = {
        ['"'] = '"',
        ["\\"] = "\\",
        ["/"] = "/",
        b = "\b",
        f = "\f",
        n = "\n",
        r = "\r",
        t = "\t",
      }
      if simple[escape] then
        table.insert(parts, simple[escape])
        position = position + 2
      elseif escape == "u" then
        local hex = text:sub(position + 2, position + 5)
        local codepoint = tonumber(hex, 16)
        if not codepoint or #hex ~= 4 then
          decode_error(text, position, "invalid unicode escape")
        end
        position = position + 6
        if codepoint >= 0xd800 and codepoint <= 0xdbff then
          if text:sub(position, position + 1) ~= "\\u" then
            decode_error(text, position, "missing low surrogate")
          end
          local low = tonumber(text:sub(position + 2, position + 5), 16)
          if not low or low < 0xdc00 or low > 0xdfff then
            decode_error(text, position, "invalid low surrogate")
          end
          codepoint = 0x10000 + (codepoint - 0xd800) * 0x400 + (low - 0xdc00)
          position = position + 6
        elseif codepoint >= 0xdc00 and codepoint <= 0xdfff then
          decode_error(text, position, "unexpected low surrogate")
        end
        table.insert(parts, utf8.char(codepoint))
      else
        decode_error(text, position, "invalid escape")
      end
      start = position
    elseif byte < 32 then
      decode_error(text, position, "control character in string")
    else
      position = position + 1
    end
  end

  decode_error(text, position, "unterminated string")
end

local function parse_number(text, position)
  local start = position
  if text:sub(position, position) == "-" then
    position = position + 1
  end

  local first = text:sub(position, position)
  if first == "0" then
    position = position + 1
    if text:sub(position, position):match("%d") then
      decode_error(text, position, "leading zero in number")
    end
  elseif first:match("[1-9]") then
    repeat
      position = position + 1
    until not text:sub(position, position):match("%d")
  else
    decode_error(text, position, "invalid number")
  end

  if text:sub(position, position) == "." then
    position = position + 1
    if not text:sub(position, position):match("%d") then
      decode_error(text, position, "missing fractional digits")
    end
    repeat
      position = position + 1
    until not text:sub(position, position):match("%d")
  end

  local exponent = text:sub(position, position)
  if exponent == "e" or exponent == "E" then
    position = position + 1
    local sign = text:sub(position, position)
    if sign == "+" or sign == "-" then
      position = position + 1
    end
    if not text:sub(position, position):match("%d") then
      decode_error(text, position, "missing exponent digits")
    end
    repeat
      position = position + 1
    until not text:sub(position, position):match("%d")
  end

  local token = text:sub(start, position - 1)
  local value = tonumber(token)
  if not value then
    decode_error(text, start, "invalid number")
  end
  return value, position
end

local function parse_array(text, position)
  local result = M.array()
  position = skip_space(text, position + 1)
  if text:sub(position, position) == "]" then
    return result, position + 1
  end

  while true do
    local value
    value, position = parse_value(text, position)
    table.insert(result, value)
    position = skip_space(text, position)
    local character = text:sub(position, position)
    if character == "]" then
      return result, position + 1
    elseif character ~= "," then
      decode_error(text, position, "expected ',' or ']'")
    end
    position = skip_space(text, position + 1)
  end
end

local function parse_object(text, position)
  local result = {}
  position = skip_space(text, position + 1)
  if text:sub(position, position) == "}" then
    return result, position + 1
  end

  while true do
    if text:sub(position, position) ~= '"' then
      decode_error(text, position, "expected string key")
    end
    local key
    key, position = parse_string(text, position)
    position = skip_space(text, position)
    if text:sub(position, position) ~= ":" then
      decode_error(text, position, "expected ':'")
    end
    position = skip_space(text, position + 1)
    result[key], position = parse_value(text, position)
    position = skip_space(text, position)
    local character = text:sub(position, position)
    if character == "}" then
      return result, position + 1
    elseif character ~= "," then
      decode_error(text, position, "expected ',' or '}'")
    end
    position = skip_space(text, position + 1)
  end
end

parse_value = function(text, position)
  position = skip_space(text, position)
  local character = text:sub(position, position)
  if character == '"' then
    return parse_string(text, position)
  elseif character == "{" then
    return parse_object(text, position)
  elseif character == "[" then
    return parse_array(text, position)
  elseif character == "-" or character:match("%d") then
    return parse_number(text, position)
  elseif text:sub(position, position + 3) == "true" then
    return true, position + 4
  elseif text:sub(position, position + 4) == "false" then
    return false, position + 5
  elseif text:sub(position, position + 3) == "null" then
    return null_marker, position + 4
  end
  decode_error(text, position, "unexpected token")
end

function M.decode(text)
  if type(text) ~= "string" then
    error("JSON input must be a string", 2)
  end
  local value, position = parse_value(text, 1)
  position = skip_space(text, position)
  if position <= #text then
    decode_error(text, position, "trailing content")
  end
  return value
end

return M
