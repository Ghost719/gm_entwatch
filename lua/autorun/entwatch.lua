if string.sub(engine.ActiveGamemode(), 1, 14) ~= "zombiesurvival" then return end

if CLIENT then
    include("entwatch/sh_constants.lua")
    include("entwatch/sh_meta.lua")
    include("entwatch/cl_init.lua")
else
    AddCSLuaFile("entwatch/sh_constants.lua")
    AddCSLuaFile("entwatch/sh_meta.lua")
    AddCSLuaFile("entwatch/cl_init.lua")
    include("entwatch/sh_constants.lua")
    include("entwatch/sh_meta.lua")
    include("entwatch/sv_init.lua")
end
