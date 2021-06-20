--[[
	=== WTSpam ===

	F#*& Boost Sellers! LFG is filled with "WTS Boost"-spam, lets get rid of it.

	By Gogh/Pampula of Mirage Raceway EU (BCClassic)

	[22:32] [4] [Tatamata]: MARA BOOST [] 330+ mobs pull [] 30-52 lvl [] 120k+ EXP/hour [] 35g / run [] nothing reserved [] Can Summon [] 2/4 
	[22:44] [4] [Ajaxthegreat]: LF1M SM BOOST cath+arm 15g a reset 
]]--
local ADDON_NAME, ns = ...

local function Debug(text, ...)
	if text then
		if text:match("%%[dfqsx%d%.]") then
			(DEBUG_CHAT_FRAME or ChatFrame3):AddMessage("|cffff9999"..ADDON_NAME..":|r " .. format(text, ...))
		else
			(DEBUG_CHAT_FRAME or ChatFrame3):AddMessage("|cffff9999"..ADDON_NAME..":|r " .. strjoin(" ", text, tostringall(...)))
		end
	end
end

local function Print(text, ...)
	if text then
		if text:match("%%[dfqs%d%.]") then
			DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00".. ADDON_NAME ..":|r " .. format(text, ...))
		else
			DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00".. ADDON_NAME ..":|r " .. strjoin(" ", text, tostringall(...)))
		end
	end
end

-- Round function, copied from http://lua-users.org/wiki/SimpleRound
local function _round(num, idp)
	local mult = 10^(idp or 0)
	return math.floor(num * mult + 0.5) / mult
end

-- deepcopy
local function deepcopy(orig) -- http://lua-users.org/wiki/CopyTable
	local orig_type = type(orig)
	local copy

	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in next, orig, nil do
			copy[deepcopy(orig_key)] = deepcopy(orig_value)
		end
		--setmetatable(copy, deepcopy(getmetatable(orig)))
	else -- number, string, boolean, etc
		copy = orig
	end

	return copy
end

local db, f, b
local DEBUG, ANNOUNCE, FLASHING = false, false, false
local strfind, strlower = strfind, strlower
local wtsMatch = "wts"
local wtbMatch = "wtb"
local goldMatch = "%d+%s?g"
local boostMatch = "boost"
local spamTable, nameTable, whitelistTable = {}, {}, {}
local whitelistNameTable = {
	-- Put your friends booster characters here
	-- Format: (case sensitive and has to be 100% exact)
	-- ["CharacterName"] = true,
}

-- EventHandler frame
local ChatCatcher = CreateFrame("Frame")
ChatCatcher:RegisterEvent("ADDON_LOADED")

-- (1)
f = CreateFrame("Frame", "ChatCatcherFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
f:Hide()
f:SetSize(600, 400)
f:SetPoint("CENTER")

-- (2)
f:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	insets = {left = 11, right = 11, top = 12, bottom = 11},
	tile = true,
	tileSize = 32,
	edgeSize = 32,
})

-- (3)
f:EnableMouse(true)
f:SetMovable(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetScript("OnHide", f.StopMovingOrSizing)
tinsert(UISpecialFrames, f:GetName())

-- (4)
f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
f.title:SetText("=== WTSpam ===")
f.title:SetPoint("TOP", 0, -24)

f.count = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLeft")
f.count:SetText("Showing 0 - 0 / 0")
f.count:SetPoint("BOTTOMLEFT", 24, 14)

-- (5)
f.close = CreateFrame("Button", "ChatCatcherFrameCloseButton", f, "UIPanelCloseButton")
f.close:SetPoint("TOPRIGHT", -5, -5)
f.close:SetScript("OnClick", function()
	f:Hide()
end)

-- (6)
local function sortByTime(a, b)
	local l = db.IgnoreList
	if not (l[a] and l[b]) then
		return a < b
	elseif type(l[a].timestamp) ~= "table" or type(l[b].timestamp) ~= "table" then
		return a < b
	else
		if l[a].timestamp.year ~= l[b].timestamp.year then
			return l[a].timestamp.year < l[b].timestamp.year
		elseif l[a].timestamp.month ~= l[b].timestamp.month then
			return l[a].timestamp.month < l[b].timestamp.month
		elseif l[a].timestamp.day ~= l[b].timestamp.day then
			return l[a].timestamp.day < l[b].timestamp.day
		elseif l[a].timestamp.hour ~= l[b].timestamp.hour then
			return l[a].timestamp.hour < l[b].timestamp.hour
		elseif l[a].timestamp.min ~= l[b].timestamp.min then
			return l[a].timestamp.min < l[b].timestamp.min
		elseif l[a].timestamp.sec ~= l[b].timestamp.sec then
			return l[a].timestamp.sec < l[b].timestamp.sec
		else
			return a < b
		end
	end
end

local IgnoreListNameTable = {}
local function ScrollList_Update()
	local entryOffset = FauxScrollFrame_GetOffset(f.list)
	local selectedTab = PanelTemplates_GetSelectedTab(f)

	for i = 1, 20 do
		local entryIndex = entryOffset + i
		if ( entryIndex == f.selectedEntry ) then
			if f["listitem" .. i].text:IsShown() then -- Show buttons only if there is some text in the button
				f["listitem" .. i]:LockHighlight()
				f.remove:SetPoint("RIGHT", f["listitem" .. i], "RIGHT", -2, 0)
				f.remove:Show()
				if selectedTab == 1 then
					f.ignore:Show()
				else
					f.ignore:Hide()
				end
			else
				f.remove:Hide()
				f.ignore:Hide()
			end
		else
			f["listitem" .. i]:UnlockHighlight()
		end
	end

	if (f.selectedEntry > entryOffset + 20) or (f.selectedEntry <= entryOffset) then
		f.remove:Hide()
		f.ignore:Hide()
	end

	local line, lineplusoffset
	local hex = "ffffffff"
	local stopPoint, totalPoint = 0, 0

	if selectedTab == 1 then
		totalPoint = #spamTable

		for line = 1, 20 do
			lineplusoffset = line + FauxScrollFrame_GetOffset(f.list)
			if lineplusoffset <= #spamTable then
				local rPerc, gPerc, bPerc, argbHex = GetClassColor(spamTable[lineplusoffset].class)
				hex = argbHex or hex
				local timeframe = math.floor((nameTable[spamTable[lineplusoffset].playerName][#nameTable[spamTable[lineplusoffset].playerName]] - nameTable[spamTable[lineplusoffset].playerName][1]) / 60)
				local count = #nameTable[spamTable[lineplusoffset].playerName] >= 3 and "|cffff0000" .. #nameTable[spamTable[lineplusoffset].playerName] .. "|r" or #nameTable[spamTable[lineplusoffset].playerName]
				if spamTable[lineplusoffset].playerName then
					local nameWithoutRealm = gsub(spamTable[lineplusoffset].playerName, "%-[^|]+", "")
					f["listitem" .. line].text:SetText("|cffffffff" .. count .. "x (" .. timeframe .. "m)|r [".. spamTable[lineplusoffset].channelIndex .."] [|c" .. hex .. nameWithoutRealm .. "|r] " .. spamTable[lineplusoffset].text)
				else
					f["listitem" .. line].text:SetText("|cffffffff" .. "?x (" .. timeframe .. "m)|r [".. spamTable[lineplusoffset].channelIndex .."] [|c" .. hex .. "(unnamed)|r] " .. spamTable[lineplusoffset].text)
				end
				f["listitem" .. line].text:Show()

				stopPoint = lineplusoffset
			else
				f["listitem" .. line].text:Hide()
			end
		end

		if totalPoint <= 20 then
			stopPoint = totalPoint
		end

		FauxScrollFrame_Update(f.list, #spamTable, 20, 16)

	elseif selectedTab == 2 then
		wipe(IgnoreListNameTable)
		for n in pairs(db.IgnoreList) do
			IgnoreListNameTable[#IgnoreListNameTable + 1] = n
		end
		table.sort(IgnoreListNameTable , sortByTime)

		totalPoint = #IgnoreListNameTable

		for line = 1, 20 do
			lineplusoffset = line + FauxScrollFrame_GetOffset(f.list)
			if lineplusoffset <= #IgnoreListNameTable then
				if IgnoreListNameTable[lineplusoffset] then
					local fullname = IgnoreListNameTable[lineplusoffset]
					local nameWithoutRealm = gsub(fullname, "%-[^|]+", "")
					local rPerc, gPerc, bPerc, argbHex = GetClassColor(db.IgnoreList[fullname].class)
					hex = argbHex or hex
					local timestamp = type(db.IgnoreList[fullname].timestamp) == "table" and date("%d.%m.%y %H:%M", time(db.IgnoreList[fullname].timestamp)) or "!" .. db.IgnoreList[fullname].timestamp .. "!"
					f["listitem" .. line].text:SetText("|cffffffff" .. timestamp .."|r [".. db.IgnoreList[fullname].channelIndex .."] [|c" .. hex .. nameWithoutRealm .. "|r] " .. db.IgnoreList[fullname].text)
				else
					local timestamp = db.IgnoreList[IgnoreListNameTable[lineplusoffset]] and date("%d.%m.%y %H:%M:%S", db.IgnoreList[IgnoreListNameTable[lineplusoffset]].timestamp) or "!ERROR!"
					local channelIndex = db.IgnoreList[IgnoreListNameTable[lineplusoffset]] and db.IgnoreList[IgnoreListNameTable[lineplusoffset]].channelIndex or "!ERROR!"
					local text = db.IgnoreList[IgnoreListNameTable[lineplusoffset]] and db.IgnoreList[IgnoreListNameTable[lineplusoffset]].text or "!ERROR!"
					f["listitem" .. line].text:SetText("|cffffffff" .. timestamp .. "|r [".. channelIndex .."] [|c" .. hex .. "(unnamed)|r] " .. text)
				end
				f["listitem" .. line].text:Show()

				stopPoint = lineplusoffset
			else
				f["listitem" .. line].text:Hide()
			end
		end

		if totalPoint <= 20 then
			stopPoint = totalPoint
		end

		FauxScrollFrame_Update(f.list, #IgnoreListNameTable, 20, 16)
	end

	local startPoint = totalPoint == 0 and 0 or stopPoint > entryOffset and entryOffset + 1 or 1
	f.count:SetText("Showing " .. startPoint .. " - " .. stopPoint .. " / " .. totalPoint)
end

f.list = CreateFrame("ScrollFrame", "ChatCatcherFrameScrollList", f, "FauxScrollFrameTemplate")
f.list:SetPoint("TOPLEFT", 10, -50)
f.list:SetWidth(550)
f.list:SetHeight(320)
f.list:SetScript("OnVerticalScroll", function(this, offset)
	FauxScrollFrame_OnVerticalScroll(this, offset, 16, ScrollList_Update)
end)
f.selectedEntry = 0
for i = 1, 20 do
	f["listitem" .. i] = CreateFrame("Button", "ChatCatcherFrameScrollListItem" .. i, f)
	if i == 1 then
		f["listitem" .. i]:SetPoint("TOPLEFT", f.list, "TOPLEFT", 8, 0)
	else
		f["listitem" .. i]:SetPoint("TOPLEFT", f["listitem" .. i - 1], "BOTTOMLEFT")
	end
	f["listitem" .. i].text = f["listitem" .. i]:CreateFontString("ChatCatcherFrameScrollListItem" .. i .. "_Text", "BORDER", "GameFontNormalLeft")
	f["listitem" .. i].text:SetText("listitem" .. i)
	f["listitem" .. i].text:SetAllPoints()
	f["listitem" .. i]:SetWidth(550)
	f["listitem" .. i]:SetHeight(16)
	f["listitem" .. i]:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	f["listitem" .. i]:EnableMouse(true)
	f["listitem" .. i]:SetScript("OnClick", function(this, button, down)
		local clickedEntry = FauxScrollFrame_GetOffset(f.list) + this:GetID()
		if f.selectedEntry == clickedEntry then
			f.selectedEntry = 0
		else
			f.selectedEntry = clickedEntry
		end
		ScrollList_Update()
	end)
	f["listitem" .. i]:SetScript("OnEnter", function(this)
		if not this.text:IsShown() then return end

		local text = this.text:GetText() or "Fail!"

		GameTooltip:SetOwner(this, "ANCHOR_BOTTOM", 0, -10)
		GameTooltip:SetText(text)
		GameTooltip:Show()
	end)
	f["listitem" .. i]:SetScript("OnLeave", function(this)
		GameTooltip:Hide()
	end)
	f["listitem" .. i]:SetID(i)
end

-- (7)
--f.remove = CreateFrame("Button", "ChatCatcherFrameIgnoreButton", f, "UIPanelScrollDownButtonTemplate")
f.remove = CreateFrame("Button", "ChatCatcherFrameRemoveButton", f, "UIPanelSquareButton")
f.remove:SetScale(18 / f.remove:GetHeight())
f.remove:SetPoint("RIGHT", f.listitem1, "RIGHT")
f.remove:SetFrameStrata("FULLSCREEN")
f.remove:SetScript("OnClick", function(this, button, down)
	local selectedTab = PanelTemplates_GetSelectedTab(f)

	if selectedTab == 1 then
		local fullname = spamTable[f.selectedEntry] and spamTable[f.selectedEntry].playerName or false
		if fullname and f.selectedEntry > 0 and f.selectedEntry <= #spamTable then
			if DEBUG then Debug("Remove:", fullname) end
			whitelistTable[fullname] = spamTable[f.selectedEntry].text -- Put in whitelistTable to prevent later hits with same line
			tremove(spamTable, f.selectedEntry)
			nameTable[fullname] = false
			f.selectedEntry = f.selectedEntry > 1 and f.selectedEntry - 1 or (#spamTable > 0 and f.selectedEntry or 0)
		else
			if DEBUG then Debug("Error Removing") end
		end
	elseif selectedTab == 2 then
		if DEBUG then Debug("Clicking Remove Tab 2") end
		local fullname = db.IgnoreList[IgnoreListNameTable[f.selectedEntry]] and db.IgnoreList[IgnoreListNameTable[f.selectedEntry]].playerName or false
		if fullname and f.selectedEntry > 0 and f.selectedEntry <= #IgnoreListNameTable then
			if DEBUG then Debug("Remove 2:", fullname) end
			tremove(IgnoreListNameTable, f.selectedEntry)
			db.IgnoreList[fullname] = nil
			f.selectedEntry = f.selectedEntry > 1 and f.selectedEntry - 1 or (#IgnoreListNameTable > 0 and f.selectedEntry or 0)
		else
			if DEBUG then Debug("Error Removing 2") end
		end
	end
	ScrollList_Update()
	b:SetText("WTSpam: " .. #spamTable)
end)
f.remove:Hide()

f.ignore = CreateFrame("Button", "ChatCatcherFrameRemoveButton", f, "UIPanelScrollUpButtonTemplate")
f.ignore:SetPoint("RIGHT", f.remove, "LEFT")
f.ignore:SetFrameStrata("FULLSCREEN")
f.ignore:SetScript("OnClick", function(this, button, down)
	local fullname = spamTable[f.selectedEntry] and spamTable[f.selectedEntry].playerName or false
	if not strmatch(fullname, "%-[^|]+") then -- Check Realmname is part of the name
		fullname = fullname .. "-MirageRaceway"
	end
	if fullname and f.selectedEntry > 0 and f.selectedEntry <= #spamTable then
		if DEBUG then Debug("Ignore:", fullname) end
		db.IgnoreList[fullname] = deepcopy(spamTable[f.selectedEntry]) -- Save to DB
		tremove(spamTable, f.selectedEntry)
		nameTable[fullname] = false
		f.selectedEntry = f.selectedEntry > 1 and f.selectedEntry - 1 or (#spamTable > 0 and f.selectedEntry or 0)

		if DEBUG then Debug("Check:", db.IgnoreList[fullname] and db.IgnoreList[fullname].text or "!!!No entry!!!") end
	else
		if DEBUG then Debug("Error Ignoring") end
	end
	ScrollList_Update()
	b:SetText("WTSpam: " .. #spamTable)
end)
f.ignore:Hide()

-- (8)
local function ClickTab(self, button, down)
	if DEBUG then Debug("Tab:", self:GetName(), self:GetID(), button, down) end
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
	PanelTemplates_SetTab(f, self:GetID())
	f.selectedEntry = 0

	ScrollList_Update()
end

f.cTab = CreateFrame("Button", "ChatCatcherFrameTab1", f, "CharacterFrameTabButtonTemplate")
f.cTab:SetPoint("LEFT", f, "BOTTOMLEFT", 10, -10)
f.cTab:SetID(1)
f.cTab:SetText("Catched Spammers -list")
f.cTab:SetScript("OnClick", ClickTab)

f.iTab = CreateFrame("Button", "ChatCatcherFrameTab2", f, "CharacterFrameTabButtonTemplate")
f.iTab:SetPoint("LEFT", f.cTab, "RIGHT", -14, 0)
f.iTab:SetID(2)
f.iTab:SetText("Ignore DB -list")
f.iTab:SetScript("OnClick", ClickTab)

PanelTemplates_SetNumTabs(f, 2)
PanelTemplates_SetTab(f, 1)

-- (9)
b = CreateFrame("Button", "ChatCatcherButton", UIParent, "UIPanelButtonTemplate")
b:SetSize(120, 36)
b:SetPoint("BOTTOM", -330, 5)
b:SetText("WTSpam: 0")
b:SetScript("OnClick", function(this, button, down)
	if f:IsShown() then
		f:Hide()
	else
		PanelTemplates_SetTab(f, 1)
		f:Show()
		ScrollList_Update()

		if UIFrameIsFlashing(b:GetHighlightTexture()) then
			UIFrameFlashStop(b:GetHighlightTexture())
			b:UnlockHighlight()
		end
	end
end)

local function filterFunction(self, event, msg, author, ...)
	if event == "CHAT_MSG_CHANNEL" then
		--local nameWithoutRealm = gsub(author, "%-[^|]+", "")
		if db.IgnoreList[author] then -- We found baddie, let's filter it
			return true
		end
	end

	--return false, msg, author, ...
	return false -- You don't need to return the rest if you don't change them
end

-- EventHandler
ChatCatcher:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" and (...) == ADDON_NAME then
		WTSpamDB = WTSpamDB or {}
		db = WTSpamDB
		db.IgnoreList = db.IgnoreList or {}

		self:UnregisterEvent(event)
		self:RegisterEvent("CHAT_MSG_CHANNEL")
		self:RegisterEvent("PLAYER_LOGIN")

	elseif event == "PLAYER_LOGIN" then
		ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", filterFunction) -- Let's filter

	elseif event == "CHAT_MSG_CHANNEL" then
		local msg, author, languageName, channelName, targetName, specialFlags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons = ...

		if channelIndex == 4 then
			local nameWithoutRealm = gsub(author, "%-[^|]+", "")

			if whitelistNameTable[nameWithoutRealm] then return end -- Whitelisted name (incase your friend is promoting boosts, you don't want to list your friends)

			if whitelistTable[author] and whitelistTable[author] == msg then -- Previously whitelisted line
				if DEBUG then Debug("whitelistTable HIT:", nameWithoutRealm) end
				
			elseif strfind(strlower(msg), wtsMatch) or (strfind(msg, goldMatch) and strfind(strlower(msg), boostMatch)) then -- Matched new hit [wts] or [gold and boost]
				if not (nameTable[author] or db.IgnoreList[author]) then -- No previous match for this hit
					--if DEBUG then Debug(">", author, channelName, zoneChannelID, channelIndex, channelBaseName, lineID) end
					--[04:08] SanexDeving: > Gauzz-MirageRaceway 4. LookingForGroup 26 4 LookingForGroup 7141

					local class
					if guid then
						local localizedClass, englishClass, localizedRace, englishRace, sex, name, realm = GetPlayerInfoByGUID(guid)
						class = englishClass or "PRIEST"
					else
						class = "PRIEST"
					end

					local timeTable = date("*t")
					local unixTime = time()
					spamTable[#spamTable + 1] = { channelIndex=channelIndex, channelName=channelName, timestamp=timeTable, class=class, playerName=author, text=msg }
					nameTable[author] = { unixTime }
					b:SetText("WTSpam: " .. #spamTable)
					if ANNOUNCE then Debug("NEW HIT - spamTable:", #spamTable) end

					if f:IsShown() then
						ScrollList_Update()
					else -- HEY YO! LOOK AT ME!
						if FLASHING then
							UIFrameFlash(b:GetHighlightTexture(), 1, 1, -1, false, .5, .5, ADDON_NAME)
							b:LockHighlight()
						end
					end

				else -- Previously matched hit
					local unixTime = time()
					if nameTable[author] then
						nameTable[author][#nameTable[author] + 1] = unixTime

						if ANNOUNCE then Debug("Timer:", _round((unixTime - nameTable[author][#nameTable[author]]) / 60, 2), #nameTable[author]) end

					end
					if ANNOUNCE then Debug("Old HIT:", nameWithoutRealm, nameTable[author] and #nameTable[author] or "!0!", db.IgnoreList[author] and "true" or "false") end

					if f:IsShown() then
						ScrollList_Update()
					end
				end
			end
		end
	end
end)

-- SlashHandler
SLASH_CHATCATCHER1 = "/wts"
SLASH_CHATCATCHER2 = "/wtf"

SlashCmdList["CHATCATCHER"] = function(text)
	Print("=== WTSpam ===")
	if not text or text == "" then
		PanelTemplates_SetTab(f, 1)
		f:Show()
		ScrollList_Update()

		if UIFrameIsFlashing(b:GetHighlightTexture()) then
			UIFrameFlashStop(b:GetHighlightTexture())
			b:UnlockHighlight()
		end

	elseif text and text == "fix" then
		Print("- Trying to fix DB")
		local t, pf, rt, rn = 0, 0, 0, 0
		local tempTable = {}
		for k, v in pairs(db.IgnoreList) do
			t = t + 1
			if v and (v.count or v.firstTime or v.lastTime) then
				Print("> Purging", k)
				v.count = nil
				v.firstTime = nil
				v.lastTime = nil
				pf = pf + 1
			end

			if v and type(v.timestamp) == "string" then
				--[[
				"01.06.21 16:24:30"
				/dump strsplit(" ", "01.06.21 16:24:30")
					[1]="01.06.21",
					[2]="16:24:30"
				/dump strsplit(".", "01.06.21")
					[1]="01",
					[2]="06",
					[3]="21"
				/dump strsplit(":", "16:24:30")
					[1]="16",
					[2]="24",
					[3]="30"
				/dump time({day=tonumber("01"), month=tonumber("06"), year=tonumber("21"), hour=tonumber("16"), min=tonumber("24"), sec=tonumber("30")})
					^-- This fails, but this works:
				/dump time({day=tonumber("01"), month=tonumber("06"), year=tonumber("2021"), hour=tonumber("16"), min=tonumber("24"), sec=tonumber("30")})
				]]--
				local td, tt = strsplit(" ", v.timestamp)
				local day, month, year = strsplit(".", td)
				local hour, min, sec = strsplit(":", tt)
				local dateTbl = {
					day = tonumber(day),
					month = tonumber(month),
					year = tonumber(#year < 4 and "20" .. year or year),
					hour = tonumber(hour),
					min = tonumber(min),
					sec = tonumber(sec)
				}
				-- /dump date("*t", time({day=29, month=05, year=2021, hour=15, min=16, sec=35}))
				Print("> Retiming", k, year, month, day, hour, min, sec, time(dateTbl))
				v.timestamp = date("*t", time(dateTbl))
				rt = rt + 1
			end

			if not strmatch(k, "%-[^|]+") then
				Print("> Renaming", k)
				local fullname = v.playerName .. "-MirageRaceway"
				v.playerName = fullname
				tempTable[fullname] = deepcopy(v)
				rn = rn + 1
			end
		end
		if pf > 0 then
			Print("- Total purges: %d / %d", pf, t)
		end
		if rt > 0 then
			Print("- Total retimes: %d / %d", rt, t)
		end
		if rn > 0 then
			--if rn == t then -- Replace whole list
			--	db.IgnoreList = deepcopy(tempTable)
			--else -- Add only changed
				for k, v in pairs(tempTable) do
					db.IgnoreList[k] = deepcopy(v)
					if db.IgnoreList[k] then
						local nameWithoutRealm = gsub(k, "%-[^|]+", "")
						db.IgnoreList[nameWithoutRealm] = nil
					else
						Print("ERROR RENAMING!")
					end
				end
			--end

			Print("- Total renames: %d / %d", rn, t)
		end
		if pf == 0 and rt == 0 and rn == 0 then
			Print("- Found nothing to be fixed!")
		end

	end
end