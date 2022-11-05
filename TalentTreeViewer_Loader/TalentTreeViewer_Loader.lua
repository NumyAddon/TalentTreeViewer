local name, _ = ...

if LE_EXPANSION_LEVEL_CURRENT <= LE_EXPANSION_SHADOWLANDS then print(name, 'requires Dragonflight to work') return end

--- @class TVLoader
local TVLoader = {}
local LibDBIcon = LibStub('LibDBIcon-1.0')

local frame = CreateFrame('Frame')
frame:HookScript('OnEvent', function(_, event, ...) TVLoader[event](TVLoader, event, ...) end)
frame:RegisterEvent('ADDON_LOADED')

function TVLoader:ADDON_LOADED(_, addonName)
    if addonName == name then
        TVLoader:OnInitialize()
        if(IsAddOnLoaded('BlizzMove')) then TVLoader:RegisterToBlizzMove() end
    end
    if addonName == 'Blizzard_ClassTalentUI' then
        TVLoader:AddButtonToBlizzardTalentFrame()
        TVLoader:HookIntoBlizzardImport()
    end
end

function TVLoader:OnInitialize()
    local defaults = {
        ldbOptions = { hide = false },
        ignoreRestrictions = false,
    }

    TalentTreeViewerDB = TalentTreeViewerDB or {}
    self.db = TalentTreeViewerDB

    for key, value in pairs(defaults) do
        if self.db[key] == nil then
            self.db[key] = value
        end
    end

    local dataObject = LibStub('LibDataBroker-1.1'):NewDataObject(
            name,
            {
                type = 'launcher',
                text = 'Talent Tree Viewer',
                icon = 'interface/icons/inv_inscription_talenttome01.blp',
                OnClick = function()
                    if IsShiftKeyDown() then
                        TalentViewer.db.ldbOptions.hide = true
                        LibDBIcon:Hide(name)
                        return
                    end
                    TVLoader:ToggleTalentView()
                end,
                OnTooltipShow = function(tooltip)
                    tooltip:AddLine('Talent Tree Viewer')
                    tooltip:AddLine('|cffeda55fClick|r to view the talents for any spec.')
                    tooltip:AddLine('|cffeda55fShift-Click|r to hide this button. (|cffeda55f/tv reset|r to restore)')
                end,
            }
    )
    LibDBIcon:Register(name, dataObject, self.db.ldbOptions)

    SLASH_TALENT_VIEWER1 = '/tv'
    SLASH_TALENT_VIEWER2 = '/talentviewer'
    SLASH_TALENT_VIEWER3 = '/talenttreeviewer'
    SlashCmdList['TALENT_VIEWER'] = function(message)
        if message == 'reset' then
            wipe(TalentViewer.db.ldbOptions)
            TalentViewer.db.ldbOptions.hide = false
            TalentViewer.db.lastSelected = nil

            LibDBIcon:Hide(name)
            LibDBIcon:Show(name)

            return
        end
        TVLoader:ToggleTalentView()
    end
end

function TVLoader:AddButtonToBlizzardTalentFrame()
    local button = CreateFrame('Button', nil, ClassTalentFrame, 'UIPanelButtonTemplate')
    button:SetText('Talent Viewer')
    button:SetSize(100, 22)
    button:SetPoint('TOPRIGHT', ClassTalentFrame, 'TOPRIGHT', -22, 0)
    button:SetScript('OnClick', function()
        self:ToggleTalentView()
    end)
    button:SetFrameStrata('HIGH')
end

function TVLoader:HookIntoBlizzardImport()
    --- @type TalentViewerImportExport
    local lastError
    local importString

    StaticPopupDialogs["TalentViewerDefaultImportFailedDialog"] = {
        text = LOADOUT_ERROR_WRONG_SPEC .. "\n\n" .. "Would you like to open the build in Talent Viewer instead?",
        button1 = OKAY,
        button2 = CLOSE,
        OnAccept = function(dialog)
            ClassTalentLoadoutImportDialog:OnCancel();
            self:GetTV():ImportLoadout(importString);
            dialog:Hide();
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    hooksecurefunc(ClassTalentFrame.TalentsTab, 'ImportLoadout', function(self, str)
        if lastError == LOADOUT_ERROR_WRONG_SPEC then
            importString = str
            StaticPopup_Hide('LOADOUT_IMPORT_ERROR_DIALOG')

            StaticPopup_Show('TalentViewerDefaultImportFailedDialog')
        end
        lastError = nil
    end)
    hooksecurefunc(ClassTalentFrame.TalentsTab, 'ShowImportError', function(self, error)
        lastError = error
    end)
end

function TVLoader:ToggleTalentView()
    self:GetTV():ToggleTalentView()
end

function TVLoader:LoadTV()
    LoadAddOn('TalentTreeViewer')
end

--- @return TalentViewer
function TVLoader:GetTV()
    self:LoadTV()
    return _G.TalentViewer
end

function TVLoader:RegisterToBlizzMove()
    if not BlizzMoveAPI then return end
    BlizzMoveAPI:RegisterAddOnFrames(
        {
            ['TalentTreeViewer'] = {
                ['TalentViewer_DF'] = {
                    MinVersion = 100000,
                    SubFrames = {
                        ['TalentViewer_DF.Talents.ButtonsParent'] = {
                            MinVersion = 100000,
                        },
                    },
                },
            },
        }
    )
end
