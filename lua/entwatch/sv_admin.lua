--- Server admin core: materia usage bans and admin locks.
-- Equivalent of "eban" from sm-plugin-entwatch-4: banned players cannot pick
-- up or use materias. Bans are persisted in the server SQLite database
-- (sv.db) and expire automatically. Also exposes the API consumed by the
-- ULX commands in ze_entwatch_admin.lua.
-- @module entwatch.sv_admin

EntWatch.Bans = EntWatch.Bans or {} -- cache: [steamid64] = { expires, admin, reason }
sql.Query([[
    CREATE TABLE IF NOT EXISTS entwatch_bans (
        steamid TEXT PRIMARY KEY,
        expires INTEGER NOT NULL,
        admin   TEXT,
        reason  TEXT,
        created INTEGER
    )
]])

local function LoadBans()
    EntWatch.Bans = {}
    local rows = sql.Query("SELECT * FROM entwatch_bans") or {}
    local now = os.time()
    for _, row in ipairs(rows) do
        local expires = tonumber(row.expires) or 0
        if expires ~= 0 and expires <= now then
            sql.Query("DELETE FROM entwatch_bans WHERE steamid = " .. sql.SQLStr(row.steamid))
        else
            EntWatch.Bans[row.steamid] = {
                expires = expires,
                admin   = row.admin,
                reason  = row.reason,
            }
        end
    end
end
LoadBans()

--- Whether a player is item-banned. Expired bans are removed lazily here.
-- @param ply_or_sid Player|string player object or SteamID64 string
-- @return boolean banned
-- @return table|nil ban record when banned
function EntWatch.IsBanned(ply_or_sid)
    local sid = isstring(ply_or_sid) and ply_or_sid or ply_or_sid:SteamID64()
    if not sid then return false end

    local ban = EntWatch.Bans[sid]
    if not ban then return false end

    if ban.expires ~= 0 and ban.expires <= os.time() then
        EntWatch.Unban(sid)
        return false
    end
    return true, ban
end

--- Bans a player from picking up and using materias.
-- When the target is online, their materias are stripped immediately.
-- @param ply_or_sid Player|string player object or SteamID64 string
-- @param minutes number ban length; <= 0 means permanent
-- @param admin_name string|nil who issued the ban (for the ban list)
-- @param reason string|nil free-form reason
-- @return boolean true on success
function EntWatch.Ban(ply_or_sid, minutes, admin_name, reason)
    local sid = isstring(ply_or_sid) and ply_or_sid or ply_or_sid:SteamID64()
    if not sid then return false end

    minutes = tonumber(minutes) or 0
    local expires = minutes > 0 and (os.time() + math.floor(minutes * 60)) or 0

    EntWatch.Bans[sid] = {
        expires = expires,
        admin   = admin_name or "console",
        reason  = reason or "",
    }
    sql.Query(string.format(
        "REPLACE INTO entwatch_bans (steamid, expires, admin, reason, created) VALUES (%s, %d, %s, %s, %d)",
        sql.SQLStr(sid), expires, sql.SQLStr(admin_name or "console"), sql.SQLStr(reason or ""), os.time()
    ))

    -- if the player is online, take their materias away right now
    if not isstring(ply_or_sid) and IsValid(ply_or_sid) then
        EntWatch.StripMaterias(ply_or_sid)
    else
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID64() == sid then
                EntWatch.StripMaterias(ply)
                break
            end
        end
    end

    return true
end

--- Removes an item ban.
-- @param ply_or_sid Player|string player object or SteamID64 string
-- @return boolean true when a ban existed and was removed
function EntWatch.Unban(ply_or_sid)
    local sid = isstring(ply_or_sid) and ply_or_sid or ply_or_sid:SteamID64()
    if not sid then return false end
    local existed = EntWatch.Bans[sid] ~= nil
    EntWatch.Bans[sid] = nil
    sql.Query("DELETE FROM entwatch_bans WHERE steamid = " .. sql.SQLStr(sid))
    return existed
end

--- Drops every materia weapon the player is holding.
-- @param ply Player
function EntWatch.StripMaterias(ply)
    if not IsValid(ply) then return end
    for _, wep in ipairs(ply:GetWeapons()) do
        if ENTWATCH_CSSWEAPONS[wep:GetClass()] and wep:IsMateria() then
            ply:DropWeapon(wep)
        end
    end
end

--- Returns the materia weapon currently held by the player, if any.
-- @param ply Player
-- @return Entity|nil materia weapon
function EntWatch.GetHeldMateria(ply)
    if not IsValid(ply) then return nil end
    for _, wep in ipairs(ply:GetWeapons()) do
        if ENTWATCH_CSSWEAPONS[wep:GetClass()] and wep:IsMateria() then
            return wep
        end
    end
    return nil
end

--- Admin lock: the materia button stops reacting to Use entirely.
-- Implemented as a flag checked by the AcceptInput hook below, because the
-- core would auto-Unlock a plainly locked button while uses remain.
-- @param weapon Entity materia weapon
-- @param locked boolean
-- @return boolean true when the weapon was valid
function EntWatch.SetMateriaLocked(weapon, locked)
    if not IsValid(weapon) then return false end
    weapon.m_EWAdminLocked = locked and true or nil
    return true
end

-- Enforcement: banned players cannot pick a materia up.
hook.Add("PlayerCanPickupWeapon", "EntWatch.BanPickup", function(ply, wep)
    if not ENTWATCH_CSSWEAPONS[wep:GetClass()] then return end
    if not wep:IsMateria() then return end
    if EntWatch.IsBanned(ply) then return false end
end)

-- Enforcement: suppress button Use for admin-locked materias and for
-- banned activators (covers materias already in hand).
hook.Add("AcceptInput", "EntWatch.AdminAcceptInput", function(ent, input, activator)
    if not ENTWATCH_BUTTON_CLASSNAMES[ent:GetClass()] then return end

    local parent = ent:GetMateriaParent()
    if not parent or not parent:IsValid() then return end
    if input:lower() ~= "use" then return end

    if parent.m_EWAdminLocked then return true end

    if IsValid(activator) and activator:IsPlayer() and EntWatch.IsBanned(activator) then
        return true
    end
end)

-- Safety net: a banned player managed to grab a materia bypassing the
-- pickup hook (forced PickupWeapon and similar) - drop it back.
hook.Add("WeaponEquip", "EntWatch.BanEquipCheck", function(weapon, owner)
    timer.Simple(0, function()
        if not IsValid(weapon) or not IsValid(owner) then return end
        if not ENTWATCH_CSSWEAPONS[weapon:GetClass()] then return end
        if weapon:IsMateria() and EntWatch.IsBanned(owner) then
            owner:DropWeapon(weapon)
        end
    end)
end)
