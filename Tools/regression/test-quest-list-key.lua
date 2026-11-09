-- Quest List default key: Gamepad style never writes/saves bindings or consumes the first-login marker; keyboard/mouse retains the free-key and already-bound checks.
local checks = 0
local function Check(ok, label) assert(ok, label); checks = checks + 1 end
local function Fixture(gamepad, account, taken, existing)
    local h = { writes = 0, saves = 0, enabled = true }
    local frame
    local ns = {
        L = function(s) return s end, Print = function() end,
        GamepadStandDown = function() return gamepad end,
        AccountSettings = function() return account end,
        Completo = { CharKey = function() return "Player-1" end,
            Settings = { Get = function() return h.enabled end, Set = function() end } },
    }
    local env = setmetatable({ _G = { NaowhForever = ns },
        InCombatLockdown = function() return h.combat end,
        GetBindingKey = function() return existing end,
        GetBindingAction = function() return taken or "" end,
        GetBindingName = function(s) return s end,
        SetBinding = function(key, action)
            assert(not gamepad, "no automatic binding writes under Gamepad style")
            h.writes, h.key, h.action = h.writes + 1, key, action
        end,
        SaveBindings = function() assert(not gamepad); h.saves = h.saves + 1 end,
        GetCurrentBindingSet = function() return 1 end,
        hooksecurefunc = function(_, _, fn) h.setting = fn end,
        CreateFrame = function()
            frame = { SetScript = function(self, _, fn) self.event = fn end, RegisterEvent = function() end,
                UnregisterAllEvents = function() end }
            return frame
        end,
    }, { __index = _G })
    local chunk = assert(loadfile("NaowhForever_Discovery/QuestList/KeyBinding.lua"))
    setfenv(chunk, env); chunk()
    h.login = function() frame.event(frame) end
    return h
end
local account = {}
local pad = Fixture(true, account)
pad.login(); pad.setting("enabled")
Check(pad.writes == 0 and pad.saves == 0, "Gamepad login and settings changes leave bindings alone")
Check(not account.completoKeySet, "Gamepad does not consume the first-time marker")
local mouse = Fixture(false, account)
mouse.login()
Check(mouse.writes == 1 and mouse.saves == 1 and mouse.key == "SHIFT-L"
    and mouse.action == "NAOWHFOREVER_COMPLETO", "a later keyboard/mouse login still gets its default key")
mouse.setting("enabled")
Check(mouse.writes == 1, "the key is assigned only once")
local taken = Fixture(false, {}, "QUESTLOG")
taken.login(); Check(taken.writes == 0, "an occupied Shift-L is kept")
local bound = Fixture(false, {}, nil, "F8")
bound.login(); Check(bound.writes == 0, "an existing Quest List key is kept")
local off = Fixture(false, {}); off.enabled = false; off.login()
Check(off.writes == 0, "off does not assign a key")
local combat = Fixture(false, {}); combat.combat = true; combat.login()
Check(combat.writes == 0, "combat does not assign a key")
print(("quest-list-key: %d checks passed"):format(checks))
