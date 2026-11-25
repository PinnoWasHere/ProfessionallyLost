-- Stops a second copy of ProfLost from loading. The stable and the Dev folder share saved
-- variables, so only one may run. The first copy to load sets the global ProfLost (Init.lua).
-- A later copy finds it, sets its namespace's `stopped` flag and prints one line. Every later
-- file of that copy begins "if CP.stopped then return end". The stopped copy makes one frame,
-- which waits for the first PLAYER_ENTERING_WORLD, prints there (chat frames can be rebuilt
-- after addons load and drop earlier lines), and unregisters.

local ADDON, CP = ...

-- True when another copy than `ns` is loaded already.
function CP.Guard(ns, folder)
    local first = rawget(_G, "ProfLost")
    if type(first) ~= "table" or first == ns then return false end
    ns.stopped = true
    local line = ("Professionally Lost: %s is already loaded, so %s stays off. Turn one of them off in the addon list."):format(
        tostring(first.name), tostring(folder))
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        self:SetScript("OnEvent", nil)
        print(line)
    end)
    return true
end

CP.Guard(CP, ADDON)
