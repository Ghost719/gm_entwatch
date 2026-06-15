--- Materia config template.
-- File name must match the map: lua/entwatch/maps/<map>.lua
-- The file returns an array of config entries, one per materia.
return {
    {
        -- chat / full display name
        ["name"] = "Ultima Materia",

        -- short name shown in the HUD list
        ["shortname"] = "Ultima",

        -- targetname temporarily assigned to the holder so map filters
        -- (filter_activator_name) accept them; lets a materia be used again
        -- after another player used and dropped it
        ["filtername"] = "Ultima_Owner",
        -- FIXME: is this still needed? "weapon_map_base" could implement
        --     function ENT:KeyValue(k, v)
        --         -- 99% of all outputs are named 'OnSomethingHappened'.
        --         if string.Left(k, 2) == "On" then
        --             self:StoreOutput(k, v)
        --         end
        --     end
        -- and then fire ent:TriggerOutput("OnPlayerPickup", ply).
        -- Just remember to reset the player name on drop.

        -- unique entity identifier
        -- find it in game: lua_run for _,ent in ents.Iterator() do if ENTWATCH_CSSWEAPON[ent:GetClass()] then print(ent, ent:GetName(), ent:GetInternalVariable("m_iHammerID")) end end
        -- or in the decompiled map (search for "weapon_elite"; the block contains an "id" field)
        ["hammerid"] = 323814,

        -- button entity class (may be omitted when it is a func_button)
        ["buttonclass"] = "func_button",

        -- the next two parameters are used to display the materia cooldown
        -- correctly; in code "buttonid" takes priority over "buttonname"
        -- "mode" - anything except ENTWATCH_MODE_NOBUTTON
        ["buttonid"] = 323816, -- "id" or "hammerid" or "m_iHammerID"
        ["buttonname"] = "Item_Ultima_Button", -- "targetname" in Hammer

        -- math_counter
        -- the next two parameters are used to display the remaining
        -- seconds/charges correctly (e.g. the flamethrower, or the electro
        -- materia on fapescape); in code "energyid" takes priority over
        -- "energyname", but "energyname" is usually the safer choice
        -- "mode" - only ENTWATCH_MODE_COUNTER_FMIN_REACHED and ENTWATCH_MODE_COUNTER_FMAX_REACHED
        ["energyid"] = 1023921, -- "id" or "hammerid" or "m_iHammerID"
        ["energyname"] = "flame_counter", -- "targetname" in Hammer

        -- entity mode
        -- ENTWATCH_MODE_NOBUTTON - placeholder, no usable button
        -- ENTWATCH_MODE_SPAM_PROTECTION_ONLY - also a placeholder; useful when only an
        --                           anti-spam delay is needed (or the real cooldown is unknown)
        -- ENTWATCH_MODE_COOLDOWNS - unlimited uses with a cooldown;
        --                           set "maxuses" when several uses fit between cooldowns
        -- ENTWATCH_MODE_LIMITED_USES - one or more uses per round;
        --                              set "maxuses" for multiple uses (default is 1);
        --                              set "cooldown" when the materia also has a cooldown;
        --                              for single-use cast materias (like Ultima) the cast
        --                              time is displayed as well
        -- ENTWATCH_MODE_COUNTER_FMIN_REACHED - driven by a math_counter; typically the
        --                                      flamethrower, or the electro materia on fapescape.
        --                                      A math_counter has three values: m_OutValue, m_flMin, m_flMax;
        --                                      in this mode the materia stops working when m_OutValue
        --                                      reaches m_flMin (usually 0, although maps vary);
        --                                      the values can be overridden with "currentvalue",
        --                                      "hitmin" and "hitmax" (the third one is normally left
        --                                      alone and expected to be 2000)
        -- ENTWATCH_MODE_COUNTER_FMAX_REACHED - driven by a math_counter; the rarest mode, but the
        --                                      number of uses can effectively change at runtime.
        --                                      Same three values; in this mode the materia stops
        --                                      working when m_OutValue reaches m_flMax;
        --                                      overridable with "currentvalue", "hitmin" and
        --                                      "hitmax" (the second one is normally left alone
        --                                      and expected to be 0)
        ["mode"] = ENTWATCH_MODE_LIMITED_USES,

        -- maximum number of uses before the cooldown starts
        -- only for ENTWATCH_MODE_COOLDOWNS and ENTWATCH_MODE_LIMITED_USES
        ["maxuses"] = 1,

        -- cooldown, or the cast/effect duration in seconds
        -- (the latter only for ENTWATCH_MODE_LIMITED_USES)
        ["cooldown"] = 15,

        -- currentvalue - value the math_counter spawns with
        -- hitmin - minimum value that triggers OnHitMin (ENTWATCH_MODE_COUNTER_FMIN_REACHED)
        -- hitmax - maximum value that triggers OnHitMax (ENTWATCH_MODE_COUNTER_FMAX_REACHED)
        ["currentvalue"] = 20,
        ["hitmin"] = 0,
        ["hitmax"] = 2000,
        -- quirks observed with counter modes on real maps:
        ---- on ze_fapescape_rote_v1_3f the heal materia has a single use
        ----     (currentvalue = 1, hitmin = 0, hitmax = 2), but on stage 3
        ----     extreme it gets two uses (currentvalue = 0, hitmin = 0, hitmax = 2)
        ---- on ze_ffvii_cosmo_canyon_v5fix the electro materia also runs through a
        ----     math_counter, but the map logic is inconsistent (currentvalue = 1,
        ----     hitmin = 0, hitmax = 3) and resets m_OutValue to 1 on every OnHitMax,
        ----     which makes the values impractical to track - ENTWATCH_MODE_COOLDOWNS
        ----     is used instead
        ---- on ze_minecraft_adventure_v1_2c the "lighter" has 4 charges, 15 seconds of
        ----     effect and a 25 second cooldown, but is NOT driven by a math_counter,
        ----     so it is not tracked precisely

        -- env_entity_maker targetname, used to spawn the materia via ULX
        ["pt_spawner"] = "Item_Ultima_Temp",
    },
}
