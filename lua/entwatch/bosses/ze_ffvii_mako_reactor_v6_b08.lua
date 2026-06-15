return {
    -- Easy, Normal, Hard: Scorpion
    {
        ["name"] = "Scorpion",
        ["method"] = "hpbar",
        ["trigger"] = "Boss_Scorpion_Relay:OnUser1",

        ["counterid"] = 2474996,
        ["countername"] = "HPCounter",

        ["backupid"] = 2474994,
        ["backupname"] = "HPCounterBackUp",

        ["iteratorid"] = 2474992,
        ["iteratorname"] = "HPCounterIterator",
    },

    -- Extreme, Insane: Bahamut
    {
        ["name"] = "Bahamut",
        ["method"] = "hpbar",
        ["trigger"] = "Boss_Bahamut_Relay:OnUser1",

        ["counterid"] = 2474996,
        ["countername"] = "HPCounter",

        ["backupid"] = 2474994,
        ["backupname"] = "HPCounterBackUp",

        ["iteratorid"] = 2474992,
        ["iteratorname"] = "HPCounterIterator",
    },

    -- Insane: 2nd Bahamut @ Bridge
    {
        ["name"] = "Bahamut",
        ["method"] = "breakable",
        ["trigger"] = "Sephiroth_Final_HP_Counter:OnStartTouch",

        ["breakableid"] = 3994669,
        ["breakablename"] = "Final_Fulgor_Breakable",
    },

    -- Insane: Sephiroph @ Bridge
    {
        ["name"] = "Bahamut",
        ["method"] = "breakable",
        ["trigger"] = "Sephiroth_Final_HP_Counter:OnTrigger",
        ["timeout"] = 1,

        ["breakableid"] = 3655561,
        ["breakablename"] = "Sephiroth_Final_Breakable",
    },
}