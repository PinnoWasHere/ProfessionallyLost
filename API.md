# Professionally Lost API

Other addons can open ProfLost's guide window through one global, `ProfessionallyLostAPI`.
It exists once ProfLost has loaded, so check for it before every call.

## Version

`ProfessionallyLostAPI.VERSION` is an integer, currently `1`. A call is only added, never
changed, within a version.

## Calls

| Call | Returns |
|---|---|
| `Open(profession)` | `true`, or `false` and a short reason |
| `Toggle()` | what `Open()` returns when it opens, `true` when it closes |
| `IsShown()` | `true` while the guide window shows |
| `Guides(profession)` | `true` when ProfLost has a guide for the profession |

`profession` is a skill line id (for example `197` for Tailoring) or a name, in English or in
the game's language, any case. `Open()` with no profession keeps the one the window shows.

`Open` reasons you can see:

- `no guide for that profession`
- `profession not learned` (the character does not have it)
- the combat or busy text when ProfLost cannot open the window right now

`Open` never opens the game's own profession window and needs no click, so any button can
call it.

## Example

```lua
local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
button:SetText("Guide")
button:SetScript("OnClick", function()
    local api = ProfessionallyLostAPI
    if api then api.Open("Tailoring") end
end)
button:SetShown(ProfessionallyLostAPI ~= nil and ProfessionallyLostAPI.Guides("Tailoring"))
```
