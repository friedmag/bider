-- BidER 1.0, by Quilderaumo (chrisqeld@gmail.com)
-- 
-- Handles bids/DKP system for Eternal Retribution
-- Type /ber or /bider to open.
-- 

-- Constants:
local VERSION = "1.0"

-- Data:
local frame
local events = {}
local biditems = {}
local buttons = {}

-------------------
-- Helper Functions
-------------------

-- Print: helper function to send message to default chat frame. Messages will be prefixed with "BidER: "
local function Print(text)
	if (DEFAULT_CHAT_FRAME) then
		DEFAULT_CHAT_FRAME:AddMessage("BidER: " .. text)
	end
end

local function BidER_SendEvent(self, event, ...)
  if events[event] == nil then
    error("Invalid BidER event: " .. event)
  end
  events[event](self, ...)
end

local function GetButton(set, pos, parent)
  if buttons[set] == nil then
    buttons[set] = {}
  end
  if #buttons[set] < pos then
    button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    tinsert(buttons[set], pos, button)
  else
    button = buttons[set][pos]
    button:SetParent(parent)
  end
  return button
end

-- For global callbacks (buttons, etc.)
function BidER_Event(event, ...)
  BidER_SendEvent(nil, event, ...)
end

----------------------
-- Setup slash command
----------------------
SLASH_BIDER1 = "/bider"
SLASH_BIDER2 = "/ber"

SlashCmdList["BIDER"] = function(...)
  BidER_Event("SlashCommand", ...)
end

-----------------
-- Initialization
-----------------
function events:OnLoad()
  Print("Loaded " .. VERSION)
  frame = BidERHoverFrame
  frame:SetScript("OnEvent", BidER_SendEvent)
  frame:RegisterEvent("CHAT_MSG_WHISPER")
  hooksecurefunc("ChatFrame_OnHyperlinkShow", function(...) BidER_Event("HyperlinkShow", ...) end)
end

-----------------
-- Main Functions
-----------------
local function AddLink(itemLink)
  if BidERPickItemFrame:IsVisible() then
    tinsert(biditems, itemLink)
    useText = ""
    for i,v in ipairs(biditems) do
      useText = useText .. v
    end
    BidERPickItemFrameEditBox:SetText(useText);
  end
end

-----------------
-- Hook Functions
-----------------
-- ChatFrame_OnHyperlinkShow hook: on shift-left-click, if Pick Item frame waiting, put link there.
function events:HyperlinkShow(ref, linkText, itemLink, button, ...)
	if (BidERPickItemFrame:IsVisible() and IsShiftKeyDown() and button == "LeftButton") then
		AddLink(itemLink);
	end
end

function events:SlashCommand(command, ...)
  if command == "" then
    frame:Show()
  elseif command == "help" then
    Print("Usage for /bider or /ber:")
  end
end

function events:CHAT_MSG_WHISPER(msg, from, ...)
  item, value = string.match(msg, "(\124.+) ([0-9]+)")
  if item == nil or value == nil then
    item, value = string.match(msg, "([0-9]+) (\124.+)")
  end
  if item == nil or value == nil then
    -- Couldn't figure out the message
    return
  end
  Print("SO... " .. from .. ": " .. item .. " for " .. value .. " (" .. value:gsub("\124", "!") .. ")")
end

----------------------
-- Button/UI Functions
----------------------
function events:Close()
  frame:Hide()
end

function events:PickItem()
  BidERPickItemFrame:Show()
  if GetNumLootItems() > 0 then
    for i=1,GetNumLootItems() do
      local _, _, quantity, rarity, _ = GetLootSlotInfo(i)
      if rarity >= 3 then
        AddLink(GetLootSlotLink(i))
      end
    end
  end
end

function events:PickItemOkay()
  local prev
  local button
  for i,v in ipairs(biditems) do
    button = GetButton('scroll', i, BidERScrollChild)
    button:SetText(v)
    if prev == nil then
      button:SetPoint("TOPLEFT", BidERScrollChild, "TOPLEFT", 0, -2)
    else
      button:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
    end
    button:SetWidth(200)
    button:SetHeight(25)
    button:Show()
    prev = button
  end
  BidERPickItemFrame:Hide()
end
