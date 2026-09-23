local name = ...;
--- @class TTV_4E_NS
local ns = select(2, ...);

local isMidnight = select(4, GetBuildInfo()) >= 120000;

local ChatEdit_InsertLink = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink;
local ChatFrame_OpenChat = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat;
local GetAllClassIDs = C_SpecializationInfo.GetAllClassIDs or function()
    local classIDs = {}
    for classID = 1, GetNumClasses() do
        if GetClassInfo(classID) then
            table.insert(classIDs, classID);
        end
    end

    return classIDs;
end

ns.MAX_LEVEL_CLASS_CURRENCY_CAP = isMidnight and 34 or 31;
ns.MAX_LEVEL_SPEC_CURRENCY_CAP = isMidnight and 34 or 30;
ns.MAX_LEVEL_SUBTREE_CURRENCY_CAP = isMidnight and 13 or 10;
ns.TOTAL_CURRENCY_CAP = ns.MAX_LEVEL_CLASS_CURRENCY_CAP + ns.MAX_LEVEL_SPEC_CURRENCY_CAP + ns.MAX_LEVEL_SUBTREE_CURRENCY_CAP;
ns.MAX_LEVEL = 9 + ns.TOTAL_CURRENCY_CAP;

--- @class TalentViewer4E
local TalentViewer = {
    purchasedRanks = {},
    --- @type table<number, number> # [nodeID] = entryID
    selectedEntries = {},
    currencySpending = {},
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
    --- @type table<TalentViewer_Enum_TreeType, table<number, number>> # [treeType][level] = currencyAmount
    currencyAtLevel = {
        [TalentViewer.Enum.TreeType.Class] = {},
        [TalentViewer.Enum.TreeType.Spec] = {},
        [TalentViewer.Enum.TreeType.SubTree] = {},
    },
    --- @type table<number, TalentViewer_Enum_TreeType> # [level] = treeType
    currencyEarnedOrder = {},
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
        end
    end
end

function TalentViewer:RestoreCurrency(nodeID)
    local costInfo = self:GetTalentFrame():GetNodeCost(nodeID);
    if costInfo then
        for _, cost in ipairs(costInfo) do
            self.currencySpending[cost.ID] = (self.currencySpending[cost.ID] or 0) - cost.amount;
        end
    end
end

--- @param spent number
--- @param treeType TalentViewer_Enum_TreeType
--- @return number requiredLevel
function TalentViewer:GetRequiredLevelForCurrencySpent(spent, treeType)
    local requiredLevel;
    if self.Enum.TreeType.Class == treeType then
        -- starts at 8 (so that first talent point results in level 10)
        -- 10-70 = spendingUnderOrEqual31 * 2
        -- 81-90 = spendingOver31 * 3
        -- ignore apex talents for now
        if spent > 31 then
            requiredLevel = 79 + ((spent - 31) * 3);
        else
            requiredLevel = 8 + (spent * 2);
        end
    elseif self.Enum.TreeType.SubTree == treeType then
        -- starts at 70 (so that first talent point results in level 71)
        -- 71-80 = spendingUnderOrEqual10 * 1
        -- 81-90 = spendingOver10 * 3
        if spent > 10 then
            requiredLevel = 80 + ((spent - 10) * 3);
        else
            requiredLevel = 70 + spent;
        end
    elseif self.Enum.TreeType.Spec == treeType then
        -- if apex talent selected: minimum level is 80 regardless of spending
        -- starts at 9 (so that first talent point results in level 11)
        -- 11-70 = spendingUnderOrEqual30 * 2
        -- 81-90 = spendingOver30 * 3
        if spent > 30 then
            requiredLevel = 78 + ((spent - 30) * 3);
        else
            requiredLevel = 9 + (spent * 2);
        end
    else
        error('Invalid currency type: ' .. tostring(treeType));
    end

    return math.max(10, requiredLevel);
end

--- @param level number
--- @param treeType TalentViewer_Enum_TreeType
--- @return number currencyAmount
function TalentViewer:GetCurrencyAtLevel(level, treeType)
    if not self.cache.currencyAtLevel[treeType][level] then
        local maxCurrency;
        if self.Enum.TreeType.Class == treeType then
            maxCurrency = ns.MAX_LEVEL_CLASS_CURRENCY_CAP;
        elseif self.Enum.TreeType.Spec == treeType then
            maxCurrency = ns.MAX_LEVEL_SPEC_CURRENCY_CAP;
        elseif self.Enum.TreeType.SubTree == treeType then
            maxCurrency = ns.MAX_LEVEL_SUBTREE_CURRENCY_CAP;
        end
        for currencyAmount = 0, maxCurrency do
            local requiredLevel = self:GetRequiredLevelForCurrencySpent(currencyAmount, treeType);
            self.cache.currencyAtLevel[treeType][requiredLevel] = currencyAmount;
        end
        for lvl = 10, ns.MAX_LEVEL do
            if not self.cache.currencyAtLevel[treeType][lvl] then
                self.cache.currencyAtLevel[treeType][lvl] = self.cache.currencyAtLevel[treeType][lvl - 1] or 0;
            end
        end
    end

    return self.cache.currencyAtLevel[treeType][level] or 0;
end

--- @return table<number, TalentViewer_Enum_TreeType> # [level] = treeType
function TalentViewer:GetCurrencyEarnedOrder()
    local order = self.cache.currencyEarnedOrder;
    if not next(order) then
        for i = 1, ns.MAX_LEVEL_CLASS_CURRENCY_CAP do
            local level = self:GetRequiredLevelForCurrencySpent(i, self.Enum.TreeType.Class);
            order[level] = self.Enum.TreeType.Class;
        end
        for i = 1, ns.MAX_LEVEL_SPEC_CURRENCY_CAP do
            local level = self:GetRequiredLevelForCurrencySpent(i, self.Enum.TreeType.Spec);
            order[level] = self.Enum.TreeType.Spec;
        end
        for i = 1, ns.MAX_LEVEL_SUBTREE_CURRENCY_CAP do
            local level = self:GetRequiredLevelForCurrencySpent(i, self.Enum.TreeType.SubTree);
            order[level] = self.Enum.TreeType.SubTree;
        end
    end

    return CopyTable(order);
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
