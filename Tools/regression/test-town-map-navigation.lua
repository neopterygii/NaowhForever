-- Town-map zone exits and docks use the real shared map-opening helper: Gamepad UI and cursor auto-control never open a game panel; keyboard/mouse keeps both destinations and combat opens neither.
local function Read(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"):gsub("\r\n", "\n"); f:close(); return s
end
local checks, pad, cursor, combat, opened, printed = 0, false, false, false, {}, {}
local function Check(ok, label) assert(ok, label); checks = checks + 1 end
local ns = { Shared = { SameMaps = {} }, L = function(s) return s end,
    GamepadOwnsPanels = function() return pad or cursor end,
    Print = function(s) printed[#printed + 1] = s end }
local env = setmetatable({ _G = { NaowhForever = ns }, ns = ns, NaowhForeverZoneLinkPinMixin = {},
    InCombatLockdown = function() return combat end,
    C_Map = { OpenWorldMap = function(id)
        assert(not (pad or cursor or combat), "no game map opening while Gamepad owns panels or in combat")
        opened[#opened + 1] = id
    end },
}, { __index = _G })
local function Load(source) local chunk = assert(loadstring(source)); setfenv(chunk, env); chunk() end
Load(Read("Shared/Game/Places.lua"))
local source = Read("NaowhForever_QoL/Interface/TownMap.lua")
Load(assert(source:match("(function NaowhForeverZoneLinkPinMixin:OnClick%(button%).-\nend)")))
local pin = { link = { linkedUiMapID = 1413, rightUiMapID = 1420 } }
local click = env.NaowhForeverZoneLinkPinMixin.OnClick
pad = true
click(pin, "LeftButton"); click(pin, "RightButton")
Check(#opened == 0 and #printed == 2, "Gamepad gives the shared reason for both destinations")
pad, cursor = false, true
click(pin, "LeftButton"); click(pin, "RightButton")
Check(#opened == 0 and #printed == 4, "cursor auto-control also leaves both panels alone")
cursor = false
click(pin, "LeftButton"); click(pin, "RightButton")
Check(opened[1] == 1413 and opened[2] == 1420, "keyboard/mouse opens the primary and alternate destinations")
combat = true
click(pin, "LeftButton"); click(pin, "RightButton")
Check(#opened == 2, "combat opens neither destination")
combat = false
pin.link.rightUiMapID = nil
click(pin, "RightButton")
Check(#opened == 2, "a zone exit without an alternate ignores right-click")
print(("town-map-navigation: %d checks passed"):format(checks))
