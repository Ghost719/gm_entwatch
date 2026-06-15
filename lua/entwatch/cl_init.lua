--- Client HUD: list of materias held by teammates.
-- One parent panel (DEntWatch) with one child row (DEntWatchMateria) per
-- tracked materia. Rows reference weapons by EntIndex instead of holding an
-- entity reference: an entity outside the client PVS resolves to NULL at
-- net.Receive time, but the row is merely hidden and comes back once the
-- entity is networked. Rows are removed only on explicit server commands.
-- @module entwatch.cl_init

local color_red    = Color(255, 0,   0,   255)
local color_green  = Color(0,   255, 0,   255)
local color_yellow = Color(255, 200, 0,   255)

-- ===================== SINGLE MATERIA ROW =====================

local MATERIA = {}

--- Stores the weapon EntIndex this row represents.
-- @param entindex number weapon entity index
function MATERIA:Setup(entindex)
    self.m_EntIndex = entindex
    self.m_Hidden = true
end

--- Sets the row font and caches the text height for layout.
-- @param font string font name
function MATERIA:SetTextFont(font)
    self.Font = font
    surface.SetFont(font)
    local _, th = surface.GetTextSize("W")
    self.TextH = th
end

--- Visibility management: the row is shown only while the weapon entity is
-- networked and held by a teammate. Transitions trigger a parent re-layout
-- so hidden rows stop taking vertical space.
function MATERIA:Think()
    local ent = Entity(self.m_EntIndex or 0)
    local show = false

    if IsValid(ent) then
        local owner = ent:GetOwner()
        show = IsValid(owner) and LocalPlayer():Team() == owner:Team()
    end

    if show ~= not self.m_Hidden then
        self.m_Hidden = not show
        local parent = self:GetParent()
        if IsValid(parent) then parent:InvalidateLayout() end
    end
end

--- Draws one "Name[state]: Owner" line.
-- State markers: [N] seconds of cooldown left, [x/y] uses left,
-- [R] ready, [E] empty, [+] passive item without a button.
function MATERIA:Paint(w, h)
    if self.m_Hidden then return true end

    local ent = Entity(self.m_EntIndex or 0)
    if not IsValid(ent) then return true end
    local owner = ent:GetOwner()
    if not IsValid(owner) then return true end

    local text, clr
    local name, mode = ent:GetMateriaShortname(), ent:GetMateriaMode()
    local current_time = CurTime()

    if mode ~= ENTWATCH_MODE_NOBUTTON then
        local cooldown = ent:GetMateriaCooldown()
        local usesleft = ent:GetMateriaUseCount()
        local maxuses  = ent:GetMateriaUseMax()

        if current_time < cooldown and not (mode == ENTWATCH_MODE_LIMITED_USES and maxuses > 1 and usesleft == 0) then
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

    draw.SimpleText(text, self.Font, 0, 0, clr)
    return true
end
vgui.Register("DEntWatchMateria", MATERIA, "DPanel")

-- ===================== PARENT PANEL =====================

local PANEL = {}

function PANEL:Init()
    self.Font = "ZSHUDFontSmall"
    self:InvalidateLayout()
end

--- Finds the row representing the given weapon index.
-- @param entindex number weapon entity index
-- @return Panel|nil
function PANEL:GetMateria(entindex)
    for _, panel in ipairs(self:GetChildren()) do
        if panel.m_EntIndex == entindex then return panel end
    end
end

--- Adds a row for a weapon index (no-op when one already exists).
-- @param entindex number weapon entity index
function PANEL:AddMateria(entindex)
    if self:GetMateria(entindex) then return end

    local materia = vgui.Create("DEntWatchMateria", self)
    materia:Setup(entindex)
    materia:SetTextFont(self.Font)

    self:InvalidateLayout()
end

--- Removes the row for a weapon index, if present.
-- @param entindex number weapon entity index
function PANEL:RemoveMateria(entindex)
    local materia = self:GetMateria(entindex)
    if materia then
        materia:Remove()
        self:InvalidateLayout()
    end
end

--- Removes every row.
function PANEL:ClearMaterias()
    for _, panel in ipairs(self:GetChildren()) do
        panel:Remove()
    end
    self:InvalidateLayout()
end

--- Changes the font of every existing and future row.
-- @param font string font name
function PANEL:SetTextFont(font)
    self.Font = font
    for _, panel in ipairs(self:GetChildren()) do
        panel:SetTextFont(font)
    end
    self:InvalidateLayout()
end

--- Stacks rows top-down; hidden rows collapse to zero height.
function PANEL:PerformLayout(w, h)
    for _, panel in ipairs(self:GetChildren()) do
        panel:SetTall(panel.m_Hidden and 0 or (panel.TextH or 0))
        panel:Dock(TOP)
        panel:DockMargin(8, 0, 8, 0)
    end
end

function PANEL:Paint(w, h)
    return true
end
vgui.Register("DEntWatch", PANEL, "DPanel")

-- ===================== NETWORKING / INITIALIZATION =====================

-- Protocol (cmd, uint8):
--   0 = clear the list
--   1 = add a row for the following EntIndex (uint16)
--   2 = remove the row for the following EntIndex (uint16)
net.Receive("entwatch", function(len, ply)
    if not IsValid(EntWatch.Panel) then return end

    local cmd = net.ReadUInt(8)
    if cmd == 0 then
        EntWatch.Panel:ClearMaterias()

        if net.ReadBool() == true then
            net.Start("entwatch")
            net.WriteUInt(0, 8)
            net.SendToServer()
        end
    elseif cmd == 1 then
        EntWatch.Panel:AddMateria(net.ReadUInt(16))
    elseif cmd == 2 then
        EntWatch.Panel:RemoveMateria(net.ReadUInt(16))
    end
end)

--- (Re)creates the HUD panel and requests the current materia list.
function EntWatch.Initialize()
    if IsValid(EntWatch.Panel) then EntWatch.Panel:Remove() end

    local screenscale = BetterScreenScale()
    EntWatch.Panel = vgui.Create("DEntWatch")
    EntWatch.Panel:SetTextFont("ZSHUDFontSmallest")
    EntWatch.Panel:SetAlpha(220)
    EntWatch.Panel:SetPos(ScrW() * 0.04, ScrH() * 0.2)
    EntWatch.Panel:SetSize(screenscale * 360, screenscale * 560)
    EntWatch.Panel:ParentToHUD()

    net.Start("entwatch")
    net.WriteUInt(0, 8)
    net.SendToServer()
end
hook.Add("InitPostEntity", "EntWatch.Initialize", EntWatch.Initialize)