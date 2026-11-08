-- Sales.lua: what you sold, noted from your sold auctions at the auction house, per realm and faction (Market.Sales).
local ns = _G.NaowhForever

local Market = ns.Market
local C = Market.C

local STORE = "marketSales"

local Sales = {}
Market.Sales = Sales

local function House(create)
    local account = ns.AccountSettings()
    local all = account[STORE]
    if not all then
        if not create then return end
        all = {}
        account[STORE] = all
    end
    local key = Market.HouseKey()
    if not all[key] and create then all[key] = { list = {}, seen = {} } end
    return all[key]
end

function Sales.Note(auctionID, itemID, quantity, price)
    if not (auctionID and price and price > 0) then return false end
    local house = House(true)
    if house.seen[auctionID] then return false end
    house.seen[auctionID] = true
    table.insert(house.list, 1, { id = auctionID, item = itemID, qty = quantity, price = price, at = time() })
    while #house.list > C.SALES_KEEP do
        local old = table.remove(house.list)
        house.seen[old.id] = nil
    end
    return true
end

function Sales.Since(seconds)
    local house = House()
    local total, count, from = 0, 0, time() - seconds
    for _, sale in ipairs(house and house.list or {}) do
        if sale.at < from then break end
        total, count = total + math.floor(sale.price * sale.qty * (1 - C.AH_CUT)), count + 1
    end
    return total, count
end

function Sales.Last(itemID)
    local house = House()
    for _, sale in ipairs(house and house.list or {}) do
        if sale.item == itemID then return sale end
    end
end
