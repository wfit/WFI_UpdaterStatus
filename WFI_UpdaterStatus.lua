local WFI_UPDATER_ADDONS = {}
for i = 1, GetNumAddOns() do
	local name = GetAddOnInfo(i)
	if GetAddOnMetadata(name, "X-PKG-Manifest") then
		WFI_UPDATER_ADDONS[name] = "#Managed"
	elseif GetAddOnMetadata(name, "X-WFI-Addon") then
		WFI_UPDATER_ADDONS[name] = "#Unmanaged"
	end
end

local DIRECTORY = {}

local WFI_UpdaterStatus = LibStub("AceAddon-3.0"):NewAddon("WFI_UpdaterStatus", "AceComm-3.0", "AceSerializer-3.0", "AceConsole-3.0", "AceEvent-3.0")
WFIUP = WFI_UpdaterStatus

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceGUI = LibStub("AceGUI-3.0")

local Outer = { type = "group", childGroups = "tree", args = {} }
local GUI = Outer.args

local GroupUnits = {
	"party1", "party2", "party3", "party4", "party5",
	"raid1", "raid2", "raid3", "raid4", "raid5", "raid6", "raid7", "raid8", "raid9",
	"raid10", "raid11", "raid12", "raid13", "raid14", "raid15", "raid16", "raid17", "raid18", "raid19",
	"raid20", "raid21", "raid22", "raid23", "raid24", "raid25", "raid26", "raid27", "raid28", "raid29",
	"raid30", "raid31", "raid32", "raid33", "raid34", "raid35", "raid36", "raid37", "raid38", "raid39",
	"raid40",
}

function WFI_UpdaterStatus:RebuildGUI()
	wipe(GUI)

	for name in pairs(DIRECTORY) do
		local addon = {
			type = "group",
			name = name,
			args = {}
		}

		for _, unit in ipairs(GroupUnits) do
			if UnitExists(unit) then
				local user = Ambiguate(UnitName(unit), "short")
				if not DIRECTORY[name][user] then
					DIRECTORY[name][user] = "#NotInstalled"
				end
			end
		end

		local max = 0
		for _, rev in pairs(DIRECTORY[name]) do
			if type(rev) == "table" and rev.ts > max then
				max = rev.ts
			end
		end

		for user, rev in pairs(DIRECTORY[name]) do
			local label
			if type(rev) == "table" then
				label = "|cff" .. ((rev.ts == max) and "abd473" or "ff7f00") .. rev.date
			elseif type(rev) == "string" and rev:sub(1, 1) == "#" then
				local state = rev:sub(2)
				local color = (state == "Unmanaged") and "abd473" or "c41f3b"
				label = "|cff" .. color .. state
			else
				label = "|cffc41f3b" .. tostring(rev)
			end
			addon.args[user] = {
				type = "description",
				name = user .. "  -  " .. label,
				width = "normal"
			}
		end

		GUI[name] = addon
	end

	AceConfigRegistry:NotifyChange("WFI_UpdaterStatus")
end

function WFI_UpdaterStatus:Request()
	wipe(DIRECTORY)
	if IsInRaid(LE_PARTY_CATEGORY_HOME) then
		WFI_UpdaterStatus:SendCommMessage("WFIUPS", "$REQ", "RAID")
	end
end

function WFI_UpdaterStatus:OnInitialize()
	self:RegisterComm("WFIUPS")
	self:RegisterChatCommand("fsu", "OnSlash")
	AceConfig:RegisterOptionsTable("WFI_UpdaterStatus", Outer)
end

function WFI_UpdaterStatus:OnEnable()
	for addon, rev in pairs(WFI_UPDATER_ADDONS) do
		local name, _, _, _, reason = GetAddOnInfo(addon)
		if not name or (reason and reason == "MISSING") then
			WFI_UPDATER_ADDONS[addon] = "#NotFound"
		elseif reason then
			WFI_UPDATER_ADDONS[addon] = "#" .. reason
		elseif GetAddOnEnableState(UnitName("player"), addon) == 0 then
			WFI_UPDATER_ADDONS[addon] = "#Disabled"
		elseif not IsAddOnLoaded(addon) and not IsAddOnLoadOnDemand(addon) then
			WFI_UPDATER_ADDONS[addon] = "#NotLoaded"
		else
			local manifest = GetAddOnMetadata(addon, "X-PKG-Manifest")
			WFI_UPDATER_ADDONS[addon] = manifest and _G[manifest] or rev:sub(1, 10)
		end
	end
	self:RebuildGUI()
	self:BroadcastRevisions()
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
	self:RegisterEvent("ENCOUNTER_START")
	self:RegisterEvent("ENCOUNTER_END")
end

function WFI_UpdaterStatus:OnSlash()
	self:Request()
	AceConfigDialog:Open("WFI_UpdaterStatus")
end

do
	local delay
	function WFI_UpdaterStatus:BroadcastRevisions()
		if delay then delay:Cancel() end
		delay = C_Timer.NewTimer(5, function()
			if IsInRaid(LE_PARTY_CATEGORY_HOME) then
				local serialized = self:Serialize(WFI_UPDATER_ADDONS)
				self:SendCommMessage("WFIUPS", serialized, "RAID")
			end
		end)
	end
end

do
	local inRaid = false
	function WFI_UpdaterStatus:GROUP_ROSTER_UPDATE()
		local now = IsInRaid(LE_PARTY_CATEGORY_HOME)
		if now and not inRaid then
			self:Request()
			self:BroadcastRevisions()
		end
		inRaid = now
	end
end

do
	local encounterInProgress = false
	local deferred = false

	local updates = {}
	local warned = {}

	function WFI_UpdaterStatus:OnCommReceived(prefix, text, _, sender)
		if prefix == "WFIUPS" then
			if text == "$REQ" then
				self:BroadcastRevisions()
			else
				local res, addons = self:Deserialize(text)
				if not res then return end
				local doWarn = false

				for addon, rev in pairs(addons) do
					local list = DIRECTORY[addon]
					if not list then
						list = {}
						DIRECTORY[addon] = list
					end
					list[Ambiguate(sender, "short")] = rev
					if type(WFI_UPDATER_ADDONS[addon]) == "table" and type(rev) == "table" then
						if WFI_UPDATER_ADDONS[addon].ts < rev.ts and (not warned[addon] or warned[addon] < rev.ts) then
							if not warned[addon] then
								updates[#updates + 1] = addon
							end
							warned[addon] = rev.ts
							doWarn = true
						end
					end
				end

				if doWarn then
					if encounterInProgress then
						deferred = true
					else
						self:Open(updates)
					end
				end

				self:RebuildGUI()
			end
		end
	end

	function WFI_UpdaterStatus:ENCOUNTER_START()
		encounterInProgress = true
	end

	function WFI_UpdaterStatus:ENCOUNTER_END()
		encounterInProgress = false
		if deferred then
			self:Open(updates)
			deferred = false
		end
	end
end

--- GUI

do
	local window
	local container
	local status = {}

	-- Create a text label
	local function CreateLabel(text)
		local label = AceGUI:Create("Label")
		label:SetText(text)
		label:SetFullWidth(true)

		local old_ww = label.label:CanWordWrap()
		local old_nsw = label.label:CanNonSpaceWrap()

		label.label:SetWordWrap(true)
		label.label:SetNonSpaceWrap(true)

		label:SetCallback("OnRelease", function()
			label.label:SetWordWrap(old_ww)
			label.label:SetNonSpaceWrap(old_nsw)
		end)

		return label
	end

	local function ContainerHeight(container)
		local height = 0
		for _, child in ipairs(container.obj.children) do
			local frame = child.frame
			local fheight = frame.height or frame:GetHeight()
			height = height + fheight
		end
		return height
	end

	-- Resize the dialog window
	function WFI_UpdaterStatus:Layout()
		container:DoLayout()
		local height = ContainerHeight(container.frame)
		window:SetHeight(height + 57 - 10)
	end

	function WFI_UpdaterStatus:Open(updates)
		if not window then
			window = AceGUI:Create("Window")
			window:SetStatusTable(status)
			window:EnableResize(false)
			window:SetWidth(300)

			window:SetCallback("OnClose", function()
				window:Release()
				window = nil
				ObjectiveTrackerFrame:Show()
			end)

			container = AceGUI:Create("SimpleGroup")
			container:SetAutoAdjustHeight(true)
			container:SetFullWidth(true)
			container:SetLayout("list")
			window:AddChild(container)

			window:ClearAllPoints()
			window:SetPoint("TOPRIGHT", ObjectiveTrackerFrame)
			ObjectiveTrackerFrame:Hide()
		else
			container:ReleaseChildren()
		end

		local function add_text(text, font, cont)
			if not cont then cont = container end
			if not font then font = GameFontHighlight end

			local text_label = CreateLabel(text)
			text_label:SetFontObject(font)
			cont:AddChild(text_label)

			return text_label
		end

		local function add_buttons(buttons)
			local actions = AceGUI:Create("SimpleGroup")
			actions:SetLayout("flow")
			actions:SetFullWidth(true)
			container:AddChild(actions)

			for _, button in ipairs(buttons) do
				local btn = AceGUI:Create("Button")
				btn:SetText(button[1])
				btn:SetFullWidth(true)
				actions:AddChild(btn)

				if button[2] then
					btn:SetCallback("OnClick", button[2])
				else
					btn:SetDisabled(true)
				end
			end
		end

		window:SetTitle("Updates available")
		add_text("Updates available for some of your addons:", GameFontHighlightLarge)
		add_text(" ")
		for _, addon in ipairs(updates) do
			add_text(" -  |cff64b4ff" .. addon, GameFontHighlightLarge)
		end
		add_text("\nPlease run WFI-Updater and then reload your interface.\n")
		add_buttons({
			{ "Reload", function() ReloadUI() end }
		})

		self:Layout()
		PlaySound("DwarfExploration", "master")
	end
end
