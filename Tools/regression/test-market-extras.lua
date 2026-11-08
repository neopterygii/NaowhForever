-- Run with Lua 5.1 from the repository root: The Market's sales log and Buy's favourites.
local World = dofile("Tools/regression/market_world.lua")

local checks = 0
local function Check(label, value) assert(value, label); checks = checks + 1 end

local DAY = 86400
local t = World.Setup({ keyInfo = { [2770] = { isCommodity = true } } })
local Sales, Buy, A = t.M.Sales, t.M.Buy, t.M.Auctions

Check("no sales yet", Sales.Since(7 * DAY) == 0 and Sales.Last(2770) == nil)
t.now = 10 * DAY
Check("a sale is noted", Sales.Note(501, 2770, 20, 100))
Check("only once per auction", not Sales.Note(501, 2770, 20, 100))
Check("a sale with no price is not", not Sales.Note(502, 2770, 1, 0))
local total, count = Sales.Since(7 * DAY)
Check("the week's sales are counted after the cut", total == 20 * 95 and count == 1)
Check("the last sale of an item is found", Sales.Last(2770).qty == 20 and Sales.Last(2770).at == 10 * DAY)

t.now = 20 * DAY
Sales.Note(503, 2770, 5, 120)
total, count = Sales.Since(7 * DAY)
Check("an older sale drops out of the week", total == 5 * 114 and count == 1)
Check("the newest sale is the last", Sales.Last(2770).price == 120)
for i = 1, 205 do Sales.Note(1000 + i, 4000 + i, 1, 10) end
local house = t.account.marketSales["Realm-Horde"]
Check("only the last 200 sales are kept", #house.list == 200 and house.seen[503] == nil and house.seen[1205])

t.owned = {
    { auctionID = 77, itemKey = { itemID = 2770, itemLevel = 0, itemSuffix = 0 }, quantity = 10, buyoutAmount = 90,
      status = 1, timeLeftSeconds = 0 },
    { auctionID = 78, itemKey = { itemID = 2770, itemLevel = 0, itemSuffix = 0 }, quantity = 4, buyoutAmount = 95,
      status = 0, timeLeftSeconds = 3600 },
}
A.Start()
t.Fire("OWNED_AUCTIONS_UPDATED")
Check("a sold auction in My Auctions is noted as a sale", house.seen[77] == true and Sales.Last(2770).id == 77)
Check("one still up is not", house.seen[78] == nil)
t.Fire("OWNED_AUCTIONS_UPDATED")
Check("reading My Auctions again notes it once", house.list[1].id == 77 and house.list[2].id ~= 77)
A.Stop()

Check("nothing is a favourite at first", not Buy.IsFavourite(2589) and #Buy.Favourites({}) == 0)
Buy.ToggleFavourite(2589)
Buy.ToggleFavourite(2770)
local list = Buy.Favourites({})
Check("starring keeps an item", Buy.IsFavourite(2589) and #list == 2 and list[1] == 2589 and list[2] == 2770)
Buy.ToggleFavourite(2589)
Check("starring again lets it go", not Buy.IsFavourite(2589) and #Buy.Favourites(list) == 1)

print("market extras: " .. checks .. " checks passed")
