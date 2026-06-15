return {
    -- Easy: Scorpion
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

    -- Normal, Hard: Bahamut
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

    -- Normal
    {
        ["name"] = "Sephiroph",
        ["method"] = "breakable",
        ["trigger"] = "Seph_Bridge_Path_3:OnPass",

        ["breakableid"] = 3653695,
        ["breakablename"] = "Sephiroth_Bridge_Breakable",
    },

    -- Hard: 2nd Bahamut @ Bridge
    {
        ["name"] = "Bahamut",
        ["method"] = "counter",
        ["trigger"] = "Sephiroth_Final_HP_Trigger:OnStartTouch",
        ["timeout"] = 3,

        ["counterid"] = 6297250,
        ["countername"] = "Final_Fulgor_Counter_HP",
    },

    -- Hard: Sephiroph @ Bridge
    {
        ["name"] = "Sephiroph",
        ["method"] = "counter",
        ["trigger"] = "Final_Fulgor_Breakable:OnBreak",
        ["timeout"] = 7,

        ["counterid"] = 6297515,
        ["countername"] = "Sephiroth_Final_HP_Counter",
    },
}