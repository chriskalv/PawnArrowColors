-- Hit cap: hit above the cap does not count, for the candidate and for the equipped item alike.

-- B: a weapon scale (MeleeDps 5), A: a spell scale, D: no hit weight.
local function scales()
    return {
        { name = "A", label = "Holy", visible = true, values = { Intellect = 1, HitRating = 10 } },
        { name = "B", label = "Retribution", visible = true, values = { Strength = 1, HitRating = 10, MeleeDps = 5 } },
        { name = "D", label = "Plain", visible = true, values = { Strength = 1 } },
    }
end

local function items()
    return {
        ["item:ringHit1"] = { inv = "INVTYPE_FINGER", stats = { HitRating = 1, Strength = 5 }, name = "Ring of One", id = 1 },
        ["item:ringStr"] = { inv = "INVTYPE_FINGER", stats = { Strength = 30 }, name = "Ring of Might", id = 2 },
        ["item:ringHit3"] = { inv = "INVTYPE_FINGER", stats = { HitRating = 3 }, name = "Ring of Three", id = 3 },
        ["item:neckHit4"] = { inv = "INVTYPE_NECK", stats = { HitRating = 4, Strength = 5 }, name = "Choker of Four", id = 4 },
        ["item:neckStr30"] = { inv = "INVTYPE_NECK", stats = { Strength = 30 }, name = "Pendant of Might", id = 5 },
        ["item:neckStr20"] = { inv = "INVTYPE_NECK", stats = { Strength = 20 }, name = "Pendant", id = 6 },
        ["item:sword"] = { inv = "INVTYPE_WEAPON", stats = { Strength = 10 }, name = "Sword", id = 7 },
        ["item:dagger"] = { inv = "INVTYPE_WEAPON", stats = { Strength = 8 }, name = "Dagger", id = 8 },
        ["item:headHit2"] = { inv = "INVTYPE_HEAD", stats = { HitRating = 2, Strength = 5 }, name = "Helm", id = 9 },
        ["item:headStr"] = { inv = "INVTYPE_HEAD", stats = { Strength = 10 }, name = "Cap", id = 10 },
        ["item:headHit1ench"] = { inv = "INVTYPE_HEAD", stats = { Strength = 6 }, enchant = { HitRating = 1 }, base = "item:headHit1base", name = "Enchanted Cap", id = 11 },
        ["item:headHit1base"] = { inv = "INVTYPE_HEAD", stats = { Strength = 6 }, name = "Enchanted Cap", id = 11 },
        ["item:neckHit1Str40"] = { inv = "INVTYPE_NECK", stats = { HitRating = 1, Strength = 40 }, name = "Mighty Choker", id = 12 },
        ["item:mailHelmHit2"] = { inv = "INVTYPE_HEAD", stats = { HitRating = 2, Strength = 5, IsMail = 1 }, name = "Mail Helm", id = 13 },
        ["item:ringSpellHit2"] = { inv = "INVTYPE_FINGER", stats = { SpellHitRating = 2, Intellect = 10 }, name = "Band of Spells", id = 14 },
        ["item:ringInt20"] = { inv = "INVTYPE_FINGER", stats = { Intellect = 20 }, name = "Band of Wits", id = 15 },
        ["item:ringSpellHit1Hit2"] = { inv = "INVTYPE_FINGER", stats = { SpellHitRating = 1, HitRating = 2 }, name = "Band of Aim", id = 16 },
    }
end

local function start(opts)
    opts = opts or {}
    local cfg = {
        level = opts.level or 20,
        hit = opts.hit or { melee = 5, spell = 4, ranged = 5 },
        equipped = opts.equipped or { [11] = "item:ringHit1", [12] = "item:ringStr" },
        saved = opts.saved,
        dualWield = opts.dualWield,
        pawn = {
            scales = opts.scales or scales(), items = items(), tracking = opts.tracking, answer = opts.answer, missing = opts.missing,
            never = opts.never, tooltipUpgrades = opts.tooltipUpgrades,
        },
    }
    local ns = ReloadAddon(cfg)
    Login()
    return ns
end

local function upgradeFor(link, scaleName)
    local list = PawnIsItemAnUpgrade(PawnGetItemData(link))
    for _, u in ipairs(list or {}) do
        if u.ScaleName == scaleName then return u end
    end
    return nil
end

local function slash(text)
    ClearOutput()
    SlashCmdList.PAWNARROWCOLORS(text)
    return Output()
end

describe("hit cap", function()
    it("the example: cap 6%, 5% hit with 1% on the equipped ring, a ring with 3%: it counts 2%, the old ring 1%", function()
        local ns = start()
        local raw = STUB.modelIsItemAnUpgrade(PawnGetItemData("item:ringHit3"))
        local pawnB
        for _, u in ipairs(raw) do if u.ScaleName == "B" then pawnB = u end end
        assert_near(pawnB.PercentUpgrade, 1, 1e-9, "Pawn alone: 30 against 15")
        local u = upgradeFor("item:ringHit3", "B")
        assert_near(u.PercentUpgrade, (20 - 15) / 15, 1e-9, "20 against 15")
        assert_eq(u.ExistingItemLink, "item:ringHit1", "against the weaker ring, as Pawn does")
        assert_eq(u.LocalizedScaleName, "Retribution")
        assert_contains(table.concat(ns.notes["item:ringHit3"], "\n"),
            "Retribution: hit counted up to the cap 6.0% (you 5.0%): this item 2.0% of 3.0%, Ring of One 1.0% of 1.0%")
    end)

    it("hit beyond the cap can take away Pawn's upgrade", function()
        start({ hit = { melee = 6.5, spell = 4 } })
        -- without the old ring 5.5%, room 0.5%: the new ring is worth 5 against 15
        assert_nil(upgradeFor("item:ringHit3", "B"))
    end)

    it("the equipped item is treated the same: hit it carries beyond the cap does not protect it", function()
        local ns = start({ hit = { melee = 8, spell = 4 }, equipped = { [2] = "item:neckHit4" } })
        -- Pawn: 45 against 30, no upgrade; with the cap the old neck counts 2% of 4% (room 6 - 4): 25
        for _, u in ipairs(STUB.modelIsItemAnUpgrade(PawnGetItemData("item:neckStr30")) or {}) do
            assert_true(u.ScaleName ~= "B", "Pawn alone sees no upgrade for Retribution")
        end
        local u = upgradeFor("item:neckStr30", "B")
        assert_near(u.PercentUpgrade, (30 - 25) / 25, 1e-9)
        assert_contains(table.concat(ns.notes["item:neckStr30"], "\n"), "Choker of Four 2.0% of 4.0%")
        -- and Pawn's bag arrow follows (Pawn asks PawnIsItemAnUpgrade by its global name)
        assert_true(PawnShouldItemLinkHaveUpgradeArrowUnbudgeted("item:neckStr30", true))
        assert_eq(ns.Classify("item:neckStr30"), "other", "an upgrade for Retribution, not for the main scale Holy")
    end)

    it("an item below the cap keeps Pawn's numbers exactly", function()
        start({ hit = { melee = 1, spell = 0 } })
        local u = upgradeFor("item:ringHit3", "B")
        assert_near(u.PercentUpgrade, 1, 1e-9)
    end)

    it("a scale without hit weight is not touched", function()
        start({ hit = { melee = 9, spell = 9 } })
        local raw = STUB.modelIsItemAnUpgrade(PawnGetItemData("item:neckStr30"))
        local list = PawnIsItemAnUpgrade(PawnGetItemData("item:neckStr30"))
        assert_eq(list, raw)
    end)

    it("a spell scale counts against the spell cap and the character's spell hit", function()
        local ns = start({ hit = { melee = 0, spell = 4 }, equipped = { [11] = "item:ringStr", [12] = "item:ringStr" } })
        assert_eq(ns.ScaleHitKind("A"), "spell")
        assert_eq(ns.ScaleHitKind("B"), "weapon")
        -- Holy: the ring with 3% against a ring worth 0; room 5 - 4 = 1: counts 1% = 10
        local notes = table.concat(ns.notes["item:ringHit3"] or {}, "\n")
        assert_eq(notes, "")
        PawnIsItemAnUpgrade(PawnGetItemData("item:ringHit3"))
        assert_contains(table.concat(ns.notes["item:ringHit3"], "\n"), "Holy: hit counted up to the cap 5.0% (you 4.0%): this item 1.0% of 3.0%")
    end)

    it("an enchantment's hit is part of what the equipped item adds, Pawn's comparison stays without it", function()
        local ns = start({ hit = { melee = 6, spell = 0 }, equipped = { [1] = "item:headHit1ench" } })
        -- without the cap: 25 against 6; base without the cap's helm 6 - 1 = 5, room 1: the new helm counts 1% = 15
        local u = upgradeFor("item:headHit2", "B")
        assert_near(u.PercentUpgrade, (15 - 6) / 6, 1e-9)
        assert_contains(table.concat(ns.notes["item:headHit2"], "\n"), "this item 1.0% of 2.0%")
    end)

    it("level 60: the caps against bosses, 9% for weapons and 16% for spells", function()
        local ns = start({ level = 60, hit = { melee = 8, spell = 15 } })
        assert_eq(ns.HitCap("weapon", 60), 9)
        assert_eq(ns.HitCap("spell", 60), 16)
        assert_eq(ns.HitCap("weapon", 59), 6)
        assert_eq(ns.HitCap("spell", 59), 5)
        -- room without the old ring: 9 - 7 = 2
        local u = upgradeFor("item:ringHit3", "B")
        assert_near(u.PercentUpgrade, (20 - 15) / 15, 1e-9)
    end)

    it("a fixed number replaces both caps", function()
        local ns = start()
        slash("hitcap 7")
        assert_eq(PawnArrowColorsCharDB.hitCapValue, 7)
        assert_eq(ns.HitCap("weapon", 20), 7)
        -- room 7 - 4 = 3: Pawn's numbers again
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, 1, 1e-9)
        assert_contains(slash("hitcap"), "weapons 7.0% (fixed), spells 7.0% (fixed)")
        slash("hitcap auto")
        assert_eq(PawnArrowColorsCharDB.hitCapValue, "auto")
        assert_contains(slash("hitcap 0"), "a number of percent above 0")
    end)

    it("off: Pawn's answers as they are", function()
        start()
        slash("hitcap off")
        assert_false(PawnArrowColorsCharDB.hitCap)
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, 1, 1e-9)
        slash("hitcap on")
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, 1 / 3, 1e-9)
    end)

    it("a changed setting lets Pawn rate its bag arrows again", function()
        start()
        local before = STUB.resets
        slash("hitcap off")
        assert_eq(STUB.resets, before + 1)
    end)

    it("the cap a scale counts against can be set per scale", function()
        local ns = start()
        assert_contains(slash("hitcap 2 spell"), "Retribution counts hit against the spell cap.")
        assert_eq(ns.ScaleHitKind("B"), "spell")
        -- spell hit 4 with the old ring's 1% (an item's hit counts as part of the spell hit), cap 5: room 2
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, (20 - 15) / 15, 1e-9)
        assert_contains(table.concat(ns.notes["item:ringHit3"], "\n"), "Retribution: hit counted up to the cap 5.0% (you 4.0%)")
        slash("hitcap Retribution auto")
        assert_eq(ns.ScaleHitKind("B"), "weapon")
        assert_contains(slash("hitcap nobody weapon"), "no visible Pawn scale")
        assert_contains(slash("hitcap 2 fast"), "hitcap takes on, off, auto")
    end)

    it("while the character wields two weapons the weapon cap is not applied", function()
        start({ hit = { melee = 6.5, spell = 0 }, equipped = { [11] = "item:ringHit1", [12] = "item:ringStr", [16] = "item:sword", [17] = "item:dagger" } })
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, 1, 1e-9, "Pawn's number")
    end)

    it("hidden hit (secret in combat): Pawn's answers, and new decisions once the hit can be read again", function()
        local ns = start({ hit = { melee = "secret", spell = "secret" } })
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, 1, 1e-9)
        assert_contains(slash("hitcap"), "melee hidden by the client")
        local before = STUB.resets
        STUB.hit = { melee = 5, spell = 4 }
        FireEvent("PLAYER_REGEN_ENABLED")
        RunAllTimers()
        assert_eq(STUB.resets, before + 1, "Pawn rates its arrows again")
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, 1 / 3, 1e-9)
        assert_true(ns.adjustActive)
    end)

    it("a change of the character's hit (buff, talent) leads to new decisions, an unchanged hit does not", function()
        start()
        upgradeFor("item:ringHit3", "B") -- a decision with the hit read now
        local before = STUB.resets
        FireEvent("UNIT_STATS", "player")
        RunAllTimers()
        assert_eq(STUB.resets, before, "same hit")
        STUB.hit.melee = 4
        FireEvent("UNIT_STATS", "player")
        FireEvent("COMBAT_RATING_UPDATE")
        RunAllTimers()
        assert_eq(STUB.resets, before + 1, "one reset for several events")
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, (30 - 15) / 15, 1e-9, "room 3 now: the full 3%")
    end)

    it("a gear change is seen at once", function()
        local ns = start()
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, 1 / 3, 1e-9)
        Equip(11, "item:ringHit3")
        STUB.hit.melee = 7
        assert_nil(upgradeFor("item:ringHit3", "B"), "the equipped ring is Pawn's best item, no upgrade")
        assert_eq(ns.gear.slots[11].link, "item:ringHit3")
        Equip(2, "item:neckStr20")
        assert_nil(ns.gear, "forgotten at the event")
    end)

    it("while Pawn tracks the best items of each scale nothing is changed", function()
        local ns = start({ tracking = true })
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, 1, 1e-9)
        assert_contains(slash("hitcap"), "Track for each scale")
        assert_nil(ns.notes["item:ringHit3"])
    end)

    it("when Pawn's answer is not what the addon would compute without the cap, it stays", function()
        local ns = start({ answer = { ["item:ringHit3"] = { { ScaleName = "B", LocalizedScaleName = "Retribution", PercentUpgrade = 0.5 } } } })
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, 0.5, 1e-9)
        assert_true(ns.adjustStats.mismatch >= 1)
    end)

    it("the tooltip shows Pawn's adjusted percentage and the line about the hit", function()
        start()
        local text = HoverItem("item:ringHit3")
        assert_contains(text, "Retribution: 30.0 (+33% upgrade)")
        assert_contains(text, "Retribution: hit counted up to the cap 6.0% (you 5.0%): this item 2.0% of 3.0%")
        local plain = HoverItem("item:neckStr20")
        assert_not_contains(plain, "hit counted")
    end)

    it("an error in the adjustment leaves Pawn's answers and says so once", function()
        local ns = start()
        ns.HitRoom = function() error("boom") end
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, 1, 1e-9)
        assert_contains(Output(), "hit cap and weapon pairs stopped after an error")
        ClearOutput()
        upgradeFor("item:ringHit3", "B")
        assert_eq(Output(), "")
        assert_true(ns.adjustBroken)
    end)

    it("without one of Pawn's functions the features stay off, Pawn's answers stay, one message", function()
        local ns = start({ missing = { PawnGetSingleValueFromItem = true } })
        assert_false(ns.adjustActive)
        assert_contains(Output(), "Pawn's PawnGetSingleValueFromItem was not found (another Pawn version?); hit cap and weapon pairs are off")
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, 1, 1e-9)
        assert_contains(slash("hitcap"), "not active: Pawn's PawnGetSingleValueFromItem was not found")
    end)

    it("without the client's hit functions the cap is not applied", function()
        local ns = ReloadAddon({ level = 20, equipped = { [11] = "item:ringHit1", [12] = "item:ringStr" }, pawn = { scales = scales(), items = items() } })
        Login()
        assert_near(upgradeFor("item:ringHit3", "B").PercentUpgrade, 1, 1e-9)
        assert_true(ns.adjustActive)
    end)

    it("/pac shows the caps, the hit and the kind of every scale; the settings page has the checkbox and the value", function()
        start()
        local out = slash("")
        assert_contains(out, "hit cap: on, weapons 6.0%, spells 5.0% (against targets two levels above you).")
        assert_contains(out, "your hit: melee 5.0%, ranged 5.0%, spell 4.0%")
        assert_contains(out, "1. Holy: spell cap")
        assert_contains(out, "2. Retribution: weapon cap")
        assert_contains(out, "3. Plain: hit has no weight, not capped")
        local value = STUB.settings.settings.PAWNARROWCOLORS_HITCAPVALUE
        assert_eq(value:GetValue(), "auto")
        value:SetValue("8")
        assert_eq(PawnArrowColorsCharDB.hitCapValue, 8)
        value:SetValue("auto")
        assert_eq(PawnArrowColorsCharDB.hitCapValue, "auto")
        STUB.settings.settings.PAWNARROWCOLORS_HITCAP:SetValue(false)
        assert_false(PawnArrowColorsCharDB.hitCap)
    end)

    it("invalid saved settings get their defaults", function()
        start({ saved = { hitCap = "yes", hitCapValue = -3, hitCapKind = { B = "laser", A = "spell" } } })
        local db = PawnArrowColorsCharDB
        assert_eq({ db.hitCap, db.hitCapValue, db.hitCapKind }, { true, "auto", { A = "spell" } })
    end)
end)

describe("hit cap: reading the hit", function()
    it("a hit change leads to one reset, not to one per later event", function()
        start()
        upgradeFor("item:ringHit3", "B")
        local before = STUB.resets
        STUB.hit.melee = 4
        FireEvent("UNIT_STATS", "player")
        RunAllTimers()
        FireEvent("UNIT_STATS", "player")
        RunAllTimers()
        assert_eq(STUB.resets, before + 1)
    end)

    it("the hit becoming hidden in combat does not reset Pawn's arrows; readable again with the same value neither", function()
        start()
        upgradeFor("item:ringHit3", "B")
        local before = STUB.resets
        STUB.hit.melee = "secret"
        FireEvent("UNIT_STATS", "player")
        RunAllTimers()
        assert_eq(STUB.resets, before)
        STUB.hit.melee = 5
        FireEvent("PLAYER_REGEN_ENABLED")
        RunAllTimers()
        assert_eq(STUB.resets, before)
    end)
end)

describe("hit cap: which cap a scale counts against", function()
    -- made-up weights in the proportions of the Pawn Forever scales they stand for
    local kinds = {
        { name = "mage", label = "Fire", values = { Intellect = 0.9, SpellDamage = 1, FireSpellDamage = 0.9, RangedDps = 7, Agility = 0.01, HitRating = 12 } },
        { name = "lock", label = "Affliction", values = { Intellect = 0.8, SpellDamage = 1, ShadowSpellDamage = 0.9, RangedDps = 7, HitRating = 12 } },
        { name = "prot", label = "Protection", values = { Strength = 0.3, Agility = 0.4, Ap = 0.15, Intellect = 0.4, SpellDamage = 0.9, MeleeDps = 0.5, HitRating = 6 } },
        { name = "shock", label = "Shockadin", values = { Strength = 0.2, Agility = 0.05, Ap = 0.1, Intellect = 0.8, SpellDamage = 1, MeleeDps = 0.4, HitRating = 4 } },
        { name = "ret", label = "Retribution", values = { Strength = 1, Agility = 0.35, Ap = 0.5, Intellect = 0.7, SpellDamage = 0.25, MeleeDps = 4, HitRating = 13 } },
        { name = "hunter", label = "Marksmanship", values = { Agility = 1, Rap = 0.45, Intellect = 0.8, MeleeDps = 0.05, RangedDps = 14, HitRating = 23 } },
        { name = "holy", label = "Holy", values = { Intellect = 1.7, SpellDamage = 1.35, Healing = 1.3, MeleeDps = 0.09, HitRating = 0.5 } },
        { name = "edge", label = "Edge", values = { Strength = 1, SpellDamage = 3, HitRating = 5 } },
        { name = "below", label = "Below", values = { Strength = 0.9, SpellDamage = 3, HitRating = 5 } },
        { name = "bare", label = "Bare", values = { MeleeDps = 0.5, HitRating = 5 } },
    }

    it("casters with a wand weight count against the spell cap, the Paladin tank and Retribution against the weapon cap", function()
        local list = {}
        for _, k in ipairs(kinds) do list[#list + 1] = { name = k.name, label = k.label, visible = true, values = k.values } end
        local ns = start({ scales = list })
        local want = {
            mage = "spell", lock = "spell", prot = "weapon", shock = "spell", ret = "weapon", hunter = "weapon", holy = "spell",
            edge = "weapon", below = "spell", bare = "weapon",
        }
        for name, kind in pairs(want) do assert_eq(ns.ScaleHitKind(name), kind, name) end
        assert_eq(ns.WeaponHand("hunter"), "ranged")
        assert_eq(ns.WeaponHand("prot"), "melee")
        assert_eq(ns.WeaponHand("ret"), "melee")
        assert_eq(ns.ScaleHitKind("A"), "spell", "Intellect and hit only: no weapon")
    end)
end)

describe("hit cap: edge cases", function()
    it("hit above the cap even without the replaced item: nothing of the new item's hit counts", function()
        local ns = start({ hit = { melee = 7, spell = 0 }, equipped = { [2] = "item:neckStr30" } })
        -- Pawn: 50 against 30; the room is 0 (7% without the old neck), not -1: 40 against 30
        local u = upgradeFor("item:neckHit1Str40", "B")
        assert_near(u.PercentUpgrade, (40 - 30) / 30, 1e-9)
        assert_contains(table.concat(ns.notes["item:neckHit1Str40"], "\n"), "this item 0.0% of 1.0%")
    end)

    it("an equipped item worth 0 (X value) with hit beyond the cap: Pawn's answer, no negative percentage", function()
        local sc = scales()
        sc[2].values.IsMail = -1000000
        start({ scales = sc, hit = { melee = 8, spell = 0 }, equipped = { [1] = "item:mailHelmHit2" } })
        local raw
        for _, e in ipairs(STUB.modelIsItemAnUpgrade(PawnGetItemData("item:headStr"))) do if e.ScaleName == "B" then raw = e end end
        local u = upgradeFor("item:headStr", "B")
        assert_true(u.PercentUpgrade > 0, "positive")
        assert_near(u.PercentUpgrade, raw.PercentUpgrade, 1e-6 * raw.PercentUpgrade, "as Pawn: an upgrade over an item worth 0")
    end)

    it("a capped value never goes below 0, a value of 0 or less stays as it is", function()
        local ns = start()
        assert_eq(ns.CappedValue(20, 3, 0, { unit = 10 }), 0)
        assert_eq(ns.CappedValue(0, 3, 0, { unit = 10 }), 0)
        assert_eq(ns.CappedValue(-5, 3, 0, { unit = 10 }), -5)
        assert_eq(ns.CappedValue(40, 3, 2, { unit = 10 }, 1), 20, "hit Pawn does not value fills the room first")
    end)

    it("an equipped item is the best or second item, as in Pawn", function()
        local ns = start()
        local gear = ns.Gear()
        local scale = PawnCommon.Scales.B
        assert_eq(ns.ModelScale(PawnGetItemData("item:ringHit1"), "B", scale, gear, nil).kind, "second")
        assert_eq(ns.ModelScale(PawnGetItemData("item:ringStr"), "B", scale, gear, nil).kind, "best")
        ns = start({ equipped = { [2] = "item:neckHit4" } })
        assert_nil(ns.ModelScale(PawnGetItemData("item:neckHit4"), "B", PawnCommon.Scales.B, ns.Gear(), nil), "an equipped item: Pawn's answer stays")
    end)

    it("an equipped item Pawn never shows upgrades for keeps Pawn's answer", function()
        start({ hit = { melee = 8, spell = 0 }, equipped = { [2] = "item:neckHit4" }, never = { [4] = true } })
        -- without the rule the capped old neck (25) would lose to the pendant (30)
        assert_nil(upgradeFor("item:neckStr30", "B"))
    end)

    it("spell cap: an item's spell hit (worth 0 to Pawn) counts for the room on both sides", function()
        local ns = start({ hit = { melee = 0, spell = 5 }, equipped = { [11] = "item:ringSpellHit2", [12] = "item:ringInt20" } })
        -- Holy: without the weaker ring (10) the spell hit is 3%, room 2: the ring with 3% counts 2 (20 against 10)
        assert_near(upgradeFor("item:ringHit3", "A").PercentUpgrade, (20 - 10) / 10, 1e-9)
        -- a ring with 1% spell hit and 2% hit: its spell hit fills 1 of the 2, its hit counts 1 (10 against 10)
        assert_nil(upgradeFor("item:ringSpellHit1Hit2", "A"))
        assert_contains(table.concat(ns.notes["item:ringSpellHit1Hit2"], "\n"), "Holy: hit counted up to the cap 5.0% (you 5.0%): this item 1.0% of 2.0%")
    end)

    it("with hit cap and weapon pairs off the addon does not look at the answer at all", function()
        local ns = start()
        slash("hitcap off")
        slash("pairs off")
        local calls = ns.adjustStats.calls
        upgradeFor("item:ringHit3", "B")
        assert_eq(ns.adjustStats.calls, calls)
    end)

    it("with Pawn's upgrades in tooltips off, a bag check's notes do not show in the tooltip", function()
        start({ tooltipUpgrades = false })
        PawnIsItemAnUpgrade(PawnGetItemData("item:ringHit3")) -- the bag arrow check
        assert_not_contains(HoverItem("item:ringHit3"), "hit counted")
    end)
end)
