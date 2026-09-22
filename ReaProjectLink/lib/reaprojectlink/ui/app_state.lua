-- Transient UI state for the active REAPER project (D067). `clock` returns
-- seconds, for example `reaper.time_precise`.
local M = {}

M.TOAST_SECONDS = 4

function M.new(clock)
  local app = { clock = clock }

  function app:reset()
    self.view = "main"
    self.review = nil
    self.toast = nil
    self.lock = nil
    self.media_error = nil
    self.checks = { reference = { state = "idle" }, deliveries = {} }
    self.check_phase = nil
    self.checked_at = nil
    self.moved_items_change_count = -1
  end

  function app:open_review(kind, fields)
    fields = fields or {}
    fields.kind = kind
    self.review = fields
    self.view = "review"
  end

  function app:open_settings()
    self.view = "settings"
  end

  function app:back()
    self.review = nil
    self.view = "main"
  end

  function app:notify(text, is_error)
    self.toast = { text = tostring(text), is_error = is_error == true, shown_at = self.clock() }
  end

  function app:visible_toast()
    local toast = self.toast
    if toast and not toast.is_error and self.clock() - toast.shown_at >= M.TOAST_SECONDS then
      self.toast = nil
    end
    return self.toast
  end

  function app:dismiss_toast()
    self.toast = nil
  end

  -- The first frame after a request renders "Checking..."; the next one runs it.
  function app:request_check()
    self.check_phase = "requested"
    self.checks.reference = { state = "checking", latest = self.checks.reference.latest }
    for id, check in pairs(self.checks.deliveries) do
      self.checks.deliveries[id] = {
        state = "checking", latest = check.latest, reviewed_reference = check.reviewed_reference,
      }
    end
  end

  function app:check_due()
    if self.check_phase == "requested" then
      self.check_phase = "shown"
      return false
    end
    if self.check_phase == "shown" then
      self.check_phase = nil
      return true
    end
    return false
  end

  function app:finish_check()
    self.checked_at = self.clock()
  end

  function app:seconds_since_check()
    if not self.checked_at then return nil end
    return math.floor(self.clock() - self.checked_at)
  end

  app:reset()
  return app
end

return M
