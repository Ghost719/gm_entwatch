--- Client HUD: boss health bars.
-- Panel based, mirroring cl_init: a parent panel (DEntWatchBoss) stacked
-- with one bar child (DEntWatchBossBar) per active boss, sized through
-- BetterScreenScale() so the layout holds on any resolution. Bars remove
-- themselves a few seconds after the boss dies or stops receiving updates.
-- @module entwatch.cl_boss

local HIDE_AFTER_DEATH = 4   -- seconds an empty bar stays visible after death
local HIDE_AFTER_IDLE  = 30  -- seconds without updates before the bar hides

local color_bg     = Color(0, 0, 0, 180)
local color_hp     = Color(200, 40, 40, 230)
local color_hp_lag = Color(255, 160, 40, 200) -- "trail" of recently lost HP
local color_text   = Color(255, 255, 255, 255)
local color_frame  = Color(255, 255, 255, 40)

-- ===================== SINGLE BOSS BAR =====================

local BAR = {}

function BAR:Init()
    self.shown_hp = 0
end

--- Configures the bar geometry for a boss.
-- Minibosses get a shorter, lower-profile bar with a smaller font.
-- @param uid number server-side boss uid
-- @param miniboss boolean miniboss flag from the config
function BAR:SetupBoss(uid, miniboss)
    self.m_uid  = uid
    self.m_mini = miniboss

    local ss = BetterScreenScale()
    self.Font  = miniboss and "ZSHUDFontSmallest" or "ZSHUDFontSmall"
    self.BarH  = math.ceil(ss * (miniboss and 14 or 20))
    -- BarW removed: width is fully driven by the container size. The parent's
    -- PerformLayout decides how wide each row is (full width for a regular
    -- boss, 60% for a solo miniboss, ~50% for paired minibosses).

    surface.SetFont(self.Font)
    local _, name_h = surface.GetTextSize("W")
    self.NameH = name_h

    -- full row height: name + gap + bar
    self:SetTall(self.NameH + math.ceil(ss * 2) + self.BarH)
end

--- Applies a server update.
-- Tracks the moment HP reached zero so the empty bar can linger briefly.
-- @param name string boss display name
-- @param hp number current HP
-- @param maxhp number maximum HP
function BAR:UpdateData(name, hp, maxhp)
    self.m_name  = name
    self.m_hp    = hp
    self.m_maxhp = math.max(maxhp, 1)
    self.m_last_update = CurTime()

    if hp <= 0 and not self.m_dead_at then
        self.m_dead_at = CurTime()
    elseif hp > 0 then
        self.m_dead_at = nil
    end
end

--- Self-removal: shortly after death, or after a long period without
-- updates (the fight moved on elsewhere on the map).
function BAR:Think()
    local now = CurTime()
    if (self.m_dead_at and now - self.m_dead_at > HIDE_AFTER_DEATH)
    or (self.m_last_update and now - self.m_last_update > HIDE_AFTER_IDLE) then
        local parent = self:GetParent()
        self:Remove()
        if IsValid(parent) then parent:InvalidateLayout() end
    end
end

--- Draws the boss name, the HP bar with a damage trail and the numbers.
function BAR:Paint(w, h)
    local hp, maxhp = self.m_hp or 0, self.m_maxhp or 1
    local frac = math.Clamp(hp / maxhp, 0, 1)

    -- displayed HP smoothly catches up with the real value
    -- ("chunk being removed" effect)
    if self.shown_hp > hp then
        self.shown_hp = math.max(hp, self.shown_hp - maxhp * FrameTime() * 0.6)
    else
        self.shown_hp = hp
    end
    local shown_frac = math.Clamp(self.shown_hp / maxhp, 0, 1)

    -- the bar fills the container; sizing is the parent panel's job
    local bw = w
    local bx = 0
    local by = h - self.BarH

    draw.SimpleText(self.m_name or "Boss", self.Font, w * 0.5, by - 2, color_text,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)

    surface.SetDrawColor(color_bg)
    surface.DrawRect(bx, by, bw, self.BarH)

    if shown_frac > frac then
        surface.SetDrawColor(color_hp_lag)
        surface.DrawRect(bx + 2, by + 2, (bw - 4) * shown_frac, self.BarH - 4)
    end

    surface.SetDrawColor(color_hp)
    surface.DrawRect(bx + 2, by + 2, (bw - 4) * frac, self.BarH - 4)

    surface.SetDrawColor(color_frame)
    surface.DrawOutlinedRect(bx, by, bw, self.BarH, 1)

    draw.SimpleText(string.format("%d / %d", math.max(hp, 0), maxhp),
        "ZSHUDFontSmallest", w * 0.5, by + self.BarH * 0.5, color_text,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    return true
end
vgui.Register("DEntWatchBossBar", BAR, "DPanel")

-- ===================== PARENT PANEL =====================

local PANEL = {}

--- Finds the bar for a boss uid.
-- @param uid number server-side boss uid
-- @return Panel|nil
function PANEL:GetBar(uid)
    for _, panel in ipairs(self:GetChildren()) do
        if panel.m_uid == uid then return panel end
    end
end

--- Creates or updates the bar for a boss.
-- @param uid number server-side boss uid
-- @param name string boss display name
-- @param hp number current HP
-- @param maxhp number maximum HP
-- @param miniboss boolean miniboss flag
function PANEL:UpdateBoss(uid, name, hp, maxhp, miniboss)
    local bar = self:GetBar(uid)
    if not bar then
        bar = vgui.Create("DEntWatchBossBar", self)
        bar:SetupBoss(uid, miniboss)
        bar.shown_hp = hp
        self:InvalidateLayout()
    end
    bar:UpdateData(name, hp, maxhp)
end

--- Removes the bar for a boss uid, if present.
-- @param uid number server-side boss uid
function PANEL:RemoveBoss(uid)
    local bar = self:GetBar(uid)
    if bar then
        bar:Remove()
        self:InvalidateLayout()
    end
end

--- Removes every bar (round restart).
function PANEL:ClearBosses()
    for _, panel in ipairs(self:GetChildren()) do
        panel:Remove()
    end
    self:InvalidateLayout()
end

--- Stacks bars top-down with a screen-scaled padding between them.
--- Manual layout instead of Dock(TOP):
-- regular boss -> full-width row
-- two consecutive minibosses -> one row, split half-half with a small gap
-- one miniboss (no neighbor or neighbor is a regular boss) -> centered solo,
-- 60% width so it visually reads as a miniboss even alone.
function PANEL:PerformLayout(w, h)
    local ss = BetterScreenScale()
    local pad = math.ceil(ss * 6) -- vertical gap between rows
    local gap = math.ceil(ss * 8) -- horizontal gap inside a paired row

    local children = self:GetChildren()
    local y = 0
    local i = 1
    while i <= #children do
        local a = children[i]
        local b = children[i + 1]

        if a.m_mini and b and b.m_mini then
            -- Paired row: two minibosses share the width
            local half = math.floor((w - gap) * 0.5)
            local row_h = math.max(a:GetTall(), b:GetTall())
            a:SetSize(half, row_h)
            a:SetPos(0, y)
            b:SetSize(w - half - gap, row_h)
            b:SetPos(half + gap, y)
            y = y + row_h + pad
            i = i + 2
        elseif a.m_mini then
            -- Solo miniboss: 60% width, centered
            local bw = math.floor(w * 0.6)
            a:SetSize(bw, a:GetTall())
            a:SetPos(math.floor((w - bw) * 0.5), y)
            y = y + a:GetTall() + pad
            i = i + 1
        else
            -- Regular boss: full width
            a:SetSize(w, a:GetTall())
            a:SetPos(0, y)
            y = y + a:GetTall() + pad
            i = i + 1
        end
    end
end

function PANEL:Paint(w, h)
    return true
end
vgui.Register("DEntWatchBoss", PANEL, "DPanel")

-- ===================== NETWORKING / INITIALIZATION =====================

-- Protocol (cmd, 4 bits):
--   0 = reset: drop every bar
--   1 = update: uid (uint8), name (string), hp/maxhp (float), miniboss (bool)
--   2 = remove: drop the bar for uid (uint8)
net.Receive("entwatch_boss", function()
    if not IsValid(EntWatch.BossPanel) then return end

    local cmd = net.ReadUInt(4)
    if cmd == 0 then
        EntWatch.BossPanel:ClearBosses()
        return
    end

    local uid = net.ReadUInt(8)
    if cmd == 1 then
        local name     = net.ReadString()
        local hp       = net.ReadFloat()
        local maxhp    = net.ReadFloat()
        local miniboss = net.ReadBool()

        EntWatch.BossPanel:UpdateBoss(uid, name, hp, maxhp, miniboss)
    elseif cmd == 2 then
        EntWatch.BossPanel:RemoveBoss(uid)
        return
    end
end)

--- (Re)creates the boss HUD panel, top-centered on the screen.
function EntWatch.BossInitialize()
    if IsValid(EntWatch.BossPanel) then EntWatch.BossPanel:Remove() end

    local ss = BetterScreenScale()
    local w = math.min(ScrW() * 0.4, ss * 640)

    EntWatch.BossPanel = vgui.Create("DEntWatchBoss")
    EntWatch.BossPanel:SetAlpha(235)
    EntWatch.BossPanel:SetSize(w, ScrH() * 0.4)
    EntWatch.BossPanel:SetPos((ScrW() - w) * 0.5, ScrH() * 0.18)
    EntWatch.BossPanel:ParentToHUD()
end
hook.Add("InitPostEntity", "EntWatch.BossInitialize", EntWatch.BossInitialize)