return {
    -- Normal mode: Scorpion
    {
        ["name"] = "Scorpion",
        ["method"] = "breakable",
        ["trigger"] = "calcVidaM:OnStartTouch",
        ["breakableid"] = 503736,
        ["breakablename"] = "Monstruo_Breakable",
    },

    -- Hard, Extreme, Extreme 2: Bahamut
    {
        ["name"] = "Bahamut",
        ["method"] = "counter",
        ["trigger"] = "calcVidaD:OnStartTouch",
        ["counterid"] = 2710,
        ["countername"] = "bahamut_vida",
        ["mode"] = ENTWATCH_MODE_COUNTER_FMIN_REACHED,
    },

    -- Hard, Extreme: Moving Sephiroph @ Bridge
    {
        ["name"] = "Sephiroph",
        ["method"] = "breakable",
        ["trigger"] = "puertafinal:OnStartTouch",
        ["breakableid"] = 3276,
        ["breakablename"] = "glassT",
    },

    -- Extreme 2: 2nd Bahamut @ Bridge
    {
        ["name"] = "Bahamut",
        ["method"] = "breakable",
        ["trigger"] = "baha_vida:OnStartTouch",
        ["breakableid"] = 3644,
        ["breakablename"] = "bahamutend",
    },

    -- Extreme 2: Sephiroph @ Bridge
    {
        ["name"] = "Sephiroph",
        ["method"] = "breakable",
        ["trigger"] = "baha_vida2:OnStartTouch",
        ["breakableid"] = 3666,
        ["breakablename"] = "bahamutend1",
    },
}