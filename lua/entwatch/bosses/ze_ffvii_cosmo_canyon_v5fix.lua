return {
    -- Normal, Hard, Extreme
    {
        ["name"] = "Gi Nattak",
        ["method"] = "hpbar",
        ["trigger"] = "Gi_Nattak_Spawner:OnEntitySpawned",

        ["counterid"] = 2305805,
        ["countername"] = "Special_Health",

        ["backupid"] = 2305799,
        ["backupname"] = "Special_HealthInit",

        ["iteratorid"] = 2305807,
        ["iteratorname"] = "Special_HealthCount",

        ["mode"] = ENTWATCH_MODE_COUNTER_FMAX_REACHED,
        ["killtimer"] = 125,
    },

    -- Hard
    {
        ["name"] = "Bomb",
        ["method"] = "counter",
        ["trigger"] = "Hard_End:OnTrigger",

        ["counterid"] = 370349,
        ["countername"] = "lvl2_Gi_Nattak_Counter",
    },

    -- Extreme
    {
        ["name"] = "Ifrit",
        ["method"] = "counter",
        ["trigger"] = "Hojo_Temp:OnEntitySpawned",

        ["counterid"] = 370349,
        ["countername"] = "lvl2_Gi_Nattak_Counter",
    },

    -- Rage
    {
        ["name"] = "Genesis",
        ["method"] = "hpbar",
        ["trigger"] = "Ifrit_Fail_Relay:OnTrigger",

        ["counterid"] = 2305805,
        ["countername"] = "Special_Health",

        ["backupid"] = 2305799,
        ["backupname"] = "Special_HealthInit",

        ["iteratorid"] = 2305807,
        ["iteratorname"] = "Special_HealthCount",

        ["mode"] = ENTWATCH_MODE_COUNTER_FMAX_REACHED,
        ["killtimer"] = 145,
    },

    -- Rage
    {
        ["name"] = "Ifrit",
        ["method"] = "counter",
        ["trigger"] = "Shinra_Ifrit_Phys:OnHealthChanged",
        ["timeout"] = 3,

        ["counterid"] = 4736841,
        ["countername"] = "Shinra_Ifrit_Counter",

        ["miniboss"] = true,
    },

    -- Rage
    {
        ["name"] = "Jenova",
        ["method"] = "counter",
        ["trigger"] = "Shinra_Jenova_Phys:OnHealthChanged",
        ["timeout"] = 3,

        ["counterid"] = 4736855,
        ["countername"] = "Shinra_Jenova_Counter",

        ["miniboss"] = true,
    },

    -- Rage
    {
        ["name"] = "Shiva",
        ["method"] = "counter",
        ["trigger"] = "Shinra_Shiva_Phys:OnHealthChanged",
        ["timeout"] = 3,

        ["counterid"] = 4736863,
        ["countername"] = "Shinra_Shiva_Counter",

        ["miniboss"] = true,
    },

    -- Rage
    {
        ["name"] = "Genesis",
        ["method"] = "counter",
        ["trigger"] = "Genesis_Temp:OnEntitySpawned",

        ["counterid"] = 1046021,
        ["countername"] = "Genesis_Counter",
    },
}