-- BidER 1.0, by Quilderaumo (chrisqeld@gmail.com)
-- 
-- Handles bids/DKP system for Eternal Retribution
-- Type /ber or /bider to open.
-- 

-- Constants:
local VERSION = "1.0"
local FRAME = "BidERFrame"

-- Data:
local dkp
local dkpresets
local raids
local settings
local aliases
local minbids
local frame
local events = {}
local biditems = {}
local bidwinners = {}
local link_regex = "|c%x+|H[^|]+|h%[[^|]+%]|h|r"
local link_regex_p = "(" .. link_regex .. ")"
local sep_regex = "[-_ :;|!]"

local debug = false
local pick_active = false
local auction_active = false
local active_raid = nil
local last_kill = ''

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

local function MyDate(at)
  return date("%m/%d/%y %H:%M:%S", at)
end

local function GetWidget(name)
  return _G[FRAME .. name]
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

local function GetItemInfo(item)
  local r = {}
  r.itemName, r.itemLink, r.itemRarity, r.itemLevel, r.itemMinLevel, r.itemType, r.itemSubType, r.itemStackCount,
    r.itemEquipLoc, r.itemTexture = _G.GetItemInfo(item) 
  return r
end

local function HandleAliases()
  -- Handle character aliases - this is a simple map of names to other names.  Just 
  -- maps one to the other, primarily in the form of BidER_Aliases[alt_name] = main_name
  for alt,main in pairs(aliases) do
    for j,w in pairs(dkp) do
      if w[main] == nil then w[main] = {total=0} end
      w[alt] = w[main]
    end
  end
end

local function ImportDKP(set, str)
  if dkp[set] == nil then dkp[set] = {} end
  local dkp = dkp[set]
  for i,v in pairs(dkp) do dkp[i] = nil end -- erase existing DKP
  local count = 0
  for who,points,looted in str:gmatch("(%a+): (%d+) %((%d+)%)") do
    dkp[who] = {total = tonumber(points)}
    count = count + 1
  end
  Print("Imported DKP '" .. set .. "': " .. count .. " players", true)
end

local function FixName(name)
  return (name:sub(1,1):upper() .. name:sub(2):lower())
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
  frame = GetWidget("")
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
  Print("     alias           adds an alias for 'main' as 'alt'")
  Print("       [alt] [main]")
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
  Print("                     amount is a DKP value or the word 'win' or 'cancel'")
end

local function AddLink(item_link, count)
  if pick_active then
    if biditems[item_link] ~= nil then
      local v = biditems[item_link]
      v.count = v.count + count
      Print("Updated item: " .. item_link .. "x" .. v.count)
      return
    end
    biditems[item_link] = {bids={}, count=count, lvl=GetItemInfo(item_link).itemLevel}
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
  if dkp[settings.dkp] == nil then
    dkp[settings.dkp] = {}
    HandleAliases() -- initialize aliases for this new DKP set
  end
  return dkp[settings.dkp]
end

local function GetDKPResetsSet()
  return dkpresets[settings.dkp]
end

local function NeedDKPReset(who)
  local dkpresets = GetDKPResetsSet()
  if dkpresets == nil then return false end
  if aliases[who] ~= nil then who = aliases[who] end
  return not contains(dkpresets, who)
end

local function AddDKPReset(who)
  local dkpresets = GetDKPResetsSet()
  if aliases[who] ~= nil then who = aliases[who] end
  tinsert(dkpresets, who)
end

local function MinimumBid(item)
  return minbids[biditems[item].lvl] or 0
end

local function SubtractDKP(who, amount, item)
  local dkp = GetDKPSet()
  local orig = dkp[who].total
  if NeedDKPReset(who) then
    dkp[who].total = 0
    AddDKPReset(who)
  else
    if item ~= nil then
      -- Check that the minimum bid has been met...
      -- the logic here is basically that you want the bid amount or the minimum,
      -- whichever is MORE, then whichever is less between that and the player's total
      -- DKP (as they cannot go negative)
      amount = min(max(MinimumBid(item), amount), dkp[who].total)
    end
    dkp[who].total = dkp[who].total - amount
    if dkp[who].total < 0 then dkp[who].total = 0 end
  end
  return (orig - dkp[who].total)
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

local function AddLoot(item, who, amount)
  if active_raid then
    local event = active_raid.events[last_kill]
    if event ~= nil then
      tinsert(event.loots, {who=who, item=item, amount=amount})
    end
  end
end

local function GrantDKP(who, amount)
  local dkp = GetDKPSet()
  if who == nil then
    local given = {}
    for i=1,GetNumRaidMembers() do
      local name = GetRaiderInfo(i).name
      -- Lookup if this is an alt, register as the main toon
      -- so that they will only get one point
      if aliases[name] then name = aliases[name] end
      if not contains(given, name) then
        if dkp[name] == nil then dkp[name] = {total=amount}
        else dkp[name].total = dkp[name].total + amount end
        tinsert(given, name)
      end
    end
    Print("Added " .. amount .. " DKP for all raid members", true)
  end
end

-----------------
-- Hook Functions
-----------------
local function HandleBossEvent(boss, killed)
  if active_raid then
    if killed then
      Print("Killed " .. boss)
      GrantDKP(nil, 1)
      last_kill = boss
    end

    local raiders = {}
    for i=1,GetNumRaidMembers() do
      tinsert(raiders, GetRaiderInfo(i).name)
    end

    local attempt = {
      time = time(),
      attendance = raiders,
      killed = killed,
    }
    local event = active_raid.events[boss]
    if event == nil then
      event = {
        attempts = {},
        loots = {},
      }
    end
    tinsert(event.attempts, attempt)
    active_raid.events[boss] = event
  end
end

function events:DBM_Kill(mod)
  HandleBossEvent(mod.combatInfo.name, true)
end

function events:DBM_Wipe(mod)
  HandleBossEvent(mod.combatInfo.name, false)
end

function events:ADDON_LOADED(addon, ...)
  if addon:lower() == "bider" then
    if BidER_DKP == nil then BidER_DKP = {} end
    if BidER_DKPResets == nil then BidER_DKPResets = {} end
    if BidER_Raids == nil then BidER_Raids = {} end
    if BidER_Settings == nil then BidER_Settings = {enchanter="", threshold=3, dkp='default', channel='Officer'} end
    if BidER_Aliases == nil then BidER_Aliases = {} end
    if BidER_Imports == nil then BidER_Imports = {} end
    if BidER_MinimumBids == nil then BidER_MinimumBids = {[219]=5, [226]=10, [232]=15, [239]=20} end
    dkp = BidER_DKP
    dkpresets = BidER_DKPResets
    raids = BidER_Raids
    settings = BidER_Settings
    aliases = BidER_Aliases
    minbids = BidER_MinimumBids

    HandleAliases()

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
  elseif addon:lower() == "dbm-core" then
    DBM:RegisterCallback('kill', function(...) events:DBM_Kill(...) end)
    DBM:RegisterCallback('wipe', function(...) events:DBM_Wipe(...) end)
    Print("Registered callbacks with DBM.")
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
  elseif cmd == "raid" then
    BidER_Event("RaidCommand", args)
  elseif cmd == "set" then
    BidER_Event("SetCommand", args)
  elseif cmd == "start" then
    BidER_Event("StartAuctionCommand", args)
  elseif cmd == "end" then
    BidER_Event("EndAuctionCommand", args)
  elseif cmd == "debug" then
    BidER_Event("DebugCommand", args)
  elseif cmd == "reset" then
    BidER_Event("ResetCommand", args)
  elseif cmd == "alias" then
    BidER_Event("AliasCommand", args)
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

function events:UICommand(args)
  BidERItemText:SetText("[" .. settings.dkp .. "]")
  frame:Show()
end

function events:DebugCommand(args)
  if args:match(".+") then
    Print(args:gsub("|", "!"))
  else
    debug = not debug
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
          if NeedDKPReset(name) then
            if count > 1 then out = out .. ", " end
            out = out .. name
            count = count + 1
          end
        end
        Print(out)
      end
    end
  end
end

function events:AliasCommand(args)
  local alt, main = strsplit(" ", args)
  if alt:match("^-") then
    alt = FixName(alt:sub(2))
    if aliases[alt] == nil then
      Print("There is no alias for " .. alt)
    else
      main = aliases[alt]
      aliases[alt] = nil
      for j,w in pairs(dkp) do
        if w[alt] ~= nil then w[alt] = {total=w[alt].total} end
      end
      Print("Removed alias " .. alt .. " for " .. main)
    end
  else
    alt, main = FixName(alt), FixName(main)
    aliases[alt] = main
    HandleAliases()
    Print("Created alias " .. alt .. " for " .. main)
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

function events:RaidCommand(args)
  cmd, arg = strsplit(" ", args)
  if cmd:lower() == "start" then
    if active_raid then
      Print("A raid is already active!  Please end or resume.")
      return
    end
    local new_raid = {
      start_time = time(),
      zone = GetZoneText(),
      events = {},
    }
    raids[new_raid.start_time] = new_raid
    active_raid = new_raid
    Print("Started raid: " .. active_raid.zone .. " (" .. MyDate(active_raid.start_time) .. ")")
  elseif cmd:lower() == "resume" then
    local max_date = 0
    for i,v in pairs(raids) do
      if i > max_date then max_date = i end
    end
    if max_date == 0 then
      Print("There is no raid to resume!")
    else
      active_raid = raids[max_date]
      Print("Resumed raid in " .. active_raid.zone .. " (" .. MyDate(active_raid.start_time) .. ")")
    end
  elseif cmd:lower() == "end" then
    active_raid.end_time = time()
    Print("Ended raid: " .. active_raid.zone .. " (" ..
      (active_raid.end_time - active_raid.start_time) .. ")")
    active_raid = nil
  end
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
      if val:match("%d+") then
        val = tonumber(val)
      end
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
  PostChat("Auction is now in progress")
  DumpBidInfo()
end

function events:EndAuctionCommand(args)
  if not auction_active then
    Print("No auction is active!")
    return
  end
  auction_active = false
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
        AddLoot(item)
      else
        tinsert(bidwinners[item], bidders[count].who)
        local real_amount = SubtractDKP(bidders[count].who, bidders[count].amount, item)
        Print("Updated " .. bidders[count].who .. " dkp: " .. GetDKP(bidders[count].who), true)
        PostChat("Winner for " .. item .. " - " .. bidders[count].who)
        AddLoot(item, bidders[count].who, real_amount)
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
    for i=GetNumLootItems(), 1, -1 do
      if GetLootSlotLink(i) == item then
        for _,who in ipairs(v) do
          local found_who = false
          for j=1, 40 do
            if GetMasterLootCandidate(j) == who then
              GiveMasterLoot(i, j)
              Print("Gave " .. item .. " to " .. who)
              found_who = true
              break
            end
          end
          if not found_who then
            Print("Could not find " .. who .. " to give " .. item)
          end
        end
        found_item = true
        break
      end
    end
    if not found_item then
      Print("Could not find " .. item .. " in loot list")
    end
  end
end

local function BidText(bid)
  return ((bid and (bid.win and (bid.amount .. "/WIN") or bid.amount)) or "CANCELLED")
end

function events:StatusAuctionCommand(args)
  local share = nil
  if args == "-" then share = true end
  for item,v in pairs(biditems) do
    Print("Bids on " .. item, share)
    for who,bid in pairs(v.bids) do
      local flag = ""
      if NeedDKPReset(who) then flag = "*" end
      Print("     " .. flag .. who .. " - " .. BidText(bid) .. " / " .. GetDKP(who), share)
    end
  end
  Print("End of bids.", share)
end

function events:EditAuctionCommand(args)
  for who,link,amount in args:gmatch("(%a+)" .. sep_regex .. "*" .. link_regex_p .. sep_regex .. "*(%w+)") do
    who = FixName(who)
    if biditems[link] == nil then
      Print("Not taking bids on " .. link)
    else
      amount = amount:lower()
      if tonumber(amount) == nil and not contains({"win", "cancel"}, amount) then
        Print("Invalid bid amount '" .. amount .. "' - must be a number or 'win'")
      else
        local old_bid, new_bid, toprint = biditems[link].bids[who], {}, ""
        if tonumber(amount) == nil then
          -- Win case
          if amount == "win" then
            if old_bid == nil then
              new_bid.win = true
              new_bid.amount = 0
            else
              if old_bid.win ~= true then new_bid.win = true
              else new_bid.win = false end
              new_bid.amount = old_bid.amount
            end
          elseif amount == "cancel" then
            new_bid = nil
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
    GrantDKP(nil, tonumber(args))
  elseif args:match("%d") then
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
  else
    for name in args:gmatch("(%a+)") do
      if dkp[name] == nil then dkp[name] = {total=0} end
      Print("DKP for " .. name .. ": " .. dkp[name].total, true)
    end
  end
end

function events:PickCommand(args)
  if auction_active then
    Print("An auction is already active!")
    return
  elseif not active_raid then
    Print("There is no active raid! Please /ber raid start [name]")
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
  local dkp = GetDKP(who)
  if dkp < amount or dkp < (amount+OtherBids(who, item)) then
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
  elseif amount < dkp then
    -- Check minimum bid, if amount is less than total DKP [if it's total, that's fine]
    local minbid = MinimumBid(item)
    if amount < minbid then
      PostMsg("WARNING!  " .. item .. " has a minimum bid of " .. minbid .. " but you have only bid " .. amount .. ".  If you win the item, it will cost the minimum amount or your total DKP (" .. dkp .. "), whichever is less.", who)
    end
  end
end

function events:CHAT_MSG_WHISPER(msg, from, ...)
  if msg:lower():match("^ *dkp *$") then
    GetDKP(from, true)
    return
  elseif auction_active then
    if msg:lower():match("^ *cancel *$") then
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
    elseif msg:lower():match("^ *bids? *$") then
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
      return
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
end

----------------------
-- Button/UI Functions
----------------------
function events:CloseWindow()
  frame:Hide()
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
