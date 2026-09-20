local delivery_manifest = require("reaprojectlink.delivery_manifest")
local json = require("reaprojectlink.json")

local snapshot, pointer = delivery_manifest.build({
  source_project_id = "source-1",
  delivery_id = "set-1",
  source_project_name = "CIN_030_DX",
  source_project_file = "../../../CIN_030_DX.rpp",
  delivery_revision = 3,
  published_at = "2026-09-13T12:00:00+08:00",
  published_by = "Alice",
  reference_id = "reference-1",
  reviewed_reference_revision = 7,
  sample_rate = 48000,
  lanes = {},
})

assert(snapshot.schemaVersion == 1, "snapshot schema version")
assert(snapshot.sourceProjectId == "source-1", "snapshot source identity")
assert(snapshot.deliveryId == "set-1", "snapshot set identity")
assert(snapshot.deliveryRevision == 3, "snapshot revision")
assert(snapshot.reference.referenceId == "reference-1", "snapshot reference identity")
assert(snapshot.reference.reviewedRevision == 7, "snapshot reference revision")
assert(json.encode(snapshot.lanes) == "[]", "empty lanes remain a JSON array")

assert(pointer.schemaVersion == 1, "pointer schema version")
assert(pointer.latestDeliveryRevision == 3, "pointer revision")
assert(pointer.manifest == "history/delivery-0003.json", "pointer history path")

return 1
