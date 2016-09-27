-- Abort if addons list is not available
local FS_UPDATER_ADDONS = FS_UPDATER_ADDONS
if not FS_UPDATER_ADDONS then return end

local DIRECTORY = {}

local FS_UpdaterStatus = LibStub("AceAddon-3.0"):NewAddon("FS_UpdaterStatus", "AceComm-3.0", "AceSerializer-3.0", "AceConsole-3.0")
FSUP = FS_UpdaterStatus

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

local Outer = { type = "group", childGroups = "tree", args = {} }
local GUI = Outer.args

function FS_UpdaterStatus:RebuildGUI()
    wipe(GUI)

    for name in pairs(DIRECTORY) do
        local addon = {
            type = "group",
            name = name,
            args = {}
        }

        for user, rev in pairs(DIRECTORY[name]) do
            addon.args[user] = {
                type = "description",
                name = user .. "  -  |cff" .. (rev:sub(1, 6)) .. rev,
                width = "full"
            }
        end

        GUI[name] = addon
    end

    AceConfigRegistry:NotifyChange("FS_UpdaterStatus")
end

function FS_UpdaterStatus:Request()
    if IsInRaid() then
        FS_UpdaterStatus:SendCommMessage("FSUPS", "$REQ", "RAID")
    end
    if IsInGuild() then
        FS_UpdaterStatus:SendCommMessage("FSUPS", "$REQ", "GUILD")
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
end

function FS_UpdaterStatus:OnSlash()
    AceConfigDialog:Open("FS_UpdaterStatus")
end

do
    local delay
    function FS_UpdaterStatus:BroadcastRevisions()
        if delay then delay:Cancel() end
        delay = C_Timer.NewTimer(5, function()
            local serialized = self:Serialize(FS_UPDATER_ADDONS)
            if IsInRaid() then
                self:SendCommMessage("FSUPS", serialized, "RAID")
            end
            if IsInGuild() then
                self:SendCommMessage("FSUPS", serialized, "GUILD")
            end
        end)
    end
end

function FS_UpdaterStatus:OnCommReceived(prefix, text, _, sender)
    if prefix == "FSUPS" then
        if text == "$REQ" then
            self:BroadcastRevisions()
        else
            local res, addons = self:Deserialize(text)
            if not res then return end

            for addon, rev in pairs(addons) do
                local list = DIRECTORY[addon]
                if not list then
                    list = {}
                    DIRECTORY[addon] = list
                end
                list[sender] = rev
            end

            self:RebuildGUI()
        end
    end
end
