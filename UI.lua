-- Level Ledger: dashboard window and minimap button.
-- Layout, top to bottom: filter bar (dropdowns) -> KPI tiles -> chart toolbar -> chart -> legend.
-- Filters apply to everything below them; clicking a bar or a level in the chart sets that filter.
local _, ns = ...

local W, ROWS, ROW_H = 720, 12, 22
local BODY_Y, BODY_H = -208, ROWS * ROW_H
local LABEL_W, VALUE_W = 150, 190
local BAR_W = W - 32 - LABEL_W - VALUE_W
local MAX_PARTS = 8
local FONT = "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ACCENT = { 0.95, 0.72, 0.30 }
local INK = { 0.055, 0.06, 0.075 }
local MUTED = { 0.5, 0.52, 0.58 }
local TEXT = { 0.85, 0.86, 0.9 }

local TOWN = { 0.88, 0.80, 0.40 }
local COLORS = {
  Combat = { 0.86, 0.30, 0.28 }, ["On foot"] = { 0.40, 0.72, 0.45 }, Standing = { 0.55, 0.57, 0.62 },
  Mounted = { 0.80, 0.58, 0.32 }, Flying = { 0.42, 0.68, 0.95 }, ["Flight path"] = { 0.36, 0.52, 0.90 },
  Swimming = { 0.30, 0.75, 0.82 }, AFK = { 0.40, 0.40, 0.45 }, Dead = { 0.55, 0.30, 0.60 },
  Ghost = { 0.70, 0.62, 0.88 }, Vendor = TOWN, Mailbox = TOWN, ["Auction house"] = TOWN, Bank = TOWN,
  Trainer = TOWN, ["Flight master"] = TOWN,
  Eating = { 0.85, 0.65, 0.45 }, Drinking = { 0.45, 0.65, 0.90 }, ["Eating & drinking"] = { 0.68, 0.66, 0.72 },
  Crafting = { 0.75, 0.55, 0.95 }, Mining = { 0.70, 0.55, 0.40 }, Herbalism = { 0.45, 0.78, 0.35 },
  Skinning = { 0.82, 0.48, 0.40 }, Fishing = { 0.30, 0.60, 0.85 },
  Quest = { 0.95, 0.72, 0.30 }, Mob = { 0.86, 0.30, 0.28 }, Exploration = { 0.40, 0.72, 0.45 },
  ["Mob · rested"] = { 0.95, 0.58, 0.56 }, ["Mob · group"] = { 0.62, 0.18, 0.22 },
  Total = { 0.95, 0.95, 0.95 }, Other = { 0.35, 0.36, 0.40 },
}
local PALETTE = {
  { 0.36, 0.62, 0.95 }, { 0.95, 0.55, 0.35 }, { 0.45, 0.80, 0.55 }, { 0.80, 0.45, 0.85 },
  { 0.95, 0.80, 0.35 }, { 0.35, 0.80, 0.85 }, { 0.90, 0.40, 0.50 }, { 0.65, 0.65, 0.70 },
}
local function colorFor(key, i)
  return COLORS[key] or PALETTE[((i or 1) - 1) % #PALETTE + 1]
end

-- Dimensions each measure has; filters on other dimensions are kept but don't apply.
local DIMS = {
  time = { "level", "zone", "activity" },
  xp = { "level", "zone", "source", "name" },
  deaths = { "level", "zone" },
}
local FILTER_DIMS = { "level", "zone", "activity", "source", "name" }
local DIM_LABEL = { activity = "Activity", zone = "Zone", level = "Level", source = "Source", name = "Mob / Quest" }

local view = { measure = "time", mode = "bars", by = "level", split = "activity", filter = {}, offset = 0 }

local function fmtTime(s)
  s = math.floor(s or 0)
  local h, m = math.floor(s / 3600), math.floor(s % 3600 / 60)
  if h >= 24 then return ("%dd %02dh"):format(math.floor(h / 24), h % 24) end
  if h > 0 then return ("%dh %02dm"):format(h, m) end
  if m > 0 then return ("%dm"):format(m) end
  return ("%ds"):format(s)
end

local function fmtNum(n)
  local s = tostring(math.floor(n + 0.5))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function fmtValue(v)
  return view.measure == "time" and fmtTime(v) or (fmtNum(v) .. " XP")
end

local BONUS_HINT = "Bonus XP from mob kills, shown apart from the base kill XP"
local function addHint(key)
  if type(key) == "string" and key:find("^Mob · ") then
    GameTooltip:AddLine(BONUS_HINT, MUTED[1], MUTED[2], MUTED[3], true)
  end
end

local function keyLabel(dim, key)
  return dim == "level" and ("Level " .. key) or tostring(key)
end

local function text(parent, size, c)
  local t = parent:CreateFontString(nil, "OVERLAY")
  t:SetFont(FONT, size, "")
  c = c or TEXT
  t:SetTextColor(c[1], c[2], c[3])
  return t
end

local function box(f, bg, border)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function tex(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer)
  t:SetTexture(WHITE)
  t:SetVertexColor(c[1], c[2], c[3], a or 1)
  return t
end

-- A flat pill button; active pills are filled with the accent color.
local function pill(parent, label, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b.label = text(b, 11)
  b.label:SetPoint("CENTER")
  b:SetHeight(20)
  b:SetScript("OnClick", onClick)
  function b:Set(txt, active)
    self.label:SetText(txt)
    self:SetWidth(self.label:GetStringWidth() + 20)
    if active then
      box(self, { ACCENT[1], ACCENT[2], ACCENT[3], 0.9 }, ACCENT)
      self.label:SetTextColor(INK[1], INK[2], INK[3])
    else
      box(self, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.12 })
      self.label:SetTextColor(0.8, 0.82, 0.86)
    end
  end
  b:Set(label, false)
  return b
end

-- Dropdowns share one popup list. getOptions() returns { { value, label, info }, ... }.
local popup
local POPUP_ROWS = 14

local function closePopup()
  if popup then popup:Hide() end
end

local function openPopup(anchor, options, onPick)
  if popup:IsShown() and popup.anchor == anchor then popup:Hide() return end
  popup.anchor, popup.options, popup.onPick, popup.offset = anchor, options, onPick, 0
  popup:ClearAllPoints()
  popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  popup:SetWidth(math.max(anchor:GetWidth(), 240))
  popup:Show()
  popup:Render()
end

local function buildPopup()
  popup = CreateFrame("Frame", "LevelLedgerPopup", UIParent, "BackdropTemplate")
  popup:SetFrameStrata("DIALOG")
  box(popup, { 0.09, 0.10, 0.12, 0.98 }, { 1, 1, 1, 0.18 })
  popup:EnableMouseWheel(true)
  popup:Hide()
  tinsert(UISpecialFrames, "LevelLedgerPopup")
  popup.items = {}
  for i = 1, POPUP_ROWS do
    local it = CreateFrame("Button", nil, popup)
    it:SetHeight(18)
    it:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 18)
    it:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 18)
    it.label = text(it, 11)
    it.label:SetPoint("LEFT", 6, 0)
    it.label:SetJustifyH("LEFT")
    it.label:SetWordWrap(false)
    it.info = text(it, 10, MUTED)
    it.info:SetPoint("RIGHT", -6, 0)
    it.label:SetPoint("RIGHT", it.info, "LEFT", -6, 0)
    local hl = tex(it, "HIGHLIGHT", { 1, 1, 1 }, 0.08)
    hl:SetAllPoints()
    it:SetScript("OnClick", function(self)
      popup:Hide()
      popup.onPick(self.value)
    end)
    popup.items[i] = it
  end
  function popup:Render()
    local opts = self.options
    self.offset = math.max(0, math.min(self.offset, #opts - POPUP_ROWS))
    local shown = math.min(#opts, POPUP_ROWS)
    for i, it in ipairs(self.items) do
      local o = opts[i + self.offset]
      it:SetShown(o ~= nil)
      if o then
        it.value = o[1]
        it.label:SetText(o[2])
        it.info:SetText(o[3] or "")
        local active = o[1] == self.anchor.current
        local c = active and ACCENT or TEXT
        it.label:SetTextColor(c[1], c[2], c[3])
      end
    end
    self:SetHeight(shown * 18 + 8)
  end
  popup:SetScript("OnMouseWheel", function(self, d) self.offset = self.offset - d * 3; self:Render() end)
end

local function dropdown(parent, width, title, getOptions, onPick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width, 22)
  box(b, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.14 })
  b.title = text(b, 9, MUTED)
  b.title:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 1, 2)
  b.title:SetText(title)
  b.label = text(b, 11)
  b.label:SetPoint("LEFT", 8, 0)
  b.label:SetPoint("RIGHT", -18, 0)
  b.label:SetJustifyH("LEFT")
  b.label:SetWordWrap(false)
  b.arrow = text(b, 10, MUTED)
  b.arrow:SetPoint("RIGHT", -7, 0)
  b.arrow:SetText("v")
  b:SetScript("OnClick", function(self) openPopup(self, getOptions(), onPick) end)
  function b:Set(value, label, active)
    self.current = value
    self.label:SetText(label)
    local c = active and ACCENT or { 0.3, 0.3, 0.33 }
    self:SetBackdropBorderColor(c[1], c[2], c[3], active and 0.9 or 1)
  end
  return b
end

local frame, ui, rows = nil, {}, {}

local function char() return LevelLedgerDB[view.char] or ns.char() end

-- The filter restricted to the dimensions a measure has.
local function filterFor(measure, except)
  local f = {}
  for _, d in ipairs(DIMS[measure]) do
    if d ~= except then f[d] = view.filter[d] end
  end
  return f
end

local function has(measure, dim)
  for _, d in ipairs(DIMS[measure]) do if d == dim then return true end end
end

-- Options for a filter dropdown: "All" plus each value that exists under the other filters.
local function filterOptions(dim)
  local m = (view.measure ~= "deaths" and has(view.measure, dim)) and view.measure or (dim == "source" or dim == "name") and "xp" or "time"
  local list = ns.group(m, dim, filterFor(m, dim), nil, char())
  local fmt = m == "time" and fmtTime or function(v) return fmtNum(v) .. " XP" end
  local opts = { { nil, "All" } }
  for _, r in ipairs(list) do opts[#opts + 1] = { r.key, keyLabel(dim, r.key), fmt(r.v) } end
  return opts
end

local function dimOptions(exclude, withNone)
  local opts = withNone and { { false, "None" } } or {}
  for _, d in ipairs(DIMS[view.measure]) do
    if d ~= exclude then opts[#opts + 1] = { d, DIM_LABEL[d] } end
  end
  return opts
end

-- Clicking a bar filters by it, then shows the next level of detail.
local function drill(key)
  view.filter[view.by] = key
  local free = {}
  for _, d in ipairs(DIMS[view.measure]) do
    if view.filter[d] == nil then free[#free + 1] = d end
  end
  if view.split and view.filter[view.split] == nil then
    view.by = view.split
  elseif free[1] then
    view.by = free[1]
  end
  view.split = nil
  for _, d in ipairs(free) do
    if d ~= view.by then view.split = d break end
  end
  view.offset = 0
  ns.refresh()
end

-- Split keys ordered by their total over all rows.
local function splitOrder(list)
  local totals, keys = {}, {}
  for _, r in ipairs(list) do
    for k, v in pairs(r.parts) do
      if not totals[k] then keys[#keys + 1] = k end
      totals[k] = (totals[k] or 0) + v
    end
  end
  table.sort(keys, function(a, b) return totals[a] > totals[b] end)
  return keys
end

-- KPI tiles: everything under the current level/zone filters (plus activity or source/name where they apply).
-- First and last tracked level of a character.
local function levelRange(c)
  local lo, hi
  for l in pairs(c.levels) do
    if not lo or l < lo then lo = l end
    if not hi or l > hi then hi = l end
  end
  return lo or 0, hi or 0
end

local function kpis()
  local c = char()
  local lo, hi = levelRange(c)
  local scope = view.filter.level and ("level " .. view.filter.level) or ("levels %d-%d"):format(lo, hi)
  local function sum(list) local s = 0 for _, r in ipairs(list) do s = s + r.v end return s end
  local timeAll = sum(ns.group("time", "level", { level = view.filter.level, zone = view.filter.zone }, nil, c))
  local timeSel = sum(ns.group("time", "level", filterFor("time"), nil, c))
  local xp, kills, quests = 0, 0, 0
  for _, r in ipairs(ns.group("xp", "source", filterFor("xp"), nil, c)) do
    xp = xp + r.v
    if r.key == "Mob" then kills = r.n elseif r.key == "Quest" then quests = r.n end
  end
  local deaths = 0
  for lvl, l in pairs(c.levels) do
    if view.filter.level == nil or view.filter.level == lvl then
      for z, n in pairs(l.deaths) do
        if view.filter.zone == nil or view.filter.zone == z then deaths = deaths + n end
      end
    end
  end
  return {
    { "TIME", fmtTime(timeSel), view.filter.activity and ("of " .. fmtTime(timeAll)) or scope },
    { "XP", fmtNum(xp), scope },
    { "XP / HOUR", timeAll > 0 and fmtNum(xp / timeAll * 3600) or "-", "over all time" },
    { "KILLS", fmtNum(kills), "with XP" },
    { "QUESTS", fmtNum(quests), "turned in" },
    { "DEATHS", fmtNum(deaths), "" },
  }
end

local function showLegend(keys)
  local x = 0
  for i, item in ipairs(ui.legend) do
    local k = keys[i]
    item:SetShown(k ~= nil and x < W - 60)
    if k then
      local c = colorFor(k, i)
      item.swatch:SetVertexColor(c[1], c[2], c[3])
      item.label:SetText(tostring(k))
      item:SetWidth(item.label:GetStringWidth() + 16)
      item:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + x, BODY_Y - BODY_H - 10)
      x = x + item:GetWidth() + 10
    end
  end
end

-- XP per hour for a bar. Level and zone rows use all time spent there;
-- source and mob rows use the combat time of the fights those kills happened in.
local function rateFn(c)
  if view.measure ~= "xp" then return function() end end
  if view.by == "level" or view.by == "zone" then
    local secs = {}
    local tf = { level = view.filter.level, zone = view.filter.zone }
    for _, t in ipairs(ns.group("time", view.by, tf, nil, c)) do secs[t.key] = t.v end
    return function(r)
      local t = secs[r.key]
      if t and t > 0 then return r.v / t * 3600, false end
    end
  end
  return function(r)
    if r.sec and r.sec > 0 then return r.v / r.sec * 3600, true end
  end
end

local function drawBars()
  local c = char()
  local list = ns.group(view.measure, view.by, filterFor(view.measure), view.split, c)
  local rate = rateFn(c)
  local keys = view.split and splitOrder(list) or {}
  local total, max = 0, 0
  for _, r in ipairs(list) do total = total + r.v; if r.v > max then max = r.v end end
  view.offset = math.max(0, math.min(view.offset, #list - ROWS))
  for k = 1, ROWS do
    local row, r = rows[k], list[k + view.offset]
    row:SetShown(r ~= nil)
    for _, seg in ipairs(row.segs) do seg:Hide() end
    if r then
      row.data = r
      row.name:SetText(keyLabel(view.by, r.key))
      local width = max > 0 and BAR_W * r.v / max or 0
      if view.split then
        -- stacked: biggest split keys first, the rest merged into "Other"
        local x, other = 0, 0
        for i, sk in ipairs(keys) do
          local v = r.parts[sk]
          if v and v > 0 and r.v > 0 then
            if i < MAX_PARTS then
              local seg = row.segs[i]
              local col = colorFor(sk, i)
              seg:SetVertexColor(col[1], col[2], col[3], 0.9)
              seg:SetPoint("LEFT", row.track, "LEFT", x, 0)
              local w = width * v / r.v
              seg:SetWidth(math.max(1, w))
              seg:Show()
              x = x + w
            else
              other = other + v
            end
          end
        end
        if other > 0 and r.v > 0 then
          local seg = row.segs[MAX_PARTS]
          seg:SetVertexColor(COLORS.Other[1], COLORS.Other[2], COLORS.Other[3], 0.9)
          seg:SetPoint("LEFT", row.track, "LEFT", x, 0)
          seg:SetWidth(math.max(1, width * other / r.v))
          seg:Show()
        end
      else
        local seg = row.segs[1]
        local col = COLORS[r.key] or ACCENT
        seg:SetVertexColor(col[1], col[2], col[3], 0.9)
        seg:SetPoint("LEFT", row.track, "LEFT", 0, 0)
        seg:SetWidth(math.max(1, width))
        seg:Show()
      end
      local val = fmtValue(r.v)
      if view.measure == "xp" and view.by == "name" and r.n > 1 then val = val .. "  " .. r.n .. "x" end
      row.value:SetText(val)
      r.rate, r.combatRate = rate(r)
      row.rate:SetText(r.rate and (fmtNum(r.rate) .. "/h") or "")
      row.pct:SetText(("%d%%"):format(total > 0 and math.floor(r.v / total * 100 + 0.5) or 0))
    end
  end
  frame.empty:SetShown(#list == 0)
  local legend = {}
  for i = 1, math.min(#keys, MAX_PARTS - 1) do legend[i] = keys[i] end
  if #keys >= MAX_PARTS then legend[#legend + 1] = "Other" end
  showLegend(legend)
end

local function drawLines()
  local chart, c = ui.chart, char()
  local list = ns.group(view.measure, "level", filterFor(view.measure, "level"), view.split, c)
  for _, l in ipairs(ui.lines) do l:Hide() end
  for _, col in ipairs(ui.cols) do col:Hide() end
  frame.empty:SetShown(#list == 0)
  if #list == 0 then showLegend({}) return end

  local byLevel, first, last = {}, list[1].key, list[#list].key
  for _, r in ipairs(list) do byLevel[r.key] = r end
  local series = { "Total" }
  if view.split then
    series = {}
    for i, k in ipairs(splitOrder(list)) do if i < MAX_PARTS then series[i] = k end end
    series[#series + 1] = "Total"
  end
  local function value(lvl, s)
    local r = byLevel[lvl]
    if not r then return 0 end
    if s == "Total" then return r.v end
    return r.parts[s] or 0
  end
  local max = 0
  for _, r in ipairs(list) do if r.v > max then max = r.v end end
  if max <= 0 then max = 1 end

  local cw, ch = chart:GetWidth(), chart:GetHeight()
  local steps = math.max(1, last - first)
  local function px(lvl) return (lvl - first) / steps * cw end
  local function py(v) return v / max * ch end

  for i, g in ipairs(ui.grid) do
    g.label:SetText(fmtValue(max * i / #ui.grid))
  end
  local every = math.max(1, math.ceil((last - first + 1) / 12))
  for i, lab in ipairs(ui.xlabels) do
    local lvl = first + (i - 1) * every
    lab:SetShown(lvl <= last)
    if lvl <= last then
      lab:SetText(lvl)
      lab:SetPoint("TOP", chart, "BOTTOMLEFT", px(lvl), -4)
    end
  end

  local n = 0
  for si, s in ipairs(series) do
    local col = colorFor(s, si)
    for lvl = first, last - 1 do
      n = n + 1
      local line = ui.lines[n]
      if not line then
        line = chart:CreateLine(nil, "ARTWORK")
        line:SetTexture(WHITE)
        ui.lines[n] = line
      end
      line:SetThickness(s == "Total" and 2.5 or 1.5)
      line:SetVertexColor(col[1], col[2], col[3], s == "Total" and 1 or 0.9)
      line:SetStartPoint("BOTTOMLEFT", chart, px(lvl), py(value(lvl, s)))
      line:SetEndPoint("BOTTOMLEFT", chart, px(lvl + 1), py(value(lvl + 1, s)))
      line:Show()
    end
  end

  -- one hover column per level: guide line, dots and a tooltip; click filters to that level
  local colW = cw / (last - first + 1)
  for lvl = first, last do
    local i = lvl - first + 1
    local col = ui.cols[i]
    if not col then
      col = CreateFrame("Button", nil, chart)
      col:SetScript("OnEnter", function(self)
        ui.guide:ClearAllPoints()
        ui.guide:SetPoint("BOTTOM", chart, "BOTTOMLEFT", self.x, 0)
        ui.guide:Show()
        for si, s in ipairs(self.series) do
          local dot = ui.dots[si]
          local cc = colorFor(s, si)
          dot:SetVertexColor(cc[1], cc[2], cc[3])
          dot:ClearAllPoints()
          dot:SetPoint("CENTER", chart, "BOTTOMLEFT", self.x, self.py(self.value(self.level, s)))
          dot:Show()
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Level " .. self.level, ACCENT[1], ACCENT[2], ACCENT[3])
        for si, s in ipairs(self.series) do
          local cc = colorFor(s, si)
          GameTooltip:AddDoubleLine(tostring(s), fmtValue(self.value(self.level, s)), cc[1], cc[2], cc[3], 1, 1, 1)
        end
        for _, s in ipairs(self.series) do addHint(s) end
        GameTooltip:AddLine("Click to filter to this level", MUTED[1], MUTED[2], MUTED[3])
        GameTooltip:Show()
      end)
      col:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ui.guide:Hide()
        for _, d in ipairs(ui.dots) do d:Hide() end
      end)
      col:SetScript("OnClick", function(self)
        view.mode, view.filter.level = "bars", self.level
        if view.by == "level" then view.by = "zone" end
        ns.refresh()
      end)
      ui.cols[i] = col
    end
    col.level, col.series, col.value, col.x, col.py = lvl, series, value, px(lvl), py
    col:SetSize(colW, ch)
    col:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", px(lvl) - colW / 2, 0)
    col:Show()
  end
  showLegend(series)
end

-- Deaths view: a list of recorded deaths; clicking one opens its recap.
local function drawDeathList()
  local list = ns.deaths(view.filter, char())
  view.offset = math.max(0, math.min(view.offset, #list - ROWS))
  for k, row in ipairs(ui.drows) do
    local d = list[k + view.offset]
    row:SetShown(d ~= nil)
    if d then
      row.death = d
      row.date:SetText(date("%d.%m. %H:%M", d.time))
      row.level:SetText("Level " .. d.level)
      row.zone:SetText(d.zone)
      row.killer:SetText(d.killer and (d.killer .. "  ·  " .. (d.spell or "?"))
        or (d.target and ("while targeting " .. d.target)) or "unknown")
      row.hits:SetText(#d.events .. " events")
    end
  end
  frame.empty:SetText("No recorded deaths for these filters.")
  frame.empty:SetShown(#list == 0)
end

local function drawRecap(d)
  local r = ui.recap
  r:Show()
  local last
  for i = #d.events, 1, -1 do if not d.events[i].heal then last = d.events[i] break end end
  local who = d.killer or d.target
  r.head:SetText(("Died%s%s"):format(who and (d.killer and " to |cffffffff" or " while targeting |cffffffff") .. who .. "|r" or "",
    last and ("  ·  last hit |cffffffff" .. fmtNum(last.amt) .. "|r") or ""))
  r.sub:SetText(("Level %d  ·  %s  ·  %s"):format(d.level, d.zone, date("%d.%m.%Y %H:%M", d.time)))
  r.ready:SetText(d.ready and (#d.ready > 0 and ("Still ready:  |cffffffff" .. table.concat(d.ready, ",  ") .. "|r") or "Still ready:  nothing") or "")

  -- health line: one point per event, -15 s to 0 s
  local cw, ch = r.hp:GetWidth(), r.hp:GetHeight()
  local function px(dt) return (dt + 15) / 15 * cw end
  local function py(e) return (e.hp or 0) / math.max(1, d.max or 1) * ch end
  for _, l in ipairs(r.lines) do l:Hide() end
  for _, m in ipairs(r.marks) do m:Hide() end
  local prev
  for i, e in ipairs(d.events) do
    local mk = r.marks[i]
    if not mk then
      mk = r.hp:CreateTexture(nil, "OVERLAY")
      mk:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
      mk:SetSize(6, 6)
      r.marks[i] = mk
    end
    local c = e.heal and COLORS["On foot"] or COLORS.Combat
    mk:SetVertexColor(c[1], c[2], c[3])
    mk:SetPoint("CENTER", r.hp, "BOTTOMLEFT", px(e.dt), py(e))
    mk:Show()
    if prev then
      local l = r.lines[i]
      if not l then
        l = r.hp:CreateLine(nil, "ARTWORK")
        l:SetTexture(WHITE)
        l:SetThickness(1.5)
        l:SetVertexColor(1, 1, 1, 0.8)
        r.lines[i] = l
      end
      l:SetStartPoint("BOTTOMLEFT", r.hp, px(prev.dt), py(prev))
      l:SetEndPoint("BOTTOMLEFT", r.hp, px(e.dt), py(e))
      l:Show()
    end
    prev = e
  end

  -- event list, newest at the bottom; mouse wheel scrolls
  local n = #d.events
  local rowsN = #r.rows
  view.offset = math.max(0, math.min(view.offset, n - rowsN))
  local start = math.max(0, n - rowsN - view.offset)
  for k, row in ipairs(r.rows) do
    local e = d.events[start + k]
    row:SetShown(e ~= nil)
    if e then
      row.t:SetText(("%.1fs"):format(e.dt))
      row.src:SetText(e.src or (e.heal and "Healing" or "Damage"))
      row.spell:SetText((e.spell or "") .. (e.crit and "  (crit)" or ""))
      local c = e.heal and COLORS["On foot"] or COLORS.Combat
      row.amt:SetTextColor(c[1], c[2], c[3])
      row.amt:SetText((e.heal and "+" or "-") .. fmtNum(e.amt) .. (e.over and ("  (" .. fmtNum(e.over) .. " over)") or ""))
      row.hp:SetText(("%d%%"):format(math.floor((e.hp or 0) / math.max(1, d.max or 1) * 100 + 0.5)))
    end
  end
  frame.empty:SetText("No hits were recorded before this death.")
  frame.empty:SetShown(n == 0)
end

function ns.refresh()
  if not frame or not frame:IsShown() then return end
  local m, lines = view.measure, view.mode == "lines"
  view.char = view.char or ns.charKey()
  if not has(m, view.by) then view.by = "zone" end
  local axis = lines and "level" or view.by
  if view.split and (view.split == axis or not has(m, view.split)) then view.split = nil end

  -- header + filter bar
  ui.char:Set(view.char, view.char, false)
  local c = char()
  local lo, hi = levelRange(c)
  ui.summary:SetText(("Level %d   ·   /played %s   ·   tracked levels %d-%d"):format(hi, c.played and fmtTime(c.played) or "?", lo, hi))
  local any = false
  local x = 0
  for _, d in ipairs(FILTER_DIMS) do
    local dd, v = ui.filters[d], view.filter[d]
    local show = has(m, d)
    dd:SetShown(show)
    if show then
      dd:Set(v, v == nil and "All" or keyLabel(d, v), v ~= nil)
      dd:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + x, -78)
      x = x + dd:GetWidth() + 8
      any = any or v ~= nil
    end
  end
  ui.clear:SetShown(any)
  local overview = not any and view.measure == "time" and view.mode == "bars" and view.by == "level"
  ui.overview:Set("Character overview", overview)
  ui.clear:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + x, -79)

  -- KPI tiles
  for i, k in ipairs(kpis()) do
    local t = ui.tiles[i]
    t.title:SetText(k[1])
    t.value:SetText(k[2])
    t.sub:SetText(k[3])
  end

  -- chart toolbar
  ui.time:Set("Time", m == "time")
  ui.xp:Set("XP", m == "xp")
  ui.deathsB:Set("Deaths", m == "deaths")
  local deaths = m == "deaths"
  for _, w in ipairs({ ui.bars, ui.linesB, ui.by, ui.split }) do w:SetShown(not deaths) end
  for _, row in ipairs(ui.drows) do row:Hide() end
  ui.recap:Hide()
  if deaths then
    for _, row in ipairs(rows) do row:SetShown(false) end
    ui.chart:Hide()
    showLegend({})
    if view.death then drawRecap(view.death) else drawDeathList() end
    return
  end
  frame.empty:SetText("No data for these filters.")
  ui.bars:Set("Bars", not lines)
  ui.linesB:Set("Lines", lines)
  ui.by:Set(view.by, lines and "Level (x axis)" or DIM_LABEL[view.by], false)
  ui.by:EnableMouse(not lines)
  ui.split:Set(view.split or false, view.split and DIM_LABEL[view.split] or "None", view.split ~= nil)

  for _, row in ipairs(rows) do row:SetShown(false) end
  ui.chart:SetShown(lines)
  if lines then drawLines() else drawBars() end
end

local function build()
  buildPopup()
  frame = CreateFrame("Frame", "LevelLedgerFrame", UIParent, "BackdropTemplate")
  frame:SetSize(W, -BODY_Y + BODY_H + 40)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  box(frame, { INK[1], INK[2], INK[3], 0.96 }, { 1, 1, 1, 0.08 })
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetScript("OnHide", closePopup)
  frame:SetClampedToScreen(true)
  tinsert(UISpecialFrames, "LevelLedgerFrame")

  local stripe = tex(frame, "ARTWORK", ACCENT)
  stripe:SetPoint("TOPLEFT", 1, -1)
  stripe:SetPoint("TOPRIGHT", -1, -1)
  stripe:SetHeight(2)

  local title = text(frame, 14, ACCENT)
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("L E V E L   L E D G E R")
  ui.summary = text(frame, 11, TEXT)
  ui.summary:SetPoint("TOPLEFT", 16, -40)

  local close = CreateFrame("Button", nil, frame)
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", -8, -10)
  close.t = text(close, 14, { 0.6, 0.6, 0.65 })
  close.t:SetPoint("CENTER")
  close.t:SetText("x")
  close:SetScript("OnClick", function() frame:Hide() end)

  ui.char = dropdown(frame, 200, "", function()
    local opts = {}
    for _, k in ipairs(ns.chars()) do
      local lv = 0
      for l in pairs(LevelLedgerDB[k].levels) do if l > lv then lv = l end end
      opts[#opts + 1] = { k, k, "level " .. lv }
    end
    return opts
  end, function(k)
    view.char, view.filter, view.offset = k, {}, 0
    ns.refresh()
  end)
  ui.char:SetPoint("RIGHT", close, "LEFT", -8, 0)

  -- filter bar
  ui.filters = {}
  local widths = { level = 100, zone = 150, activity = 130, source = 120, name = 160 }
  for _, d in ipairs(FILTER_DIMS) do
    ui.filters[d] = dropdown(frame, widths[d], DIM_LABEL[d]:upper(), function() return filterOptions(d) end, function(v)
      view.filter[d] = v
      view.offset = 0
      ns.refresh()
    end)
  end
  ui.clear = pill(frame, "Clear filters", function() view.filter, view.offset = {}, 0; ns.refresh() end)
  ui.clear:Set("Clear filters", false)
  -- one click back to the whole character: every level, time per level split by activity
  ui.overview = pill(frame, "Character overview", function()
    view.filter, view.offset = {}, 0
    view.measure, view.mode, view.by, view.split = "time", "bars", "level", "activity"
    ns.refresh()
  end)
  ui.overview:SetPoint("TOPRIGHT", -16, -36)

  -- KPI tiles
  ui.tiles = {}
  local tileW = (W - 32 - 5 * 8) / 6
  for i = 1, 6 do
    local t = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    t:SetSize(tileW, 50)
    t:SetPoint("TOPLEFT", 16 + (i - 1) * (tileW + 8), -112)
    box(t, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.06 })
    t.title = text(t, 9, MUTED)
    t.title:SetPoint("TOPLEFT", 8, -7)
    t.value = text(t, 15, { 1, 1, 1 })
    t.value:SetPoint("TOPLEFT", 8, -20)
    t.sub = text(t, 9, MUTED)
    t.sub:SetPoint("BOTTOMLEFT", 8, 5)
    ui.tiles[i] = t
  end

  -- chart toolbar: measure, group by, color by, chart type
  local function setMeasure(m)
    view.measure = m
    view.by, view.split = "zone", (m == "time" and "activity" or "source")
    view.offset = 0
    ns.refresh()
  end
  ui.time = pill(frame, "Time", function() setMeasure("time") end)
  ui.time:SetPoint("TOPLEFT", 16, -180)
  ui.xp = pill(frame, "XP", function() setMeasure("xp") end)
  ui.xp:SetPoint("LEFT", ui.time, "RIGHT", 4, 0)
  ui.deathsB = pill(frame, "Deaths", function()
    view.measure, view.death, view.offset = "deaths", nil, 0
    ns.refresh()
  end)
  ui.deathsB:SetPoint("LEFT", ui.xp, "RIGHT", 4, 0)

  ui.by = dropdown(frame, 130, "GROUP BY", function() return dimOptions(nil) end, function(d)
    view.by, view.offset = d, 0
    if view.split == d then view.split = nil end
    ns.refresh()
  end)
  ui.by:SetPoint("TOPLEFT", 190, -179)
  ui.split = dropdown(frame, 130, "COLOR BY", function()
    return dimOptions(view.mode == "lines" and "level" or view.by, true)
  end, function(d)
    view.split = d or nil
    ns.refresh()
  end)
  ui.split:SetPoint("LEFT", ui.by, "RIGHT", 10, 0)

  ui.linesB = pill(frame, "Lines", function() view.mode = "lines"; ns.refresh() end)
  ui.linesB:SetPoint("TOPRIGHT", -16, -180)
  ui.bars = pill(frame, "Bars", function() view.mode = "bars"; ns.refresh() end)
  ui.bars:SetPoint("RIGHT", ui.linesB, "LEFT", -4, 0)

  local sep = tex(frame, "ARTWORK", { 1, 1, 1 }, 0.06)
  sep:SetPoint("TOPLEFT", 16, -170)
  sep:SetPoint("TOPRIGHT", -16, -170)
  sep:SetHeight(1)

  -- bar rows
  for k = 1, ROWS do
    local row = CreateFrame("Button", nil, frame)
    local y = BODY_Y - (k - 1) * ROW_H
    row:SetHeight(ROW_H - 4)
    row:SetPoint("TOPLEFT", 16, y)
    row:SetPoint("TOPRIGHT", -16, y)
    row.name = text(row, 11)
    row.name:SetPoint("LEFT")
    row.name:SetWidth(LABEL_W - 8)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.track = tex(row, "BACKGROUND", { 1, 1, 1 }, 0.04)
    row.track:SetPoint("LEFT", LABEL_W, 0)
    row.track:SetSize(BAR_W, ROW_H - 4)
    row.segs = {}
    for s = 1, MAX_PARTS do
      local seg = tex(row, "ARTWORK", ACCENT)
      seg:SetHeight(ROW_H - 4)
      row.segs[s] = seg
    end
    row.value = text(row, 11, { 1, 1, 1 })
    row.value:SetPoint("RIGHT", -38, 0)
    row.rate = text(row, 10, ACCENT)
    row.rate:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
    row.pct = text(row, 10, MUTED)
    row.pct:SetPoint("RIGHT")
    local hl = tex(row, "HIGHLIGHT", { 1, 1, 1 }, 0.05)
    hl:SetAllPoints()
    row:SetScript("OnClick", function(self) drill(self.data.key) end)
    row:SetScript("OnEnter", function(self)
      local r = self.data
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddDoubleLine(keyLabel(view.by, r.key), fmtValue(r.v), ACCENT[1], ACCENT[2], ACCENT[3], 1, 1, 1)
      addHint(r.key)
      if r.rate then
        GameTooltip:AddDoubleLine(r.combatRate and "XP per hour in combat" or "XP per hour", fmtNum(r.rate), MUTED[1], MUTED[2], MUTED[3], ACCENT[1], ACCENT[2], ACCENT[3])
      end
      if view.by == "name" and r.n > 0 then
        GameTooltip:AddDoubleLine("Count", r.n .. "x", MUTED[1], MUTED[2], MUTED[3], 1, 1, 1)
      end
      if view.split then
        local parts = {}
        for k2, v in pairs(r.parts) do parts[#parts + 1] = { k = k2, v = v } end
        table.sort(parts, function(a, b) return a.v > b.v end)
        for i, p in ipairs(parts) do
          if i > 25 then GameTooltip:AddLine(("+ %d more"):format(#parts - 25), MUTED[1], MUTED[2], MUTED[3]) break end
          GameTooltip:AddDoubleLine(keyLabel(view.split, p.k), fmtValue(p.v) .. ("  %d%%"):format(math.floor(p.v / r.v * 100 + 0.5)), TEXT[1], TEXT[2], TEXT[3], 1, 1, 1)
        end
      end
      GameTooltip:AddLine("Click to filter by " .. keyLabel(view.by, r.key), MUTED[1], MUTED[2], MUTED[3])
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[k] = row
  end
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, d) view.offset = view.offset - d * 3; ns.refresh() end)

  -- line chart area with 4 grid lines
  ui.chart = CreateFrame("Frame", nil, frame)
  ui.chart:SetPoint("TOPLEFT", 16 + 70, BODY_Y)
  ui.chart:SetSize(W - 32 - 70, BODY_H - 20)
  ui.lines, ui.cols, ui.grid, ui.xlabels = {}, {}, {}, {}
  local base = tex(ui.chart, "BACKGROUND", { 1, 1, 1 }, 0.15)
  base:SetPoint("BOTTOMLEFT")
  base:SetPoint("BOTTOMRIGHT")
  base:SetHeight(1)
  for i = 1, 4 do
    local g = tex(ui.chart, "BACKGROUND", { 1, 1, 1 }, 0.05)
    g:SetPoint("BOTTOMLEFT", 0, (BODY_H - 20) * i / 4)
    g:SetPoint("BOTTOMRIGHT", 0, (BODY_H - 20) * i / 4)
    g:SetHeight(1)
    g.label = text(ui.chart, 9, MUTED)
    g.label:SetPoint("RIGHT", g, "LEFT", -6, 0)
    ui.grid[i] = g
  end
  for i = 1, 13 do
    ui.xlabels[i] = text(ui.chart, 9, MUTED)
  end
  ui.guide = tex(ui.chart, "OVERLAY", { 1, 1, 1 }, 0.35)
  ui.guide:SetSize(1, BODY_H - 20)
  ui.guide:Hide()
  ui.dots = {}
  for i = 1, MAX_PARTS + 1 do
    local dot = ui.chart:CreateTexture(nil, "OVERLAY", nil, 7)
    dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    dot:SetSize(8, 8)
    dot:Hide()
    ui.dots[i] = dot
  end

  ui.legend = {}
  for i = 1, MAX_PARTS + 1 do
    local item = CreateFrame("Frame", nil, frame)
    item:SetHeight(12)
    item.swatch = tex(item, "ARTWORK", ACCENT)
    item.swatch:SetSize(10, 10)
    item.swatch:SetPoint("LEFT")
    item.label = text(item, 10, { 0.8, 0.82, 0.86 })
    item.label:SetPoint("LEFT", 16, 0)
    ui.legend[i] = item
  end

  -- deaths list rows
  ui.drows = {}
  for k = 1, ROWS do
    local row = CreateFrame("Button", nil, frame)
    local y = BODY_Y - (k - 1) * ROW_H
    row:SetHeight(ROW_H - 2)
    row:SetPoint("TOPLEFT", 16, y)
    row:SetPoint("TOPRIGHT", -16, y)
    local hl = tex(row, "HIGHLIGHT", { 1, 1, 1 }, 0.05)
    hl:SetAllPoints()
    row.date = text(row, 10, MUTED)
    row.date:SetPoint("LEFT", 4, 0)
    row.level = text(row, 11, { 1, 1, 1 })
    row.level:SetPoint("LEFT", 90, 0)
    row.zone = text(row, 11)
    row.zone:SetPoint("LEFT", 160, 0)
    row.zone:SetWidth(150)
    row.zone:SetJustifyH("LEFT")
    row.zone:SetWordWrap(false)
    row.killer = text(row, 11, COLORS.Combat)
    row.killer:SetPoint("LEFT", 320, 0)
    row.killer:SetWidth(260)
    row.killer:SetJustifyH("LEFT")
    row.killer:SetWordWrap(false)
    row.hits = text(row, 10, MUTED)
    row.hits:SetPoint("RIGHT", -4, 0)
    row:SetScript("OnClick", function(self) view.death, view.offset = self.death, 0; ns.refresh() end)
    row:Hide()
    ui.drows[k] = row
  end

  -- recap panel: headline, health line over 15 s, event list
  local r = CreateFrame("Frame", nil, frame)
  r:SetPoint("TOPLEFT", 16, BODY_Y)
  r:SetSize(W - 32, BODY_H)
  r:Hide()
  ui.recap = r
  r.head = text(r, 12, COLORS.Combat)
  r.head:SetPoint("TOPLEFT", 0, 0)
  r.sub = text(r, 10, MUTED)
  r.sub:SetPoint("TOPLEFT", 0, -16)
  local back = pill(r, "Back to all deaths", function() view.death, view.offset = nil, 0; ns.refresh() end)
  back:Set("Back to all deaths", false)
  back:SetPoint("TOPRIGHT", 0, 0)
  r.hp = CreateFrame("Frame", nil, r)
  r.ready = text(r, 10, COLORS["On foot"])
  r.ready:SetPoint("TOPLEFT", 0, -32)
  r.ready:SetWidth(W - 32)
  r.ready:SetJustifyH("LEFT")
  r.ready:SetWordWrap(false)
  r.hp:SetPoint("TOPLEFT", 40, -52)
  r.hp:SetSize(W - 32 - 40, 80)
  local base = tex(r.hp, "BACKGROUND", { 1, 1, 1 }, 0.04)
  base:SetAllPoints()
  for _, lab in ipairs({ { "100%", "TOPLEFT" }, { "0%", "BOTTOMLEFT" } }) do
    local t = text(r.hp, 9, MUTED)
    t:SetPoint("RIGHT", r.hp, lab[2], -6, 0)
    t:SetText(lab[1])
  end
  for _, lab in ipairs({ { "-15s", 0 }, { "-10s", 1 / 3 }, { "-5s", 2 / 3 }, { "death", 1 } }) do
    local t = text(r.hp, 9, MUTED)
    t:SetPoint("TOP", r.hp, "BOTTOMLEFT", (W - 72) * lab[2], -3)
    t:SetText(lab[1])
  end
  r.lines, r.marks, r.rows = {}, {}, {}
  for k = 1, 6 do
    local row = CreateFrame("Frame", nil, r)
    row:SetHeight(17)
    row:SetPoint("TOPLEFT", 0, -150 - (k - 1) * 18)
    row:SetPoint("TOPRIGHT", 0, -150 - (k - 1) * 18)
    row.t = text(row, 10, MUTED)
    row.t:SetPoint("LEFT", 4, 0)
    row.src = text(row, 11)
    row.src:SetPoint("LEFT", 60, 0)
    row.src:SetWidth(170)
    row.src:SetJustifyH("LEFT")
    row.src:SetWordWrap(false)
    row.spell = text(row, 11, { 1, 1, 1 })
    row.spell:SetPoint("LEFT", 240, 0)
    row.spell:SetWidth(200)
    row.spell:SetJustifyH("LEFT")
    row.spell:SetWordWrap(false)
    row.amt = text(row, 11)
    row.amt:SetPoint("RIGHT", -60, 0)
    row.hp = text(row, 10, MUTED)
    row.hp:SetPoint("RIGHT", -4, 0)
    r.rows[k] = row
  end

  frame.empty = text(frame, 12, MUTED)
  frame.empty:SetPoint("TOP", 0, BODY_Y - 60)
  frame.empty:SetText("No data for these filters.")

  frame:SetScript("OnShow", ns.refresh)
  -- ponytail: full re-aggregation costs a few ms with a 1-60 history, so live updates run every 5 s
  C_Timer.NewTicker(5, function() if not popup:IsShown() then ns.refresh() end end)
end

function ns.toggle()
  if not frame then build() frame:Hide() end
  frame:SetShown(not frame:IsShown())
end

SLASH_LEVELLEDGER1, SLASH_LEVELLEDGER2, SLASH_LEVELLEDGER3 = "/ledger", "/levelledger", "/ll"
SlashCmdList.LEVELLEDGER = ns.toggle

-- Minimap button: click toggles the window, drag moves it around the minimap edge.
local function placeButton(b)
  local a = math.rad(LevelLedgerSettings.minimapAngle)
  local r = Minimap:GetWidth() / 2 + 5
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
  LevelLedgerSettings = LevelLedgerSettings or {}
  LevelLedgerSettings.minimapAngle = LevelLedgerSettings.minimapAngle or 200
  local b = CreateFrame("Button", "LevelLedgerMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  b:RegisterForClicks("AnyUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnClick", ns.toggle)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      LevelLedgerSettings.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
      self:ClearAllPoints()
      placeButton(self)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Level Ledger", ACCENT[1], ACCENT[2], ACCENT[3])
    GameTooltip:AddLine("Click to open, drag to move", 0.8, 0.82, 0.86)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  placeButton(b)
end)
