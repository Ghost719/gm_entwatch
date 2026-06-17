--- Boss HP HUD: server side.
-- Reference: sm-plugin-BossHP and the NiDE-gg/ZE-Configs config repositories.
-- Per-map configs live in entwatch/bosses/<map>.lua and are loaded into
-- EntWatch.Bosses. The client (cl_boss.lua) is method-agnostic: it only ever
-- receives name/hp/maxhp/miniboss tuples.
--
-- Damage tracking methods:
--   "breakable" - func_breakable/func_physbox etc., uses the entity's own HP
--   "counter"   - hit-based, a single math_counter holds the HP value
--   "hpbar"     - hit-based, three math_counters:
--                 counter  - current HP of the active segment (signals backup on 0)
--                 backup   - constant segment HP (refills counter, decrements iterator)
--                 iterator - segments remaining (boss dies when it reaches 0)
--                 hp = (iterator - 1) * backup + counter
--
-- Trigger ("trigger" = "EntityName:Output"):
--   The bar only appears after the trigger fires. This also lets several
--   bosses share the same counter names (Scorpion/Bahamut on mako v6):
--   whichever boss triggered last is the active one.
--   Outputs are hooked directly via a named lua_run entity: AddOutput is
--   installed on the trigger entity so that the chosen output runs
--   EntWatch.TrackOutput through lua_run's RunPassedCode input.
-- "timeout" (seconds): the bar hides if there was no activity (trigger fire
--   or damage) within this window. Used for phase-based fights.
--
-- @module entwatch.sv_boss

util.AddNetworkString("entwatch_boss")

local bossdebug = false
local SEND_INTERVAL = 0.15
local LUA_RUN_NAME = "entwatch_trigger_output"

EntWatch.BossStates = EntWatch.BossStates or {} -- [uid] = runtime state

local mapluahook = nil
local next_boss_uid = 0
local bind_breakable = {}  -- [id|name] = { cfg, ... }
local bind_counter   = {}  -- [id|name] = { cfg, ... }
local trigger_output = {}  -- [entname] = { { cfg, output = "onuser1" }, ... }

--- Append a value to a list stored under tbl[key], creating the list on demand.
-- Used to build the bind/trigger lookup tables, where one key (a hammerid or
-- a targetname) may belong to several boss configs at once.
-- @param tbl table Lookup table of lists.
-- @param key any Key to file the value under; nil keys are silently skipped.
-- @param value any Value to append.
local function MultiAdd(tbl, key, value)
    if key == nil then return end
    local list = tbl[key]
    if not list then list = {}; tbl[key] = list end
    list[#list + 1] = value
end

--- (Re)load the boss config for the current map and rebuild all lookup tables.
-- Wipes every runtime state, re-includes the config file (via
-- EntWatch.LoadRawBossConfig from autorun), then indexes each config entry by
-- every identifier it can be bound through: hammerid and targetname of the
-- breakable or of the counter trio, plus the parsed trigger source.
-- States and lookup tables are rebuilt together so that config tables are
-- always compared by the same reference in GetState.
function EntWatch.LoadBossConfig()
    EntWatch.BossStates = {}
    EntWatch.LoadRawBossConfig()

    next_boss_uid = 0
    bind_breakable = {}
    bind_counter   = {}
    trigger_output = {}

    for _, cfg in ipairs(EntWatch.Bosses) do
        if cfg.method == "breakable" then
            MultiAdd(bind_breakable, cfg.breakableid,   cfg)
            MultiAdd(bind_breakable, cfg.breakablename, cfg)
        else -- counter / hpbar
            cfg.mode = cfg.mode or ENTWATCH_MODE_COUNTER_FMIN_REACHED
            MultiAdd(bind_counter, cfg.counterid,   cfg)
            MultiAdd(bind_counter, cfg.countername, cfg)
            if cfg.method == "hpbar" then
                MultiAdd(bind_counter, cfg.backupid,     cfg)
                MultiAdd(bind_counter, cfg.backupname,   cfg)
                MultiAdd(bind_counter, cfg.iteratorid,   cfg)
                MultiAdd(bind_counter, cfg.iteratorname, cfg)
            end
        end

        -- Parse "EntityName:Output" into an activation trigger record.
        if isstring(cfg.trigger) and #cfg.trigger > 0 then
            local entname, output = cfg.trigger:match("^([^:]+):?(.*)$")
            if entname and output and output ~= "" then
                MultiAdd(trigger_output, entname, {
                    cfg = cfg, output = output:lower(), kind = "activate",
                })
            end
        end

        -- Death-output: hooks the boss's own counter/iterator/breakable so
        -- that depletion or break fires KillBoss directly, without waiting
        -- for periodic counter reads to drift down to hp=0.
        --
        -- breakable -> OnBreak from the breakable itself
        -- counter   -> OnHitMin / OnHitMax on the counter, depending on mode
        -- hpbar     -> OnHitMin on the iterator (segment count down to 0)
        local death_ent, death_out
        if cfg.method == "breakable" then
            death_ent = cfg.breakablename
            death_out = "onbreak"
        elseif cfg.method == "counter" then
            death_ent = cfg.countername
            death_out = (cfg.mode == ENTWATCH_MODE_COUNTER_FMAX_REACHED)
                and "onhitmax" or "onhitmin"
        elseif cfg.method == "hpbar" then
            death_ent = cfg.iteratorname
            death_out = (cfg.mode == ENTWATCH_MODE_COUNTER_FMAX_REACHED)
                and "onhitmax" or "onhitmin"
        end

        if death_ent and death_out then
            MultiAdd(trigger_output, death_ent, {
                cfg = cfg, output = death_out, kind = "death",
            })
        end
    end
end
EntWatch.LoadBossConfig()

--- Find or create the runtime state for a config entry.
-- States are matched by config table reference, which is why the config must
-- not be re-included without also wiping the states (see LoadBossConfig).
-- A boss with no trigger starts active: its bar appears on first damage.
-- @param cfg table Config entry from EntWatch.Bosses.
-- @return table Runtime state ({ config, uid, active, triggered, dirty, ... }).
function EntWatch.GetState(cfg)
    for _, state in pairs(EntWatch.BossStates) do
        if state.config == cfg then return state end
    end

    next_boss_uid = next_boss_uid + 1
    local state = {
        config    = cfg,
        uid       = next_boss_uid,
        active    = cfg.trigger == nil or cfg.trigger == "", -- no trigger: activate on first damage
        triggered = false,
        dirty     = false,
        next_send = 0,
    }

    EntWatch.BossStates[state.uid] = state
    return state
end

--- Compute the current and maximum HP for a boss state.
-- Dispatches on the config method; every branch falls back to (0, maxhp or 1)
-- when its required entities are not (yet) valid.
-- @param state table Runtime state from GetState.
-- @return number Current HP (>= 0).
-- @return number Maximum HP (>= 1).
function EntWatch.CalcBossHP(state)
    local cfg = state.config

    if cfg.method == "breakable" then
        local ent = state.breakable
        if not IsValid(ent) then return 0, state.maxhp or 1 end

        local hp = math.max(ent:Health(), 0)
        -- Capture/raise the maximum from observed health; an explicit
        -- cfg.maxhp pins it instead.
        if not state.maxhp or hp > state.maxhp then
            state.maxhp = (cfg.maxhp and cfg.maxhp > 0) and cfg.maxhp or math.max(hp, 1)
        end

        return hp, state.maxhp
    elseif cfg.method == "hpbar" then
        local hpcounter = state.counter
        local hpbackup = state.backup
        local hpiterator = state.iterator
        if not IsValid(hpcounter) or not IsValid(hpbackup) or not IsValid(hpiterator) then return 0, state.maxhp or 1 end

        -- Segment size: explicit cfg.basehp, else the backup counter's
        -- mirrored value, else the main counter's engine max.
        local basehp = cfg.basehp or hpbackup.m_OutValue or 0
        local backupmin = hpbackup.m_flMin or 0
        local backupmax = hpbackup.m_flMax or 0

        if (backupmin != 0 or backupmax != 0) and basehp <= 0 then basehp = hpcounter.m_flMax or 1 end

        local current_hp = hpcounter.m_OutValue or 0
        local segment_num = hpiterator.m_OutValue or 0
        local segment_max = hpiterator.m_flMax or 40

        if cfg.mode == ENTWATCH_MODE_COUNTER_FMAX_REACHED then
            -- FMAX mode: counter has already reached its max, so report 0
            if segment_max <= segment_num then return 0, state.maxhp or 1 end
        elseif segment_num <= 0 then
            -- FMIN mode (default): counter has reached its min
            return 0, state.maxhp or 1
        end

        local segments_left
        if cfg.mode == ENTWATCH_MODE_COUNTER_FMAX_REACHED then
            -- FMAX mode: the counter counts damage up towards its max, so the
            -- remaining HP is the distance to the max.
            segments_left = math.max(1, segment_max - segment_num) - 1
        else
            -- FMIN mode (default): the counter value is the HP itself.
            segments_left = math.max(0, segment_num - 1)
        end

        -- Continuous across a segment break: (N-1)*B + 0 == (N-2)*B + B.
        local hp = segments_left * basehp + current_hp
        if not state.maxhp then
            state.maxhp = math.max(segments_left * basehp, basehp, 1)
        end

        return hp, math.max(state.maxhp, hp)
    elseif cfg.method == "counter" then
        local counter = state.counter
        if not IsValid(counter) then return 0, state.maxhp or 1 end

        local outv = counter.m_OutValue or 0
        -- FMAX mode: the counter counts damage up towards its max, so the
        -- remaining HP is the distance to the max.
        if cfg.mode == ENTWATCH_MODE_COUNTER_FMAX_REACHED then
            local maxv = counter.m_flMax or 1
            return maxv - outv, maxv
        end

        -- FMIN mode (default): the counter value is the HP itself.
        local initial = counter.m_InitialValue or 0
        local maxhp = initial > 0 and initial or counter.m_flMax or 1

        return outv, maxhp
    end

    return 0, state.maxhp or 1
end

-- ===================== NETWORKING =====================

--- Send a boss state update to one player or to everybody.
-- Applies send throttling (SEND_INTERVAL) and the peak ratchet: maps often
-- adjust boss HP after spawn (scaling by player count), so the initial
-- counter value is not the real maximum. The maximum therefore grows to
-- follow the highest HP ever observed; an explicit cfg.maxhp disables the
-- ratchet and pins the maximum instead.
-- @param state table Runtime state to send.
-- @param target Player|nil Single recipient, or nil to broadcast.
function EntWatch.SendBossState(state, target)
    if not state then return end

    state.next_send = CurTime() + SEND_INTERVAL
    state.dirty = false

    local hp, maxhp = EntWatch.CalcBossHP(state)

    -- Maps top up the boss's HP after spawn (scales with player count),
    -- so the initial counter value isn't the cap. Ratchet behavior:
    -- the cap rises to match the highest HP we've observed. Setting
    -- cfg.maxhp explicitly disables the ratchet and locks the cap.
    local cfg = state.config
    if cfg.maxhp and cfg.maxhp > 0 then
        maxhp = cfg.maxhp
    else
        if hp > (state.peak_hp or 0) then state.peak_hp = hp end
        if state.peak_hp and state.peak_hp > maxhp then maxhp = state.peak_hp end
    end

    -- Kill timer absolute end time (CurTime-based). 0 = no timer configured
    local killtimer_end = 0
    if state.killtimer_started and isnumber(cfg.killtimer) and cfg.killtimer > 0 then
        killtimer_end = state.killtimer_started + cfg.killtimer
    end

    EntWatch.BossLog("send: uid=%d '%s' hp=%.0f/%.0f", state.uid, state.config.name or "?", hp, maxhp)
    net.Start("entwatch_boss")
    net.WriteUInt(1, 4) -- update
    net.WriteUInt(state.uid, 8)
    net.WriteString(state.config.name or "Boss")
    net.WriteFloat(math.max(hp, 0))
    net.WriteFloat(math.max(maxhp, 1))
    net.WriteBool(state.config.miniboss == true)
    net.WriteFloat(killtimer_end)
    if target then net.Send(target) else net.Broadcast() end
end

--- Deactivate a boss and tell every client to remove its bar.
-- Used by the timeout logic and when the tracked counter is killed.
-- @param state table Runtime state to hide.
function EntWatch.HideBoss(state)
    if not state then return end
    state.active = false
    net.Start("entwatch_boss")
    net.WriteUInt(2, 4) -- remove
    net.WriteUInt(state.uid, 8)
    net.Broadcast()
end

-- ===================== BINDING =====================

--- Check whether the entities required by the state's method are bound.
-- Nothing is sent for unbound states; otherwise the client would briefly
-- display a meaningless "0/1" bar.
-- @param state table Runtime state.
-- @return boolean True when the state can produce meaningful HP values.
function EntWatch.IsBound(state)
    if state.config.method == "breakable" then
        return IsValid(state.breakable)
    end
    return IsValid(state.counter) -- hpbar: backup/iterator are optional (fallbacks exist)
end

--- Attach a runtime state to an entity's m_BossStates list.
-- One entity may carry several states at once: stage bosses commonly share
-- counters, and each sharing config gets its own state. The list is what the
-- AcceptInput/PostEntityTakeDamage hooks walk to find affected bosses.
-- @param ent Entity Entity the state tracks (counter or breakable).
-- @param state table Runtime state to attach.
function EntWatch.AttachState(ent, state)
    local list = ent.m_BossStates
    if not list then list = {}; ent.m_BossStates = list end
    for _, s in ipairs(list) do
        if s == state then return end
    end
    list[#list + 1] = state
    EntWatch.BossLog("bind: %s -> uid=%d '%s' (bound=%s)",
                    tostring(ent), state.uid, state.config.name or "?", tostring(EntWatch.IsBound(state)))
    if state.active and EntWatch.IsBound(state) then
        state.dirty = true
    end
end

--- Try to bind an entity into every boss config that references the given key.
-- math_counter entities are matched against the counter/backup/iterator slots
-- of counter/hpbar configs; any other class is matched against breakable
-- configs. Re-binding the same entity is idempotent.
-- @param ent Entity Candidate entity.
-- @param id_or_name number|string HammerID or targetname to look up.
function EntWatch.TryBind(ent, id_or_name)
    if ent:GetClass() == "math_counter" then
        local cfgs = bind_counter[id_or_name]
        if not cfgs then return end
        for _, cfg in ipairs(cfgs) do
            local state = EntWatch.GetState(cfg)
            if id_or_name == cfg.counterid or id_or_name == cfg.countername then
                state.counter = ent
            elseif id_or_name == cfg.backupid or id_or_name == cfg.backupname then
                state.backup = ent
            elseif id_or_name == cfg.iteratorid or id_or_name == cfg.iteratorname then
                state.iterator = ent
            end
            EntWatch.AttachState(ent, state)
        end
    else
        local cfgs = bind_breakable[id_or_name]
        if not cfgs then return end
        for _, cfg in ipairs(cfgs) do
            local state = EntWatch.GetState(cfg)
            state.breakable = ent
            if cfg.maxhp and cfg.maxhp > 0 then state.maxhp = cfg.maxhp end
            EntWatch.AttachState(ent, state)
        end
    end
end

-- Passive binding: every map entity announces its hammerid/targetname through
-- EntityKeyValue while it is being constructed, both at map load and when
-- game.CleanUpMap recreates entities on round restart.
hook.Add("EntityKeyValue", "EntWatch.BossKeyValue", function(ent, key, value)
    if #EntWatch.Bosses == 0 then return end

    local keylow = key:lower()
    if keylow == "hammerid" then
        local id = tonumber(value) or 0
        ent:SetHammerID(id) -- ordering with the core hook is not guaranteed, so duplicate it
        EntWatch.TryBind(ent, id)

        -- A trigger entity (relay/trigger brush) just spawned: install the
        -- output hook. timer.Simple(0) because AddOutput on an entity that is
        -- still being constructed is unreliable.
        local shammerid = "#" .. value
        if trigger_output[shammerid] then
            timer.Simple(0, function()
                if IsValid(ent) then EntWatch.HookEntityOutputs(ent, value) end
            end)
        end
    elseif keylow == "targetname" then
        EntWatch.TryBind(ent, value)

        -- A trigger entity (relay/trigger brush) just spawned: install the
        -- output hook. timer.Simple(0) because AddOutput on an entity that is
        -- still being constructed is unreliable.
        if trigger_output[value] then
            timer.Simple(0, function()
                if IsValid(ent) then EntWatch.HookEntityOutputs(ent, value) end
            end)
        end
    end
end)

-- ===================== ACTIVATION / TRACKING =====================

--- Activate a boss: mark it triggered, refresh its activity timestamp and
-- queue a network update. Idempotent; repeated calls keep extending the
-- timeout window, which is exactly what periodic trigger outputs rely on.
-- @param cfg table Config entry whose boss should activate.
function EntWatch.ActivateBoss(cfg)
    local state = EntWatch.GetState(cfg)
    if state.dead then return end -- do not revive a boss that already died
    EntWatch.BossLog("activate: uid=%d '%s' (bound=%s)",
        state.uid, cfg.name or "?", tostring(EntWatch.IsBound(state)))
    state.active = true
    state.triggered = true
    state.last_trigger = CurTime()
    state.dirty = true
    if not state.killtimer_started and isnumber(cfg.killtimer) and cfg.killtimer > 0 then
        state.killtimer_started = CurTime()
    end
end

--- Mark a boss as dead and push a final hp=0 update.
-- Triggered by an OnBreak/OnHitMin/OnHitMax output hooked at config-load time.
-- Idempotent (repeated fires after death are ignored). Also guards against
-- shared counters: a shared HPCounter would fire its death output for every
-- bound config, but only the currently active one should die from it.
-- @param cfg table Config entry whose boss should die.
function EntWatch.KillBoss(cfg)
    local state = EntWatch.GetState(cfg)
    if state.dead then return end
    if not state.active then return end -- shared counter or pre-trigger fire

    EntWatch.BossLog("death: uid=%d '%s'", state.uid, cfg.name or "?")
    state.dead   = true
    state.active = false
    state.dirty  = false

    -- Final hp=0 update; client marks dead_at and hides the bar after
    -- HIDE_AFTER_DEATH. Using update (cmd=1) instead of remove (cmd=2) so
    -- players briefly see "0 / max" as a kill confirmation.
    local maxhp = math.max(state.peak_hp or state.maxhp or 1, 1)
    net.Start("entwatch_boss")
    net.WriteUInt(1, 4) -- update
    net.WriteUInt(state.uid, 8)
    net.WriteString(cfg.name or "")
    net.WriteFloat(0)
    net.WriteFloat(maxhp)
    net.WriteBool(cfg.miniboss == true)
    net.WriteFloat(0)
    net.Broadcast()
end

--- Entry point invoked from the map I/O system.
-- The lua_run entity created by EnsureLuaRun executes this through its
-- RunPassedCode input whenever a hooked output fires (ACTIVATOR/CALLER/
-- TRIGGER_PLAYER globals are available here if ever needed).
-- @param entname string Targetname of the entity whose output fired.
-- @param outputname string Lower-case output name, e.g. "onuser1".
function EntWatch.TrackOutput(entname, outputname)
    local list = trigger_output[entname]
    if not list then return end

    for _, rec in ipairs(list) do
        if rec.output == outputname then
            if rec.kind == "death" then
                EntWatch.KillBoss(rec.cfg)
            else
                -- Activation: deliberately not latched. Repeated fires refresh
                -- last_trigger, which the timeout feature relies on (e.g. a
                -- periodic OnTrigger output during a phased boss).
                EntWatch.ActivateBoss(rec.cfg)
            end
        end
    end
end

-- ===================== OUTPUT HOOKING =====================

--- Make sure the named lua_run entity exists, creating it on demand.
-- game.CleanUpMap removes it every round; recreating lazily keeps the
-- reference valid no matter the round-restart flow.
local function EnsureLuaRun()
    if IsValid(mapluahook) then return end
    mapluahook = ents.Create("lua_run")
    mapluahook:SetName(LUA_RUN_NAME)
    mapluahook:Spawn()
end

--- Install AddOutput hooks for every trigger record matching this entity.
-- The "already hooked" flag lives on the entity itself rather than on the
-- config: boss relays are commonly spawned by point_template in the middle
-- of a round, and every fresh instance must be hooked again.
-- The generated output runs EntWatch.TrackOutput through the lua_run entity.
-- Note: the AddOutput parameter string is split on ':' by the engine, so the
-- generated Lua snippet must never contain a colon.
-- @param ent Entity Entity to install outputs on.
-- @param entname string Its targetname (the trigger_output key).
function EntWatch.HookEntityOutputs(ent, entname)
    if ent.m_EWOutputHooked then return end
    local list = trigger_output[entname]
    if not list then return end

    ent.m_EWOutputHooked = true
    EntWatch.BossLog("hook outputs: %s '%s'", tostring(ent), entname)
    EnsureLuaRun()

    local seen = {}
    for _, rec in ipairs(list) do
        if not seen[rec.output] then
            seen[rec.output] = true
            ent:Fire("AddOutput", string.format(
                "%s %s:RunPassedCode:EntWatch.TrackOutput(\"%s\", \"%s\"):0:-1",
                rec.output, LUA_RUN_NAME, entname, rec.output
            ))
        end
    end
end

-- Inputs that change a math_counter's value and therefore count as activity.
local counter_inputs = {
    add = true, subtract = true, setvalue = true, setvaluenofire = true,
    multiply = true, divide = true,
}

-- Counter activity tracking. The engine does not expose math_counter values
-- to Lua, so sv_init.lua shadow-mirrors them into m_OutValue/m_flMin/m_flMax;
-- this hook only decides whether the activity should (re)activate a boss and
-- queue a network update.
hook.Add("AcceptInput", "EntWatch.BossAcceptInput", function(ent, input, activator, caller)
    local states = ent.m_BossStates
    if not states then return end
    if ent:GetClass() ~= "math_counter" then return end

    local inputlow = input:lower()
    if counter_inputs[inputlow] then
        -- A counter owned by exactly one boss is unambiguous: its activity
        -- belongs to that boss. Shared counters (Scorpion/Bahamut sharing
        -- HPCounter on mako) can only be activated by their triggers.
        local exclusive = #states == 1
        for _, state in ipairs(states) do
            if not state.dead then -- dead bosses never reactivate
                local cfg = state.config
                local no_trigger = cfg.trigger == nil or cfg.trigger == ""
                -- With a trigger configured, an exclusive counter is activated
                -- by activity only AFTER the trigger fired at least once
                -- (state.triggered): map init SetValue calls during stage
                -- setup will not raise the bar prematurely, while the first
                -- Subtract after a timeout-hide between phases brings it back.
                if no_trigger or (exclusive and state.triggered) then
                    state.active = true
                end
                if state.active then
                    state.dirty = true
                    if cfg.timeout then state.last_trigger = CurTime() end
                end
            end
        end
    elseif inputlow == "kill" then
        for _, state in ipairs(states) do
            if state.counter == ent and state.active then
                EntWatch.HideBoss(state)
            end
        end
    end
end)

-- Breakable damage tracking.
hook.Add("PostEntityTakeDamage", "EntWatch.BossDamage", function(ent, dmginfo, took)
    local states = ent.m_BossStates
    if not states or not took then return end

    for _, state in ipairs(states) do
        if state.breakable == ent and not state.dead then
            if not state.maxhp then
                state.maxhp = math.max(ent:Health() + dmginfo:GetDamage(), 1)
            end
            -- A breakable is bound to exactly one config, so damage to it
            -- UNAMBIGUOUSLY belongs to that boss. Activate unconditionally,
            -- trigger or not (a trigger is merely an early activator).
            -- This is also what brings the bar back after a timeout-hide
            -- when boss phases alternate.
            state.active = true
            state.dirty = true
            if state.config.timeout then state.last_trigger = CurTime() end
        end
    end
end)

-- A breakable getting removed while active means the boss died (or the stage
-- ended): push one final update. Health() is no longer valid at this point,
-- so CalcBossHP reports 0 and the client hides the bar after its death delay.
hook.Add("EntityRemoved", "EntWatch.BossRemoved", function(ent)
    local states = ent.m_BossStates
    if not states then return end
    for _, state in ipairs(states) do
        if state.breakable == ent and state.active and not state.dead then
            -- Breakable removed mid-round = boss died. Route through KillBoss
            -- so the death path is shared with the OnBreak hook (idempotent).
            EntWatch.KillBoss(state.config)
        end
    end
end)

-- Heartbeat: applies the activity timeout and flushes throttled updates.
-- The IsBound guard keeps unbound states from ever reaching the client.
hook.Add("Think", "EntWatch.BossThink", function()
    local now = CurTime()
    for uid, state in pairs(EntWatch.BossStates) do
        if state.active and not state.dead then
            local timeout = state.config.timeout
            if timeout and state.last_trigger and now - state.last_trigger > timeout then
                EntWatch.HideBoss(state)
            elseif state.dirty and now >= state.next_send and EntWatch.IsBound(state) then
                EntWatch.SendBossState(state)
            end
        end
    end
end)

-- ===================== ROUND LIFECYCLE / LATE JOIN =====================

-- Wipe BEFORE the map entities are recreated: EntityKeyValue of the fresh
-- entities then binds them into clean states. Wiping in InitPostEntityMap
-- instead would destroy bindings made during CleanUpMap, which runs earlier.
hook.Add("PreCleanupMap", "EntWatch.BossPreCleanup", function()
    EntWatch.LoadBossConfig()
    mapluahook = nil -- the lua_run dies in CleanUpMap; EnsureLuaRun recreates it
end)

--- Safety-net rescan of live entities: first map load, manual ReloadConfig,
-- or a gamemode fork with a non-standard round restart order. Re-binds
-- counters/breakables and installs output hooks for trigger entities that
-- already exist; entities spawned later are caught by EntityKeyValue.
local function RescanEntities()
    if #EntWatch.Bosses == 0 then return end

    for _, ent in ents.Iterator() do
        local hid = ent.GetHammerID and ent:GetHammerID()
        if hid and (bind_counter[hid] or bind_breakable[hid]) then
            EntWatch.TryBind(ent, hid)
        end

        local name = ent.GetName and ent:GetName() or ent:GetInternalVariable("m_iName")
        if name ~= "" then
            if bind_counter[name] or bind_breakable[name] then
                EntWatch.TryBind(ent, name)
            end
            if trigger_output[name] then
                EntWatch.HookEntityOutputs(ent, name)
            end
        end
    end
end

--- Soft-reset a state that survived a round restart, which means
-- PreCleanupMap never fired in this gamemode fork. Clears dead entity
-- references and combat flags while keeping the config binding and uid.
-- @param state table Runtime state to reset in place.
local function SoftResetState(state)
    local cfg = state.config
    state.counter      = nil
    state.backup       = nil
    state.iterator     = nil
    state.breakable    = nil
    state.active       = cfg.trigger == nil or cfg.trigger == ""
    state.triggered    = false
    state.dirty        = false
    state.next_send    = 0
    state.last_trigger = nil
    state.peak_hp      = nil
    state.killtimer_started = nil
    state.maxhp        = nil -- (cfg.maxhp and cfg.maxhp > 0) and cfg.maxhp or nil
    state.dead         = false
end

hook.Add("InitPostEntityMap", "EntWatch.BossReset", function()
    -- The config is deliberately NOT reloaded here: PreCleanupMap already did
    -- that before the entities were recreated. If PreCleanupMap does NOT fire
    -- in this gamemode fork, states from the previous round survive to this
    -- point with dead entities and stale flags, so soft-reset them while
    -- keeping their config bindings.
    for _, state in pairs(EntWatch.BossStates) do
        SoftResetState(state)
    end

    net.Start("entwatch_boss")
    net.WriteUInt(0, 4) -- reset all
    net.Broadcast()

    timer.Simple(0, RescanEntities)
end)

--- Explicit config reload (for the ULX ew_reloadconfig command and manual use).
-- Reloads the config, resets every client and immediately rebinds whatever
-- entities are currently alive.
function EntWatch.ReloadBossConfig()
    EntWatch.LoadBossConfig()

    net.Start("entwatch_boss")
    net.WriteUInt(0, 4)
    net.Broadcast()

    RescanEntities()
end

-- Late joiners receive every active bound boss once their client is ready;
-- the delay also guarantees the client-side panel exists by then.
hook.Add("PlayerInitialSpawn", "EntWatch.BossLateJoin", function(ply)
    timer.Simple(5, function()
        if not IsValid(ply) then return end
        for _, state in pairs(EntWatch.BossStates) do
            if state.active and not state.dead and EntWatch.IsBound(state) then
                EntWatch.SendBossState(state, ply)
            end
        end
    end)
end)

-- ===================== DIAGNOSTICS =====================
-- entwatch_boss_verbose 1  - print bind/hook/activate/send events
-- ew_boss_status           - dump the whole pipeline (rcon/server console/superadmin)

if bossdebug then
    local cv_verbose = CreateConVar("entwatch_boss_verbose", "0", FCVAR_ARCHIVE)

    --- Verbose diagnostics printer, gated by the entwatch_boss_verbose convar.
    -- Mirrors every line into garrysmod/data/ew_boss_log.txt.
    -- @param fmt string string.format pattern.
    -- @param ... any Format arguments.
    function EntWatch.BossLog(fmt, ...)
        if not cv_verbose:GetBool() then return end
        local text = "[EW:Boss " .. math.Round(CurTime(), 1) .. "] " .. string.format(fmt, ...)
        print(text)
        file.Append("ew_boss_log.txt", text .. "\n")
    end

    concommand.Add("ew_boss_status", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local out = IsValid(ply)
            and function(s) ply:PrintMessage(HUD_PRINTCONSOLE, s) end
            or print

        out("=== EntWatch Boss Status | map: " .. game.GetMap() .. " ===")
        out("configs loaded: " .. #EntWatch.Bosses)
        out("lua_run: " .. (IsValid(mapluahook) and tostring(mapluahook) or "NOT SPAWNED"))

        out("--- trigger_output ---")
        local any = false
        for entname, list in pairs(trigger_output) do
            any = true
            local ents_found, hooked = 0, 0
            for _, e in ipairs(ents.FindByName(entname)) do
                ents_found = ents_found + 1
                if e.m_EWOutputHooked then hooked = hooked + 1 end
            end
            local outs = {}
            for _, rec in ipairs(list) do outs[#outs + 1] = rec.output end
            out(string.format("  %s -> [%s] | entities alive: %d, hooked: %d",
                entname, table.concat(outs, ","), ents_found, hooked))
        end
        if not any then out("  (empty: no triggers were parsed from the config!)") end

        out("--- states ---")
        local count = 0
        for uid, st in pairs(EntWatch.BossStates) do
            count = count + 1
            local hp, maxhp = EntWatch.CalcBossHP(st)
            out(string.format(
                "  uid=%d '%s' method=%s | active=%s dead=%s triggered=%s dirty=%s bound=%s | counter=%s backup=%s iter=%s brk=%s | hp=%.0f/%.0f peak=%s",
                uid, st.config.name or "?", st.config.method or "?",
                tostring(st.active), tostring(st.dead),
                tostring(st.triggered), tostring(st.dirty),
                tostring(EntWatch.IsBound(st)),
                tostring(IsValid(st.counter)), tostring(IsValid(st.backup)),
                tostring(IsValid(st.iterator)), tostring(IsValid(st.breakable)),
                hp, maxhp, tostring(st.peak_hp)
            ))
        end
        if count == 0 then out("  (нет состояний - ни одна энтити из конфига не привязана)") end
        out("=== end ===")
    end)
else -- bossdebug
    function EntWatch.BossLog() end
end