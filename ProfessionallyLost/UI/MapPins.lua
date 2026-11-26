local _, CP = ...
if CP.stopped then return end

-- ProfLost's HereBeDragons pins on the world map and minimap. HereBeDragons
-- places them on whatever map the player uses: the minimap frame it holds (Blizzard's,
-- or one a minimap addon moved, reshaped or rescaled) and WorldMapFrame's canvas.
--
-- A pin waits in a hidden home while no map holds it. HereBeDragons gives a released world
-- map pin to UIParent, and a map addon that hands it back there and shows it would put it
-- in the middle of the screen, so a pin given to UIParent or to no parent goes home instead.

local Pins = LibStub("HereBeDragons-Pins-2.0")

local MapPins = {}
CP.MapPins = MapPins

local home = CreateFrame("Frame", nil, UIParent)
home:Hide()
MapPins.home = home

local function homeless(f, parent)
    if parent == nil or parent == UIParent then f:SetParent(home) end
end

-- HereBeDragons reads the minimap's size only when the player moves or zooms, so pins on a
-- minimap an addon resizes keep the old spacing until then. A resize places them again.
local watched

local function resized()
    if Pins.SetMinimapObject then Pins:SetMinimapObject(Pins.Minimap) end
end

local function watch()
    local mm = Pins.Minimap
    if mm and mm ~= watched and mm.HookScript then
        watched = mm
        mm:HookScript("OnSizeChanged", resized)
    end
end
if Pins.SetMinimapObject then hooksecurefunc(Pins, "SetMinimapObject", watch) end

-- Makes a new frame a map pin: unseen until a map places it.
function MapPins.Adopt(f)
    watch()
    f:SetParent(home)
    hooksecurefunc(f, "SetParent", homeless)
    return f
end
