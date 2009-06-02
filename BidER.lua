-- BidER 1.0, by Quilderaumo (chrisqeld@gmail.com)
-- 
-- Handles bids/DKP system for Eternal Retribution
-- Type /ber or /bider to open.
-- 

-- Constants:
local VERSION = "1.0"

-- Data:
BidER_DKP = {} -- Stores player DKP amounts
BidER_Loots = {} -- Stores loots taken by players
local dkp = BidER_DKP
local loots = BidER_Loots
local frame
local events = {}
local biditems = {}
local buttons = {}
local pick_active = false
local auction_active = false
local link_regex = "|c%x+|H[^|]+|h%[[^|]+%]|h|r"

-------------------
-- Helper Functions
-------------------

-- Print: helper function to send message to default chat frame. Messages will be prefixed with "BidER: "
local function Print(text)
	if (DEFAULT_CHAT_FRAME) then
		DEFAULT_CHAT_FRAME:AddMessage("BidER: " .. text)
	end
end

local function PostChat(msg)
  local target = "RAID"
  if GetNumRaidMembers() == 0 then
    target = "PARTY"
  end
  if GetNumPartyMembers() == 0 then
    Print("[CHAT] " .. msg)
  else
    SendChatMessage("BidER: " .. msg, target)
  end
end

local function PostMsg(msg, target)
  if target == UnitName("player") then
    Print("[MSG] " .. msg)
  else
    SendChatMessage("BidER: " .. msg, "WHISPER", nil, target)
  end
end

local function BidER_SendEvent(self, event, ...)
  if events[event] == nil then
    error("Invalid BidER event: " .. event)
  end
  events[event](self, ...)
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

SlashCmdList.BIDER = function(...)
  BidER_Event("SlashCommand", ...)
end

-----------------
-- Initialization
-----------------
function events:OnLoad()
  Print("Loaded " .. VERSION)
  frame = BidERHoverFrame
  frame:SetScript("OnEvent", BidER_SendEvent)
  hooksecurefunc("ChatFrame_OnHyperlinkShow", function(...) BidER_Event("HyperlinkShow", ...) end)
end

-----------------
-- Main Functions
-----------------
local function PrintHelp()
  Print("Usage for /bider (or /ber):")
end

local function AddLink(item_link, count)
  if pick_active then
    for i,v in ipairs(biditems) do
      if v.item_link == item_link then
        v.count = v.count + count
        Print("Updated item: " .. item_link .. "x" .. v.count)
        return
      end
    end
    tinsert(biditems, {item_link=item_link, bids={}, count=count})
    Print("Adding item: " .. item_link .. "x" .. count)
  end
end

local function EndItemPicking()
  if pick_active then
    pick_active = false
    Print("item picking completed.")
    for i,v in ipairs(biditems) do
      Print("Item: " .. v.item_link)
    end
  else
    Print("item picking is not in progress.")
  end
end

-----------------
-- Hook Functions
-----------------
function events:SlashCommand(args, ...)
  local space, cmd
  space = args:find(" ")
  if space == nil then
    cmd, args = args, ""
  else
    cmd = args:sub(1, space-1)
    args = args:sub(space+1)
  end
  if cmd == "" or cmd == "help" then
    PrintHelp()
  elseif cmd == "dkp" then
    BidER_Event("DKPCommand", args)
  elseif cmd == "pick" then
    BidER_Event("PickCommand", args)
  elseif cmd == "start" then
    BidER_Event("StartAuctionCommand", args)
  elseif cmd == "end" then
    BidER_Event("EndAuctionCommand", args)
  elseif cmd:match('^ann') then
    BidER_Event("AnnounceCommand", args)
  else
    Print("Unknown command: " .. cmd)
    PrintHelp()
  end
end

local function DumpBidInfo()
  local count_msg = ""
  local player = UnitName("player")
  for i,v in ipairs(biditems) do
    if v.bids == nil or #v.bids == 0 then count_msg = "no bids"
    elseif #v.bids == 1 then count_msg = #v.bids .. " bid"
    else count_msg = #v.bids .. " bids" end
    PostChat(v.item_link .. "x" .. v.count .. " -- " .. count_msg)
  end
  PostChat("To bid on any item: /w " .. player .. " <link> <bid amount>")
  PostChat("To see your current DKP: /w " .. player .. " dkp")
end

function events:AnnounceCommand(args)
  DumpBidInfo()
end

function events:StartAuctionCommand(args)
  if auction_active then
    Print("Auction is already active")
    return
  end
  EndItemPicking()
  if #biditems == 0 then
    Print("No items have been picked for bidding.  Use /ber pick")
    return
  end
  auction_active = true
  frame:RegisterEvent("CHAT_MSG_WHISPER")
  PostChat("Auction is now in progress")
  DumpBidInfo()
end

function events:DKPCommand(args)
  local old_value
  local name,value = strsplit(" ", args)

  if dkp[name] == nil then dkp[name] = {} end
  if dkp[name].total ~= nil then old_value = dkp[name].total end
  dkp[name].total = tonumber(value)

  if dkp[name].total == nil then
    Print("Invalid DKP value for " .. name)
    return
  end

  if dkp[name].total ~= old_value then
    local was_str = ""
    if old_value ~= nil then was_str = " (was: " .. old_value .. ")"end
    Print("DKP value for " .. name .. " updated: " .. dkp[name].total .. was_str)
  else
    Print("DKP value for " .. name .. " unchanged (" .. old_value .. ")")
  end
end

function events:PickCommand(args)
  if auction_active then
    Print("An auction is already active!")
    return
  end
  local opt1,opt2 = strsplit(" ", args)
  if opt1 == "stop" then
    EndItemPicking()
  else
    if not pick_active then
      pick_active = true
      biditems = {}
      Print("item picking now in progress.")
    end
    if opt1 == "loot" then
      local threshold = 3
      if opt2 ~= nil then threshold = tonumber(opt2) end
      for i=1,GetNumLootItems() do
        local _, _, quantity, rarity, _ = GetLootSlotInfo(i)
        if rarity >= threshold then
          AddLink(GetLootSlotLink(i), quantity)
        end
      end
    elseif opt1 == "remove" then
      for link in args:gmatch(link_regex) do
        RemoveLink(link)
      end
    else
      for link in args:gmatch(link_regex) do
        AddLink(link, 1)
      end
    end
  end
end

-- ChatFrame_OnHyperlinkShow hook: on shift-left-click, if we're collecting items to bid on, add it
function events:HyperlinkShow(ref, link_text, item_link, button, ...)
	if pick_active and IsShiftKeyDown() and button == "LeftButton" then
		AddLink(item_link, 1);
	end
end

local function CancelBid(who, item, bids)
  local old_value
  for j,w in ipairs(bids) do
    if w.name == who then
      old_value = tremove(bids, j)
      break
    end
  end
  if old_value == nil then
    PostMsg("You do not have a bid in for " .. item, who)
  else
    PostMsg("Cancelled bid for " .. item, who)
  end
end

local function PlaceBid(who, item, bids, amount)
  local tosend, old_value
  for j,w in ipairs(bids) do
    if w.name == who then
      old_value = tremove(bids, j)
      break
    end
  end
  tinsert(bids, {name=who, amount=amount})
  if old_value then
    tosend = "Updated bid for " .. item .. " from " .. old_value.amount .. " to " .. amount
  else
    tosend = "Recorded bid for " .. item .. ": " .. amount
  end
  PostMsg(tosend .. ".  You can still update your bid. To cancel, /w " ..
    UnitName("player") .. " " .. item .. " cancel", who)
end

function events:CHAT_MSG_WHISPER(msg, from, ...)
  if msg == "cancel" then
    -- TODO: Cancel all bids
    return
  elseif msg == "dkp" then
    if dkp[from] == nil or dkp[from].total == nil or dkp[from].total == 0 then
      PostMsg("You have no DKP.", from)
    else
      PostMsg("You have " .. dkp[from].total .. " DKP.", from)
    end
    return
  end
  local found
  for item, value in string.gmatch(msg, "(" .. link_regex .. ")" .. "([^|]*)") do
    found = false
    for i,v in ipairs(biditems) do
      if v.item_link == item then
        found = true
        if value:match('cancel') then
          CancelBid(from, item, v.bids)
        elseif tonumber(value) ~= nil then
          PlaceBid(from, item, v.bids, tonumber(value))
        else
          PostMsg("Couldn't determine bid for " .. item .. ": '" .. value .. "'", from)
        end
      end
    end
    if not found then
      PostMsg("There is no auction in progress for " .. item, from)
    end
  end
end

----------------------
-- Button/UI Functions
----------------------
