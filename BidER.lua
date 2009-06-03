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
local pick_active = false
local auction_active = false
local link_regex = "|c%x+|H[^|]+|h%[[^|]+%]|h|r"
local link_regex_p = "(" .. link_regex .. ")"
local sep_regex = "[-_ :;|!]"

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

local function count_pairs(tab)
  local count = 0
  for i,v in pairs(tab) do count = count + 1 end
  return count
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
  frame = CreateFrame("FRAME", nil, UIParent)
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
    if biditems[item_link] ~= nil then
      local v = biditems[item_link]
      v.count = v.count + count
      Print("Updated item: " .. item_link .. "x" .. v.count)
      return
    end
    biditems[item_link] = {bids={}, count=count}
    Print("Adding item: " .. item_link .. "x" .. count)
  end
end

local function RemoveLink(item_link)
  if pick_active then
    if biditems[item_link] == nil then
      Print("Item " .. item_link .. " hasn't been picked, anyway.")
    else
      biditems[item_link] = nil
      Print("Removed item " .. item_link)
    end
  end
end

local function EndItemPicking()
  if pick_active then
    pick_active = false
    Print("item picking completed.")
    for item_link,v in pairs(biditems) do
      Print("Item: " .. item_link)
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
  elseif cmd == "bid" or cmd == "edit" then
    BidER_Event("EditCommand", args)
  elseif cmd:match('^st') then
    BidER_Event("StatusCommand", args)
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
  for item_link,v in pairs(biditems) do
    local bid_count = count_pairs(v.bids)
    if bid_count == 0 then count_msg = "no bids"
    elseif bid_count == 1 then count_msg = bid_count .. " bid"
    else count_msg = bid_count .. " bids" end
    PostChat(item_link .. "x" .. v.count .. " -- " .. count_msg)
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
  if next(biditems) == nil then
    Print("No items have been picked for bidding.  Use /ber pick")
    return
  end
  auction_active = true
  frame:RegisterEvent("CHAT_MSG_WHISPER")
  PostChat("Auction is now in progress")
  DumpBidInfo()
end

function events:EndAuctionCommand(args)
  if not auction_active then
    Print("No auction is active!")
    return
  end
  auction_active = false
  frame:UnregisterEvent("CHAT_MSG_WHISPER")
  PostChat("Bidding is now closed!")
end

local function BidText(bid)
  return (bid.win and "WIN" or bid.amount)
end

function events:StatusCommand(args)
  for item,v in biditems do
    Print("Bids on " .. item)
    for who,bid in v.bids do
      Print("\t" .. who .. " - " .. BidText(bid))
    end
    Print("End of bids.")
  end
end

function events:EditCommand(args)
  for who,link,amount in args:gmatch("(%a+)" .. sep_regex .. "?" .. link_regex_p .. sep_regex .. "?(%w+)") do
    if biditems[link] == nil then
      Print("Not taking bids on " .. link)
    else
      if tonumber(amount) == nil and amount ~= "win" then
        Print("Invalid bid amount '" .. amount .. "' - must be a number or 'win'")
      else
        local bid, toset, toprint = nil, {}, ""
        if tonumber(amount) == nil then toset.win = true else toset.amount = tonumber(amount) end

        local bid = biditems[link][who]
        if bid ~= nil then
          toprint = " (old bid: " .. BidText(bid) .. ")"
        end
        biditems[link][who] = toset
        Print("Updated bid to " .. BidText(bid) .. " for " .. who .. " on " .. link .. toprint)
      end
    end
  end
end

function events:DKPCommand(args)
  local old_value

  if args == "" then
    for name,v in pairs(dkp) do
      Print("DKP for " .. name .. " - " .. v.total)
    end
  else
    for name,value in args:gmatch("(%a+)" .. sep_regex .. "(%d+)") do
      if dkp[name] == nil then dkp[name] = {} end
      if dkp[name].total ~= nil then old_value = dkp[name].total else old_value = nil end
      dkp[name].total = tonumber(value)

      if dkp[name].total ~= old_value then
        local was_str = ""
        if old_value ~= nil then was_str = " (was: " .. old_value .. ")" end
        Print("DKP value for " .. name .. " updated: " .. dkp[name].total .. was_str)
      else
        Print("DKP value for " .. name .. " unchanged (" .. old_value .. ")")
      end
    end
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
  if bids[who] ~= nil then
    old_value, bids[who] = bids[who], nil
  end
  if old_value == nil then
    PostMsg("You do not have a bid in for " .. item, who)
  else
    PostMsg("Cancelled bid for " .. item, who)
  end
end

local function PlaceBid(who, item, bids, amount)
  local tosend, old_value
  if bids[who] ~= nil then
    old_value, bids[who] = bids[who], nil
  end
  bids[who] = {amount=amount}
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
  for item, value in string.gmatch(msg, link_regex_p .. "([^|]*)") do
    local v = biditems[item]
    if v == nil then
      PostMsg("There is no auction in progress for " .. item, from)
      return
    end
    if value:match('cancel') then
      CancelBid(from, item, v.bids)
    elseif tonumber(value) ~= nil then
      PlaceBid(from, item, v.bids, tonumber(value))
    else
      PostMsg("Couldn't determine bid for " .. item .. ": '" .. value .. "'", from)
    end
  end
end

----------------------
-- Button/UI Functions
----------------------

-- Start 'er up
events:OnLoad()
