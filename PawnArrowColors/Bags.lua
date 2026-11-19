-- Pawn Arrow Colors: the two bag paths.
--
-- ElvUI bags and bank: ElvUI's bag module shows its own arrow texture slot.UpgradeIcon in
-- B:UpdateItemUpgradeIcon(slot), asking Pawn; it calls that function for every slot update and again
-- from the slot's OnUpdate script while Pawn cannot answer yet. A secure post-hook on that function
-- paints the arrow after ElvUI has decided whether it is shown.
--
-- Blizzard bags: Pawn shows Blizzard's texture button.UpgradeIcon (atlas bags-greenarrow) with
-- UpgradeIcon:SetShown(...) from its hooks on the container frames' UpdateItems, and again from a
-- C_Timer retry while its throttled check returns nil. Secure hooks on SetShown, Show and Hide of each
-- arrow texture follow every one of these calls, whatever order the hooks of Pawn and this addon run
-- in and also when Pawn retries later. The item buttons come from a pool and appear when a bag opens,
-- so a post-hook on UpdateItems of each container frame finds new buttons and hooks their arrow.
--
-- Apart from installing these secure hooks (hooksecurefunc, as Pawn does for its own bag hooks),
-- neither path writes fields to Blizzard's or ElvUI's frames or tables; the addon's own state lives in
-- weak tables keyed by the arrow textures.

local _, ns = ...

ns.PATH_ORDER = { "elvui", "blizzard" }

-- ---------------------------------------------------------------------------------------------
-- ElvUI
-- ---------------------------------------------------------------------------------------------

local elvui = { label = "ElvUI bags" }
ns.paths.elvui = elvui

function elvui.Update(slot)
    local icon = type(slot) == "table" and slot.UpgradeIcon
    if type(icon) ~= "table" or type(icon.IsShown) ~= "function" then return end
    if icon:IsShown() then
        ns.Paint(icon, "elvui", slot.itemLink)
    else
        ns.Restore(icon)
    end
end

-- Returns true when the hook is in place. Without ElvUI the path stays off without a message.
function elvui.Setup()
    local E = type(ElvUI) == "table" and ElvUI[1]
    if type(E) ~= "table" then return false end
    local B
    if type(E.GetModule) == "function" then
        local ok, module = pcall(E.GetModule, E, "Bags", true)
        if ok then B = module end
    end
    if type(B) ~= "table" or type(B.UpdateItemUpgradeIcon) ~= "function" then
        ns.WarnOnce("elvui", "ElvUI's bag module has no UpdateItemUpgradeIcon (another ElvUI version?); arrows in ElvUI bags keep their color.")
        return false
    end
    elvui.B = B
    hooksecurefunc(B, "UpdateItemUpgradeIcon", function(_, slot)
        elvui.Update(slot)
    end)
    return true
end

-- Repaints every ElvUI slot (bags and bank) that exists, reading ElvUI's frame list only.
function elvui.Refresh()
    local frames = elvui.B and elvui.B.BagFrames
    if type(frames) ~= "table" then return end
    for _, frame in pairs(frames) do
        local bags = type(frame) == "table" and frame.Bags
        if type(bags) == "table" then
            for _, bag in pairs(bags) do
                if type(bag) == "table" then
                    for slotID, slot in pairs(bag) do
                        if type(slotID) == "number" then elvui.Update(slot) end
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Blizzard bags
-- ---------------------------------------------------------------------------------------------

local blizzard = { label = "Blizzard bags" }
ns.paths.blizzard = blizzard
blizzard.icons = setmetatable({}, { __mode = "k" }) -- hooked arrow texture -> true

local function itemLink(button)
    if type(button) ~= "table" or type(button.GetID) ~= "function" then return nil end
    local bagID
    if type(button.GetBagID) == "function" then
        bagID = button:GetBagID()
    elseif type(button.GetParent) == "function" and button:GetParent() then
        bagID = button:GetParent():GetID()
    end
    if bagID == nil or type(C_Container) ~= "table" or type(C_Container.GetContainerItemInfo) ~= "function" then return nil end
    local info = C_Container.GetContainerItemInfo(bagID, button:GetID())
    return type(info) == "table" and info.hyperlink or nil
end

function blizzard.Update(icon)
    if icon:IsShown() then
        ns.Paint(icon, "blizzard", itemLink(icon:GetParent()))
    else
        ns.Restore(icon)
    end
end

local function onArrowChanged(icon)
    blizzard.Update(icon)
end

-- Hooks the arrow textures of a container frame's item buttons that are new, then repaints them.
function blizzard.Discover(frame)
    local items = type(frame) == "table" and frame.Items
    if type(items) ~= "table" then return end
    for _, button in ipairs(items) do
        local icon = type(button) == "table" and button.UpgradeIcon
        if type(icon) == "table" and type(icon.SetShown) == "function" then
            if not blizzard.icons[icon] then
                blizzard.icons[icon] = true
                hooksecurefunc(icon, "SetShown", onArrowChanged)
                hooksecurefunc(icon, "Show", onArrowChanged)
                hooksecurefunc(icon, "Hide", onArrowChanged)
            end
            blizzard.Update(icon)
        end
    end
end

function blizzard.Frames()
    local frames = {}
    if type(ContainerFrameCombinedBags) == "table" then frames[#frames + 1] = ContainerFrameCombinedBags end
    local count = NUM_CONTAINER_FRAMES or NUM_TOTAL_BAG_FRAMES or 13
    for i = 1, count do
        local frame = _G["ContainerFrame" .. i]
        if type(frame) == "table" then frames[#frames + 1] = frame end
    end
    return frames
end

function blizzard.Setup()
    local hooked = 0
    blizzard.frames = {}
    for _, frame in ipairs(blizzard.Frames()) do
        if type(frame.UpdateItems) == "function" then
            hooksecurefunc(frame, "UpdateItems", blizzard.Discover)
            blizzard.frames[#blizzard.frames + 1] = frame
            hooked = hooked + 1
        end
    end
    if hooked == 0 then
        ns.WarnOnce("blizzard", "Blizzard's bag frames were not found (another client version?); arrows in Blizzard bags keep their color.")
        return false
    end
    for _, frame in ipairs(blizzard.frames) do blizzard.Discover(frame) end
    return true
end

function blizzard.Refresh()
    for icon in pairs(blizzard.icons) do blizzard.Update(icon) end
end
