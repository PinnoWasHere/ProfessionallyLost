local _, CP = ...
if CP.stopped then return end

-- Marks guide recipes on Daylight UI's recipe lines (Paint kind "craftrow"): an accent bar
-- on the left edge, full for the current step, faint for later steps. Drawn on the
-- holder Daylight UI hands out (API.Attach), never on its own pieces.

local CraftRows = {}
CP.CraftRows = CraftRows

CraftRows.STEP_ALPHA = 0.35
local BAR_W = 3

local api
local lines = setmetatable({}, { __mode = "k" })   -- line -> recipeID
local marks = {}                                    -- recipeID -> "current" | "step"

local function bar(line)
    local holder = api.Attach(line)
    if not holder then return nil end
    if not holder.cpBar then
        local t = holder:CreateTexture(nil, "OVERLAY")
        t:SetPoint("TOPLEFT")
        t:SetPoint("BOTTOMLEFT")
        t:SetWidth(BAR_W)
        holder.cpBar = t
    end
    return holder.cpBar
end

local function paint(line, recipeID)
    local b = bar(line)
    if not b then return end
    local mark = recipeID and marks[recipeID]
    if not mark then return b:Hide() end
    local c = CP.Style.color.accent
    b:SetColorTexture(c[1], c[2], c[3], mark == "current" and 1 or CraftRows.STEP_ALPHA)
    b:Show()
end

-- The guide's step recipes: { [recipeID] = "current" | "step" }. Repaints the lines on show.
function CraftRows.Set(newMarks)
    marks = newMarks or {}
    if not api then return end
    for line, id in pairs(lines) do paint(line, id) end
end

function CraftRows.Marks() return marks end

-- Plugin.Start hands over `me` and the API. Nothing happens without Paint and Attach.
function CraftRows.UseDaylight(me, API)
    if not (me and type(me.Paint) == "function" and API and type(API.Attach) == "function") then
        return false
    end
    api = API
    me.Paint("craftrow", function(line, _, info)
        local id = type(info) == "table" and info.recipeID or nil
        lines[line] = id or false
        paint(line, id)
    end)
    return true
end
