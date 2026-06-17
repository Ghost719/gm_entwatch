--- Server core: materia tracking.
-- Resolves map config entries to live entities (weapon + button + counter),
-- enforces use modes (cooldowns, limited uses, counters), mirrors materia
-- state into networked vars for the client HUD and notifies clients about
-- pickups/drops.
--
-- Design note: tracking is passive. There are no Think hooks; everything is
-- driven by EntityKeyValue (entity creation), AcceptInput (map I/O traffic)
-- and weapon pickup/drop gamemode hooks.
-- @module entwatch.sv_init

util.AddNetworkString("entwatch")

EntWatch.CachedConfigs = EntWatch.CachedConfigs or {}

--- Builds a flat lookup table from every id/name key of every config entry.
-- After this, EntWatch.CachedConfigs[<hammerid|buttonid|energyname|...>]
-- resolves to the owning config entry in O(1) instead of scanning
-- EntWatch.MapConfig. First entry wins on key collisions.
function EntWatch.CacheConfigs()
    EntWatch.CachedConfigs = {}

    for _, config in ipairs(EntWatch.MapConfig) do
        for _, key in ipairs({"hammerid", "hammername", "buttonid", "buttonname", "energyid", "energyname"}) do
            if config[key] ~= nil and EntWatch.CachedConfigs[config[key]] == nil then
                EntWatch.CachedConfigs[config[key]] = config
            end
        end
    end
end

--- Finds a config entry by an arbitrary key/value pair.
-- Tries the O(1) cache first (where `key` itself is the cached id/name),
-- then falls back to a linear scan comparing config[key] == value.
-- @param key string config field name (or a cached id/name)
-- @param value any expected field value for the linear scan
-- @return table|nil config entry
function EntWatch.GetConfig(key, value)
    if EntWatch.CachedConfigs[key] ~= nil then
        return EntWatch.CachedConfigs[key]
    end

    for _, config in ipairs(EntWatch.MapConfig) do
        if config[key] == value then
            return config
        end
    end
end

--- Resolves the config entry for a live entity and caches it on the entity.
-- Resolution order: previously cached config on the entity, then the flat
-- id/name cache (by hammer id, then by targetname), then a linear scan over
-- "<key>id"/"<key>name" config fields.
-- @param ent Entity entity to resolve (weapon, button or counter)
-- @param key string config field prefix: "hammer", "button" or "energy"
-- @param name string|nil optional targetname override (used when GetName is not reliable yet)
-- @return table|nil config entry
function EntWatch.GetConfigByEntity(ent, key, name)
    local config = ent:GetMateriaConfig()
    if config then
        return config
    end

    local hammerid = ent.GetHammerID and ent:GetHammerID() or ent:GetInternalVariable("m_iHammerID") or "nil"
    name = name or ent.GetName and ent:GetName() or ent:GetInternalVariable("m_iName")

    if EntWatch.CachedConfigs[hammerid] then
        config = EntWatch.CachedConfigs[hammerid]
    elseif EntWatch.CachedConfigs[name] then
        config = EntWatch.CachedConfigs[name]
    end

    if not config then
        for _, tbl in ipairs(EntWatch.MapConfig) do
            if tbl[key.."id"] == hammerid or tbl[key.."name"] == name then
                config = tbl
                break
            end
        end
    end

    if config then
        ent:SetMateriaConfig(config)
        return config
    end
end

--- Depth-first search for a child entity of a given class.
-- Walks the parent/child attachment tree below `ent` up to `val` levels deep.
-- @param ent Entity root of the search
-- @param entclass string entity class to look for
-- @param val number|nil maximum recursion depth (default 4)
-- @return Entity|nil first matching descendant
function EntWatch.FindEntityRecursively(ent, entclass, val)
    if !val then
        val = 4
    elseif val < 0 then
        return nil
    end

    for _, child in ipairs(ent:GetChildren()) do
        if child:GetClass() == entclass then
            return child
        end

        if #child:GetChildren() > 0 then
            local ent = EntWatch.FindEntityRecursively(child, entclass, val - 1)
            if ent ~= nil then
                return ent
            end
        end
    end

    return nil
end

--- Initializes a weapon as a materia from its config entry.
-- Sets networked name/mode/uses/cooldown fields. Use count and cooldown are
-- only reset when the weapon was not a materia before, so a re-init does not
-- refill a partially used item.
-- @param weapon Entity CS:S weapon entity
-- @return boolean true when a config entry was found and applied
function EntWatch.OnWeaponInit(weapon)
    local config = EntWatch.GetConfigByEntity(weapon, "hammer")
    if !config then
        --ErrorNoHalt("[entWatch] Missing config for m_iHammerID = "..tostring(weapon:GetHammerID()).."\n")
        return false
    end

    if !weapon:IsMateria() then
        weapon:SetMateriaUseCount(config.maxuses or 1)
        weapon:SetMateriaCooldown(0)
    end

    weapon:SetMateriaName(config.name or weapon:GetName())
    weapon:SetMateriaShortname(config.shortname or weapon:GetMateriaName())
    weapon:SetMateriaMode(config.mode or ENTWATCH_MODE_NOBUTTON)
    weapon:SetMateriaUseMax(config.maxuses or 1)
    weapon:SetMateriaCooldownByConfig(config.cooldown or 0)
    weapon:SetMateria(true)

    return true
end

--- Handles a materia being picked up (or re-scanned with owner == nil).
-- Registers the weapon in CachedEntities, lazily resolves and links the
-- button/counter entities, applies the config filtername to the owner and
-- notifies all clients about the new HUD entry.
-- @param owner Player|nil new owner; nil when called from ReloadMateria
-- @param weapon Entity materia weapon
-- @return boolean true when the weapon has a config entry
function EntWatch.OnWeaponPickup(owner, weapon)
    local config = EntWatch.GetConfigByEntity(weapon, "hammer")
    if !config then return false end

    EntWatch.CachedEntities[#EntWatch.CachedEntities + 1] = weapon

    if config.mode ~= ENTWATCH_MODE_NOBUTTON then
        -- if the func_button entity is not valid, we'll find them
        if !weapon:GetMateriaButton() or !weapon:GetMateriaButton():IsValid() then
            local buttonclass = config.buttonclass or "func_button"

            if config.buttonid or config.buttonname then
                -- explicit button reference in the config: match by id/name
                for _, button in ipairs(ents.FindByClass(buttonclass)) do
                    if button:GetHammerID() == config.buttonid or button:GetName() == config.buttonname then
                        weapon:SetMateriaButton(button)
                        button:SetMateriaParent(weapon)

                        EntWatch.OnButtonInit(button)
                        break
                    end
                end
            else
                -- no explicit reference: assume the button is parented
                -- somewhere below the weapon in the attachment tree
                local button = EntWatch.FindEntityRecursively(weapon, buttonclass)
                if button and button:IsValid() then
                    weapon:SetMateriaButton(button)
                    button:SetMateriaParent(weapon)

                    EntWatch.OnButtonInit(button)
                end
            end
        end

        -- if the math_counter entity is not valid, we'll find them
        if config.mode == ENTWATCH_MODE_COUNTER_FMIN_REACHED or config.mode == ENTWATCH_MODE_COUNTER_FMAX_REACHED then
            if !weapon:GetMateriaCounter() or !weapon:GetMateriaCounter():IsValid() then
                for _, counter in ipairs(ents.FindByClass("math_counter")) do
                    if counter:GetHammerID() == config.energyid or counter:GetName() == config.energyname then
                        weapon:SetMateriaCounter(counter)
                        counter:SetMateriaParent(weapon)

                        EntWatch.OnCounterInit(counter)
                        break
                    end
                end
            end
        end
    end

    if IsValid(owner) then
        -- allows you to use a materia after another player has used and dropped the materia:
        -- map filters target players by name, so the holder temporarily takes
        -- the config filtername; the original name is restored on drop
        if isstring(config.filtername) then
            owner.m_oldFilterName = owner:GetInternalVariable("m_iName")
            owner:SetName(config.filtername)
        end

        net.Start("entwatch")
        net.WriteUInt(1, 8) -- cmd 1: add HUD entry
        net.WriteUInt(weapon:EntIndex(), 16)
        net.Broadcast()
    end

    return true
end

--- Handles a materia being dropped.
-- Removes the weapon from CachedEntities, restores the owner's original
-- targetname and, when the owner died, asks their client to do a full
-- HUD refresh (cmd 1 with re-request flag).
-- @param owner Player|nil previous owner
-- @param weapon Entity materia weapon
-- @return boolean always true
function EntWatch.OnWeaponDropped(owner, weapon)
    for id, ent in ipairs(EntWatch.CachedEntities) do
        if ent == weapon then
            table.remove(EntWatch.CachedEntities, id)
            break
        end
    end

    if owner and owner:IsValid() then
        if isstring(owner.m_oldFilterName) then
            owner:SetName(owner.m_oldFilterName)
            owner.m_oldFilterName = nil
        end

        if !owner:Alive() then
            net.Start("entwatch")
            net.WriteUInt(2, 8)  -- cmd 2: clear HUD entity
            net.WriteUInt(weapon:EntIndex(), 8)
            net.Broadcast()

            net.Start("entwatch")
            net.WriteUInt(0, 8) -- cmd 0: clear HUD list
            net.WriteBool(true) -- and send a request to get the full material list
            net.Send(owner)
        end
    end

    return true
end

--- Links a button entity to its materia weapon.
-- When the button has its own config entry, the weapon is found by the
-- config hammerid. Otherwise the parent attachment chain is walked upwards
-- until a configured CS:S weapon is found.
-- @param button Entity button-class entity
-- @return boolean true when a link was established
function EntWatch.OnButtonInit(button)
    local config = EntWatch.GetConfigByEntity(button, "button")

    if config then
        if !button:GetMateriaParent() or !button:GetMateriaParent():IsValid() then
            for _, ent in ents.Iterator() do
                if !ENTWATCH_CSSWEAPONS[ent:GetClass()] then continue end

                if ent:GetHammerID() == config.hammerid then
                    ent:SetMateriaButton(button)
                    button:SetMateriaParent(ent)

                    return true
                end
            end
        end
    else
        -- no direct config: walk up the parent chain looking for a
        -- configured weapon this button is attached to
        local ent = button:GetParent()
        while IsValid(ent) do
            if ENTWATCH_CSSWEAPONS[ent:GetClass()] then
                config = EntWatch.GetConfigByEntity(ent, "hammer")
                if config then
                    ent:SetMateriaButton(button)
                    button:SetMateriaParent(ent)

                    return true
                end
            end
            ent = ent:GetParent()
        end
    end

    return false
end

--- Applies the materia use-mode bookkeeping after a successful button press.
-- SPAM_PROTECTION: just start the cooldown.
-- COOLDOWNS: consume a use; when uses run out, start the cooldown and refill.
-- LIMITED_USES: consume a use and start the cooldown while uses remain.
-- COUNTER modes: toggle the active state (the counter tracks the resource).
-- @param button Entity pressed button (its MateriaParent is the weapon)
-- @return boolean always true
function EntWatch.OnButtonPressed(button)
    local parent = button:GetMateriaParent()
    local cooldown = parent:GetMateriaCooldownByConfig()
    local mode = parent:GetMateriaMode()

    if mode == ENTWATCH_MODE_SPAM_PROTECTION_ONLY then
        parent:SetMateriaCooldown(CurTime() + cooldown)
    elseif mode == ENTWATCH_MODE_COOLDOWNS then
        parent:SetMateriaUseCount(parent:GetMateriaUseCount() - 1)
        if parent:GetMateriaUseCount() <= 0 then
            parent:SetMateriaCooldown(CurTime() + cooldown)
            parent:SetMateriaUseCount(parent:GetMateriaUseMax())
        end
    elseif mode == ENTWATCH_MODE_LIMITED_USES then
        if parent:GetMateriaUseCount() > 0 then
            parent:SetMateriaUseCount(parent:GetMateriaUseCount() - 1)
            parent:SetMateriaCooldown(CurTime() + cooldown)
        end
    elseif mode == ENTWATCH_MODE_COUNTER_FMIN_REACHED or mode == ENTWATCH_MODE_COUNTER_FMAX_REACHED then
        local counter = parent:GetMateriaCounter()
        if IsValid(counter) then
            parent:SetMateriaState(!parent:GetMateriaState())
        end
    end

    return true
end

--- Reacts to the map locking a materia button.
-- For counter-based materias this means the ability turned off: start the
-- cooldown and clear the active state.
-- @param button Entity locked button
-- @return boolean always true
function EntWatch.OnButtonLocked(button)
    local parent = button:GetMateriaParent()
    local mode = parent:GetMateriaMode()

    if mode == ENTWATCH_MODE_COUNTER_FMIN_REACHED or mode == ENTWATCH_MODE_COUNTER_FMAX_REACHED then
        parent:SetMateriaCooldown(CurTime() + parent:GetMateriaCooldownByConfig())
        parent:SetMateriaState(false)
    end

    return true
end

--- Reacts to the map unlocking a materia button.
-- For cooldown-mode materias an unlock is treated as a refill.
-- @param button Entity unlocked button
-- @return boolean always true
function EntWatch.OnButtonUnlocked(button)
    local parent = button:GetMateriaParent()

    if parent:GetMateriaMode() == ENTWATCH_MODE_COOLDOWNS then
        parent:SetMateriaUseCount(parent:GetMateriaUseMax())
    end

    return true
end

--- Reacts to the map killing a materia button.
-- Counter-based materias lose their active state.
-- @param button Entity button being removed
-- @return boolean always true
function EntWatch.OnButtonKilled(button)
    local parent = button:GetMateriaParent()
    local mode = parent:GetMateriaMode()

    if mode == ENTWATCH_MODE_COUNTER_FMIN_REACHED or mode == ENTWATCH_MODE_COUNTER_FMAX_REACHED then
        parent:SetMateriaState(false)
    end

    return true
end

--- Initializes a math_counter that backs a counter-mode materia.
-- The engine does not expose math_counter internals to Lua, so the addon
-- shadows them in plain fields (m_OutValue/m_flMin/m_flMax/...) which are
-- filled from keyvalues and kept in sync by the AcceptInput hook below.
-- Applies config overrides, links the counter to its weapon and seeds the
-- weapon's use count/max from the counter value.
-- @param counter Entity math_counter
-- @return boolean true when a config entry was found
function EntWatch.OnCounterInit(counter, onlyinit)
    -- sets the default values
    counter.m_OutValue = counter.m_OutValue or 0
    counter.m_InitialValue = counter.m_InitialValue or 0
    counter.m_flMin = counter.m_flMin or 0
    counter.m_flMax = counter.m_flMax or 2000
    counter.m_bDisabled = counter.m_bDisabled or false

    if onlyinit then return true end

    local config = EntWatch.GetConfigByEntity(counter, "energy")
    if !config then return false end

    if config.hitmax then counter:Fire("SetHitMax", config.hitmax) end
    if config.hitmin then counter:Fire("SetHitMin", config.hitmin) end
    if config.currentvalue then counter:Fire("SetValue", config.currentvalue) end

    -- if the parent weapon is not valid, we'll find them
    if !counter:GetMateriaParent() or !counter:GetMateriaParent():IsValid() then
        for _, ent in ents.Iterator() do
            if !ENTWATCH_CSSWEAPONS[ent:GetClass()] then continue end

            if ent:GetHammerID() == config.hammerid then
                ent:SetMateriaCounter(counter)
                counter:SetMateriaParent(ent)
                break
            end
        end
    end

    local parent = counter:GetMateriaParent()
    if parent and parent:IsValid() then
        if config.mode == ENTWATCH_MODE_COUNTER_FMIN_REACHED then
            -- the counter may have been raised above its keyvalue start
            -- value by map logic; adopt the higher value as the new maximum
            if counter.m_OutValue > counter.m_InitialValue and counter.m_OutValue <= counter.m_flMax then
                counter.m_InitialValue = counter.m_OutValue
            end

            parent:SetMateriaUseCount(counter.m_OutValue)
            parent:SetMateriaUseMax(counter.m_InitialValue)
        else
            -- FMAX mode counts upwards: remaining = max - current
            parent:SetMateriaUseCount(counter.m_flMax - counter.m_OutValue)
            parent:SetMateriaUseMax(counter.m_flMax)
        end
    end

    return true
end

--- Re-initializes a single materia weapon (config + button/counter links).
-- @param weapon Entity CS:S weapon entity
-- @return boolean true on success
function EntWatch.ReloadMateria(weapon)
    -- reload weapon' materia
    if !EntWatch.OnWeaponInit(weapon) then return false end
    -- getting the func_button and math_counter entities
    if !EntWatch.OnWeaponPickup(nil, weapon) then return false end

    return true
end

--- Reloads the map config from disk and rebuilds the lookup cache.
-- @param skip_reload boolean|nil when true, existing weapons are not re-scanned
function EntWatch.ReloadConfig(skip_reload)
    EntWatch.LoadRawConfig()
    EntWatch.CacheConfigs()

    if not skip_reload then
        for _, ent in ents.Iterator() do
            if ENTWATCH_CSSWEAPONS[ent:GetClass()] then
                EntWatch.ReloadMateria(ent)
            end
        end
    end
end

hook.Add("Initialize", "EntWatch.Initialize", function()
    if #EntWatch.MapConfig == 0 then return end

    EntWatch.ReloadConfig(true)
end)

hook.Add("InitPostEntityMap", "EntWatch.InitPostEntityMap", function()
    if #EntWatch.MapConfig == 0 then return end

    EntWatch.ReloadConfig(true)

    -- send to client to reset all materias
    if #player.GetAll() > 0 then
        net.Start("entwatch")
        net.WriteUInt(0, 8) -- cmd 0: clear HUD list
        net.WriteBool(false)
        net.Broadcast()
    end
end)

-- Entity creation. Keyvalues arrive one by one while the entity is still
-- being constructed, so initialization is anchored to the "hammerid" key
-- (one of the last keys the engine dispatches).
hook.Add("EntityKeyValue", "EntWatch.EntityKeyValue", function(ent, key, value)
    -- in this state, the entities are not yet fully initialized
    -- so we can't get the internal variables of the entity

    if ENTWATCH_CSSWEAPONS[ent:GetClass()] and key == "hammerid" then
        ent:SetHammerID(tonumber(value) or 0)
        EntWatch.OnWeaponInit(ent)
    end

    if ENTWATCH_BUTTON_CLASSNAMES[ent:GetClass()] and key == "hammerid" then
        ent:SetHammerID(tonumber(value) or 0)
        EntWatch.OnButtonInit(ent)
    end

    if ent:GetClass() == "math_counter" then
        -- shadow the counter internals: the engine never exposes them,
        -- so they are reconstructed from keyvalues here and updated from
        -- inputs in the AcceptInput hook below
        local keylow = key:lower()
        if keylow == "startvalue" then
            ent.m_OutValue = tonumber(value) or 0
            ent.m_InitialValue = ent.m_OutValue
        elseif keylow == "min" then
            ent.m_flMin = tonumber(value) or 0
        elseif keylow == "max" then
            ent.m_flMax = tonumber(value) or 0
        elseif keylow == "startdisabled" then
            ent.m_bDisabled = tobool(value) or false
        elseif keylow == "hammerid" then
            ent:SetHammerID(tonumber(value) or 0)
            EntWatch.OnCounterInit(ent)
        end
    end
end)

-- Map I/O traffic. This is where use-mode enforcement happens (button "Use")
-- and where the shadowed math_counter state is kept in sync with the engine.
hook.Add("AcceptInput", "EntWatch.AcceptInput", function(ent, input, activator, caller, value)
    -- after EntityKeyValue we can be sure that the entity is initialized

    -- some maps spawning entities via env_entity_maker
    -- which is why the fix does not work via InitPostEntityMap (gamemodes/zombiesurvival/gamemode/sv_zombieescape.lua)
    if ent:GetClass() == "filter_activator_team" and ent.ZEFix then
        if tostring(ent:GetInternalVariable("filterteam")) ~= ent.ZEFix then
            ent:SetKeyValue("filterteam", ent.ZEFix)
        end
    end
 
    local parent = ent:GetMateriaParent()

    -- checking the "func_button" entity and the parent (weapon) entity
    if ENTWATCH_BUTTON_CLASSNAMES[ent:GetClass()] and parent and parent:IsValid() then
        local inputlow = input:lower()
        if inputlow == "use" then
            if !IsValid(activator) or ent:IsPressed() then return end

            -- filtername gate: only the player carrying the config
            -- filtername (i.e. the current holder) may press the button
            local config = parent:GetMateriaConfig() or {}
            local filtername = config["filtername"]
            if isstring(filtername) and #filtername > 0 and filtername ~= activator:GetInternalVariable("m_iName") then return end

            if CurTime() < parent:GetMateriaCooldown() then
                -- we're not ready yet; returning true suppresses the input
                return true
            elseif ENTWATCH_MODE_SPAM_PROTECTION_ONLY <= parent:GetMateriaMode() and parent:GetMateriaMode() <= ENTWATCH_MODE_LIMITED_USES then
                local usesleft = parent:GetMateriaUseCount()
                if usesleft > 0 and ent:IsLocked() then
                    -- bypass the locked state after cooldown:
                    -- unlock the button and replay the original Use input
                    ent:Fire("Unlock")
                    ent:Fire(input, value, 0.1, activator, caller)
                    return true
                elseif usesleft <= 0 and !ent:IsLocked() then
                    -- limit usage when the maxuses is reached
                    ent:Fire("Lock", nil, 0.1)
                    return true
                end
            end

            EntWatch.OnButtonPressed(ent)
        elseif inputlow == "lock" then
            EntWatch.OnButtonLocked(ent)
        elseif inputlow == "unlock" then
            EntWatch.OnButtonUnlocked(ent)
        elseif inputlow == "kill" then
            EntWatch.OnButtonKilled(ent)
        --else
            --print("[BUG] AcceptInput: ", ent:GetInternalVariable("m_iHammerID"), ent, activator, caller, input, value)
        end
    end

    -- checking the "math_counter" entity
    if ent:GetClass() == "math_counter" then
        local inputlow = input:lower()
        local valuenew = tonumber(value) or 0

        if ent.m_OutValue == nil then
            -- LAZYFIX: entity may begin math_counter processing
            -- while the Lua side hasn't initialized yet.
            EntWatch.OnCounterInit(ent, true)
        end

        -- mirror every math_counter input on the shadowed Lua-side state,
        -- since the engine value itself cannot be read back
        if inputlow == "enable" then
            ent.m_bDisabled = false
        elseif inputlow == "disable" then
            ent.m_bDisabled = true
        elseif inputlow == "add" then
            ent.m_OutValue = ent.m_OutValue + valuenew
        elseif inputlow == "subtract" then
            ent.m_OutValue = ent.m_OutValue - valuenew
        elseif inputlow == "divide" and valuenew ~= 0 then
            ent.m_OutValue = ent.m_OutValue / valuenew
        elseif inputlow == "multiply" then
            ent.m_OutValue = ent.m_OutValue * valuenew
        elseif inputlow == "setvalue" or inputlow == "setvaluenofire" then
            ent.m_OutValue = valuenew
        elseif inputlow == "sethitmax" then
            ent.m_flMax = valuenew
            if ent.m_flMax < ent.m_flMin then
                ent.m_flMin = ent.m_flMax
            end
        elseif inputlow == "sethitmin" then
            ent.m_flMin = valuenew
            if ent.m_flMax < ent.m_flMin then
                ent.m_flMax = ent.m_flMin
            end
        elseif inputlow == "addoutput" and value ~= nil then
            -- AddOutput can also rewrite keyvalues at runtime
            local valuelow = value:lower()
            if valuelow:match("^startvalue (%d+)") then
                ent.m_OutValue = tonumber(valuelow:match("^startvalue (%d+)")) or 0
            elseif valuelow:match("^min (%d+)") then
                ent.m_flMin = tonumber(valuelow:match("^min (%d+)")) or 0
            elseif valuelow:match("^max (%d+)") then
                ent.m_flMax = tonumber(valuelow:match("^max (%d+)")) or 0
            elseif valuelow:match("^startdisabled (%d+)") then
                ent.m_bDisabled = tobool(valuelow:match("^startdisabled (%d+)")) or false
            end
        end

        -- clamp to the engine behaviour: math_counter never leaves [min, max]
        if ent.m_flMin != 0 or ent.m_flMax != 0 then
            if ent.m_OutValue < ent.m_flMin then
                ent.m_OutValue = ent.m_flMin
            elseif ent.m_OutValue > ent.m_flMax then
                ent.m_OutValue = ent.m_flMax
            end
        end

        if parent and parent:IsValid() then
            if parent:GetMateriaMode() == ENTWATCH_MODE_COUNTER_FMIN_REACHED then
                -- adopt a raised value as the new maximum (map logic may
                -- scale boss/ability energy after spawn)
                if ent.m_OutValue > ent.m_InitialValue and ent.m_OutValue <= ent.m_flMax then
                    ent.m_InitialValue = ent.m_OutValue
                end

                parent:SetMateriaUseCount(ent.m_OutValue)
                parent:SetMateriaUseMax(ent.m_InitialValue)
            else
                parent:SetMateriaUseCount(ent.m_flMax - ent.m_OutValue)
                parent:SetMateriaUseMax(ent.m_flMax)
            end
        end
    end
end)

-- Weapon pickup. Deferred by one tick: at WeaponEquip time the owner is not
-- assigned yet and networked vars may not be ready.
hook.Add("WeaponEquip", "EntWatch.WeaponEquip", function(weapon, owner)
    timer.Simple(0, function()
        if !IsValid(weapon) or !IsValid(owner) then return end
        if !ENTWATCH_CSSWEAPONS[weapon:GetClass()] then return end

        if !weapon:IsMateria() then
            EntWatch.OnWeaponInit(weapon)
        end

        if weapon:IsMateria() then
            EntWatch.OnWeaponPickup(owner, weapon)
        end
    end)
end)

hook.Add("PlayerDroppedWeapon", "EntWatch.OnDroppedWeapon", function(owner, weapon)
    if weapon:IsMateria() then
        EntWatch.OnWeaponDropped(owner, weapon)
    end
end)

-- Client list request (cmd 0): reply with one "add" message per tracked
-- materia held by a teammate. Rate limited to one request per second
-- per player to prevent traffic amplification.
net.Receive("entwatch", function(len, ply)
    if not ply.m_EWNextRequest then
        ply.m_EWNextRequest = CurTime() + 1
    elseif CurTime() < ply.m_EWNextRequest then
        return
    end

    local cmd = net.ReadUInt(8)
    if cmd == 0 then
        for _, ent in ipairs(EntWatch.CachedEntities) do
            if !ent or !ent:IsValid() then continue end

            local owner = ent:GetOwner()
            if owner and owner:IsValid() and owner:Team() == ply:Team() then
                net.Start("entwatch")
                net.WriteUInt(1, 8) -- cmd 1: add HUD entry
                net.WriteUInt(ent:EntIndex(), 16)
                net.Send(ply)
            end
        end
    end
end)

-- Late joiners: push the current materia list once the client is ready.
hook.Add("PlayerInitialSpawn", "EntWatch.LateJoin", function(ply)
    timer.Simple(5, function()
        if not IsValid(ply) then return end
        for _, ent in ipairs(EntWatch.CachedEntities) do
            if !ent or !ent:IsValid() then continue end

            local owner = ent:GetOwner()
            if owner and owner:IsValid() and owner:Team() == ply:Team() then
                net.Start("entwatch")
                net.WriteUInt(1, 8) -- cmd 1: add HUD entry
                net.WriteUInt(ent:EntIndex(), 16)
                net.Send(ply)
            end
        end
    end)
end)
