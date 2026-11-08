-- History.lua: each item's lowest price per day from your scans, two weeks of them per realm and faction (Market.History).
local ns = _G.NaowhForever

local Market = ns.Market
local C = Market.C

local STORE = "marketHistory"
local REALM_JOIN = "-"
local PERCENT = 100

local History = {}
Market.History = History

local function Day(when)
    return math.floor(when / C.SECONDS_PER_DAY)
end

local function House(create)
    local account = ns.AccountSettings()
    local all = account[STORE]
    if not all then
        if not create then return end
        all = {}
        account[STORE] = all
    end
    local key = GetRealmName() .. REALM_JOIN .. (UnitFactionGroup("player") or "")
    local house = all[key]
    if not house and create then
        house = { days = {} }
        all[key] = house
    end
    return house
end

function History.Record()
    local list = ns.AuctionPriceList
    if not list then return false end
    local prices, at = list()
    if not (prices and at) then return false end
    local house = House(true)
    if house.at and house.at >= at then return false end
    house.at = at
    local today = Day(at)
    local day = house.days[today] or {}
    house.days[today] = day
    for id, price in pairs(prices) do
        if not day[id] or price < day[id] then day[id] = price end
    end
    for d in pairs(house.days) do
        if d <= today - C.HISTORY_DAYS then house.days[d] = nil end
    end
    return true
end

local function Latest(house, itemID)
    local today = Day(house.at)
    local day = house.days[today]
    return day and day[itemID], today
end

function History.Change(itemID, days)
    local house = House()
    if not (house and house.at) then return end
    local now, today = Latest(house, itemID)
    if not now then return end
    for back = days, 1, -1 do
        local day = house.days[today - back]
        local past = day and day[itemID]
        if past and past > 0 then return (now - past) / past * PERCENT, back end
    end
end

function History.Series(itemID, out)
    wipe(out)
    local house = House()
    if not (house and house.at) then return out, 0 end
    local today, found = Day(house.at), 0
    for i = 1, C.HISTORY_DAYS do
        local day = house.days[today - C.HISTORY_DAYS + i]
        local price = day and day[itemID]
        out[i] = price or false
        if price then found = found + 1 end
    end
    return out, found
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    if Market.On() then History.Record() end
end)
