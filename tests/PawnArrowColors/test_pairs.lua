-- Weapon pairs: a two-hand weapon against the equipped one-hand pair, a one-hand item with its best
-- partner from the bags against the equipped two-hand weapon.

local X = -1000000 -- Pawn's value for "unusable" (PawnIgnoreStatValue)

-- B: Retribution (no off-hand weapons), P: Protection.
local function scales(extraB, extraP)
    local b = { Strength = 1, MeleeDps = 5, HitRating = 10, IsOffHand = X }
    local p = { Strength = 1, MeleeDps = 2, Stamina = 1, BlockValue = 1, HitRating = 5 }
    for k, v in pairs(extraB or {}) do b[k] = v end
    for k, v in pairs(extraP or {}) do p[k] = v end
    return {
        { name = "B", label = "Retribution", visible = true, values = b },
        { name = "P", label = "Protection", visible = true, values = p },
    }
end

local function items()
    return {
        ["item:greatsword"] = { inv = "INVTYPE_2HWEAPON", stats = { Strength = 20, MeleeDps = 10, Is2HSword = 1 }, name = "Greatsword", id = 1 },
        ["item:hitsword"] = { inv = "INVTYPE_2HWEAPON", stats = { Strength = 20, MeleeDps = 10, HitRating = 3 }, name = "Keen Greatsword", id = 2 },
        ["item:mace"] = { inv = "INVTYPE_WEAPON", stats = { Strength = 10, MeleeDps = 6 }, name = "Mace", id = 3 },
        ["item:hitmace"] = { inv = "INVTYPE_WEAPON", stats = { Strength = 10, MeleeDps = 6, HitRating = 1 }, name = "Keen Mace", id = 4 },
        ["item:shield"] = { inv = "INVTYPE_SHIELD", stats = { Stamina = 20, BlockValue = 15, IsShield = 1 }, name = "Kite Shield", id = 5 },
        ["item:mhsword"] = { inv = "INVTYPE_WEAPONMAINHAND", stats = { Strength = 12, MeleeDps = 7 }, name = "Main Sword", id = 6 },
        ["item:tome"] = { inv = "INVTYPE_HOLDABLE", stats = { Intellect = 10 }, name = "Tome", id = 7 },
        ["item:bigshield"] = { inv = "INVTYPE_SHIELD", stats = { Stamina = 50, IsShield = 1 }, name = "Tower Shield", id = 8, minLevel = 40 },
        ["item:offdagger"] = { inv = "INVTYPE_WEAPONOFFHAND", stats = { Strength = 5, MeleeDps = 3, IsOffHand = 1 }, name = "Parrying Dagger", id = 9 },
        ["item:boots"] = { inv = "INVTYPE_FEET", stats = { Stamina = 5 }, name = "Boots", id = 10 },
        ["item:classlocked"] = { inv = "INVTYPE_SHIELD", stats = { Stamina = 60, IsShield = 1 }, name = "Totem Shield", id = 11, canEquip = false },
        ["item:bigsword"] = { inv = "INVTYPE_2HWEAPON", stats = { Strength = 26, MeleeDps = 10 }, name = "Heavy Greatsword", id = 12 },
        ["item:bigmace"] = { inv = "INVTYPE_WEAPONMAINHAND", stats = { Strength = 40, MeleeDps = 8 }, name = "Great Mace", id = 13 },
        ["item:staff"] = { inv = "INVTYPE_2HWEAPON", stats = { SpellDamage = 30 }, name = "Staff", id = 14 },
        ["item:spellmace"] = { inv = "INVTYPE_WEAPONMAINHAND", stats = { SpellDamage = 20, HitRating = 2 }, name = "Spell Mace", id = 15 },
        ["item:aimtome"] = { inv = "INVTYPE_HOLDABLE", stats = { SpellDamage = 15, SpellHitRating = 1 }, name = "Tome of Aim", id = 16 },
    }
end

local function start(opts)
    opts = opts or {}
    local cfg = {
        level = opts.level or 20,
        hit = opts.hit or { melee = 0, spell = 0, ranged = 0 },
        equipped = opts.equipped or { [16] = "item:greatsword" },
        dualWield = opts.dualWield,
        saved = opts.saved,
        pawn = { scales = opts.scales or scales(), items = items(), tracking = opts.tracking, options = opts.options },
        elvui = opts.elvui,
    }
    local ns = ReloadAddon(cfg)
    for i, link in ipairs(opts.bags or {}) do PutItem(0, i, link) end
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

local function notes(ns, link)
    return table.concat(ns.notes[link] or {}, "\n")
end

local function slash(text)
    ClearOutput()
    SlashCmdList.PAWNARROWCOLORS(text)
    return Output()
end

describe("weapon pairs with a two-hand weapon equipped", function()
    it("Pawn alone never compares a one-hand item with the two-hand weapon", function()
        start({ bags = { "item:mace", "item:shield" } })
        assert_nil(STUB.modelIsItemAnUpgrade(PawnGetItemData("item:mace")))
    end)

    it("a one-hand weapon with the best shield from the bags against the two-hand weapon", function()
        local ns = start({ bags = { "item:mace", "item:shield", "item:tome" } })
        local u = upgradeFor("item:mace", "P")
        assert_near(u.PercentUpgrade, (22 + 35 - 40) / 40, 1e-9)
        assert_eq(u.ExistingItemLink, "item:greatsword")
        assert_contains(notes(ns, "item:mace"), "Protection: with Kite Shield, against Greatsword")
        -- Retribution takes no off-hand weapon (X) and values the shield 0: the mace alone, 40 against 70
        assert_nil(upgradeFor("item:mace", "B"))
        assert_contains(notes(ns, "item:mace"), "Retribution: alone (no item for the off hand in your bags), against Greatsword")
    end)

    it("a shield with the best main-hand weapon from the bags", function()
        local ns = start({ bags = { "item:mace", "item:mhsword", "item:shield" } })
        local u = upgradeFor("item:shield", "P")
        assert_near(u.PercentUpgrade, (26 + 35 - 40) / 40, 1e-9, "the main sword (26) is a better partner than the mace (22)")
        assert_contains(notes(ns, "item:shield"), "Protection: with Main Sword, against Greatsword")
        assert_nil(upgradeFor("item:shield", "B"), "worth 0 for Retribution")
    end)

    it("an off-hand item without a main-hand partner is no upgrade", function()
        local ns = start({ bags = { "item:shield" } })
        assert_nil(upgradeFor("item:shield", "P"))
        assert_contains(notes(ns, "item:shield"), "Protection: no main-hand weapon for it in your bags, not compared with Greatsword")
    end)

    it("a partner must be usable now: required level and class", function()
        local ns = start({ bags = { "item:mace", "item:bigshield", "item:classlocked" } })
        assert_nil(upgradeFor("item:mace", "P"), "alone: 22 against 40")
        assert_contains(notes(ns, "item:mace"), "Protection: alone")
        STUB.level = 40
        ns.Recompute()
        assert_near(upgradeFor("item:mace", "P").PercentUpgrade, (22 + 50 - 40) / 40, 1e-9)
    end)

    it("the candidate is not its own partner; a second copy in the bags is", function()
        local sc = scales(nil, {})
        local ns = start({ scales = sc, bags = { "item:mace" } })
        assert_nil(upgradeFor("item:mace", "P"), "one mace: alone, 22 against 40")
        ns = start({ scales = sc, bags = { "item:mace", "item:mace" } })
        assert_near(upgradeFor("item:mace", "P").PercentUpgrade, (44 - 40) / 40, 1e-9)
        assert_contains(notes(ns, "item:mace"), "with Mace")
        start({ scales = sc, bags = { "item:mace", "item:mace" }, dualWield = false })
        assert_nil(upgradeFor("item:mace", "P"), "the character cannot dual wield")
    end)

    it("the scale's switch \"Don't show upgrades for 1H items\" is respected", function()
        start({ bags = { "item:mace", "item:shield" }, options = { P = { DoNotShow1HUpgrades = true } } })
        assert_nil(upgradeFor("item:mace", "P"))
    end)

    it("Pawn's arrow shows on a pair upgrade, yellow when it is not the main scale", function()
        local ns = start({ bags = { "item:mace", "item:shield" } })
        PutItem(0, 1, "item:mace")
        ContainerFrame1:Open({ 1, 2 })
        local icon = BlizzardButton(ContainerFrame1, 1).UpgradeIcon
        assert_true(icon:IsShown(), "Pawn shows the arrow")
        assert_eq(icon.texture, ns.TEXTURE, "yellow: an upgrade for Protection, the main scale is Retribution")
        assert_true(BlizzardButton(ContainerFrame1, 2).UpgradeIcon:IsShown(), "the shield with the mace as partner")
    end)
end)

describe("weapon pairs with one-hand items equipped", function()
    it("a two-hand weapon against the sum of main hand and off hand", function()
        local ns = start({ equipped = { [16] = "item:mace", [17] = "item:shield" } })
        assert_nil(STUB.modelIsItemAnUpgrade(PawnGetItemData("item:greatsword")), "Pawn alone: no comparison")
        local u = upgradeFor("item:greatsword", "B")
        assert_near(u.PercentUpgrade, (70 - 40) / 40, 1e-9)
        assert_eq(u.ExistingItemLink, "item:mace")
        assert_nil(upgradeFor("item:greatsword", "P"), "40 against 22 + 35")
        assert_contains(notes(ns, "item:greatsword"), "Retribution: against Mace + Kite Shield")
        assert_eq(ns.Classify("item:greatsword"), "main", "green: an upgrade for the main scale Retribution")
    end)

    it("an X value of the scale makes the two-hand weapon worth 0", function()
        start({ equipped = { [16] = "item:mace", [17] = "item:shield" }, scales = scales({ Is2HSword = X }) })
        assert_nil(upgradeFor("item:greatsword", "B"))
    end)

    it("the scale's switch \"Don't show upgrades for 2H items\" is respected", function()
        start({ equipped = { [16] = "item:mace", [17] = "item:shield" }, options = { B = { DoNotShow2HUpgrades = true } } })
        assert_nil(upgradeFor("item:greatsword", "B"))
    end)

    it("the hit cap applies to the pair values", function()
        local ns = start({ equipped = { [16] = "item:hitmace", [17] = "item:shield" }, hit = { melee = 5, spell = 0 } })
        -- without both hands 4% hit, room 2: the greatsword's 3% count 2 (100 - 10), the mace's 1% in full (50)
        local u = upgradeFor("item:hitsword", "B")
        assert_near(u.PercentUpgrade, (90 - 50) / 50, 1e-9)
        assert_contains(notes(ns, "item:hitsword"), "Retribution: against Keen Mace + Kite Shield; hit 2.0% of 3.0% counted (cap 6.0%)")
    end)

    it("the tooltip shows Pawn's percentage for the pair and what was compared", function()
        start({ equipped = { [16] = "item:mace", [17] = "item:shield" } })
        local text = HoverItem("item:greatsword")
        assert_contains(text, "Retribution: 70.0 (+75% upgrade)")
        assert_contains(text, "Retribution: against Mace + Kite Shield")
    end)
end)

describe("weapon pairs: settings and invalidation", function()
    it("off: Pawn's answers as they are", function()
        start({ bags = { "item:mace", "item:shield" } })
        slash("pairs off")
        assert_false(PawnArrowColorsCharDB.weaponPairs)
        assert_nil(upgradeFor("item:mace", "P"))
        slash("pairs on")
        assert_true(upgradeFor("item:mace", "P") ~= nil)
        assert_contains(slash("pairs"), "weapon pairs: on; two-hand weapons are compared with one-hand pairs, 2 weapons and off-hand items in your bags.")
        assert_contains(slash("pairs maybe"), "pairs is on or off.")
    end)

    it("while Pawn tracks the best items of each scale nothing is changed", function()
        start({ bags = { "item:mace", "item:shield" }, tracking = true })
        assert_nil(upgradeFor("item:mace", "P"))
        assert_contains(slash("pairs"), "not applied while Pawn tracks each scale")
    end)

    it("a new partner in the bags changes the decision and lets Pawn rate its arrows again", function()
        local ns = start({ bags = { "item:mace" } })
        assert_nil(upgradeFor("item:mace", "P"))
        local before = STUB.resets
        PutItem(1, 1, "item:boots")
        FireEvent("BAG_UPDATE_DELAYED")
        assert_eq(STUB.resets, before, "boots change nothing")
        PutItem(1, 2, "item:shield")
        FireEvent("BAG_UPDATE_DELAYED")
        assert_eq(STUB.resets, before + 1)
        assert_true(upgradeFor("item:mace", "P") ~= nil)
        assert_contains(notes(ns, "item:mace"), "with Kite Shield")
    end)

    it("the result per scale and item is kept until something changes", function()
        local ns = start({ bags = { "item:mace", "item:shield" } })
        upgradeFor("item:mace", "P")
        local calls = STUB.valueCalls
        upgradeFor("item:mace", "P")
        local again = STUB.valueCalls - calls
        PawnResetBags()
        calls = STUB.valueCalls
        upgradeFor("item:mace", "P")
        assert_true(STUB.valueCalls - calls > again, "after Pawn's reset the pair is computed again")
        assert_true(ns.pairCache ~= nil)
    end)

    it("the settings page has the checkbox", function()
        start()
        STUB.settings.settings.PAWNARROWCOLORS_WEAPONPAIRS:SetValue(false)
        assert_false(PawnArrowColorsCharDB.weaponPairs)
    end)
end)

describe("weapon pairs: edge cases", function()
    it("a scale with X on IsOffHand takes no one-hand weapon as off-hand partner", function()
        local ns = start({ bags = { "item:mace", "item:hitmace" } })
        -- Retribution: the Keen Mace (50) would make 90 against 70, but it cannot go into the off hand
        assert_nil(upgradeFor("item:mace", "B"))
        assert_contains(notes(ns, "item:mace"), "Retribution: alone (no item for the off hand in your bags)")
        assert_contains(notes(ns, "item:mace"), "Protection: with Keen Mace")
    end)

    it("an off-hand candidate worth 0 is no upgrade, whatever its partner", function()
        start({ bags = { "item:tome", "item:bigmace" } })
        -- Retribution values the tome 0; the Great Mace alone (80) would beat the Greatsword (70)
        assert_nil(upgradeFor("item:tome", "B"))
    end)

    it("two weapons equipped against a two-hand weapon: the equipped hit counts in full, the two-hand weapon's is capped", function()
        start({ equipped = { [16] = "item:mace", [17] = "item:hitmace" }, hit = { melee = 7, spell = 0 } })
        -- Protection: Mace 22 + Keen Mace 27 = 49 (no cap while dual wielding); Heavy Greatsword 46
        assert_nil(upgradeFor("item:bigsword", "P"))
    end)

    it("spell cap: the partner's spell hit (worth 0 to Pawn) fills the room before the candidate's hit", function()
        local sc = { { name = "H", label = "Fire", visible = true, values = { Intellect = 1, SpellDamage = 1, HitRating = 10 } } }
        local ns = start({ scales = sc, equipped = { [16] = "item:staff" }, bags = { "item:spellmace", "item:aimtome" }, hit = { melee = 0, spell = 4 } })
        -- room 1, taken by the tome's 1% spell hit: the mace's 2% hit count 0 (35 against 30)
        assert_near(upgradeFor("item:spellmace", "H").PercentUpgrade, (35 - 30) / 30, 1e-9)
        assert_contains(notes(ns, "item:spellmace"), "Fire: with Tome of Aim, against Staff; hit 0.0% of 2.0% counted (cap 5.0%)")
    end)

    it("a partner whose data is still loading: no decision kept, a new one once the data arrived", function()
        local ns = start({ bags = { "item:mace", "item:shield" } })
        ns.pairsChanged() -- a new decision (as after a gear change) ...
        STUB.pawn.nolink["item:shield"] = 2 -- ... while Pawn has no stats for the shield yet (asked once per scale)
        assert_nil(upgradeFor("item:mace", "P"), "Pawn's answer while the shield has no data")
        assert_nil(ns.pairCache["P\0item:mace"], "nothing kept")
        local before = STUB.resets
        FireEvent("GET_ITEM_INFO_RECEIVED", 5, true)
        FireEvent("GET_ITEM_INFO_RECEIVED", 3, true)
        RunAllTimers()
        assert_eq(STUB.resets, before + 1, "one new rating for both events")
        assert_near(upgradeFor("item:mace", "P").PercentUpgrade, (22 + 35 - 40) / 40, 1e-9)
        assert_contains(notes(ns, "item:mace"), "Protection: with Kite Shield")
        FireEvent("GET_ITEM_INFO_RECEIVED", 7, true)
        RunAllTimers()
        assert_eq(STUB.resets, before + 1, "nothing waits any more")
    end)

    it("ElvUI's arrows follow a changed setting without a slot update by ElvUI", function()
        start({ bags = { "item:mace", "item:shield" }, elvui = {} })
        local slot = ElvUpdate(STUB.elvBags, 0, 1)
        assert_true(slot.UpgradeIcon:IsShown(), "the mace with the shield, for Protection")
        slash("pairs off")
        assert_false(slot.UpgradeIcon:IsShown(), "ElvUI asked again")
        slash("pairs on")
        assert_true(slot.UpgradeIcon:IsShown())
    end)
end)
