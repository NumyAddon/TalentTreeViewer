local name = ...;
--- @class TTV_4E_NS
local ns = select(2, ...);

local ChatEdit_InsertLink = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink;
local ChatFrame_OpenChat = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat;
local GetAllClassIDs = C_SpecializationInfo.GetAllClassIDs;

ns.TOTAL_CURRENCY_CAP = 51;
ns.MAX_LEVEL = 9 + ns.TOTAL_CURRENCY_CAP;
ns.MAX_ROWS = 7;
ns.MAX_COLS = 4 * 3;

--- @class TalentViewer4E
local TalentViewer = {
    purchasedRanks = {},
    --- @type table<number, number> # [nodeID] = entryID
    selectedEntries = {},
    currencySpending = {},
    currencyGroupSpending = {},
    _ns = ns,
};
_G.TalentViewer = TalentViewer;

ns.ImportExport = {};
ns.IcyVeinsImport = {};
ns.TalentViewer = TalentViewer;

TalentViewer.Enum = {
    --- @enum TalentViewer_Enum_TreeType
    TreeType = {
        Class = 1,
        Spec = 2,
        SubTree = 3,
    },
};

--- @class TalentViewer_Cache4E
local cache = {
    classNames = {},
    classFiles = {},
    classSpecs = {},
    classOrder = {},
    nodes = {},
    specNames = {},
    specIndexToIdMap = {},
    specIdToClassIdMap = {},
    specIconId = {},
    groupDisplayInfoByClass = {},
};
TalentViewer.cache = cache;
---@type LibTalentTree-1.0
local LibTalentTree = LibStub('LibTalentTree-1.0');

local L = ns.L;

local function wipe(table)
    if table and type(table) == 'table' then
        _G['wipe'](table);
    end
end

----------------------
--- Build class / spec cache
----------------------
do
    for i, classID in ipairs(GetAllClassIDs()) do
        cache.classOrder[i] = classID;
        cache.classNames[classID], cache.classFiles[classID] = GetClassInfo(classID);
        cache.specIndexToIdMap[classID] = {};
        cache.classSpecs[classID] = {};
        local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID);
        for specIndex = 1, numSpecs do
            local specID = GetSpecializationInfoForClassID(classID, specIndex);
            local specName, _, specIcon = select(2, GetSpecializationInfoForSpecID(specID));
            if specName ~= '' then
                cache.specNames[specID] = specName;
                cache.classSpecs[classID][specID] = specName;
                cache.specIndexToIdMap[classID][specIndex] = specID;
                cache.specIconId[specID] = specIcon;
                cache.specIdToClassIdMap[specID] = classID;
            end
        end
        local treeID = LibTalentTree:GetClassTreeID(classID);
        cache.groupDisplayInfoByClass[classID] = C_Traits.GetGroupDisplayInfoByTreeID(treeID);
        for _, info in ipairs(cache.groupDisplayInfoByClass[classID]) do
            cache.groupDisplayInfoByClass[classID][info.groupID] = info;
        end
    end
end

local frame = CreateFrame('FRAME')
local function OnEvent(_, event, ...)
    if event == 'ADDON_LOADED' then
        local addonName = ...;
        if addonName == name then
            TalentViewer:OnInitialize();
        end
    end
end
frame:HookScript('OnEvent', OnEvent);
frame:RegisterEvent('ADDON_LOADED');

-----------------------------
--- Talent Tree Utilities ---
-----------------------------

--- @return TalentViewer_ClassTalentsFrameTemplate4E
function TalentViewer:GetTalentFrame()
    return TalentViewer_DF.Talents;
end

function TalentViewer:ApplyCurrencySpending(treeCurrency)
    local spending = self.currencySpending[treeCurrency.traitCurrencyID] or 0;
    treeCurrency.spent = spending;
    treeCurrency.quantity = treeCurrency.maxQuantity - spending;

    return treeCurrency;
end

function TalentViewer:ResetTree()
    local talentFrame = self:GetTalentFrame();
    wipe(self.purchasedRanks);
    wipe(self.selectedEntries);
    wipe(self.currencySpending);
    wipe(self.currencyGroupSpending);
    wipe(talentFrame.edgeRequirementsCache);
    talentFrame.nodesPerGate = nil;
    talentFrame.eligibleNodesPerGate = nil;
    talentFrame:SelectSubTree(nil);
    talentFrame:SetTalentTreeID(self.treeId, true);
    talentFrame:UpdateClassVisuals();
    talentFrame:UpdateSpecBackground();
end

function TalentViewer:GetActiveRank(nodeID)
    return self.purchasedRanks[nodeID] or 0;
end

function TalentViewer:GetSelectedEntryId(nodeID)
    return self.selectedEntries[nodeID];
end

function TalentViewer:SetRank(nodeID, rank)
    local currentRank;
    repeat
        currentRank = self.purchasedRanks[nodeID] or 0;
        if currentRank == rank then return; end
        if rank > currentRank then
            TalentViewer:PurchaseRank(nodeID);
        else
            TalentViewer:RefundRank(nodeID);
        end
    until currentRank == rank;
end

function TalentViewer:PurchaseRank(nodeID)
    self:ReduceCurrency(nodeID);
    self.purchasedRanks[nodeID] = (self.purchasedRanks[nodeID] or 0) + 1;
end

function TalentViewer:RefundRank(nodeID)
    self:RestoreCurrency(nodeID);
    self.purchasedRanks[nodeID] = (self.purchasedRanks[nodeID] or 0) - 1;
end

function TalentViewer:SetSelection(nodeID, entryID)
    local hasPreviousSelection = self.selectedEntries[nodeID] ~= nil;

    if (entryID and not hasPreviousSelection) then
        self:ReduceCurrency(nodeID);
    elseif (not entryID and hasPreviousSelection) then
        self:RestoreCurrency(nodeID);
    end

    self.selectedEntries[nodeID] = entryID;
end

function TalentViewer:ReduceCurrency(nodeID)
    local costInfo = self:GetTalentFrame():GetNodeCost(nodeID);
    if costInfo then
        for _, cost in ipairs(costInfo) do
            self.currencySpending[cost.ID] = (self.currencySpending[cost.ID] or 0) + cost.amount;
            self.currencyGroupSpending[cost.groupID] = (self.currencyGroupSpending[cost.groupID] or 0) + cost.amount;
        end
    end
end

function TalentViewer:RestoreCurrency(nodeID)
    local costInfo = self:GetTalentFrame():GetNodeCost(nodeID);
    if costInfo then
        for _, cost in ipairs(costInfo) do
            self.currencySpending[cost.ID] = (self.currencySpending[cost.ID] or 0) - cost.amount;
            self.currencyGroupSpending[cost.groupID] = (self.currencyGroupSpending[cost.groupID] or 0) - cost.amount;
        end
    end
end

----------------------
--- UI Interaction ---
----------------------

function TalentViewer:InitSpecSelection()
    local _, _, classId = UnitClass('player');
    local currentSpec = C_SpecializationInfo.GetSpecialization() or 1;
    local specId = cache.specIndexToIdMap[classId][currentSpec] or cache.specIndexToIdMap[classId][1];
    TalentViewer:SelectSpec(classId, specId);
end

function TalentViewer:OnInitialize()
    self.db = TalentTreeViewerDB;

    if(self.ignoreRestrictionsCheckbox) then
        self.ignoreRestrictionsCheckbox:SetChecked(self.db.ignoreRestrictions);
    end
end

function TalentViewer:ImportLoadout(importString)
    --- @type TalentViewerImportExport4E
    local ImportExport = ns.ImportExport;
    --- @type TalentViewerIcyVeinsImport4E
    local IcyVeinsImport = ns.IcyVeinsImport;

    if TalentViewer_DF:IsShown() then
        TalentViewer_DF:Raise();
    else
        TalentViewer:ToggleTalentView();
    end
    ImportExport:ImportLoadout(importString);
end

function TalentViewer:ExportLoadout()
    --- @type TalentViewerImportExport4E
    local ImportExport = ns.ImportExport;

    return ImportExport:GetLoadoutExportString();
end

function TalentViewer:LinkToChat()
    local exportString = self:ExportLoadout();
    if not exportString then return; end

    if not TALENT_BUILD_CHAT_LINK_TEXT then
        if not ChatEdit_InsertLink(exportString) then
            ChatFrame_OpenChat(exportString);
        end
        return;
    end

    local talentsTab = self:GetTalentFrame();

    local specName = talentsTab:GetSpecName();
    local className = talentsTab:GetClassName()
    local specID = talentsTab:GetSpecID();
    local classColor = RAID_CLASS_COLORS[select(2, GetClassInfo(talentsTab:GetClassID()))];
    local level = ns.MAX_LEVEL;

    local linkDisplayText = ("[%s]"):format(TALENT_BUILD_CHAT_LINK_TEXT:format(specName, className));
    local linkText = LinkUtil.FormatLink("talentbuild", linkDisplayText, specID, level, exportString);
    local chatLink = classColor:WrapTextInColorCode(linkText);
    if not ChatEdit_InsertLink(chatLink) then
        ChatFrame_OpenChat(chatLink);
    end
end

function TalentViewer:ToggleTalentView()
    self:InitFrame();
    TalentViewer_DF:SetShown(not TalentViewer_DF:IsShown());
end

function TalentViewer:InitFrame()
    if self.frameInitialized then return; end
    self.frameInitialized = true;
    UIPanelUpdateScaleForFit(TalentViewer_DF, 200, 270);
    table.insert(UISpecialFrames, 'TalentViewer_DF');
    TalentViewer_DF.Inset:Hide();
    self:InitDropdown();
    self:InitCheckbox();
    self:InitSpecSelection();
end

--- Reset the talent tree, and select the specified spec
--- @param classId number
--- @param specId number
--- @param skipDropdownUpdate boolean?
function TalentViewer:SelectSpec(classId, specId, skipDropdownUpdate)
    assert(type(classId) == 'number', 'classId must be a number');
    assert(type(specId) == 'number', 'specId must be a number');

    self.selectedClassId = classId;
    self.selectedSpecId = specId;
    self.treeId = LibTalentTree:GetClassTreeID(classId);
    self:SetPortraitIcon(specId);

    TalentViewer_DF:SetTitle(string.format(
        '%s %s - %s',
        cache.classNames[classId],
        TALENTS,
        cache.classSpecs[classId][specId] or ''
    ));
    if not skipDropdownUpdate then
        self.dropDownButton:PickClassID(classId);
    end

    self:ResetTree();
end

function TalentViewer:SetPortraitIcon(specId)
    local icon = cache.specIconId[specId];
    TalentViewer_DF:SetPortraitTexCoord(0, 1, 0, 1);
    TalentViewer_DF:SetPortraitToAsset(icon);
end

function TalentViewer:InitCheckbox()
    if self.ignoreRestrictionsCheckbox then return; end
    self.ignoreRestrictionsCheckbox = TalentViewer_DF.Talents.IgnoreRestrictions;
    local checkbox = self.ignoreRestrictionsCheckbox;
    checkbox.Text:SetText(L['Ignore Restrictions']);
    if self.db then
        checkbox:SetChecked(self.db.ignoreRestrictions);
    end
    checkbox:SetScript('OnEnter', function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip_AddNormalLine(GameTooltip, L['Ignore restrictions when selecting talents']);
        GameTooltip:Show();
    end);
    checkbox:SetScript('OnLeave', function(self)
        GameTooltip:Hide();
    end);
    checkbox:SetScript('OnClick', function(button)
        self.db.ignoreRestrictions = button:GetChecked()
        self:GetTalentFrame():UpdateTreeCurrencyInfo()
    end);
end

function TalentViewer:InitDropdown()
    if self.dropDownButton then return; end
    --- @type WowStyle1DropdownTemplate
    self.dropDownButton = TalentViewer_DF.Talents.TV_DropdownButton;

    self.dropDownButton:SetupMenu(function(owner, rootDescription)
        rootDescription:CreateTitle(L['Select another Class']);
        self:BuildMenu(rootDescription);
    end);
    self.dropDownButton:SetSelectionText(function(selections)
        return selections[1].text;
    end);

    local classListReverse = tInvert(cache.classOrder);
    local numClasses = table.count(cache.classOrder);

    self.dropDownButton:EnableMouseWheel(true);
    function self.dropDownButton:Increment()
        local currentClassIndex = classListReverse[TalentViewer.selectedClassId];
        local nextClassIndex = currentClassIndex + 1;
        if nextClassIndex > numClasses then
            nextClassIndex = 1;
        end
        self:PickClassID(cache.classOrder[nextClassIndex]);
    end
    function self.dropDownButton:Decrement()
        local currentClassIndex = classListReverse[TalentViewer.selectedClassId];
        local previousClassIndex = currentClassIndex - 1;
        if previousClassIndex < 1 then
            previousClassIndex = numClasses;
        end
        self:PickClassID(cache.classOrder[previousClassIndex]);
    end
    function self.dropDownButton:PickClassID(classID)
        MenuUtil.TraverseMenu(self:GetMenuDescription(), function(description)
            if description.data == classID then self:Pick(description, MenuInputContext.None) end
        end);
    end
end

--- @param rootDescription RootMenuDescriptionProxy
function TalentViewer:BuildMenu(rootDescription)
    local function isClassSelected(classID)
        return classID == self.selectedClassId;
    end
    local function selectClass(classID)
        self:SelectSpec(classID, cache.specIndexToIdMap[classID][1], true);
    end

    for _, classID in ipairs(cache.classOrder) do
        local nameFormat = '|T%s:16|t %s';
        rootDescription:CreateRadio(
            nameFormat:format(
                'interface/icons/classicon_' .. cache.classFiles[classID],
                cache.classNames[classID]
            ),
            isClassSelected,
            selectClass,
            classID
        );
    end
end

-------------------------
--- Button highlights ---
-------------------------
function TalentViewer:SetActionBarHighlights(talentButton, shown)
    local spellID = talentButton:GetSpellID();
    if (spellID and talentButton:GetActionBarStatus() == ActionButtonUtil.ActionBarActionStatus.NotMissing) then
        self:HandleBlizzardActionButtonHighlights(shown and spellID);
        self:HandleLibActionButtonHighlights(shown and spellID);
    end
end

function TalentViewer:HandleBlizzardActionButtonHighlights(spellID)
    local ON_BAR_HIGHLIGHT_MARKS = spellID and tInvert(C_ActionBar.FindSpellActionButtons(spellID) or {}) or {};
    for _, actionButton in pairs(ActionBarButtonEventsFrame.frames) do
        if actionButton.SpellHighlightTexture and actionButton.SpellHighlightAnim then
            SharedActionButton_RefreshSpellHighlight(actionButton, ON_BAR_HIGHLIGHT_MARKS[actionButton.action]);
        end
    end
end

function TalentViewer:HandleLibActionButtonHighlights(spellID)
    local libName = 'LibActionButton-1.';
    for mayor, lib in LibStub:IterateLibraries() do
        if mayor:sub(1, string.len(libName)) == libName then
            for button in pairs(lib:GetAllButtons()) do
                if button.SpellHighlightTexture and button.SpellHighlightAnim and button.GetSpellId then
                    local shown = spellID and button:GetSpellId() == spellID;
                    SharedActionButton_RefreshSpellHighlight(button, shown);
                end
            end
        end
    end
end
