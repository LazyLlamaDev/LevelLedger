-- Level Ledger: tracking. Every datapoint is stored per level and per zone.
--   l.t[zone][activity] = seconds
--   l.x[zone][source][name] = { xp = n, n = count, sec = combat seconds (Mob only) }
--     source: Quest | Mob | Mob · rested | Mob · group | Exploration (Mob is the kill XP without bonuses)
--   l.deaths[zone] = count
--   l.deathLog[i] = { time, zone, target, max, ready = { "Shield Wall", "Healing Potion x2" }, events = { { dt, amt, heal, hp } } }
local _, ns = ...

local char, cur
local busy -- "Vendor", "Mailbox", ... while such a window is open
local playedBase, playedAt, silentUntil

local function zone()
  local z = GetRealZoneText()
  return (z and z ~= "") and z or "Unknown"
end

local function sub(t, k)
  local v = t[k]
  if not v then v = {} t[k] = v end
  return v
end

function ns.level(lvl)
  local l = char.levels[lvl]
  if not l then
    l = { started = time(), t = {}, x = {}, deaths = {} }
    char.levels[lvl] = l
  end
  return l
end

-- Played seconds on the current level (live), or the stored value for a finished level.
local function livePlayed()
  return playedBase and playedBase + (GetTime() - playedAt)
end

function ns.played(lvl, c)
  local l = (c or char).levels[lvl]
  if l == cur and playedBase then return livePlayed() end
  return l and l.played
end

function ns.char() return char end

-- Mob entries killed in the current fight; the fight's duration is shared among them at its end.
local fightStart, fightKills = nil, {}

local function addXP(source, name, xp)
  local e = sub(sub(sub(cur.x, zone()), source), name)
  e.xp = (e.xp or 0) + xp
  e.n = (e.n or 0) + 1
  if source == "Mob" and fightStart then fightKills[#fightKills + 1] = e end
end

-- Builds a Lua pattern from a localized format string like "%s dies, you gain %d experience."
local function pattern(fmt)
  if not fmt then return nil end
  fmt = fmt:gsub("%%%d%$", "%%") -- "%1$s" -> "%s" before "$" gets escaped (localized clients)
  fmt = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  fmt = fmt:gsub("%%%d%$s", "(.-)"):gsub("%%s", "(.-)")
  fmt = fmt:gsub("%%%d%$d", "(%%d+)"):gsub("%%d", "(%%d+)")
  return "^" .. fmt
end
ns.pattern = pattern

-- Most specific first; captures: mob, total, rested ("+60"), bonus type, group.
local KILL_PATTERNS = {
  { pattern(COMBATLOG_XPGAIN_EXHAUSTION1_GROUP), "rested", "type", "group" },
  { pattern(COMBATLOG_XPGAIN_EXHAUSTION1), "rested", "type" },
  { pattern(COMBATLOG_XPGAIN_FIRSTPERSON_GROUP), "group" },
  { pattern(COMBATLOG_XPGAIN_FIRSTPERSON) },
}
local PAT_EXPLORE = pattern(ERR_ZONE_EXPLORED_XP)

-- The total in the message includes the bonuses, so Mob gets the rest.
function ns.onKillMsg(msg)
  for _, p in ipairs(KILL_PATTERNS) do
    if p[1] then
      local caps = { msg:match(p[1]) }
      if caps[1] then
        local mob, total, got = caps[1], tonumber(caps[2]), {}
        for i = 2, #p do got[p[i]] = caps[i + 1] end
        local rested = got.rested and tonumber(got.rested:match("%d+")) or 0
        local group = got.group and tonumber(got.group) or 0
        addXP("Mob", mob, total - rested - group)
        if rested > 0 then addXP("Mob · rested", mob, rested) end
        if group > 0 then addXP("Mob · group", mob, group) end
        return
      end
    end
  end
end

function ns.onSystemMsg(msg)
  if not PAT_EXPLORE then return end
  local area, xp = msg:match(PAT_EXPLORE)
  if area then addXP("Exploration", area, tonumber(xp)) end
end

-- Main bucket by priority; the first match wins.
-- Localized spell names by spell ID, so this works on every client language.
local spellName = (C_Spell and C_Spell.GetSpellName) or GetSpellInfo
local function names(map)
  local out = {}
  if not spellName then return out end
  for id, label in pairs(map) do
    local n = spellName(id)
    if n then out[n] = label end
  end
  return out
end
local GATHER = names({ [2575] = "Mining", [2366] = "Herbalism", [8613] = "Skinning", [7620] = "Fishing", [7731] = "Fishing", [7732] = "Fishing", [18248] = "Fishing" })
local FOOD = names({ [433] = "Eating", [430] = "Drinking" })

local function gathering()
  local n = UnitCastingInfo and UnitCastingInfo("player")
  if not n and UnitChannelInfo then n = UnitChannelInfo("player") end
  return n and GATHER[n]
end

-- UnitBuff is gone on newer clients; C_UnitAuras returns a table instead.
local function buffName(i)
  if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
    local aura = C_UnitAuras.GetBuffDataByIndex("player", i)
    return aura and aura.name
  end
  return UnitBuff and UnitBuff("player", i)
end

local function eatingDrinking()
  local eat, drink
  for i = 1, 40 do
    local n = buffName(i)
    if not n then break end
    local what = FOOD[n]
    if what == "Eating" then eat = true elseif what == "Drinking" then drink = true end
  end
  if eat and drink then return "Eating & drinking" end
  return (eat and "Eating") or (drink and "Drinking") or nil
end

-- Main bucket by priority; the first match wins.
function ns.activity()
  if UnitIsGhost("player") then return "Ghost" end
  if UnitIsDead("player") then return "Dead" end
  if UnitOnTaxi("player") then return "Flight path" end
  local ok, g = pcall(gathering) -- spell and aura names can be hidden in combat on newer clients
  g = ok and g
  if g then return g end
  if UnitAffectingCombat("player") then return "Combat" end
  -- crafting queues keep counting as crafting even when the game flags you AFK
  if busy == "Crafting" then return busy end
  if UnitIsAFK("player") then return "AFK" end
  if busy then return busy end
  if IsFlying and IsFlying() then return "Flying" end
  if IsMounted() then return "Mounted" end
  if IsSwimming() then return "Swimming" end
  if GetUnitSpeed("player") > 0 then return "On foot" end
  local ok2, food = pcall(eatingDrinking)
  return (ok2 and food) or "Standing"
end

local lastTick
local function tick()
  local now = GetTime()
  -- ponytail: gaps over 3 s (loading screens, freezes) are dropped; /played stays the exact total
  local dt = math.min(now - (lastTick or now), 3)
  lastTick = now
  if not cur or dt <= 0 then return end
  local acts = sub(cur.t, zone())
  local a = ns.activity()
  acts[a] = (acts[a] or 0) + dt
end

-- Every chat window that shows system messages prints /played, so the reply is muted for a short
-- window instead of a one-shot flag (which let the second window print it, or swallowed a later manual /played).
local function requestPlayed()
  silentUntil = GetTime() + 5
  RequestTimePlayed()
end

local BUSY = {
  MERCHANT_SHOW = "Vendor", MAIL_SHOW = "Mailbox", AUCTION_HOUSE_SHOW = "Auction house",
  BANKFRAME_OPENED = "Bank", TRAINER_SHOW = "Trainer", TAXIMAP_OPENED = "Flight master",
  TRADE_SKILL_SHOW = "Crafting", CRAFT_SHOW = "Crafting",
}
local IDLE = {
  MERCHANT_CLOSED = true, MAIL_CLOSED = true, AUCTION_HOUSE_CLOSED = true,
  BANKFRAME_CLOSED = true, TRAINER_CLOSED = true, TAXIMAP_CLOSED = true,
  TRADE_SKILL_CLOSE = true, CRAFT_CLOSE = true,
}

local questTitle
local handlers = {}

function handlers.ADDON_LOADED(name)
  if name ~= "LevelLedger" then return end
  LevelLedgerDB = LevelLedgerDB or {}
  local key = ns.charKey()
  char = LevelLedgerDB[key] or { levels = {} }
  LevelLedgerDB[key] = char
  char.class = select(2, UnitClass("player"))
  cur = ns.level(UnitLevel("player"))
  -- Hide the /played chat lines only when this addon asked for them.
  local display = ChatFrame_DisplayTimePlayed
  ChatFrame_DisplayTimePlayed = function(...)
    if silentUntil and GetTime() < silentUntil then return end
    if display then return display(...) end
  end
  C_Timer.NewTicker(1, tick)
end

function handlers.PLAYER_ENTERING_WORLD(login, reload)
  if login or reload then C_Timer.After(2, requestPlayed) end
end

function handlers.TIME_PLAYED_MSG(total, thisLevel)
  C_Timer.After(0.5, function() silentUntil = nil end) -- after every chat window had its turn
  char.played = total
  playedBase, playedAt = thisLevel, GetTime()
end

function handlers.PLAYER_LEVEL_UP(newLevel)
  cur.played = livePlayed()
  cur.reached = time()
  cur = ns.level(newLevel)
  playedBase, playedAt = 0, GetTime()
  C_Timer.After(1, requestPlayed)
end

function handlers.CHAT_MSG_COMBAT_XP_GAIN(msg) ns.onKillMsg(msg) end
function handlers.CHAT_MSG_SYSTEM(msg) ns.onSystemMsg(msg) end

function handlers.QUEST_COMPLETE() questTitle = GetTitleText() end

function handlers.QUEST_TURNED_IN(questID, xp)
  if xp and xp > 0 then
    local title = questTitle
    if not title and C_QuestLog and C_QuestLog.GetQuestInfo then title = C_QuestLog.GetQuestInfo(questID) end
    addXP("Quest", title or ("Quest " .. questID), xp)
  end
  questTitle = nil
end

function handlers.PLAYER_REGEN_DISABLED()
  fightStart, fightKills = GetTime(), {}
end

-- ponytail: a fight's time is split evenly per kill; per-mob damage timing would need the combat log
function handlers.PLAYER_REGEN_ENABLED()
  if fightStart and #fightKills > 0 then
    local share = (GetTime() - fightStart) / #fightKills
    for _, e in ipairs(fightKills) do e.sec = (e.sec or 0) + share end
  end
  fightStart, fightKills = nil, {}
end

-- Death recap. The combat log is blocked for addons on this client, so the recap is built from
-- the player's own health changes: every drop is a hit, every rise a heal, kept for 15 seconds.
local RECAP_SECONDS, RECAP_MAX = 15, 40
local recent, lastHP = {}, nil

local function readHealth()
  local ok, hp, max = pcall(function()
    local h, m = UnitHealth("player"), UnitHealthMax("player")
    return h + 0, m + 0 -- fails if the client hides the values
  end)
  if ok then return hp, max end
end

function ns.onHealth()
  local hp, max = readHealth()
  if not hp then return end
  if lastHP and hp ~= lastHP then
    local now = GetTime()
    recent[#recent + 1] = { t = now, amt = math.abs(hp - lastHP), heal = hp > lastHP or nil, hp = hp, max = max }
    while #recent > RECAP_MAX or (recent[1] and now - recent[1].t > RECAP_SECONDS) do
      table.remove(recent, 1)
    end
  end
  lastHP = hp
end

function handlers.UNIT_HEALTH(unit)
  if unit == "player" then ns.onHealth() end
end

-- Healing potions and healthstones (all ranks) worth listing as "still had".
local POTIONS = { 118, 858, 929, 1710, 3928, 13446, 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009,
  5510, 19010, 19011, 9421, 19012, 19013, 11951, 11952 }

-- Spells with a base cooldown of 1 minute or more that were off cooldown, plus usable potions.
local function spellReady(id)
  if C_Spell and C_Spell.GetSpellCooldown then
    local cd = C_Spell.GetSpellCooldown(id)
    return cd and cd.startTime == 0
  end
  return GetSpellCooldown(id) == 0
end

local function readyAtDeath()
  local out, seen = {}, {}
  local book = C_SpellBook
  if GetSpellBaseCooldown and book and book.GetNumSpellBookSkillLines then
    for line = 1, book.GetNumSpellBookSkillLines() do
      local info = book.GetSpellBookSkillLineInfo(line)
      for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
        local item = book.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
        local id, name = item and item.spellID, item and item.name
        if name and id and not seen[name] and (GetSpellBaseCooldown(id) or 0) >= 60000 then
          seen[name] = true
          if spellReady(id) then out[#out + 1] = name end
        end
      end
    end
  elseif GetSpellBaseCooldown and GetNumSpellTabs then
    for tab = 1, GetNumSpellTabs() do
      local _, _, offset, n = GetSpellTabInfo(tab)
      for i = offset + 1, offset + n do
        local name = GetSpellBookItemName(i, "spell")
        local _, id = GetSpellBookItemInfo(i, "spell")
        if name and id and not seen[name] and (GetSpellBaseCooldown(id) or 0) >= 60000 then
          seen[name] = true
          if spellReady(id) then out[#out + 1] = name end
        end
      end
    end
  end
  local itemCooldown = GetItemCooldown or (C_Container and C_Container.GetItemCooldown)
  local itemCount = GetItemCount or C_Item.GetItemCount
  local itemName = GetItemInfo or C_Item.GetItemNameByID
  for _, id in ipairs(POTIONS) do
    local count = itemCount(id)
    if count and count > 0 and (not itemCooldown or itemCooldown(id) == 0) then
      out[#out + 1] = (itemName(id) or ("Item " .. id)) .. " x" .. count
    end
  end
  return out
end

function handlers.PLAYER_DEAD()
  local z = zone()
  cur.deaths[z] = (cur.deaths[z] or 0) + 1
  local now = GetTime()
  local events = {}
  for _, e in ipairs(recent) do
    if now - e.t <= RECAP_SECONDS then
      events[#events + 1] = { dt = math.floor((e.t - now) * 10 + 0.5) / 10, amt = e.amt, heal = e.heal, hp = e.hp }
    end
  end
  -- best guess at the killer: the hostile unit you had targeted
  local target = UnitExists("target") and UnitCanAttack("player", "target") and UnitName("target") or nil
  local _, max = readHealth()
  local log = sub(cur, "deathLog")
  log[#log + 1] = { time = time(), zone = z, max = max, events = events, target = target }
  local ok, ready = pcall(readyAtDeath)
  log[#log].ready = ok and ready or nil
  recent, lastHP = {}, nil
end

-- Recorded deaths matching a level/zone filter, newest first.
function ns.deaths(filter, c)
  local list = {}
  for lvl, l in pairs((c or char).levels) do
    if l.deathLog and (filter.level == nil or filter.level == lvl) then
      for _, d in ipairs(l.deathLog) do
        if filter.zone == nil or filter.zone == d.zone then
          d.level = lvl
          list[#list + 1] = d
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.time > b.time end)
  return list
end

function handlers.PLAYER_LOGOUT()
  cur.played = livePlayed() or cur.played
end

local f = CreateFrame("Frame")
for e in pairs(handlers) do f:RegisterEvent(e) end
for e in pairs(BUSY) do pcall(f.RegisterEvent, f, e) end
for e in pairs(IDLE) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, e, ...)
  if BUSY[e] then busy = BUSY[e]
  elseif IDLE[e] then busy = nil
  else handlers[e](...) end
end)

-- All tracked characters, "Name-Realm" sorted.
function ns.chars()
  local list = {}
  for k in pairs(LevelLedgerDB) do list[#list + 1] = k end
  table.sort(list)
  return list
end

function ns.charKey() return UnitName("player") .. "-" .. GetRealmName() end

-- Sums values matching every filter, grouped by one dimension, biggest first.
-- measure: "time" or "xp". split: optional second dimension, summed into row.parts.
-- c: character table (default: the logged-in one). Walks saved tables, no temporary records.
function ns.group(measure, by, filter, split, c)
  local rows = {}
  local r = {}
  local function add(v, n, sec)
    for k, want in pairs(filter) do
      if r[k] ~= want then return end
    end
    local k = r[by]
    local row = rows[k]
    if not row then row = { key = k, v = 0, n = 0, sec = 0, parts = {} } rows[k] = row end
    row.sec = row.sec + (sec or 0)
    row.v = row.v + v
    row.n = row.n + (n or 0)
    if split then
      local sk = r[split]
      row.parts[sk] = (row.parts[sk] or 0) + v
    end
  end
  for lvl, l in pairs((c or char).levels) do
    r.level = lvl
    if filter.level == nil or filter.level == lvl then
      if measure == "time" then
        for z, acts in pairs(l.t) do
          r.zone = z
          for a, s in pairs(acts) do r.activity = a; add(s) end
        end
      else
        for z, srcs in pairs(l.x) do
          r.zone = z
          for src, names in pairs(srcs) do
            r.source = src
            for n, e in pairs(names) do r.name = n; add(e.xp, e.n, e.sec) end
          end
        end
      end
    end
  end
  local list = {}
  for _, row in pairs(rows) do list[#list + 1] = row end
  table.sort(list, function(a, b)
    if by == "level" then return a.key < b.key end
    return a.v > b.v
  end)
  return list
end
