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
  if not input.source then
    return {
      retired = true,
      fields = {},
      conflict_count = 0,
      media = { pending = false, choice = "skip" },
    }
  end

  local result = {
    retired = false,
    fields = {},
    conflict_count = 0,
    media = {
      pending = (input.source_media_revision or 0) >
        (input.accepted_media_revision or 0),
    },
  }
  result.media.choice = result.media.pending and "accept_new_take" or "skip"
  if input.media_choice then result.media.choice = input.media_choice end

  for _, field in ipairs(FIELDS) do
    local baseline = input.baseline and input.baseline[field]
    local source = input.source[field]
    local mix = input.mix and input.mix[field]
    local source_changed = not equal(source, baseline)
    local mix_changed = not equal(mix, baseline)
    local kind, choice
    if source_changed and mix_changed then
      if equal(source, mix) then
        kind, choice = "same_change", "use_source"
      else
        kind, choice = "conflict", "keep_mix"
        result.conflict_count = result.conflict_count + 1
      end
    elseif source_changed then
      kind, choice = "source_only", "use_source"
    elseif mix_changed then
      kind, choice = "mix_only", "keep_mix"
    else
      kind, choice = "unchanged", "keep_mix"
    end
    if input.field_choices and input.field_choices[field] then
      choice = input.field_choices[field]
    end
    result.fields[field] = {
      baseline = baseline,
      source = source,
      mix = mix,
      kind = kind,
      choice = choice,
    }
  end
  return result
end

return M
