local delivery_manifest = require("readelivery.delivery_manifest")
local json = require("readelivery.json")

local snapshot, pointer = delivery_manifest.build({
  source_project_id = "source-1",
  delivery_set_id = "set-1",
  source_project_name = "CIN_030_DX",
  source_project_file = "../../../CIN_030_DX.rpp",
  publish_revision = 3,
  published_at = "2026-09-13T12:00:00+08:00",
  published_by = "Alice",
  picture_id = "picture-1",
  reviewed_picture_revision = 7,
  sample_rate = 48000,
  lanes = {},
})

assert(snapshot.schemaVersion == 1, "snapshot schema version")
assert(snapshot.sourceProjectId == "source-1", "snapshot source identity")
assert(snapshot.deliverySetId == "set-1", "snapshot set identity")
assert(snapshot.publishRevision == 3, "snapshot revision")
assert(snapshot.picture.pictureId == "picture-1", "snapshot picture identity")
assert(snapshot.picture.reviewedRevision == 7, "snapshot picture revision")
assert(json.encode(snapshot.lanes) == "[]", "empty lanes remain a JSON array")

assert(pointer.schemaVersion == 1, "pointer schema version")
assert(pointer.latestPublishRevision == 3, "pointer revision")
assert(pointer.manifest == "history/publish-0003.json", "pointer history path")

return 1
