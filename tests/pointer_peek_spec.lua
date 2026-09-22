local json = require("reaprojectlink.json")
local reference_subscription = require("reaprojectlink.reference_subscription")
local delivery_update = require("reaprojectlink.delivery_update")

local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local files, values = {}, {}
local fs = {}
function fs.exists(path) return files[path] ~= nil end
function fs.read_file(path) return files[path] end
function fs.join(...) return (table.concat({ ... }, "/"):gsub("/+", "/")) end
function fs.hash_file() error("a pointer check must not hash media") end

local adapter = {}
function adapter.get_project_value(key) return values[key] end

local reference_path = "C:/mix/_ReaProjectLink/MIX/reference.json"
local delivery_root = "C:/dx/_ReaProjectLink/DX"
local subscription = {
  pointerPath = delivery_root .. "/delivery.json",
  sourceProjectId = "source-1",
  deliveryId = "delivery-1",
}

local function reset()
  files, values = {}, {}
  files[reference_path] = json.encode({
    schemaVersion = 2, masterProjectId = "master-1", referenceId = "reference-1",
    latestReferenceRevision = 5, manifest = "history/reference-0005.json",
  })
  files[delivery_root .. "/delivery.json"] = json.encode({
    schemaVersion = 1, sourceProjectId = "source-1", deliveryId = "delivery-1",
    latestDeliveryRevision = 3, manifest = "history/delivery-0003.json",
  })
  files[delivery_root .. "/history/delivery-0003.json"] = json.encode({
    schemaVersion = 1, reference = { referenceId = "reference-1", reviewedRevision = 6 },
  })
  values.reference_manifest_path = reference_path
  values.reference_id = "reference-1"
end

local tests = {}

function tests.reference_peek_requires_a_subscription()
  reset()
  values.reference_manifest_path = nil
  local status, _, kind = reference_subscription.peek(adapter, fs)
  equal(status, nil, "no status")
  equal(kind, "unsubscribed", "kind")
end

function tests.reference_peek_reports_unreachable_storage()
  reset()
  files[reference_path] = nil
  local status, err, kind = reference_subscription.peek(adapter, fs)
  equal(status, nil, "no status")
  equal(kind, "unreachable", "kind")
  equal(err, "Couldn't reach shared storage.", "message")
end

function tests.reference_peek_reads_only_the_pointer()
  reset()
  local status = assert(reference_subscription.peek(adapter, fs))
  equal(status.latest_revision, 5, "latest revision")
end

function tests.reference_peek_rejects_a_changed_identity()
  reset()
  values.reference_id = "other-reference"
  local status, _, kind = reference_subscription.peek(adapter, fs)
  equal(status, nil, "no status")
  equal(kind, "invalid", "kind")
end

function tests.delivery_peek_reads_the_pointer_and_latest_snapshot()
  reset()
  local status = assert(delivery_update.peek(fs, subscription))
  equal(status.latest_revision, 3, "latest revision")
  equal(status.reviewed_reference_revision, 6, "reviewed Reference revision")
end

function tests.delivery_peek_reports_unreachable_storage()
  reset()
  files[subscription.pointerPath] = nil
  local status, _, kind = delivery_update.peek(fs, subscription)
  equal(status, nil, "no status")
  equal(kind, "unreachable", "kind")
end

function tests.delivery_peek_rejects_a_changed_identity()
  reset()
  local changed = { pointerPath = subscription.pointerPath, sourceProjectId = "other", deliveryId = "delivery-1" }
  local status, _, kind = delivery_update.peek(fs, changed)
  equal(status, nil, "no status")
  equal(kind, "invalid", "kind")
end

local passed = 0
for name, test in pairs(tests) do
  local ok, err = pcall(test)
  if not ok then error(name .. ": " .. tostring(err)) end
  passed = passed + 1
end

return passed
