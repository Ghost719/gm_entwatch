util.AddNetworkString("entwatch")

function EntWatch.GetConfig(key, value)
    for _, config in ipairs(EntWatch.MapConfig) do
        if config[key] == value then
            return config
        end
    end
end

function EntWatch.GetConfigByEntity(ent, key, name)
    if ent:GetMateriaConfig() then
        return ent:GetMateriaConfig()
    end

    name = name or ent:GetName()

    local config
    for _, tbl in ipairs(EntWatch.MapConfig) do
        if tbl[key.."id"] == ent:GetHammerID() or tbl[key.."name"] == name then
            config = tbl
            break
        end
    end

    if config then
        ent:SetMateriaConfig(config)
        return config
    end
end

function EntWatch.FindEntityRecursively(ent, entclass, val)
    if !val then val = 4 end

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

function EntWatch.OnWeaponPickup(owner, weapon)
    local config = EntWatch.GetConfigByEntity(weapon, "hammer")
    if !config then return false end

    EntWatch.CachedEntities[#EntWatch.CachedEntities + 1] = weapon

    if config.mode ~= ENTWATCH_MODE_NOBUTTON then
        -- if the func_button entity is not valid, we'll find them
        if !weapon:GetMateriaButton() or !weapon:GetMateriaButton():IsValid() then
            local buttonclass = config.buttonclass or "func_button"

            if config.buttonid or config.buttonname then
                for _, button in ipairs(ents.FindByClass(buttonclass)) do
                    if button:GetHammerID() == config.buttonid or button:GetName() == config.buttonname then
                        weapon:SetMateriaButton(button)
                        button:SetMateriaParent(weapon)

                        EntWatch.OnButtonInit(button)
                        break
                    end
                end
            else
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
        -- allows you to use a materia after another player has used and dropped the materia
        if isstring(config.filtername) then
            owner:SetName(config.filtername)
        end

        net.Start("entwatch")
        net.WriteUInt(2, 8)
        net.WriteEntity(weapon)
        net.Broadcast()
    end

    return true
end

function EntWatch.OnWeaponDropped(owner, weapon)
    for id, ent in ipairs(EntWatch.CachedEntities) do
        if ent == weapon then
            table.remove(EntWatch.CachedEntities, id)
            break
        end
    end

    if owner and owner:IsValid() then
        owner:SetName("player")

        if !owner:Alive() then
            net.Start("entwatch")
            net.WriteUInt(1, 8)
            net.WriteUInt(1, 8)
            net.Send(owner)
        end
    end

    return true
end

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
        end
    end

    return false
end

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

function EntWatch.OnButtonLocked(button)
    local parent = button:GetMateriaParent()
    local mode = parent:GetMateriaMode()

    if mode == ENTWATCH_MODE_COUNTER_FMIN_REACHED or mode == ENTWATCH_MODE_COUNTER_FMAX_REACHED then
        parent:SetMateriaCooldown(CurTime() + parent:GetMateriaCooldownByConfig())
        parent:SetMateriaState(false)
    end

    return true
end

function EntWatch.OnButtonUnlocked(button)
    local parent = button:GetMateriaParent()

    if parent:GetMateriaMode() == ENTWATCH_MODE_COOLDOWNS then
        parent:SetMateriaUseCount(parent:GetMateriaUseMax())
    end

    return true
end

function EntWatch.OnButtonKilled(button)
    local parent = button:GetMateriaParent()
    local mode = parent:GetMateriaMode()

    if mode == ENTWATCH_MODE_COUNTER_FMIN_REACHED or mode == ENTWATCH_MODE_COUNTER_FMAX_REACHED then
        parent:SetMateriaState(false)
    end

    return true
end

function EntWatch.OnCounterInit(counter)
    local config = EntWatch.GetConfigByEntity(counter, "energy")
    if !config then return false end

    -- sets the default values
    counter.m_OutValue = counter.m_OutValue or 0
    counter.m_InitialValue = counter.m_InitialValue or 0
    counter.m_flMin = counter.m_flMin or 0
    counter.m_flMax = counter.m_flMax or 2000
    counter.m_bDisabled = counter.m_bDisabled or false

    if config.currentvalue then counter:Fire("SetValue", config.currentvalue) end
    if config.hitmax then counter:Fire("SetHitMax", config.hitmax) end
    if config.hitmin then counter:Fire("SetHitMin", config.hitmax) end

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
            parent:SetMateriaUseCount(counter.m_OutValue)
            parent:SetMateriaUseMax(counter.m_InitialValue)
        else
            parent:SetMateriaUseCount(counter.m_flMax - counter.m_OutValue)
            parent:SetMateriaUseMax(counter.m_flMax)
        end
    end

    return true
end

function EntWatch.ReloadMateria(weapon)
    -- reload weapon' materia
    if !EntWatch.OnWeaponInit(weapon) then return false end
    -- getting the func_button and math_counter entities
    if !EntWatch.OnWeaponPickup(nil, weapon) then return false end

    return true
end

function EntWatch.ReloadConfig()
    EntWatch.CachedEntities = {}

    if file.Exists("entwatch/maps/" .. game.GetMap() .. ".lua", "LUA") then
        EntWatch.MapConfig = include("entwatch/maps/" .. game.GetMap() .. ".lua")
    end

    for _, ent in ents.Iterator() do
        if ENTWATCH_CSSWEAPONS[ent:GetClass()] then
            EntWatch.ReloadMateria(ent)
        end
    end
end

hook.Add("InitPostEntityMap", "EntWatch.InitPostEntityMap", function()
    if #EntWatch.MapConfig == 0 then return end

    EntWatch.CachedEntities = {}

    -- send to client to reset all materias
    net.Start("entwatch")
    net.WriteUInt(1, 8)
    net.WriteUInt(0, 8)
    net.Broadcast()
end)

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
        if key == "startvalue" then
            ent.m_OutValue = tonumber(value) or 0
            ent.m_InitialValue = ent.m_OutValue
        elseif key == "min" then
            ent.m_flMin = tonumber(value) or 0
        elseif key == "max" then
            ent.m_flMax = tonumber(value) or 0
        elseif key == "StartDisabled" then
            ent.m_bDisabled = tobool(value) or false
        elseif key == "hammerid" then
            ent:SetHammerID(tonumber(value) or 0)
            EntWatch.OnCounterInit(ent)
        end
    end
end)

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
        if input == "Use" then
            if !IsValid(activator) or ent:IsPressed() then return end

            local filtername = parent:GetMateriaConfig()["filtername"]
            if isstring(filtername) and #filtername > 0 and filtername ~= activator:GetInternalVariable("m_iName") then return end

            if CurTime() < parent:GetMateriaCooldown() then
                -- we're not ready yet
                return true
            elseif ENTWATCH_MODE_SPAM_PROTECTION_ONLY <= parent:GetMateriaMode() and parent:GetMateriaMode() <= ENTWATCH_MODE_LIMITED_USES then
                local usesleft = parent:GetMateriaUseCount()
                if usesleft > 0 and ent:IsLocked() then
                    -- bypass the locked state after cooldown
                    ent:Fire("Unlock")
                    ent:Fire(input, value, 0.05, activator, caller)
                    return true
                elseif usesleft <= 0 and !ent:IsLocked() then
                    -- limit usage when the maxuses is reached
                    ent:Fire("Lock")
                    return true
                end
            end

            EntWatch.OnButtonPressed(ent)
        elseif input == "Lock" then
            EntWatch.OnButtonLocked(ent)
        elseif input == "Unlock" then
            EntWatch.OnButtonUnlocked(ent)
        elseif input == "Kill" then
            EntWatch.OnButtonKilled(ent)
        --else
            --print("[BUG] AcceptInput: ", ent:GetInternalVariable("m_iHammerID"), ent, activator, caller, input, value)
        end
    end

    -- checking the "math_counter" entity
    if ent:GetClass() == "math_counter" and EntWatch.GetConfigByEntity(ent, "energy") then
        local valuenew = tonumber(value) or 0

        -- a random shit to get right value from engine
        if input == "Enable" then
            ent.m_bDisabled = false
        elseif input == "Disable" then
            ent.m_bDisabled = true
        elseif input == "Add" then
            ent.m_OutValue = ent.m_OutValue + valuenew
        elseif input == "Subtract" then
            ent.m_OutValue = ent.m_OutValue - valuenew
        elseif input == "Divide" and valuenew ~= 0 then
            ent.m_OutValue = ent.m_OutValue / valuenew
        elseif input == "Multiply" then
            ent.m_OutValue = ent.m_OutValue * valuenew
        elseif input == "SetValue" or input == "SetValueNoFire" then
            ent.m_OutValue = valuenew
        elseif input == "SetHitMax" then
            ent.m_flMax = valuenew
            if ent.m_flMax < ent.m_flMin then
                ent.m_flMin = ent.m_flMax
            end
        elseif input == "SetHitMin" then
            ent.m_flMin = valuenew
            if ent.m_flMax < ent.m_flMin then
                ent.m_flMax = ent.m_flMin
            end
        end

        if ent.m_OutValue < ent.m_flMin then
            ent.m_OutValue = ent.m_flMin
        elseif ent.m_OutValue > ent.m_flMax then
            ent.m_OutValue = ent.m_flMax
        end

        if parent and parent:IsValid() then
            if parent:GetMateriaMode() == ENTWATCH_MODE_COUNTER_FMIN_REACHED then
                parent:SetMateriaUseCount(ent.m_OutValue)
                parent:SetMateriaUseMax(ent.m_InitialValue)
            else
                parent:SetMateriaUseCount(ent.m_flMax - ent.m_OutValue)
                parent:SetMateriaUseMax(ent.m_flMax)
            end
        end
    end
end)

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

net.Receive("entwatch", function(len, ply)
    local cmd = net.ReadUInt(8)

    if cmd == 1 then
        for _, ent in ipairs(EntWatch.CachedEntities) do
            if !ent or !ent:IsValid() then continue end

            local owner = ent:GetOwner()
            if owner and owner:IsValid() and owner:Team() == ply:Team() then
                net.Start("entwatch")
                net.WriteUInt(2, 8)
                net.WriteEntity(ent)
                net.Broadcast()
            end
        end
    end
end)
