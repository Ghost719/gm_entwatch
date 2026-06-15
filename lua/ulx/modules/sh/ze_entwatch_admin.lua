--- ULX commands: EntWatch admin actions.
-- Modeled after sm-plugin-entwatch-4: item bans (eban/eunban/ebanlist),
-- per-materia admin locks and live edits of uses/cooldown.
-- NOTE: the gamemode gate uses a prefix match, in sync with autorun/entwatch.lua.
-- @module ulx.ze_entwatch_admin
if string.sub(engine.ActiveGamemode(), 1, 14) ~= "zombiesurvival" then return end

local CATEGORY_NAME = "EntWatch"

-- !ew_ban <ply> <minutes, 0 = permanent> [reason]
function ulx.ew_ban(calling_ply, target_ply, minutes, reason)
    EntWatch.Ban(target_ply, minutes, IsValid(calling_ply) and calling_ply:Nick() or "console", reason)
    if minutes > 0 then
        ulx.fancyLogAdmin(calling_ply, "#A banned #T from using items for #i minute(s)", target_ply, minutes)
    else
        ulx.fancyLogAdmin(calling_ply, "#A permanently banned #T from using items", target_ply)
    end
end
local ew_ban = ulx.command(CATEGORY_NAME, "ulx ew_ban", ulx.ew_ban, "!ew_ban")
ew_ban:addParam{ type = ULib.cmds.PlayerArg }
ew_ban:addParam{ type = ULib.cmds.NumArg, min = 0, default = 0, hint = "minutes, 0 = permanent", ULib.cmds.optional, ULib.cmds.round }
ew_ban:addParam{ type = ULib.cmds.StringArg, hint = "reason", ULib.cmds.optional, ULib.cmds.takeRestOfLine }
ew_ban:defaultAccess(ULib.ACCESS_ADMIN)
ew_ban:help("Ban player from picking up/using map items")

-- !ew_unban <ply>
function ulx.ew_unban(calling_ply, target_ply)
    if EntWatch.Unban(target_ply) then
        ulx.fancyLogAdmin(calling_ply, "#A unbanned #T from item restrictions", target_ply)
    else
        ULib.tsayError(calling_ply, target_ply:Nick() .. " is not item-banned!", true)
    end
end
local ew_unban = ulx.command(CATEGORY_NAME, "ulx ew_unban", ulx.ew_unban, "!ew_unban")
ew_unban:addParam{ type = ULib.cmds.PlayerArg }
ew_unban:defaultAccess(ULib.ACCESS_ADMIN)
ew_unban:help("Remove item ban from online player")

-- !ew_unbanid <steamid64> - for offline players
function ulx.ew_unbanid(calling_ply, steamid)
    if not steamid:match("^%d+$") then
        ULib.tsayError(calling_ply, "Expected SteamID64 (digits only)!", true)
        return
    end
    if EntWatch.Unban(steamid) then
        ulx.fancyLogAdmin(calling_ply, "#A removed item ban from steamid #s", steamid)
    else
        ULib.tsayError(calling_ply, "This SteamID64 is not item-banned!", true)
    end
end
local ew_unbanid = ulx.command(CATEGORY_NAME, "ulx ew_unbanid", ulx.ew_unbanid)
ew_unbanid:addParam{ type = ULib.cmds.StringArg, hint = "steamid64" }
ew_unbanid:defaultAccess(ULib.ACCESS_ADMIN)
ew_unbanid:help("Remove item ban by SteamID64 (offline players)")

-- !ew_banlist - print the ban list to the caller's console
function ulx.ew_banlist(calling_ply)
    local count = 0
    for sid, ban in pairs(EntWatch.Bans) do
        count = count + 1
        local when = ban.expires == 0 and "permanent" or os.date("%Y-%m-%d %H:%M", ban.expires)
        local line = string.format("%s | until: %s | by: %s | %s", sid, when, ban.admin or "?", ban.reason or "")
        if IsValid(calling_ply) then calling_ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
    end
    local total = "Item bans total: " .. count
    if IsValid(calling_ply) then
        calling_ply:PrintMessage(HUD_PRINTCONSOLE, total)
        ULib.tsay(calling_ply, "Ban list printed to console (" .. count .. ")", true)
    else
        print(total)
    end
end
local ew_banlist = ulx.command(CATEGORY_NAME, "ulx ew_banlist", ulx.ew_banlist, "!ew_banlist")
ew_banlist:defaultAccess(ULib.ACCESS_ADMIN)
ew_banlist:help("Print item ban list to console")

-- !ew_lock <ply> / !ew_unlock <ply> - admin-lock the materia held by the target
local function SetLockOnTarget(calling_ply, target_ply, locked)
    local materia = EntWatch.GetHeldMateria(target_ply)
    if not materia then
        ULib.tsayError(calling_ply, target_ply:Nick() .. " doesn't have a materia!", true)
        return
    end
    EntWatch.SetMateriaLocked(materia, locked)
    ulx.fancyLogAdmin(calling_ply, "#A " .. (locked and "locked" or "unlocked") .. " the materia \"#s\" of #T",
        materia:GetMateriaName(), target_ply)
end

function ulx.ew_lock(calling_ply, target_ply)
    SetLockOnTarget(calling_ply, target_ply, true)
end
local ew_lock = ulx.command(CATEGORY_NAME, "ulx ew_lock", ulx.ew_lock, "!ew_lock")
ew_lock:addParam{ type = ULib.cmds.PlayerArg }
ew_lock:defaultAccess(ULib.ACCESS_ADMIN)
ew_lock:help("Lock the materia button held by player")

function ulx.ew_unlock(calling_ply, target_ply)
    SetLockOnTarget(calling_ply, target_ply, false)
end
local ew_unlock = ulx.command(CATEGORY_NAME, "ulx ew_unlock", ulx.ew_unlock, "!ew_unlock")
ew_unlock:addParam{ type = ULib.cmds.PlayerArg }
ew_unlock:defaultAccess(ULib.ACCESS_ADMIN)
ew_unlock:help("Unlock the materia button held by player")

-- !ew_setuses <ply> <num>
function ulx.ew_setuses(calling_ply, target_ply, num)
    local materia = EntWatch.GetHeldMateria(target_ply)
    if not materia then
        ULib.tsayError(calling_ply, target_ply:Nick() .. " doesn't have a materia!", true)
        return
    end
    materia:SetMateriaUseCount(num)
    if num > materia:GetMateriaUseMax() then
        materia:SetMateriaUseMax(num)
    end
    ulx.fancyLogAdmin(calling_ply, "#A set uses of \"#s\" to #i (#T)", materia:GetMateriaName(), num, target_ply)
end
local ew_setuses = ulx.command(CATEGORY_NAME, "ulx ew_setuses", ulx.ew_setuses, "!ew_setuses")
ew_setuses:addParam{ type = ULib.cmds.PlayerArg }
ew_setuses:addParam{ type = ULib.cmds.NumArg, min = 0, hint = "uses", ULib.cmds.round }
ew_setuses:defaultAccess(ULib.ACCESS_ADMIN)
ew_setuses:help("Set remaining uses of player's materia")

-- !ew_setcooldown <ply> <seconds> (0 resets the cooldown)
function ulx.ew_setcooldown(calling_ply, target_ply, seconds)
    local materia = EntWatch.GetHeldMateria(target_ply)
    if not materia then
        ULib.tsayError(calling_ply, target_ply:Nick() .. " doesn't have a materia!", true)
        return
    end
    materia:SetMateriaCooldown(seconds > 0 and (CurTime() + seconds) or 0)
    ulx.fancyLogAdmin(calling_ply, "#A set cooldown of \"#s\" to #i sec (#T)", materia:GetMateriaName(), seconds, target_ply)
end
local ew_setcooldown = ulx.command(CATEGORY_NAME, "ulx ew_setcooldown", ulx.ew_setcooldown, "!ew_setcooldown")
ew_setcooldown:addParam{ type = ULib.cmds.PlayerArg }
ew_setcooldown:addParam{ type = ULib.cmds.NumArg, min = 0, hint = "seconds", ULib.cmds.round }
ew_setcooldown:defaultAccess(ULib.ACCESS_ADMIN)
ew_setcooldown:help("Set current cooldown of player's materia (0 = reset)")
