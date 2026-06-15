--- Boss config template.
-- File name must match the map: lua/entwatch/bosses/<map>.lua
-- Finding ids/targetnames follows the same workflow as for materias
-- (bsp.py / map decompilation / lua_run).

return {
    -- ============ trigger / timeout (any method) ============
    -- ["trigger"] = "EntityName:Output" - the bar only appears after the
    --   trigger fires. Same format as the NiDE BossHP configs.
    --   Outputs are hooked directly via AddOutput on the entity, so any
    --   real output of that entity works (OnUser1..4, OnTrigger,
    --   OnStartTouch, OnHealthChanged, ...). Make sure the referenced
    --   entity actually has that output on THIS port of the map.
    --   Triggers are mandatory when several bosses share the same counter
    --   names (Scorpion/Bahamut on mako v6) - the boss whose trigger fired
    --   last is the active one.
    -- ["timeout"] = N - hide the bar when the boss saw no trigger or damage
    --   activity for N seconds (alternating phase fights).
    -- Without a trigger the bar appears on the first damage/counter change.
    -- ["miniboss"] = true - draw a shorter, lower-profile bar.

    -- ============ METHOD 1: breakable ============
    -- func_breakable, func_physbox and similar entities with plain HP.
    -- Any weapon damages it directly; tracked via PostEntityTakeDamage.
    {
        ["name"]            = "Scorpion",
        ["method"]          = "breakable",

        -- entity identification (id takes priority)
        ["breakableid"]     = 503736,               -- hammerid
        ["breakablename"]   = "Monstruo_Breakable", -- targetname

        -- bar maximum; 0 or nil = captured on first damage
        -- (Health() + damage taken); set it explicitly when the map adds
        -- health during the fight via AddHealth
        ["maxhp"]           = 8000,
    },

    -- ============ METHOD 2: counter ============
    -- Hit based, one math_counter. The core already tracks its value.
    {
        ["name"]        = "Bahamut",
        ["method"]      = "counter",

        ["counterid"]   = 2710,            -- math_counter hammerid
        ["countername"] = "bahamut_vida",  -- targetname

        -- FMIN (default): HP = current counter value, death on min
        -- FMAX: HP = max - current value, death on max
        ["mode"]        = ENTWATCH_MODE_COUNTER_FMIN_REACHED,
    },

    -- ============ METHOD 3: hpbar ============
    -- Hit based, THREE math_counters:
    --   counter  - current HP of one segment (mutable); signals backup on 0
    --   backup   - constant: HP per segment; refills counter to its own
    --              value and decreases iterator by 1
    --   iterator - number of segments left; the boss dies when it reaches 0
    -- Resulting formula: hp = (iterator - 1) * backup + counter
    -- Maximum: initial iterator * backup
    {
        ["name"]         = "Bahamut",
        ["method"]       = "hpbar",

        ["trigger"]      = "Boss_Bahamut_Relay:OnUser1", -- activation (see the file header)

        ["counterid"]    = 2474996,         -- segment HP counter
        ["countername"]  = "HPCounter",

        ["backupid"]     = 2474994,         -- per-segment HP constant
        ["backupname"]   = "HPCounterBackUp",

        ["iteratorid"]   = 2474992,         -- segment counter
        ["iteratorname"] = "HPCounterIterator",

        -- optional: explicit basehp for when the backup counter cannot be
        -- located or holds an unrelated value; takes priority over backup
        -- ["basehp"] = 580,
    },
}
