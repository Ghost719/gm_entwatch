local entmeta = FindMetaTable "Entity"

function entmeta:SetHammerID(value)
    self.m_iHammerID = value
end

function entmeta:GetHammerID()
    return self.m_iHammerID or self:GetInternalVariable("m_iHammerID")
end

function entmeta:IsLocked()
    return self:GetInternalVariable("m_bLocked")
end

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

AccessorFunc(entmeta, "m_MateriaConfig", "MateriaConfig")
AccessorFunc(entmeta, "m_MateriaParent", "MateriaParent")
AccessorFunc(entmeta, "m_MateriaParentButton", "MateriaButton")
AccessorFunc(entmeta, "m_MateriaParentCounter", "MateriaCounter")

function entmeta:IsMateria()
    return self:GetNWBool("m_bMateria") == true
end

function entmeta:SetMateria(value)
    self:SetNWBool("m_bMateria", value)
end

function entmeta:GetMateriaName()
    return self:GetNWString("m_sMateriaName", self.GetName and self:GetName() or self.PrintName)
end

function entmeta:SetMateriaName(value)
    self:SetNWString("m_sMateriaName", value)
end

function entmeta:GetMateriaShortname()
    return self:GetNWString("m_sMateriaShortname", self:GetMateriaName())
end

function entmeta:SetMateriaShortname(value)
    self:SetNWString("m_sMateriaShortname", value)
end

function entmeta:GetMateriaMode()
    return self:GetNWInt("m_iMateriaMode", ENTWATCH_MODE_NOBUTTON)
end

function entmeta:SetMateriaMode(value)
    self:SetNWInt("m_iMateriaMode", value)
end

function entmeta:GetMateriaUseCount()
    return self:GetNWInt("m_iMateriaUseCount")
end

function entmeta:SetMateriaUseCount(value)
    self:SetNWInt("m_iMateriaUseCount", value)
end

function entmeta:GetMateriaUseMax()
    return self:GetNWInt("m_iMateriaUseMax")
end

function entmeta:SetMateriaUseMax(value)
    self:SetNWInt("m_iMateriaUseMax", value)
end

function entmeta:GetMateriaCooldown()
    return self:GetNWFloat("m_flMateriaCooldown")
end

function entmeta:SetMateriaCooldown(value)
    self:SetNWFloat("m_flMateriaCooldown", value)
end

function entmeta:GetMateriaCooldownByConfig()
    return self:GetNWFloat("m_flMateriaCooldownByConfig")
end

function entmeta:SetMateriaCooldownByConfig(value)
    self:SetNWFloat("m_flMateriaCooldownByConfig", value)
end

function entmeta:GetMateriaState()
    return self:GetNWBool("m_bMateriaState")
end

function entmeta:SetMateriaState(value)
    self:SetNWBool("m_bMateriaState", value)
end
