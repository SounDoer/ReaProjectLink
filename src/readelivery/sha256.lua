local M = {}

local MASK = 0xffffffff
local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function rotate_right(value, amount)
  return ((value >> amount) | (value << (32 - amount))) & MASK
end

local function add(...)
  local sum = 0
  for index = 1, select("#", ...) do
    sum = (sum + select(index, ...)) & MASK
  end
  return sum
end

local function initial_hash()
  return {
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  }
end

local function compress(hash, chunk)
  local words = {}
  for index = 0, 15 do
    words[index] = string.unpack(">I4", chunk, 1 + index * 4)
  end
  for index = 16, 63 do
    local x = words[index - 15]
    local y = words[index - 2]
    local sigma0 = rotate_right(x, 7) ~ rotate_right(x, 18) ~ (x >> 3)
    local sigma1 = rotate_right(y, 17) ~ rotate_right(y, 19) ~ (y >> 10)
    words[index] = add(words[index - 16], sigma0, words[index - 7], sigma1)
  end

  local a, b, c, d = hash[1], hash[2], hash[3], hash[4]
  local e, f, g, h = hash[5], hash[6], hash[7], hash[8]

  for index = 0, 63 do
    local sum1 = rotate_right(e, 6) ~ rotate_right(e, 11) ~ rotate_right(e, 25)
    local choose = (e & f) ~ ((~e) & g)
    local temp1 = add(h, sum1, choose, K[index + 1], words[index])
    local sum0 = rotate_right(a, 2) ~ rotate_right(a, 13) ~ rotate_right(a, 22)
    local majority = (a & b) ~ (a & c) ~ (b & c)
    local temp2 = add(sum0, majority)

    h = g
    g = f
    f = e
    e = add(d, temp1)
    d = c
    c = b
    b = a
    a = add(temp1, temp2)
  end

  hash[1] = add(hash[1], a)
  hash[2] = add(hash[2], b)
  hash[3] = add(hash[3], c)
  hash[4] = add(hash[4], d)
  hash[5] = add(hash[5], e)
  hash[6] = add(hash[6], f)
  hash[7] = add(hash[7], g)
  hash[8] = add(hash[8], h)
end

local function new_hasher()
  return {
    hash = initial_hash(),
    buffer = "",
    byte_length = 0,
  }
end

local function update(hasher, bytes)
  hasher.byte_length = hasher.byte_length + #bytes
  local data = hasher.buffer .. bytes
  local complete_length = #data - (#data % 64)
  for position = 1, complete_length, 64 do
    compress(hasher.hash, data:sub(position, position + 63))
  end
  hasher.buffer = data:sub(complete_length + 1)
end

local function finish(hasher)
  local padding_length = (56 - ((hasher.byte_length + 1) % 64)) % 64
  local final_bytes = hasher.buffer .. "\128" .. string.rep("\0", padding_length)
  final_bytes = final_bytes .. string.pack(">I8", hasher.byte_length * 8)
  for position = 1, #final_bytes, 64 do
    compress(hasher.hash, final_bytes:sub(position, position + 63))
  end
  local parts = {}
  for index, value in ipairs(hasher.hash) do
    parts[index] = string.format("%08x", value)
  end
  return table.concat(parts)
end

function M.digest(message)
  if type(message) ~= "string" then
    error("SHA-256 input must be a string", 2)
  end
  local hasher = new_hasher()
  update(hasher, message)
  return finish(hasher)
end

function M.file(path)
  local file, open_error = io.open(path, "rb")
  if not file then
    return nil, open_error
  end
  local hasher = new_hasher()
  while true do
    local bytes = file:read(1024 * 1024)
    if not bytes then
      break
    end
    update(hasher, bytes)
  end
  file:close()
  return finish(hasher)
end

return M
