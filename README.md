# EntWatch for Garry's Mod Zombie Escape
A custom addon for tracking special items ("materias") on ZE maps, with item
admin tools and a boss HP HUD.

## Adding a map config
Initial values can be taken from the
[NiDE-GG configs](https://github.com/NiDE-gg/ZE-Configs/tree/master/cstrike/addons/sourcemod/configs/entwatch/maps)
or found by searching the map for `"weapon_*"` (e.g. with Notepad++).

For `func_button`, `math_counter` and `pt_spawner` values you will have to
inspect the map sources (decompile the BSP or use the bundled `bsp.py`).

Find your materia by `hammerid`. Then, by `targetname`, locate either the
`point_template` that contains that targetname, or find the `func_button`
manually, take its `id` and write it into the config as `buttonid`.

The button has an `OnPressed` output that fires a `filter_activator_name`
(the first parameter is its `targetname`; search for it as well). Inside it
there is an `OnPass` output; find the button by name and check what happens
to it:
- If there is no `Unlock` there, or there is a `Kill`, the materia is single
  use (`["mode"] = ENTWATCH_MODE_LIMITED_USES`).
- If there is an `Unlock`, its 4th parameter is the cooldown. Write it into
  the config as `cooldown` (`["mode"] = ENTWATCH_MODE_COOLDOWNS` when there
  is no `math_counter`).

Also look carefully for any line whose 2nd parameter is `Add`, `Substract`
or `SetValue` and follow it. That is the `math_counter` (it may also live
inside a `point_template`, but not necessarily). Write its `id` into the
config as `energyid`, or its `targetname` as `energyname`.
- If it contains `OnHitMin`, set `["mode"] = ENTWATCH_MODE_COUNTER_FMIN_REACHED`.
- If it contains `OnHitMax`, set `["mode"] = ENTWATCH_MODE_COUNTER_FMAX_REACHED`.
- Optionally copy `startvalue`, `min` and `max` into the config as well.
- As a shortcut, these values can be written into `maxuses` with
  `["mode"] = ENTWATCH_MODE_LIMITED_USES` instead.

Everything else that can be configured is described in `template.lua`.

## How it works (briefly)
During map initialization three hooks are used:

### InitPostEntityMap
Clears the cached entities on both the server and the client.

### EntityKeyValue
Early materia initialization. Entities are not fully initialized inside this
hook, so initialization is anchored to the `hammerid` keyvalue. For
`weapon_elite`: name, cooldown, number of uses. For `func_button`: little
besides linking the weapon to the button. For `math_counter`: initialization
of the shadowed variables used later.

### AcceptInput
The main hook, where everything needed to track `func_button` and
`math_counter` arrives. For `func_button`: `Use`, `Lock`, `Unlock` and
`Kill`. Here the number of uses can be limited and the cooldown raised or
lowered even when the map does not provide one (effects take extra work,
though). For `math_counter`: keeping the correct value.

> [!NOTE]
> A few finishing touches complete the tracking: weapon pickup, dropping via
> a command/bind, dropping on death, and changing the player's targetname
> (so that only the holder can use the materia).

### WeaponEquip
A player picks the materia up. If the materia was not linked to its
`func_button` and/or `math_counter` during `EntityKeyValue`, the link is
made here. The player's name is changed so they can use the materia.
> [!CAUTION]
> Is this still needed? `weapon_map_base` could implement a `KeyValue`
> method and fire `ent:TriggerOutput("OnPlayerPickup", ply)` instead.
> Just remember to reset the player's name on drop.
```
function ENT:KeyValue(k, v)
    -- 99% of all outputs are named 'OnSomethingHappened'.
    if string.Left(k, 2) == "On" then
        self:StoreOutput(k, v)
    end
end
```

### PlayerDroppedWeapon
A player drops the materia, alive or on death. The name is reset and the
client is told to stop tracking this materia.

### NET MESSAGES
The server accepts a single command: a request for the list of materias to
track.
The client side handles: clearing the whole list, adding and removing a
materia.

## Boss HP HUD
Boss configs live in `lua/entwatch/bosses/<map>.lua`; see
`bosses/template.lua` for the three damage tracking methods (`breakable`,
`counter`, `hpbar`), trigger activation and timeouts.

## Admin commands (ULX)
`!ew_reloadconfig`, `!ew_spawnitem`, `!ew_transfer` - item management;
`!ew_ban`, `!ew_unban`, `!ew_unbanid`, `!ew_banlist` - item bans;
`!ew_lock`, `!ew_unlock`, `!ew_setuses`, `!ew_setcooldown` - live item edits.
