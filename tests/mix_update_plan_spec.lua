local mix_update_plan = require("readelivery.mix_update_plan")

local plan = mix_update_plan.build({
  baseline = {
    position_seconds = 1,
    length_seconds = 2,
    source_offset_seconds = 0,
    item_gain = 1,
    take_pan = 0,
  },
  source = {
    position_seconds = 1.5,
    length_seconds = 2,
    source_offset_seconds = 0,
    item_gain = 0.8,
    take_pan = 0.25,
  },
  mix = {
    position_seconds = 1,
    length_seconds = 3,
    source_offset_seconds = 0,
    item_gain = 0.9,
    take_pan = 0.25,
  },
  accepted_media_revision = 2,
  source_media_revision = 4,
})

assert(plan.fields.position_seconds.kind == "source_only", "Source-only field")
assert(plan.fields.position_seconds.choice == "use_source", "Source-only defaults to Source")
assert(plan.fields.length_seconds.kind == "mix_only", "Mix-only field")
assert(plan.fields.length_seconds.choice == "keep_mix", "Mix-only remains local")
assert(plan.fields.item_gain.kind == "conflict", "divergent field conflict")
assert(plan.fields.item_gain.choice == "keep_mix", "conflict defaults to Mix")
assert(plan.fields.take_pan.kind == "same_change", "equal concurrent result")
assert(plan.fields.take_pan.choice == "use_source", "equal result is accepted")
assert(plan.conflict_count == 1, "conflict count")
assert(plan.media.pending, "new media revision pending")
assert(plan.media.choice == "accept_new_take", "media defaults to a new Take")

local retired = mix_update_plan.build({ baseline = {}, mix = {}, source = nil })
assert(retired.retired, "missing Source Clip is retired")
assert(retired.media.choice == "skip", "retirement never deletes media")

return 2
