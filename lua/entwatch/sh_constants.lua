--- Shared constants: materia modes and entity class lookup tables.
-- @module entwatch.sh_constants

-- Materia operating modes. Determined by what is parented to the weapon:
-- a button, a counter, or nothing at all.
ENTWATCH_MODE_NOBUTTON = 0              -- no usable button; passive/trigger item
ENTWATCH_MODE_SPAM_PROTECTION_ONLY = 1  -- button with a minimal anti-spam delay only
ENTWATCH_MODE_COOLDOWNS = 2             -- button with a real cooldown between uses
ENTWATCH_MODE_LIMITED_USES = 3          -- button with a limited number of uses
ENTWATCH_MODE_COUNTER_FMIN_REACHED = 4  -- math_counter based; depleted when it hits min
ENTWATCH_MODE_COUNTER_FMAX_REACHED = 5  -- math_counter based; depleted when it hits max

--- CS:S weapon classes that can host a materia config.
-- Used as a fast set: ENTWATCH_CSSWEAPONS[class] == true.
ENTWATCH_CSSWEAPONS = {
    ["weapon_knife"] = true,
    ["weapon_glock"] = true,
    ["weapon_usp"] = true,
    ["weapon_p228"] = true,
    ["weapon_deagle"] = true,
    ["weapon_elite"] = true,
    ["weapon_fiveseven"] = true,
    ["weapon_m3"] = true,
    ["weapon_xm1014"] = true,
    ["weapon_galil"] = true,
    ["weapon_ak47"] = true,
    ["weapon_scout"] = true,
    ["weapon_sg552"] = true,
    ["weapon_awp"] = true,
    ["weapon_g3sg1"] = true,
    ["weapon_famas"] = true,
    ["weapon_m4a1"] = true,
    ["weapon_aug"] = true,
    ["weapon_sg550"] = true,
    ["weapon_mac10"] = true,
    ["weapon_tmp"] = true,
    ["weapon_mp5navy"] = true,
    ["weapon_ump45"] = true,
    ["weapon_p90"] = true,
    ["weapon_m249"] = true
}

--- Entity classes treated as "buttons" that can be parented to a materia.
ENTWATCH_BUTTON_CLASSNAMES = {
    ["func_button"] = true,
    ["func_rot_button"] = true,
    ["func_door"] = true,
    ["func_door_rotating"] = true,

    --["func_physbox_multiplayer"] = true,
    --["game_ui"] = true,
}