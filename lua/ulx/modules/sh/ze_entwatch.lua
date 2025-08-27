if engine.ActiveGamemode() ~= "zombiesurvival" then return end

local CATEGORY_NAME = "EntWatch"

ulx.entwatch_spawners = {}

hook.Add("Initialize", "ulx.entwatch_spawners", function()
    if !EntWatch then return end

    for _, cfg in ipairs(EntWatch.MapConfig) do
        if isstring(cfg.pt_spawner) and #cfg.pt_spawner > 0 then
            table.insert(ulx.entwatch_spawners, cfg.pt_spawner)
        end
    end
end)

function ulx.ew_reloadconfig(calling_ply)
    EntWatch.ReloadConfig()
    ulx.fancyLogAdmin(calling_ply, "#A reloaded config for EntWatch")
end
local ew_reloadconfig = ulx.command(CATEGORY_NAME, "ulx ew_reloadconfig", ulx.ew_reloadconfig, "!ew_reloadconfig")
ew_reloadconfig:defaultAccess( ULib.ACCESS_ADMIN )
ew_reloadconfig:help("Reload config for current map")

function ulx.ew_spawnitem(calling_ply, target_ply, name)
    local config = EntWatch.GetConfig("pt_spawner", name)
    if !config then
        ULib.tsayError(calling_ply, "Config not found!", true)
        return
    end

    local pt_spawner = ents.FindByName(name)[1]
    if !pt_spawner or !pt_spawner:IsValid() then
        ULib.tsayError(calling_ply, "Entity \"point_template\" with specified name was not found!", true)
        return
    end

    for _, ent in ents.Iterator() do
        if ENTWATCH_CSSWEAPONS[ent:GetClass()] and config.hammerid == ent:GetHammerID() then
            ULib.tsayError(calling_ply, "It's unsafe to spawn same materia twice!", true)
            return
        end
    end

    local maker = ents.Create("env_entity_maker")
    maker:SetKeyValue("EntityTemplate", name)
    maker:SetKeyValue("spawnflags", "0")
    maker:SetPos(target_ply:GetPos() + Vector(0, 0, 20)) -- some materias will split in textures because the mappers are scumbags
    maker:Fire("ForceSpawn")
    maker:Fire("Kill")

    ulx.fancyLogAdmin(calling_ply, "#A spawned \"#s\" at #T", config.name, target_ply)
end
local ew_spawnitem = ulx.command(CATEGORY_NAME, "ulx ew_spawnitem", ulx.ew_spawnitem, "!ew_spawnitem")
ew_spawnitem:addParam{ type=ULib.cmds.PlayerArg }
ew_spawnitem:addParam{ type=ULib.cmds.StringArg, hint="pt_spawner", ULib.cmds.optional, ULib.cmds.takeRestOfLine, completes=ulx.entwatch_spawners }
ew_spawnitem:defaultAccess( ULib.ACCESS_ADMIN )
ew_spawnitem:help("Spawn materia at the given player")

function ulx.ew_transfer(calling_ply, target_from, target_to)
    if target_from == target_to then
        ULib.tsayError(calling_ply, "You listed the same target twice! Please use two different targets.", true)
        return
    end

    if ulx.getExclusive(target_from, calling_ply) then
        ULib.tsayError(calling_ply, ulx.getExclusive(target_from, calling_ply), true )
        return
    end

    if ulx.getExclusive(target_to, calling_ply) then
        ULib.tsayError(calling_ply, ulx.getExclusive(target_to, calling_ply), true )
        return
    end

    if target_from:Team() ~= target_to:Team() then
        ULib.tsayError(calling_ply, "You're trying to transfer materia from different teams", true)
        return
    end

    for _, weapon in ipairs(target_to:GetWeapons()) do
        if ENTWATCH_CSSWEAPONS[weapon:GetClass()] then
            ULib.tsayError(calling_ply, target_to:Nick() .. " already has materia!", true)
            return
        end
    end

    local materia
    for _, weapon in ipairs(target_from:GetWeapons()) do
        if ENTWATCH_CSSWEAPONS[weapon:GetClass()] then
            materia = weapon
            break
        end
    end

    if !materia or !materia:IsValid() then
        ULib.tsayError(calling_ply, target_from:Nick() .. " doesn't have a materia!", true)
        return
    end

    target_from:DropWeapon(materia)
    target_to:PickupWeapon(materia)
    ulx.fancyLogAdmin(calling_ply, "#A transferred the materia of #T to #T", target_from, target_to)
end
local ew_transfer = ulx.command(CATEGORY_NAME, "ulx ew_transfer", ulx.ew_transfer, "!ew_transfer")
ew_transfer:addParam{ type=ULib.cmds.PlayerArg }
ew_transfer:addParam{ type=ULib.cmds.PlayerArg }
ew_transfer:defaultAccess( ULib.ACCESS_ADMIN )
ew_transfer:help("Transfer materia from one player to another")