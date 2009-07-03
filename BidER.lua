-- BidER 1.0, by Quilderaumo (chrisqeld@gmail.com)
-- 
-- Handles bids/DKP system for Eternal Retribution
-- Type /ber or /bider to open.
-- 

-- Constants:
local VERSION = "1.0"

-- Data:
local dkp
local loots
local settings
local dkpresets
local frame
local events = {}
local biditems = {}
local bidwinners = {}
local pick_active = false
local auction_active = false
local link_regex = "|c%x+|H[^|]+|h%[[^|]+%]|h|r"
local link_regex_p = "(" .. link_regex .. ")"
local sep_regex = "[-_ :;|!]"

-------------------
-- Helper Functions
-------------------

-- Print: helper function to send message to default chat frame. Messages will be prefixed with "BidER: "
local function Print(text, share)
	if (DEFAULT_CHAT_FRAME) then
		DEFAULT_CHAT_FRAME:AddMessage("BidER: " .. text)
	end
  if share == true then
    if settings.channel:lower():match("officers?") then
      SendChatMessage(text, "OFFICER"); 
    else
      local index = GetChannelName(settings.channel)
      if index ~= nil then 
        SendChatMessage(text, "CHANNEL", nil, index); 
      end
    end
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

local function contains(tab, what)
  for i,v in pairs(tab) do
    if v == what then
      return true
    end
  end
  return false
end

local function GetRaiderInfo(i)
  local r = {}
  r.name, r.rank, r.subgroup, r.level, r.class, r.fileName, 
    r.zone, r.online, r.isDead, r.role, r.isML = GetRaidRosterInfo(i);
  return r
end

local function ImportDKP(set, str)
  if dkp[set] == nil then dkp[set] = {} end
  local dkp = dkp[set]
  for i,v in pairs(dkp) do dkp[i] = nil end -- erase existing DKP
  local count = 0
  for who,points,looted in str:gmatch("(%a+): (%d+) %((%d+)%)") do
    dkp[who] = {total = points}
    count = count + 1
  end
  Print("Imported DKP '" .. set .. "': " .. count .. " players", true)
end

function BidER_SendEvent(self, event, ...)
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
  frame = CreateFrame("FRAME", nil, UIParent)
  frame:SetScript("OnEvent", BidER_SendEvent)
  frame:RegisterEvent("ADDON_LOADED")
  hooksecurefunc("ChatFrame_OnHyperlinkShow", function(...) BidER_Event("HyperlinkShow", ...) end)
end

-----------------
-- Main Functions
-----------------
local function PrintHelp()
  Print("Usage for /bider (or /ber):")
  Print("  [note that most all commands can be abbreviated]")
  Print("     help            show this help")
  Print("  SETTING COMMANDS")
  Print("     set [var] [val] sets [var] to [val]")
  Print("         enchanter   enchanter to give DE items to")
  Print("         threshold   sets the default loot threshold (3=blue, 4=rare)")
  Print("         dkp         the DKP set to be used")
  Print("  RAID COMMANDS")
  Print("     init [name|-]   sets loot to master looter / loot threshold")
  Print("                       specify a name or - (self) for master looter")
  Print("                       no args sets the threshold")
  Print("                       (the API forces these operations to be separate)")
  Print("  DKP COMMANDS")
  Print("     dkp             sets/modifies/grants DKP")
  Print("       [nothing]     lists all recorded DKP")
  Print("       [+/-value]    adds/removes DKP for all raid members")
  Print("       [who] [value] sets who's DKP to value")
  Print("     loots           shows info on loots handed out (could build up a lot...)")
  Print("     reset           sets DKP reset mode on/manages it (forces FULL bids for next bid per player)")
  Print("       [nothing]     lists all people who have already been reset (if active)")
  Print("       [on]          turns DKP reset requirement on for the current DKP set")
  Print("  AUCTION COMMANDS")
  Print("     pick            starts picking items for auction")
  Print("         [item list] adds the linked items")
  Print("         loot        adds items from an open loot window")
  Print("         stop        ends item picking [optional]")
  Print("         items can also be shift-clicked in chat to pick while active")
  Print("     start           starts the auction (with announcement, auto-ends picking)")
  Print("     announce        announces auction status")
  Print("     end             ends the auction, announcing that it is closed")
  Print("                       and printing status (stops accepting bids)")
  Print("     finalize        finalizes the auction results, announcing winners")
  Print("     assign          assigns items to their winners (including designated DE'er)")
  Print("     status          prints status of bids")
  Print("     edit            edits bids for the auction")
  Print("       [who] [link] [amount]")
  Print("                     amount is a DKP value or the word 'win'")
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
      Print("Item: " .. item_link .. "x" .. v.count)
    end
  else
    Print("item picking is not in progress.")
  end
end

local function GetDKPSet()
  if dkp[settings.dkp] == nil then dkp[settings.dkp] = {} end
  return dkp[settings.dkp]
end

local function GetDKPResetsSet()
  return dkpresets[settings.dkp]
end

local function NeedDKPReset(who)
  local dkpresets = GetDKPResetsSet()
  if dkpresets == nil then return false end
  return not contains(dkpresets, who)
end

local function SubtractDKP(who, amount)
  local dkp = GetDKPSet()
  if NeedDKPReset(who) then
    dkp[who].total = 0
    tinsert(GetDKPResetsSet(), who)
  else
    dkp[who].total = dkp[who].total - amount
    if dkp[who].total < 0 then dkp[who].total = 0 end
  end
end

local function GetDKP(who, msg)
  local dkp = GetDKPSet()
  if dkp[who] == nil or dkp[who].total == nil or dkp[who].total == 0 then
    if msg then PostMsg("You have no DKP.", who) end
    return 0
  else
    if msg then PostMsg("You have " .. dkp[who].total .. " DKP.", who) end
    return dkp[who].total
  end
end

local function AddLoot(who, item)
  if loots[who] == nil then loots[who] = {} end
  tinsert(loots[who], {item=item, time=time()})
end

-----------------
-- Hook Functions
-----------------
function events:ADDON_LOADED(addon, ...)
  if addon:lower() == "bider" then
    if BidER_DKP == nil then BidER_DKP = {} end
    if BidER_Loots == nil then BidER_Loots = {} end
    if BidER_Settings == nil then BidER_Settings = {enchanter="", threshold=3, dkp='default', channel='Officer'} end
    if BidER_DKPResets == nil then BidER_DKPResets = {} end
    if BidER_Imports == nil then BidER_Imports = {} end
    dkp = BidER_DKP
    loots = BidER_Loots
    settings = BidER_Settings
    dkpresets = BidER_DKPResets

    if BidER_Imports ~= nil then
      Print("Handling data imports...")
      for i,v in pairs(BidER_Imports) do
        if i == 'dkp' then
          Print("Loading DKP...")
          for j,w in pairs(v) do
            ImportDKP(j, w)
          end
        end
      end
      BidER_Imports = nil
    end

    Print("Loaded " .. VERSION)
  end
end

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
  elseif cmd == "init" then
    BidER_Event("InitCommand", args)
  elseif cmd == "set" then
    BidER_Event("SetCommand", args)
  elseif cmd == "start" then
    BidER_Event("StartAuctionCommand", args)
  elseif cmd == "end" then
    BidER_Event("EndAuctionCommand", args)
  elseif cmd:match('^d') then
    BidER_Event("DKPCommand", args)
  elseif cmd:match('^l') then
    BidER_Event("LootsCommand", args)
  elseif cmd:match('^p') then
    BidER_Event("PickCommand", args)
  elseif cmd:match('^b') or cmd:match('^e') then
    BidER_Event("EditAuctionCommand", args)
  elseif cmd:match('^s') then
    BidER_Event("StatusAuctionCommand", args)
  elseif cmd:match('^an') then
    BidER_Event("AnnounceAuctionCommand", args)
  elseif cmd:match('^as') then
    BidER_Event("AssignAuctionCommand", args)
  elseif cmd:match('^f') then
    BidER_Event("FinalizeAuctionCommand", args)
  elseif cmd == "reset" then
    BidER_Event("ResetCommand", args)
  else
    Print("Unknown command: " .. cmd)
    PrintHelp()
  end
end

local function DumpBidInfo()
  local count_msg = ""
  for item_link,v in pairs(biditems) do
    local bid_count = count_pairs(v.bids)
    if bid_count == 0 then count_msg = "no bids"
    elseif bid_count == 1 then count_msg = bid_count .. " bid"
    else count_msg = bid_count .. " bids" end
    PostChat(item_link .. "x" .. v.count .. " -- " .. count_msg)
  end
  if auction_active then
    local player = UnitName("player")
    PostChat("To bid on any item: /w " .. player .. " <link> <bid amount>")
    PostChat("To see your current DKP: /w " .. player .. " dkp")
    PostChat("To view your current bids: /w " .. player .. " bids")
  else
    PostChat("The auction has been closed.  Results will be announced soon.")
  end
end

function events:ResetCommand(args)
  if args == "on" then
    dkpresets[settings.dkp] = {}
    Print("Initiated DKP reset mode")
  else
    local dkpresets = GetDKPResetsSet()
    if dkpresets == nil then
      Print("DKP reset mode is not active.")
    else
      out = "Players reset: "
      for i,v in ipairs(dkpresets) do
        if i > 1 then out = out .. ", " end
        out = out .. v
      end
      Print(out)
      if GetNumRaidMembers() > 1 then
        local count = 1
        out = "DKP reset needed for: "
        for i=1,GetNumRaidMembers() do
          local name = GetRaiderInfo(i).name
          if NeedsDKPReset(name) then
            if count > 1 then out = out .. ", " end
            out = out .. name
            count = count + 1
          end
        end
      end
    end
  end
end

function events:InitCommand(args)
  if not IsRaidLeader() then
    Print("You are not the raid leader, so this probably won't work...")
  end
  local master = args
  if args == '-' then master = UnitName("player") end
  if master ~= nil and master ~= '' then SetLootMethod('master', master)
  else SetLootThreshold(settings.threshold) end
end

function events:SetCommand(args)
  local var,val = strsplit(" ", args)
  if var == nil or var == "" then
    for i,v in pairs(settings) do
      Print("Setting '" .. i .. "': " .. v)
    end
  else
    if settings[var] == nil then
      Print("Setting '" .. var .. "' does not exist.")
    elseif val == nil then
      Print("Setting '" .. var .. "' currently: " .. settings[var])
      opts = ''
      if var == 'dkp' then
        for i,v in pairs(dkp) do
          if opts == '' then opts = i
          else opts = opts .. ", " .. i end
        end
      end
      if opts ~= '' then
        Print("Current options: " .. opts)
      end
    else
      settings[var] = val
      Print("Set '" .. var .. "' to " .. val)
    end
  end
end

function events:LootsCommand(args)
  for who,v in pairs(loots) do
    Print("Looted by " .. who .. ":")
    for i,w in ipairs(v) do
      Print("   " .. date("%m/%d/%y %H:%M:%S", w.time) .. " - " .. w.item)
    end
  end
  Print("End of loot listing.")
end

function events:AnnounceAuctionCommand(args)
  if auction_active then
    DumpBidInfo()
  end
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
  events:StatusAuctionCommand("-")
end

function events:FinalizeAuctionCommand(args)
  if auction_active then
    events:EndAuctionCommand()
  end
  bidwinners = {}
  for item,v in pairs(biditems) do
    bidwinners[item] = {}
    local bidders = {}
    for who,bid in pairs(v.bids) do
      if bid.win then tinsert(bidders, 1, {who=who, win=true, amount=bid.amount})
      else
        tinsert(bidders, {who=who, amount=bid.amount})
        for i,other in ipairs(bidders) do
          if other.win ~= true and bid.amount > other.amount then
            tinsert(bidders, i, tremove(bidders))
            break
          end
        end
      end
    end
    local prev = nil
    for i,other in ipairs(bidders) do
      if i > 2 then break end
      if prev ~= nil and prev.win ~= true and prev.amount == other.amount then
        Print("WARNING!  Tie for " .. item .. " between " .. prev.who .. " and " .. other.who, true)
        Print("Finalization cancelled.", true)
        return
      end
      prev = other
    end
    for count=1,v.count do
      if bidders[count] == nil then
        PostChat("Disenchant for " .. item)
        if settings.enchanter ~= "" then
          tinsert(bidwinners[item], settings.enchanter)
        end
      else
        tinsert(bidwinners[item], bidders[count].who)
        if bidders[count].amount > 0 then
          SubtractDKP(bidders[count].who, bidders[count].amount)
          Print("Updated " .. bidders[count].who .. " dkp: " .. GetDKP(bidders[count].who), true)
        end
        PostChat("Winner for " .. item .. " - " .. bidders[count].who)
        AddLoot(bidders[count].who, item)
      end
    end
  end
end

function events:AssignAuctionCommand(args)
  local _, looter, _ = GetLootMethod()
  if looter ~= 0 then
    Print('Cannot assign loot - master loot not active, or you are not master looter.')
    return
  end
  for item,v in pairs(bidwinners) do
    local found_item = false
    for i=1, GetNumLootItems() do
      if LootSlotIsItem(i) and GetLootSlotLink(i) == item then
        for _,who in ipairs(v) do
          local found_who = false
          for j=1, 40 do
            if GetMasterLootCandidate(j) == who then
              GiveMasterLoot(i, j)
              Print("Gave " .. item .. " to " .. who)
            end
          end
          if not found_who then
            Print("Could not find " .. who .. " to give " .. item)
          end
        end
      end
    end
    if not found_item then
      Print("Could not find " .. item .. " in loot list")
    end
  end
end

local function BidText(bid)
  return (bid.win and (bid.amount .. "/WIN") or bid.amount)
end

function events:StatusAuctionCommand(args)
  local share = nil
  if args == "-" then share = true end
  for item,v in pairs(biditems) do
    Print("Bids on " .. item, share)
    for who,bid in pairs(v.bids) do
      local flag = ""
      if NeedDKPReset(who) then flag = "*" end
      Print("     " .. flag .. who .. " - " .. BidText(bid), share)
    end
  end
  Print("End of bids.", share)
end

function events:EditAuctionCommand(args)
  for who,link,amount in args:gmatch("(%a+)" .. sep_regex .. "*" .. link_regex_p .. sep_regex .. "*(%w+)") do
    if biditems[link] == nil then
      Print("Not taking bids on " .. link)
    else
      if tonumber(amount) == nil and amount ~= "win" then
        Print("Invalid bid amount '" .. amount .. "' - must be a number or 'win'")
      else
        local old_bid, new_bid, toprint = biditems[link].bids[who], {}, ""
        if tonumber(amount) == nil then
          -- Win case
          if old_bid == nil then
            new_bid.win = true
            new_bid.amount = 0
          else
            if old_bid.win ~= true then new_bid.win = true
            else new_bid.win = false end
            new_bid.amount = old_bid.amount
          end
        else new_bid.amount = tonumber(amount) end

        if old_bid ~= nil then
          toprint = " (old bid: " .. BidText(old_bid) .. ")"
        end
        biditems[link].bids[who] = new_bid
        Print("Updated bid to " .. BidText(new_bid) .. " for " .. who .. " on " .. link .. toprint, true)
      end
    end
  end
end

local function PrintDKP(name)
  local dkp = GetDKPSet()
  if dkp[name] == nil then dkp[name] = {total=0} end
  local flag = ""
  if NeedDKPReset(name) then flag = "*" end
  Print("DKP for " .. flag .. name .. " - " .. dkp[name].total, true)
end

function events:DKPCommand(args)
  local old_value
  local dkp = GetDKPSet()

  if args == "" then
    if GetNumRaidMembers() > 0 then
      for i=1,GetNumRaidMembers() do
        local name = GetRaiderInfo(i).name
        PrintDKP(name)
      end
    else
      for name,v in pairs(dkp) do
        PrintDKP(name)
      end
    end
    Print("End of DKP Listing.", true)
  elseif args:match("^[-+]?%d+$") then
    local value = tonumber(args)
    for i=1,GetNumRaidMembers() do
      local name = GetRaiderInfo(i).name
      if dkp[name] == nil then dkp[name] = {total=value}
      else dkp[name].total = dkp[name].total + value end
    end
    Print("Added " .. value .. " DKP for all raid members", true)
  else
    for name,value in args:gmatch("(%a+)" .. sep_regex .. "(%d+)") do
      if dkp[name] == nil then dkp[name] = {} end
      if dkp[name].total ~= nil then old_value = dkp[name].total else old_value = nil end
      dkp[name].total = tonumber(value)

      if dkp[name].total ~= old_value then
        local was_str = ""
        if old_value ~= nil then was_str = " (was: " .. old_value .. ")" end
        Print("DKP value for " .. name .. " updated: " .. dkp[name].total .. was_str, true)
      else
        Print("DKP value for " .. name .. " unchanged (" .. old_value .. ")", true)
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
      local threshold = settings.threshold
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

local function OtherBids(who, item)
  local amount = 0
  for oitem,v in pairs(biditems) do
    if v.bids[who] ~= nil then
      amount = amount + v.bids[who].amount
    end
  end
  return amount
end

local function PlaceBid(who, item, bids, amount)
  local tosend, old_value
  if bids[who] ~= nil then
    old_value, bids[who] = bids[who], nil
  end
  if GetDKP(who) < amount or GetDKP(who) < (amount+OtherBids(who, item)) then
    PostMsg("You do not have enough DKP for that bid.", who)
    GetDKP(who, true)
    return
  end
  bids[who] = {amount=amount}
  if old_value then
    tosend = "Updated bid for " .. item .. " from " .. old_value.amount .. " to " .. amount
  else
    tosend = "Recorded bid for " .. item .. ": " .. amount
  end
  PostMsg(tosend .. ".  You can still update your bid.", who)
  PostMsg("To cancel, /w " .. UnitName("player") .. " " .. item .. " cancel", who)
  if NeedDKPReset(who) then
    PostMsg("WARNING!  You are under DKP reset conditions, and as such will lose ALL points regardless of bids if you win!", who)
  end
end

function events:CHAT_MSG_WHISPER(msg, from, ...)
  if msg == "cancel" then
    local removed = {}
    for item,v in pairs(biditems) do
      if v.bids[from] ~= nil then
        v.bids[from] = nil
        tinsert(removed, item)
      end
    end
    if #removed > 0 then
      PostMsg("Cancelled " .. #removed .. " bid(s).", from)
    else
      PostMsg("You have no active bids.", from)
    end
    return
  elseif msg == "dkp" then
    GetDKP(from, true)
    return
  elseif msg:match("^bids?$") then
    local msgd = false
    for item,v in pairs(biditems) do
      if v.bids[from] ~= nil then
        PostMsg("You have bid on " .. item .. ": " .. v.bids[from].amount, from)
        msgd = true
      end
    end
    if not msgd then
      PostMsg("You have no active bids.", from)
    end
  end
  for item, value in string.gmatch(msg, link_regex_p .. "[^|0-9A-Za-z]*([^|.-]*)") do
    local v = biditems[item]
    if v == nil then
      PostMsg("There is no auction in progress for " .. item, from)
      return
    end
    if value:match('cancel') then
      CancelBid(from, item, v.bids)
    else
      num = tonumber(value:match("%d+"))
      if num ~= nil then
        PlaceBid(from, item, v.bids, num)
      else
        PostMsg("Couldn't determine bid for " .. item .. ": '" .. value .. "'", from)
      end
    end
  end
end

----------------------
-- Button/UI Functions
----------------------

-- Start 'er up
events:OnLoad()
