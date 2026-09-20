local delivery_update_plan = require("reaprojectlink.delivery_update_plan")

local plan = delivery_update_plan.build({
  baseline = {
    position_seconds = 1,
    length_seconds = 2,
    source_offset_seconds = 0,
    item_gain = 1,
    take_pan = 0,
  },
  delivery = {
    position_seconds = 1.5,
    length_seconds = 2,
    source_offset_seconds = 0,
    item_gain = 0.8,
    take_pan = 0.25,
  },
  local_state = {
    position_seconds = 1,
    length_seconds = 3,
    source_offset_seconds = 0,
    item_gain = 0.9,
    take_pan = 0.25,
  },
  accepted_media_revision = 2,
  delivery_media_revision = 4,
})

assert(plan.fields.position_seconds.kind == "delivery_only", "Source-only field")
assert(plan.fields.position_seconds.choice == "use_delivery", "Source-only defaults to Source")
assert(plan.fields.length_seconds.kind == "local_only", "Local-only field")
assert(plan.fields.length_seconds.choice == "keep_local", "Local-only remains local")
assert(plan.fields.item_gain.kind == "conflict", "divergent field conflict")
assert(plan.fields.item_gain.choice == "keep_local", "conflict defaults to Mix")
assert(plan.fields.take_pan.kind == "same_change", "equal concurrent result")
assert(plan.fields.take_pan.choice == "use_delivery", "equal result is accepted")
assert(plan.conflict_count == 1, "conflict count")
assert(plan.media.pending, "new media revision pending")
assert(plan.media.choice == "add_new_take", "media defaults to a new Take")

local rolled_back = delivery_update_plan.build({
  baseline = {},
  delivery = {},
  local_state = {},
  accepted_media_revision = 4,
  delivery_media_revision = 2,
})
assert(rolled_back.media.pending, "an older target offers its own audio back")

local retired = delivery_update_plan.build({ baseline = {}, local_state = {}, delivery = nil })
assert(retired.retired, "missing Source Clip is retired")
assert(retired.media.choice == "keep_current_media", "retirement never deletes media")

return 3
