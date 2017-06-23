-- Abort if addons list is not available
local FS_UPDATER_ADDONS = FS_UPDATER_ADDONS
if not FS_UPDATER_ADDONS then return end

for addon, rev in pairs(FS_UPDATER_ADDONS) do
    local ts = GetAddOnMetadata(addon, "X-FSPKG-Timestamp")
	FS_UPDATER_ADDONS[addon] = ts and tonumber(ts) or rev:sub(1, 10)
end

local DIRECTORY = {}

local FS_UpdaterStatus = LibStub("AceAddon-3.0"):NewAddon("FS_UpdaterStatus", "AceComm-3.0", "AceSerializer-3.0", "AceConsole-3.0")
FSUP = FS_UpdaterStatus

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceGUI = LibStub("AceGUI-3.0")

local Outer = { type = "group", childGroups = "tree", args = {} }
local GUI = Outer.args

local function colorize(rev)
	a, b, c = rev:sub(1, 2), rev:sub(3, 4), rev:sub(5, 6)
	a, b, c = tonumber(a, 16), tonumber(b, 16), tonumber(c, 16)
	local offset = math.max(0, 128 - (a + b + c) / 3)
	a, b, c = math.min(a + offset, 255), math.min(b + offset, 255), math.min(c + offset, 255)
	return ("%02x%02x%02x"):format(a, b, c)
end

function FS_UpdaterStatus:RebuildGUI()
    wipe(GUI)

    for name in pairs(DIRECTORY) do
        local addon = {
            type = "group",
            name = name,
            args = {}
        }

        local max = 0
	    for user, rev in pairs(DIRECTORY[name]) do
		    if type(rev) == "number" and rev > max then
			    max = rev
		    end
	    end

        for user, rev in pairs(DIRECTORY[name]) do
	        local label
	        if type(rev) == "number" then
		        label = "|cff" .. ((rev == max) and "abd473" or "ff7f00") .. rev
	        else
		        label = "|cff" .. colorize(rev) .. rev:sub(1, 10)
	        end
            addon.args[user] = {
                type = "description",
                name = Ambiguate(user, "short") .. "  -  " .. label,
                width = "normal"
            }
        end

        GUI[name] = addon
    end

    AceConfigRegistry:NotifyChange("FS_UpdaterStatus")
end

function FS_UpdaterStatus:Request()
    wipe(DIRECTORY)
    if IsInRaid(LE_PARTY_CATEGORY_HOME) then
        FS_UpdaterStatus:SendCommMessage("FSUPS", "$REQ", "RAID")
    end
end

function FS_UpdaterStatus:OnInitialize()
    self:RegisterComm("FSUPS")
    self:RegisterChatCommand("fsu", "OnSlash")
    self:RebuildGUI()
    AceConfig:RegisterOptionsTable("FS_UpdaterStatus", Outer)
end

function FS_UpdaterStatus:OnEnable()
    self:BroadcastRevisions()
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
end

function FS_UpdaterStatus:OnSlash()
    self:Request()
    AceConfigDialog:Open("FS_UpdaterStatus")
end

do
    local delay
    function FS_UpdaterStatus:BroadcastRevisions()
        if delay then delay:Cancel() end
        delay = C_Timer.NewTimer(5, function()
            if IsInRaid(LE_PARTY_CATEGORY_HOME) then
                local serialized = self:Serialize(FS_UPDATER_ADDONS)
                self:SendCommMessage("FSUPS", serialized, "RAID")
            end
        end)
    end
end

do
	local inRaid = false
	function FS_UpdaterStatus:GROUP_ROSTER_UPDATE()
		local now = IsInRaid(LE_PARTY_CATEGORY_HOME)
		if now and not inRaid then
			self:Request()
			self:BroadcastRevisions()
		end
		inRaid = now
	end
end

do
	local updates = {}
	local warned = {}

	function FS_UpdaterStatus:OnCommReceived(prefix, text, _, sender)
	    if prefix == "FSUPS" then
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
	                list[sender] = rev
		            if type(FS_UPDATER_ADDONS[addon]) == "number" and type(rev) == "number" then
			            if FS_UPDATER_ADDONS[addon] < rev and not warned[addon] then
				            warned[addon] = true
				            doWarn = true
				            updates[#updates + 1] = addon
			            end
		            end
	            end

	            if doWarn then
		            self:Open(updates)
	            end

	            self:RebuildGUI()
	        end
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
	function FS_UpdaterStatus:Layout()
		container:DoLayout()
		local height = ContainerHeight(container.frame)
		window:SetHeight(height + 57 - 10)
	end

	function FS_UpdaterStatus:Open(updates)
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
		add_text("\nPlease run FS-Updater and then reload you interface.\n")
		add_buttons({
			{ "Reload", function()
				ReloadUI()
			end }
		})

		self:Layout()
		PlaySound("DwarfExploration", "master")
	end
end
