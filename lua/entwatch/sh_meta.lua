--- Entity metatable extensions shared by both realms.
-- Materia state lives in networked variables (NWBool/NWInt/NWFloat/NWString)
-- so the client HUD can read it without extra net messages. Server-only
-- bookkeeping (config/parent links) uses plain AccessorFunc fields.
-- @module entwatch.sh_meta

local entmeta = FindMetaTable "Entity"

--- Caches the Hammer editor ID on the entity.
-- Called from EntityKeyValue, where GetInternalVariable is not available yet.
-- @param value number Hammer ID parsed from the "hammerid" keyvalue
function entmeta:SetHammerID(value)
    self.m_iHammerID = value
end

--- Returns the Hammer editor ID of the entity.
-- Falls back to the engine-side internal variable when the cached value
-- is missing (e.g. for entities created before this addon loaded).
-- @return number|nil Hammer ID
function entmeta:GetHammerID()
    return self.m_iHammerID or self:GetInternalVariable("m_iHammerID")
end

--- Whether the entity is in the engine "locked" state (buttons/doors).
-- @return boolean
function entmeta:IsLocked()
    return self:GetInternalVariable("m_bLocked")
end

--- Whether a button-like entity is currently pressed.
-- m_toggle_state == 0 corresponds to TS_AT_TOP, which for buttons means
-- the pressed position. Non-button classes always report false.
-- @return boolean
function entmeta:IsPressed()
    if ENTWATCH_BUTTON_CLASSNAMES[self:GetClass()] then
        return self:GetInternalVariable("m_toggle_state") == 0
    else
        return false
    end
end

--[[
AccessorFunc(entmeta, "m_bMateria", "Materia", FORCE_BOOL)
AccessorFunc(entmeta, "m_sMateriaName", "MateriaName", FORCE_STRING)
AccessorFunc(entmeta, "m_sMateriaShortname", "MateriaShortname", FORCE_STRING)
AccessorFunc(entmeta, "m_iMateriaMode", "MateriaMode", FORCE_NUMBER)
AccessorFunc(entmeta, "m_iMateriaUseCount", "MateriaUseCount", FORCE_NUMBER)
AccessorFunc(entmeta, "m_iMateriaUseMax", "MateriaUseMax", FORCE_NUMBER)
AccessorFunc(entmeta, "m_flMateriaCooldown", "MateriaCooldown", FORCE_NUMBER)
AccessorFunc(entmeta, "m_bMateriaState", "MateriaState", FORCE_BOOL)--]]

-- Server-side only links between a materia weapon and its parts:
-- Get/SetMateriaConfig  - config table entry from the map file
-- Get/SetMateriaParent  - the materia weapon a button/counter belongs to
-- Get/SetMateriaButton  - the button parented to the weapon
-- Get/SetMateriaCounter - the math_counter parented to the weapon
AccessorFunc(entmeta, "m_MateriaConfig", "MateriaConfig")
AccessorFunc(entmeta, "m_MateriaParent", "MateriaParent")
AccessorFunc(entmeta, "m_MateriaParentButton", "MateriaButton")
AccessorFunc(entmeta, "m_MateriaParentCounter", "MateriaCounter")

--- Whether this entity is a configured materia weapon.
-- @return boolean
function entmeta:IsMateria()
    return self:GetNWBool("m_bMateria") == true
end

--- Marks/unmarks this entity as a materia weapon.
-- @param value boolean
function entmeta:SetMateria(value)
    self:SetNWBool("m_bMateria", value)
end

--- Full display name of the materia.
-- Falls back to the entity targetname (or PrintName for weapons).
-- @return string
function entmeta:GetMateriaName()
    return self:GetNWString("m_sMateriaName", self.GetName and self:GetName() or self.PrintName)
end

--- Sets the full display name of the materia.
-- @param value string
function entmeta:SetMateriaName(value)
    self:SetNWString("m_sMateriaName", value)
end

--- Short name used in the HUD list. Falls back to the full name.
-- @return string
function entmeta:GetMateriaShortname()
    return self:GetNWString("m_sMateriaShortname", self:GetMateriaName())
end

--- Sets the short HUD name of the materia.
-- @param value string
function entmeta:SetMateriaShortname(value)
    self:SetNWString("m_sMateriaShortname", value)
end

--- Operating mode of the materia (ENTWATCH_MODE_* constant).
-- @return number
function entmeta:GetMateriaMode()
    return self:GetNWInt("m_iMateriaMode", ENTWATCH_MODE_NOBUTTON)
end

--- Sets the operating mode of the materia.
-- @param value number ENTWATCH_MODE_* constant
function entmeta:SetMateriaMode(value)
    self:SetNWInt("m_iMateriaMode", value)
end

--- Remaining number of uses.
-- @return number
function entmeta:GetMateriaUseCount()
    return self:GetNWInt("m_iMateriaUseCount")
end

--- Sets the remaining number of uses.
-- @param value number
function entmeta:SetMateriaUseCount(value)
    self:SetNWInt("m_iMateriaUseCount", value)
end

--- Maximum number of uses.
-- @return number
function entmeta:GetMateriaUseMax()
    return self:GetNWInt("m_iMateriaUseMax")
end

--- Sets the maximum number of uses.
-- @param value number
function entmeta:SetMateriaUseMax(value)
    self:SetNWInt("m_iMateriaUseMax", value)
end

--- Absolute time (CurTime based) until which the materia is on cooldown.
-- @return number
function entmeta:GetMateriaCooldown()
    return self:GetNWFloat("m_flMateriaCooldown")
end

--- Sets the absolute cooldown end time.
-- @param value number CurTime() + duration, or 0 to clear
function entmeta:SetMateriaCooldown(value)
    self:SetNWFloat("m_flMateriaCooldown", value)
end

--- Cooldown duration in seconds taken from the map config.
-- Stored separately so the cooldown can be re-applied on each use.
-- @return number
function entmeta:GetMateriaCooldownByConfig()
    return self:GetNWFloat("m_flMateriaCooldownByConfig")
end

--- Sets the config-defined cooldown duration.
-- @param value number seconds
function entmeta:SetMateriaCooldownByConfig(value)
    self:SetNWFloat("m_flMateriaCooldownByConfig", value)
end

--- Toggle state for counter-based materias (active/inactive).
-- @return boolean
function entmeta:GetMateriaState()
    return self:GetNWBool("m_bMateriaState")
end

--- Sets the toggle state for counter-based materias.
-- @param value boolean
function entmeta:SetMateriaState(value)
    self:SetNWBool("m_bMateriaState", value)
end
