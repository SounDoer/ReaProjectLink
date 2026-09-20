local M = {}

local FIELDS = {
  "position_seconds",
  "length_seconds",
  "source_offset_seconds",
  "fade_in_seconds",
  "fade_out_seconds",
  "item_gain",
  "take_volume",
  "take_pan",
  "take_playback_rate",
  "take_pitch",
  "take_channel_mode",
  "take_polarity_inverted",
}

local function equal(left, right)
  if type(left) == "number" and type(right) == "number" then
    return math.abs(left - right) <= 0.000000001
  end
  return left == right
end

function M.build(input)
  if not input.delivery then
    return {
      retired = true,
      fields = {},
      conflict_count = 0,
      media = { pending = false, choice = "keep_current_media" },
    }
  end

  local result = {
    retired = false,
    fields = {},
    conflict_count = 0,
    media = {
      -- Targeting an older revision has to offer its audio back, so any
      -- difference from the accepted media revision is pending.
      pending = (input.delivery_media_revision or 0) ~=
        (input.accepted_media_revision or 0),
    },
  }
  result.media.choice = result.media.pending and "add_new_take" or "keep_current_media"
  if input.media_choice then result.media.choice = input.media_choice end

  for _, field in ipairs(FIELDS) do
    local baseline = input.baseline and input.baseline[field]
    local delivery = input.delivery[field]
    local local_state = input.local_state and input.local_state[field]
    local delivery_changed = not equal(delivery, baseline)
    local local_changed = not equal(local_state, baseline)
    local kind, choice
    if delivery_changed and local_changed then
      if equal(delivery, local_state) then
        kind, choice = "same_change", "use_delivery"
      else
        kind, choice = "conflict", "keep_local"
        result.conflict_count = result.conflict_count + 1
      end
    elseif delivery_changed then
      kind, choice = "delivery_only", "use_delivery"
    elseif local_changed then
      kind, choice = "local_only", "keep_local"
    else
      kind, choice = "unchanged", "keep_local"
    end
    if input.field_choices and input.field_choices[field] then
      choice = input.field_choices[field]
    end
    result.fields[field] = {
      baseline = baseline,
      delivery = delivery,
      local_state = local_state,
      kind = kind,
      choice = choice,
    }
  end
  return result
end

return M
