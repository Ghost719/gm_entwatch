return {
    {
        -- для чата
        ["name"] = "Ultima Materia",

         -- для отображения в HUD
        ["shortname"] = "Ultima",

        -- для корректного использования материи после дропа
        ["filtername"] = "Ultima_Owner",
        -- FIXME: а нужно ли? можно в "weapon_map_base" добавить метод по типу
        --     function ENT:KeyValue(k, v)
        --         -- 99% of all outputs are named 'OnSomethingHappened'.
        --         if string.Left(k, 2) == "On" then
        --             self:StoreOutput(k, v)
        --         end
        --     end
        -- а потом вызывать через ent:TriggerOutput("OnPlayerPickup", ply)
        -- главное не забыть при дропе ресетнуть имя игрока

        -- уникальный идентификатор для Энтити
        -- искать либо в самой игре: lua_run for _,ent in ents.Iterator() do if ENTWATCH_CSSWEAPON[ent:GetClass()] then print(ent, ent:GetName(), ent:GetInternalVariable("m_iHammerID")) end end
        -- либо через декомпилированную карту (ищешь по "weapon_elite", там внутри блока будет "id")
        ["hammerid"] = 323814,

        -- класс для кнопки (можно не добавлять в конфиг, если это func_button)
        ["buttonclass"] = "func_button",

        -- следующие два параметра используются для того, чтобы корректно отображать КД у материи
        -- в коде "buttonid" имеет приоритет над "buttonname"
        -- "mode" - любой, кроме ENTWATCH_MODE_NOBUTTON
        ["buttonid"] = 323816, -- "id" или "hammerid" или "m_iHammerID"
        ["buttonname"] = "Item_Ultima_Button", -- "targetname" в Hammer

        -- math_counter
        -- следующие два параметра используются для того, чтобы корректно отображать кол-во оставшихся секунд у материи, по типу огнемета или электро на fapescape
        -- в коде "energyid" имеет приоритет над "energyname", но лучше использовать "energyname"
        -- "mode" - только ENTWATCH_MODE_COUNTER_FMIN_REACHED и ENTWATCH_MODE_COUNTER_FMAX_REACHED
        ["energyid"] = 1023921, -- "id" или "hammerid" или "m_iHammerID"
        ["energyname"] = "flame_counter", -- "targetname" в Hammer

        -- режим для Энтити
        -- ENTWATCH_MODE_NOBUTTON - пустышка
        -- ENTWATCH_MODE_SPAM_PROTECTION_ONLY - тоже пустышка; можно использовать, если надо добавить КД (или лень разбираться, какое там КД у оружия)
        -- ENTWATCH_MODE_COOLDOWNS - материя имеет неограниченное количество использований и КД
        --                           если материя имеет несколько использований перед КД, то нужно выставить параметр "maxuses"
        -- ENTWATCH_MODE_LIMITED_USES - материя имеет одно или несколько использований за раунд
        --                              если материя имеет несколько использований, то выставляем параметр "maxuses" (по умолчанию стоит 1)
        --                              если материя имеет КД, то выставляем параметр "cooldown"
        --                              так же для материй по типу Ультимы будет отображаться время, которое оно кастуется (если одноразовая материя)
        -- ENTWATCH_MODE_COUNTER_FMIN_REACHED - материя работает через math_counter, обычно это огнемет на любой карте или электро на fapescape
        --                                      у math_counter если три значения: m_OutValue, m_flMin и m_flMax;
        --                                      для этого режима, когда значение m_OutValue достигает m_flMin (обычно 0, если маппер не гандон), то материя перестаёт работать;
        --                                      так же можно менять значения через параметры "currentvalue", "hitmin" и "hitmax" (3-й параметр обычно не трогаем, он должен быть равен 2000, если маппер не гандон)
        -- ENTWATCH_MODE_COUNTER_FMAX_REACHED - материя работает через math_counter, встречается реже всех, но зато можно "динамически" менять кол-во использований
        --                                      у math_counter если три значения: m_OutValue, m_flMin и m_flMax;
        --                                      для этого режима, когда значение m_OutValue достигает m_flMax, то материя перестаёт работать;
        --                                      так же можно менять значения через параметры "currentvalue", "hitmin" и "hitmax" (2-й параметр обычно не трогаем, он должен быть равен 0, если маппер не гандон)
        ["mode"] = ENTWATCH_MODE_LIMITED_USES,

        -- максимальное количество использований перед КД
        -- только для ENTWATCH_MODE_COOLDOWNS и ENTWATCH_MODE_LIMITED_USES
        ["maxuses"] = 1,

        -- КД или кол-во секунд, необходимое для того, чтобы скастовать материю (или сколько она действует (только для ENTWATCH_MODE_LIMITED_USES))
        ["cooldown"] = 15,

        -- currentvalue - значение, с которым спавниться math_counter
        -- hitmin - минимальное значение, при котором фильтр триггерит OnHitMin (ENTWATCH_MODE_COUNTER_FMIN_REACHED)
        -- hitmax - максимальное значение, при котором фильтр триггерит OnHitMax (ENTWATCH_MODE_COUNTER_FMAX_REACHED)
        ["currentvalue"] = 20,
        ["hitmin"] = 0,
        ["hitmax"] = 2000,
        -- из приколов, которые я заметил с этим режимом:
        ---- на карте ze_fapescape_rote_v1_3f хилка имеет только одно использование (currentvalue = 1, hitmin = 0, hitmax = 2)
        ----     но на третьем этапе на экстриме, хилка будет иметь два использования (currentvalue = 0, hitmin = 0, hitmax = 2)
        ---- на карте ze_ffvii_cosmo_canyon_v5fix электро работает так же через math_counter, но там маппер немножечко обосрался (currentvalue = 1, hitmin = 0, hitmax = 3)
        ----     и при каждом срабатывании OnHitMax, устанавливает значение m_OutValue на 1 (из-за чего я в рот ебал менять эти значения, пускай будет ENTWATCH_MODE_COOLDOWNS)
        ---- на карте ze_minecraft_adventure_v1_2c "зажигалка" имеет 4 огня, работают 15 секунд и КД 25 секунд, но не через math_counter
        ----     так что я в рот ебал эту залупу отслеживать
        ---- а, ну и пускай мапперы в аду горят за то, что делают материи с несколькими использованиями не через math_counter

        -- targetname для env_entity_maker, чтобы заспавнить материю через ULX
        ["pt_spawner"] = "Item_Ultima_Temp",
    },
}