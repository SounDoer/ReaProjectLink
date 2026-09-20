local json = require("reaprojectlink.json")

local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local manifest = json.decode([[
{
  "schemaVersion": 1,
  "sourceProjectId": "source-1",
  "latestDeliveryRevision": 18,
  "manifest": "history/delivery-0018.json"
}
]])

equal(manifest.schemaVersion, 1, "schema version")
equal(manifest.sourceProjectId, "source-1", "source id")
equal(manifest.latestDeliveryRevision, 18, "publish revision")
equal(manifest.manifest, "history/delivery-0018.json", "history path")

local encoded = json.encode({
  schemaVersion = 1,
  sourceProjectId = "source-1",
  latestDeliveryRevision = 18,
  manifest = "history/delivery-0018.json",
})

equal(
  encoded,
  '{"latestDeliveryRevision":18,"manifest":"history/delivery-0018.json",' ..
    '"schemaVersion":1,"sourceProjectId":"source-1"}',
  "canonical JSON"
)

local leading_zero_ok = pcall(json.decode, "01")
local trailing_decimal_ok = pcall(json.decode, "1.")
equal(leading_zero_ok, false, "leading-zero number rejection")
equal(trailing_decimal_ok, false, "trailing-decimal number rejection")

return 2
