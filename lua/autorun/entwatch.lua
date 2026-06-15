--- EntWatch entry point.
-- Loads shared constants, per-map configuration files and the realm-specific
-- modules. Only runs under gamemodes whose name starts with "zombiesurvival"
-- (prefix match so derived forks load it as well).
-- @module entwatch.autorun

if string.sub(engine.ActiveGamemode(), 1, 14) ~= "zombiesurvival" then return end

-- Global namespace. `or {}` keeps the tables across lua_refresh.
EntWatch = EntWatch or {}
EntWatch.CachedEntities = EntWatch.CachedEntities or {} -- materia weapons currently tracked by the server
EntWatch.MapConfig = EntWatch.MapConfig or {}           -- materia config of the current map
EntWatch.Bosses = EntWatch.Bosses or {}                 -- boss config of the current map
EntWatch.BossList = EntWatch.BossList or {}             -- client-side boss bar state

AddCSLuaFile("entwatch/sh_constants.lua")
include("entwatch/sh_constants.lua")

--- Loads the materia config for the current map into EntWatch.MapConfig.
-- The file is expected at lua/entwatch/maps/<map>.lua and must return a table.
-- Also resets the cached entity list, since old entries belong to the
-- previously loaded config.
function EntWatch.LoadRawConfig()
    EntWatch.MapConfig = {}

    local path = "entwatch/maps/" .. game.GetMap() .. ".lua"
    if file.Exists(path, "LUA") then
        AddCSLuaFile(path)
        EntWatch.MapConfig = include(path) or {}
    end

    EntWatch.CachedEntities = {}
end

--- Loads the boss config for the current map into EntWatch.Bosses.
-- The file is expected at lua/entwatch/bosses/<map>.lua and must return a table.
-- Server-only data, so the file is not AddCSLuaFile'd.
function EntWatch.LoadRawBossConfig()
    EntWatch.Bosses = {}

    local path = "entwatch/bosses/" .. game.GetMap() .. ".lua"
    if file.Exists(path, "LUA") then
        EntWatch.Bosses = include(path) or {}
    end

    if EntWatch.BossList ~= nil then EntWatch.BossList = {} end
    if EntWatch.BossStates ~= nil then EntWatch.BossState = {} end
end

EntWatch.LoadRawConfig()
EntWatch.LoadRawBossConfig()

if CLIENT then
    include("entwatch/sh_meta.lua")
    include("entwatch/cl_init.lua")
    include("entwatch/cl_boss.lua")
else
    AddCSLuaFile("entwatch/sh_meta.lua")
    AddCSLuaFile("entwatch/cl_init.lua")
    AddCSLuaFile("entwatch/cl_boss.lua")
    include("entwatch/sh_meta.lua")
    include("entwatch/sv_init.lua")
    include("entwatch/sv_admin.lua")
    include("entwatch/sv_boss.lua")
end
