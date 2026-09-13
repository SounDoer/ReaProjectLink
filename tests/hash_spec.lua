local sha256 = require("readelivery.sha256")

local actual = sha256.digest("abc")
local expected = "ba7816bf8f01cfea414140de5dae2223" ..
  "b00361a396177a9cb410ff61f20015ad"

if actual ~= expected then
  error(string.format("SHA-256 mismatch: expected %s, got %s", expected, actual))
end

local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = assert(source:match("^(.*)[/\\]"))
local fixture_path = tests_dir .. "/.hash-fixture"
local fixture = assert(io.open(fixture_path, "wb"))
fixture:write("abc")
fixture:close()

local file_digest = sha256.file(fixture_path)
os.remove(fixture_path)
if file_digest ~= expected then
  error(string.format("file SHA-256 mismatch: expected %s, got %s", expected, file_digest))
end

return 2
