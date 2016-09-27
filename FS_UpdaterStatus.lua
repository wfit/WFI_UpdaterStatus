-- Abort if addons list is not available
local FS_UPDATER_ADDONS = FS_UPDATER_ADDONS
if not FS_UPDATER_ADDONS then return end

local DIRECTORY = {}

local FS_UpdaterStatus = LibStub("AceAddon-3.0"):NewAddon("FS_UpdaterStatus", "AceComm-3.0", "AceSerializer-3.0")
local AceConfig = LibStub("AceConfig-3.0")

local GUI = {

}

function FS_UpdaterStatus:OnInitialize()
    self:RegisterComm("FSUPS")
    AceConfig:RegisterOptionsTable("FS_UpdaterStatus", GUI, "/fsu")
end

function FS_UpdaterStatus:OnEnable()
    self:BroadcastRevisions()
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
        end
    end
end
