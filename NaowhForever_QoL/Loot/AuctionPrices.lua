-- AuctionPrices.lua: Auction Prices, the lowest buyout per item from a full scan or the release's prices, per realm and faction.
local ns = _G.NaowhForever

local S = ns.QoLSettings
local Items = ns.Shared.Items

local SCAN_COOLDOWN = 900
local CHUNK = 1000
local TIMEOUT = 60
local AGE_TICK = 60
local SECONDS_PER_MINUTE, SECONDS_PER_HOUR = ns.QoLConstants.SECONDS_PER_MINUTE, ns.QoLConstants.SECONDS_PER_HOUR
local SECONDS_PER_DAY = ns.QoLConstants.SECONDS_PER_DAY
local PERCENT = ns.QoLConstants.PERCENT
local BUTTON_W, BUTTON_H = 120, 24
local BUTTON_GAP, BUTTON_DROP = 8, 4
local AGE_SIZE = 11
local COIN_SIZE = 12
local WHITE = ns.QoLConstants.WHITE_RGB
local REALM_JOIN = "-"
local function Tag() return ns.Color("accent", "Naowh AH") end
local TEXT_SCAN = ns.L("Scan Prices")
local TEXT_SCANNING = ns.L("Scanning...")
local TEXT_PROGRESS = ns.L("Scanning %d%%")
local TEXT_NO_SCAN = ns.L("No scan yet for this realm and faction")
local TEXT_NO_SCAN_SHORT = ns.L("No scan yet")
local TEXT_SCAN_LINE = ns.L("Last scan %s ago: %s items priced")
local TEXT_AGE = ns.L("Last scan %s ago%s")
local TEXT_NEXT = ns.L(", next in %dm")
local TEXT_EMPTY = ns.L("The auction house returned no listings. Try again in a moment.")
local TEXT_WAIT = ns.L("%s: Blizzard allows one full scan every 15 minutes. Next scan in %dm.")
local TEXT_TIMEOUT = ns.L("no answer from the auction house. A full scan can only run once every 15 minutes.")
local TEXT_CLOSED = ns.L("scan stopped: the auction house closed.")
local TEXT_TIP = ns.L("Reads every listing on the auction house and keeps the lowest buyout for "
    .. "each item, shown on item tooltips. Blizzard allows one full scan every 15 "
    .. "minutes.\n\n")
local TEXT_EACH = ns.L(" |cff808080each, %s ago|r")
local TEXT_FILLING = "%d %s"
local TEXT_CHEAPEST = ns.L("cheapest")
local MINUTES, HOURS, DAYS = "m", "h", "d"
local TEXT_FEED_LINE = ns.L("Prices from %s ago: %s items priced")
local TEXT_TOOLTIP_TAG = ns.L("NF AH Price")
local FEED_ADDON = "NaowhForever_AuctionData"
local FEED_BASE = 36
local MATCH_MIN = 20
local MATCH_SPREAD = 0.01

local button, scanning, scanGen = nil, nil, 0
local ownScan, houseOpen, hooked
local tooltipHooked
local houseKey
local priced, pricedAt
local ageTicker
local feedTried, feedHouses, feedTime, feedMedian, matched
local decoded = {}

local function House(create)
    local account = ns.AccountSettings()
    account.ahPrices = account.ahPrices or {}
    houseKey = houseKey or GetRealmName() .. REALM_JOIN .. (UnitFactionGroup("player") or "")
    if create and not account.ahPrices[houseKey] then account.ahPrices[houseKey] = { prices = {} } end
    return account.ahPrices[houseKey]
end

local function FeedHouses()
    if not feedTried then
        feedTried = true
        C_AddOns.LoadAddOn(FEED_ADDON)
        local feed = ns.AuctionFeed
        local region = feed and feed.regions[GetCurrentRegion()]
        local faction = UnitFactionGroup("player")
        for id, house in pairs(region or {}) do
            if house.faction == faction and house.prices ~= "" then
                feedHouses = feedHouses or {}
                feedHouses[id] = house
            end
        end
        feedTime = feed and feed.time
    end
    return feedHouses
end

local function Decode(id)
    if not decoded[id] then
        local prices, item = {}, 0
        for step, price in feedHouses[id].prices:gmatch("(%w+):(%w+)") do
            item = item + tonumber(step, FEED_BASE)
            prices[item] = tonumber(price, FEED_BASE)
        end
        decoded[id] = prices
    end
    return decoded[id]
end

local function Matches(own, feed)
    local count = 0
    for item, price in pairs(own) do
        local other = feed[item]
        if other and math.abs(other - price) <= price * MATCH_SPREAD then count = count + 1 end
    end
    return count
end

local function MatchHouse(house)
    local best, most = false, MATCH_MIN - 1
    for id in pairs(feedHouses) do
        local count = Matches(house.prices, Decode(id))
        if count > most then best, most = id, count end
    end
    return best
end

local function Median()
    if not feedMedian then
        local all = {}
        for id in pairs(feedHouses) do
            for item, price in pairs(Decode(id)) do
                all[item] = all[item] or {}
                all[item][#all[item] + 1] = price
            end
        end
        feedMedian = {}
        for item, list in pairs(all) do
            table.sort(list)
            feedMedian[item] = list[math.ceil(#list / 2)]
        end
    end
    return feedMedian
end

local function FeedPrices()
    if not FeedHouses() then return end
    local house = House()
    if matched == nil then matched = house and house.time and MatchHouse(house) or false end
    if matched then return Decode(matched) end
    return Median()
end

local function FeedNewer(house, feed)
    return feed and not (house and house.time and house.time >= feedTime)
end

function ns.AuctionPrice(itemID)
    if not itemID then return end
    local house, feed = House(), FeedPrices()
    local own = house and house.time and house.prices[itemID]
    if feed and feed[itemID] and (not own or FeedNewer(house, feed)) then return feed[itemID], feedTime end
    if own then return own, house.time end
end

function ns.AuctionScanTime()
    local house, feed = House(), FeedPrices()
    if FeedNewer(house, feed) then return feedTime end
    return house and house.time
end

function ns.AuctionPriceList()
    local house, feed = House(), FeedPrices()
    if FeedNewer(house, feed) then return feed, feedTime end
    return house and house.prices, house and house.time
end

local function Age(seconds)
    if seconds < SECONDS_PER_HOUR then return math.max(1, math.floor(seconds / SECONDS_PER_MINUTE)) .. MINUTES end
    if seconds < SECONDS_PER_DAY then return math.floor(seconds / SECONDS_PER_HOUR) .. HOURS end
    return math.floor(seconds / SECONDS_PER_DAY) .. DAYS
end
ns.AuctionAge = Age

local function Priced(house)
    if pricedAt ~= house.time then
        priced = 0
        for _ in pairs(house.prices) do priced = priced + 1 end
        pricedAt = house.time
    end
    return priced
end

local function ScanLine()
    local house = House()
    if not (house and house.time) then return TEXT_NO_SCAN end
    return TEXT_SCAN_LINE:format(Age(time() - house.time), BreakUpLargeNumbers(Priced(house)))
end

local function FeedLine(prices)
    local count = 0
    for _ in pairs(prices) do count = count + 1 end
    return TEXT_FEED_LINE:format(Age(time() - feedTime), BreakUpLargeNumbers(count))
end

function ns.AuctionScanSummary()
    local house, feed = House(), FeedPrices()
    if FeedNewer(house, feed) then return FeedLine(feed) .. "." end
    return ScanLine() .. "."
end

local function Label(text)
    if button then button.label:SetText(text) end
end

local function Wait()
    local house = House()
    local last = house and math.max(house.time or 0, house.requested or 0)
    return last and SCAN_COOLDOWN - (time() - last)
end

local function ShowAge()
    if not (button and button.age) then return end
    local house = House()
    local wait = Wait()
    local nextScan = wait and wait > 0 and TEXT_NEXT:format(math.ceil(wait / SECONDS_PER_MINUTE)) or ""
    if not (house and house.time) then return button.age:SetText(TEXT_NO_SCAN_SHORT .. nextScan) end
    button.age:SetText(TEXT_AGE:format(Age(time() - house.time), nextScan))
end

local events = CreateFrame("Frame")

local function Stop(message)
    scanning = nil
    scanGen = scanGen + 1
    events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    Label(TEXT_SCAN)
    if message and ownScan then ns.Print(Tag() .. ": " .. message) end
    ownScan = nil
end

local function ReadListing(prices, i)
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
        C_AuctionHouse.GetReplicateItemInfo(i)
    if not (itemID and buyout and buyout > 0 and count and count > 0) then return end
    local each = math.floor(buyout / count)
    if not prices[itemID] or each < prices[itemID] then prices[itemID] = each end
end

local function Finish(prices)
    local house = House(true)
    house.prices, house.time = prices, time()
    matched = nil
    Stop()
    ShowAge()
    ns.Print(Tag() .. ": " .. ns.AuctionScanSummary())
    if ns.ProfWindowRefresh then ns.ProfWindowRefresh() end
end

local function Read()
    events:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    scanGen = scanGen + 1
    local total = C_AuctionHouse.GetNumReplicateItems()
    if total == 0 then return Stop(TEXT_EMPTY) end
    local prices, index, gen = {}, 0, scanGen
    local function Step()
        if gen ~= scanGen then return end
        local last = math.min(index + CHUNK, total) - 1
        for i = index, last do ReadListing(prices, i) end
        index = last + 1
        if index < total then
            Label(TEXT_PROGRESS:format(math.floor(index * PERCENT / total)))
            C_Timer.After(0, Step)
            return
        end
        Finish(prices)
    end
    Step()
end

local function OnTimeout(gen)
    if gen ~= scanGen or not scanning then return end
    Stop(TEXT_TIMEOUT)
    events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
end

local function Scan()
    if scanning then return end
    local wait = Wait()
    if wait and wait > 0 then
        ns.Print(TEXT_WAIT:format(Tag(), math.ceil(wait / SECONDS_PER_MINUTE)))
        return
    end
    scanning, ownScan = true, true
    scanGen = scanGen + 1
    local gen = scanGen
    House(true).requested = time()
    Label(TEXT_SCANNING)
    events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    C_AuctionHouse.ReplicateItems()
    C_Timer.After(TIMEOUT, function() OnTimeout(gen) end)
end

local function OnReplicate()
    if scanning or not (houseOpen and S.Get("ahCapture")) then return end
    scanning = true
    scanGen = scanGen + 1
    local gen = scanGen
    House(true).requested = time()
    events:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    C_Timer.After(TIMEOUT, function() OnTimeout(gen) end)
end

local function HookReplicate()
    if hooked or not S.Get("ahCapture") then return end
    hooked = true
    hooksecurefunc(C_AuctionHouse, "ReplicateItems", OnReplicate)
end

local function ButtonTip()
    return TEXT_TIP .. ns.AuctionScanSummary()
end

local function LastTab(frame)
    local lib = LibStub and LibStub("LibAHTab-1-0", true)
    local tabs = lib and lib.internalState and lib.internalState.Tabs
    if tabs and #tabs > 0 then return tabs[#tabs] end
    return frame.AuctionsTab
end

local function Anchor()
    local frame = _G.AuctionHouseFrame
    if not (button and frame) then return end
    button:ClearAllPoints()
    local tab = LastTab(frame)
    if tab then
        button:SetPoint("LEFT", tab, "RIGHT", BUTTON_GAP, 0)
    else
        button:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -BUTTON_GAP, -BUTTON_DROP)
    end
end

local function BuildButton(frame)
    button = ns.Button(frame, TEXT_SCAN, BUTTON_W, BUTTON_H, Scan)
    ns.Tooltip(button, TEXT_SCAN, ButtonTip)
    button.age = ns.Font(button, AGE_SIZE, nil, ns.THEME.muted)
    button.age:SetPoint("LEFT", button, "RIGHT", BUTTON_GAP, 0)
end

local function ShowButton()
    local frame = _G.AuctionHouseFrame
    if not frame or ns.GamepadStandDown() then return end
    if not button then BuildButton(frame) end
    Anchor()
    C_Timer.After(0, Anchor)
    button:SetShown(S.Get("ahPrices"))
    ShowAge()
    if S.Get("ahPrices") and not ageTicker then ageTicker = C_Timer.NewTicker(AGE_TICK, ShowAge) end
end

local function OnClosed()
    houseOpen = nil
    Stop(scanning and TEXT_CLOSED)
    if ageTicker then
        ageTicker:Cancel()
        ageTicker = nil
    end
end

local function OnEvent(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        houseOpen = true
        ShowButton()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        OnClosed()
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        Read()
    end
end

local function Price(itemID)
    return (ns.AuctionPrice(itemID))
end

local function Cheapest(bundles)
    local cheapest
    for i = 1, #bundles do
        local price = Price(bundles[i][1])
        local total = price and price * bundles[i][2]
        if total and (not cheapest or total < cheapest) then cheapest = total end
    end
    return cheapest
end

local function AddBundles(tooltip, bundles, cheapest)
    for i = 1, #bundles do
        local item, count = bundles[i][1], bundles[i][2]
        local price = Price(item)
        local total = price and price * count
        if total then
            local coins, color = C_CurrencyInfo.GetCoinTextureString(total, COIN_SIZE), WHITE
            if total == cheapest then
                coins, color = coins .. " " .. ns.Color("muted", TEXT_CHEAPEST), ns.THEME.accent
            end
            tooltip:AddDoubleLine(TEXT_FILLING:format(count, Items.Name(item)), coins,
                color.r, color.g, color.b, WHITE.r, WHITE.g, WHITE.b)
        end
    end
end

local function OnItemTooltip(tooltip, data)
    local own, crates = S.Get("ahTooltip"), S.Get("ahCrates")
    if not (own or crates) then return end
    local id = data and data.id
    if not id or (issecretvalue and issecretvalue(id)) then return end
    local at = ns.AuctionScanTime()
    if not at then return end
    local price, priceAt
    if own then price, priceAt = ns.AuctionPrice(id) end
    local bundles = crates and ns.WaylaidCrates[id]
    local cheapest = bundles and Cheapest(bundles)
    if not (price or cheapest) then return end
    local age = Age(time() - (priceAt or at))
    local right = price and C_CurrencyInfo.GetCoinTextureString(price, COIN_SIZE) .. TEXT_EACH:format(age)
        or TEXT_AGE:format(age, "")
    tooltip:AddDoubleLine(ns.Color("accent", TEXT_TOOLTIP_TAG), right, WHITE.r, WHITE.g, WHITE.b, WHITE.r, WHITE.g, WHITE.b)
    if cheapest then AddBundles(tooltip, bundles, cheapest) end
end

local function HookTooltip()
    if tooltipHooked or not (S.Get("ahTooltip") or S.Get("ahCrates")) then return end
    tooltipHooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end

local function OnSettingChanged(key)
    if key == "ahPrices" and button then button:SetShown(S.Get("ahPrices")) end
    if key == "ahCapture" then HookReplicate() end
    if key == "ahTooltip" or key == "ahCrates" then HookTooltip() end
end

events:SetScript("OnEvent", OnEvent)
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
hooksecurefunc(S, "Set", OnSettingChanged)
hooksecurefunc(ns, "Apply", HookTooltip)
HookReplicate()
HookTooltip()

ns.Shared.Settings.Page("QoL/Loot & Items", S):Card({
    id = "auctionPrices", name = "Auction Prices", order = 30, into = "lootTrade",
    rows = {
        { key = "ahPrices", label = "Scan Prices Button", toggle = true, note = ScanLine,
          needs = ns.GamepadFree, why = ns.GamepadWhy,
          help = "A Scan Prices button on the auction house. It reads every listing and keeps the "
              .. "lowest buyout for each item, for this realm and faction. Blizzard allows one full "
              .. "scan every 15 minutes." },
        { key = "ahTooltip", label = "Auction House Price", toggle = true,
          help = "Item tooltips show an item's auction house price and how old it is." },
        { key = "ahCrates", label = "Waylaid Crate Prices", toggle = true,
          help = "Waylaid Crate tooltips show what each filling costs on the auction house." },
        { key = "ahCapture", label = "Capture Other Addons' Scans", toggle = true,
          help = "Also keeps the prices from full auction house scans that other addons start, "
              .. "such as Auctionator or TSM." },
    },
})
