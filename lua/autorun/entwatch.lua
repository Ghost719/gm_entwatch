if string.sub(engine.ActiveGamemode(), 1, 14) ~= "zombiesurvival" then return end

EntWatch = EntWatch or {}
EntWatch.CachedEntities = EntWatch.CachedEntities or {}
EntWatch.MapConfig = EntWatch.MapConfig or {}

AddCSLuaFile("entwatch/sh_constants.lua")
include("entwatch/sh_constants.lua")

if file.Exists("entwatch/maps/" .. game.GetMap() .. ".lua", "LUA") then
    AddCSLuaFile("entwatch/maps/" .. game.GetMap() .. ".lua")
    EntWatch.MapConfig = include("entwatch/maps/" .. game.GetMap() .. ".lua")
end

if CLIENT then
    include("entwatch/sh_meta.lua")
    include("entwatch/cl_init.lua")
else
    AddCSLuaFile("entwatch/sh_meta.lua")
    AddCSLuaFile("entwatch/cl_init.lua")
    include("entwatch/sh_meta.lua")
    include("entwatch/sv_init.lua")
end
