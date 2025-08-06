local PANEL = {}

local color_red = Color(255, 0, 0, 255)
local color_green = Color(0, 255, 0, 255)
local color_yellow = Color(255, 200, 0, 255)

function PANEL:Init()
    self.Font = "ZSHUDFontSmall"
    self:InvalidateLayout()
end

function PANEL:AddMateria(ent)
    for _, panel in ipairs(self:GetChildren()) do
        if panel.m_Entity == ent then
            return
        end
    end

    local dlabel = vgui.Create("DLabel", self)
    dlabel.m_Entity = ent
    dlabel.Paint = self.PaintMateria
    dlabel:SetFont(self.Font)

    self:InvalidateLayout()
end

function PANEL:RemoveMateria(ent)
    for _, panel in ipairs(self:GetChildren()) do
        if panel.m_Entity == ent then
            panel:Remove()
            break
        end
    end

    self:InvalidateLayout()
end

function PANEL:ClearMaterias()
    for _, panel in ipairs(self:GetChildren()) do
        panel:Remove()
    end

    self:InvalidateLayout()
end

function PANEL:SetTextFont(font)
    self.Font = font

    for _, panel in ipairs(self:GetChildren()) do
        panel:SetFont(font)
    end

    self:InvalidateLayout()
end

function PANEL:PerformLayout(w, h)
    for _, panel in ipairs(self:GetChildren()) do
        panel:SetWide(self:GetWide())
        panel:SizeToContentsY()
        panel:DockPadding(8, 0, 8, 0)
        panel:Dock(TOP)
    end
end

function PANEL:PaintMateria(w, h)
    local ent = self.m_Entity
    if !ent or !ent:IsValid() then
        self:Remove()
        return true
    end

    local owner = ent:GetOwner()
    if !IsValid(owner) or LocalPlayer():Team() ~= owner:Team() then
        self:Remove()
        return true
    end

    local text, clr
    local name, mode = ent:GetMateriaShortname(), ent:GetMateriaMode()
    local current_time = CurTime()

    if mode ~= ENTWATCH_MODE_NOBUTTON then
        local cooldown = ent:GetMateriaCooldown()
        local usesleft = ent:GetMateriaUseCount()
        local maxuses = ent:GetMateriaUseMax()

        if current_time < cooldown and !(mode == ENTWATCH_MODE_LIMITED_USES and maxuses > 1 and usesleft == 0) then
            text = string.format("%s[%i]: %s", name, math.floor(cooldown - current_time), owner:Nick())
            clr = color_yellow
        elseif maxuses > 1 and usesleft > 0 then
            text = string.format("%s[%i/%i]: %s", name, usesleft, maxuses, owner:Nick())
            clr = ent:GetMateriaState() and color_yellow or color_green
        elseif usesleft > 0 then
            text = string.format("%s[R]: %s", name, owner:Nick())
            clr = color_green
        else
            text = string.format("%s[E]: %s", name, owner:Nick())
            clr = color_red
        end
    else
        text = string.format("%s[+]: %s", name, owner:Nick())
        clr = color_green
    end

    draw.SimpleText(text, self:GetFont(), 0, 0, clr)
    return true
end

function PANEL:Paint(w, h)
    return true
end
vgui.Register("DEntWatch", PANEL, "DPanel")

net.Receive("entwatch", function(len, ply)
    if !EntWatch.Panel then return end

    local cmd = net.ReadUInt(8)

    if cmd == 1 then
        EntWatch.Panel:ClearMaterias()

        if net.ReadUInt(8) > 0 then
            net.Start("entwatch")
            net.WriteUInt(1, 8)
            net.SendToServer()
        end
    elseif cmd == 2 then
        local ent = net.ReadEntity()
        EntWatch.Panel:AddMateria(ent)
    elseif cmd == 3 then
        local ent = net.ReadEntity()
        EntWatch.Panel:RemoveMateria(ent)
    end
end)

function EntWatch.Initialize()
    if EntWatch.Panel then EntWatch.Panel:Remove() end

    local screenscale = BetterScreenScale()
    EntWatch.Panel = vgui.Create("DEntWatch")
    EntWatch.Panel:SetTextFont("ZSHUDFontSmallest")
    EntWatch.Panel:SetAlpha(220)
    EntWatch.Panel:SetPos(ScrW() * 0.04, ScrH() * 0.2)
    EntWatch.Panel:SetSize(screenscale * 360, screenscale * 560)
    EntWatch.Panel:ParentToHUD()

    net.Start("entwatch")
    net.WriteUInt(1, 8)
    net.SendToServer()
end
hook.Add("Initialize", "EntWatch.Initialize", EntWatch.Initialize)