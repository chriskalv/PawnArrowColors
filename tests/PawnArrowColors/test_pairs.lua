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
