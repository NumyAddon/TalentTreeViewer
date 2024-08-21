local name, _ = ...;

if LE_EXPANSION_LEVEL_CURRENT <= LE_EXPANSION_SHADOWLANDS then print(name, 'only works on Dragonflight and later') return; end

--- @class TalentViewerLoader
local TVLoader = {};
TalentViewerLoader = TVLoader;

local LibDBIcon = LibStub('LibDBIcon-1.0');
local L = LibStub('AceLocale-3.0'):GetLocale(name);
local lodAddonName = 'TalentTreeViewer_TWW';

local frame = CreateFrame('Frame');
frame:HookScript('OnEvent', function(_, event, ...) TVLoader[event](TVLoader, event, ...); end);
frame:RegisterEvent('ADDON_LOADED');

function TVLoader:ADDON_LOADED(_, addonName)
    if addonName == name then
        self:OnInitialize();
        if(C_AddOns.IsAddOnLoaded('BlizzMove')) then self:RegisterToBlizzMove(); end
    end
    if addonName == 'Blizzard_PlayerSpells' then
        self:AddButtonToBlizzardTalentFrame();
        self:HookIntoBlizzardImport();
    end
end

function TVLoader:OnInitialize()
    local defaults = {
        ldbOptions = { hide = false },
        ignoreRestrictions = false,
    };

    TalentTreeViewerDB = TalentTreeViewerDB or {};
    self.db = TalentTreeViewerDB;

    for key, value in pairs(defaults) do
        if self.db[key] == nil then
            self.db[key] = value;
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
                    self.db.ldbOptions.hide = true;
                    LibDBIcon:Hide(name);

                    return;
                end
                self:ToggleTalentView();
            end,
            OnTooltipShow = function(tooltip)
                tooltip:AddLine('Talent Tree Viewer');
                tooltip:AddLine(L['|cffeda55fClick|r to view the talents for any spec.']);
                tooltip:AddLine(L['|cffeda55fShift-Click|r to hide this button. (|cffeda55f/tv reset|r to restore)']);
            end,
        }
    );
    LibDBIcon:Register(name, dataObject, self.db.ldbOptions);

    SLASH_TALENT_VIEWER1 = '/tv';
    SLASH_TALENT_VIEWER2 = '/talentviewer';
    SLASH_TALENT_VIEWER3 = '/talenttreeviewer';
    SlashCmdList['TALENT_VIEWER'] = function(message)
        if message == 'reset' then
            wipe(TalentViewer.db.ldbOptions);
            TalentViewer.db.ldbOptions.hide = false;
            TalentViewer.db.lastSelected = nil;

            LibDBIcon:Hide(name);
            LibDBIcon:Show(name);

            return;
        end
        self:ToggleTalentView();
    end
end

function TVLoader:AddButtonToBlizzardTalentFrame()
    local button = CreateFrame('Button', nil, PlayerSpellsFrame, 'UIPanelButtonTemplate');
    PlayerSpellsFrame.TalentTreeViewer_OpenViewerButton = button;
    button:SetText('Talent Viewer');
    button:SetSize(100, 22);
    button:SetPoint('TOPRIGHT', PlayerSpellsFrame, 'TOPRIGHT', -44, 0);
    button:SetScript('OnClick', function()
        self:ToggleTalentView();
    end);
    button:SetFrameStrata('HIGH');
end

function TVLoader:HookIntoBlizzardImport()
    local lastError;
    local importString;

    StaticPopupDialogs["TalentViewerDefaultImportFailedDialog"] = {
        text = LOADOUT_ERROR_WRONG_SPEC .. "\n\n" .. L["Would you like to open the build in Talent Viewer instead?"],
        button1 = OKAY,
        button2 = CLOSE,
        OnAccept = function(dialog)
            ClassTalentLoadoutImportDialog:OnCancel();
            self:GetTalentViewer():ImportLoadout(importString);
            dialog:Hide();
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    local talentsTab = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame;
    hooksecurefunc(talentsTab, 'ImportLoadout', function(_, str)
        if lastError == LOADOUT_ERROR_WRONG_SPEC then
            importString = str;
            StaticPopup_Hide('LOADOUT_IMPORT_ERROR_DIALOG');

            StaticPopup_Show('TalentViewerDefaultImportFailedDialog');
        end
        lastError = nil;
    end);
    hooksecurefunc(talentsTab, 'ShowImportError', function(_, error)
        lastError = error;
    end);
end

function TVLoader:ToggleTalentView()
    self:GetTalentViewer():ToggleTalentView();
end

function TVLoader:LoadTalentViewer()
    -- force enable, in case someone disabled the lod addon
    C_AddOns.EnableAddOn(lodAddonName, UnitName('player'));
    C_AddOns.LoadAddOn(lodAddonName);
end

function TVLoader:GetLodAddonName()
    return lodAddonName;
end

--- @return TalentViewer|TalentViewerTWW
function TVLoader:GetTalentViewer()
    self:LoadTalentViewer();

    return _G.TalentViewer;
end

function TVLoader:RegisterToBlizzMove()
    if not BlizzMoveAPI then return; end
    BlizzMoveAPI:RegisterAddOnFrames({
        [lodAddonName] = {
            ['TalentViewer_DF'] = {
                SubFrames = {
                    ['TalentViewer_DF.Talents.ButtonsParent'] = {},
                },
            },
        },
    });
end
