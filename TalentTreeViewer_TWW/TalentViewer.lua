local name = ...
--- @class TalentViewer_NSTWW
local ns = select(2, ...)

if LE_EXPANSION_LEVEL_CURRENT <= LE_EXPANSION_SHADOWLANDS then print(name, 'requires Dragonflight to work') return end

ns.MAX_LEVEL_CLASS_CURRENCY_CAP = 31;
ns.MAX_LEVEL_SPEC_CURRENCY_CAP = 30;
ns.MAX_LEVEL_SUBTREE_CURRENCY_CAP = 10;
ns.TOTAL_CURRENCY_CAP = ns.MAX_LEVEL_CLASS_CURRENCY_CAP + ns.MAX_LEVEL_SPEC_CURRENCY_CAP + ns.MAX_LEVEL_SUBTREE_CURRENCY_CAP;
ns.MAX_LEVEL = 9 + ns.TOTAL_CURRENCY_CAP;

--- @class TalentViewerTWW
local TalentViewer = {
    purchasedRanks = {},
    selectedEntries = {},
    currencySpending = {},
    _ns = ns,
};
_G.TalentViewer = TalentViewer;

ns.ImportExport = {};
ns.IcyVeinsImport = {};
ns.TalentViewer = TalentViewer;

--- @class TalentViewer_CacheTWW
local cache = {
    classNames = {},
    classFiles = {},
    classSpecs = {},
    nodes = {},
    tierLevel = {},
    specNames = {},
    specIndexToIdMap = {},
    specIdToClassIdMap = {},
    specIconId = {},
};
TalentViewer.cache = cache;
---@type LibTalentTree-1.0
local LibTalentTree = LibStub('LibTalentTree-1.0');

local L = LibStub('AceLocale-3.0'):GetLocale(name);

local function wipe(table)
    if table and type(table) == 'table' then
        _G['wipe'](table);
    end
end

----------------------
--- Build class / spec cache
----------------------
do
    local initialSpecs = {
        [1] = 1446,
        [2] = 1451,
        [3] = 1448,
        [4] = 1453,
        [5] = 1452,
        [6] = 1455,
        [7] = 1444,
        [8] = 1449,
        [9] = 1454,
        [10] = 1450,
        [11] = 1447,
        [12] = 1456,
        [13] = 1465,
    };
    for classID = 1, GetNumClasses() do
        local _;
        cache.classNames[classID], cache.classFiles[classID], _ = GetClassInfo(classID);
        cache.specIndexToIdMap[classID] = {};
        cache.classSpecs[classID] = {};
        local numSpecs = GetNumSpecializationsForClassID(classID);
        for specIndex = 1, (numSpecs + 1) do
            local specID = GetSpecializationInfoForClassID(classID, specIndex) or initialSpecs[classID];
            local specName, _, specIcon = select(2, GetSpecializationInfoForSpecID(specID));
            local isInitial = specIndex > numSpecs;
            if isInitial then
                specName = 'Initial ' .. cache.classNames[classID];
            end
            if specName ~= '' then
                cache.specNames[specID] = specName;
                cache.classSpecs[classID][specID] = specName;
                cache.specIndexToIdMap[classID][specIndex] = specID;
                cache.specIconId[specID] = not isInitial and specIcon or ('interface/icons/classicon_' .. cache.classFiles[classID]);
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
            if(C_AddOns.IsAddOnLoaded('ElvUI')) then TalentViewer:ApplyElvUISkin(); end
        end
    end
end
frame:HookScript('OnEvent', OnEvent);
frame:RegisterEvent('ADDON_LOADED');

-----------------------------
--- Talent Tree Utilities ---
-----------------------------

---@return TalentViewerUIMixinTWW
function TalentViewer:GetTalentFrame()
    return TalentViewer_DF.Talents;
end

function TalentViewer:ApplyCurrencySpending(treeCurrency)
    local spending = self.currencySpending[treeCurrency.traitCurrencyID] or 0;
    treeCurrency.spent = spending;
    treeCurrency.quantity = treeCurrency.maxQuantity - spending;

    return treeCurrency;
end

--- @param lockLevelingBuild ?boolean # by default, a new leveling build is created and activated when this function is called, passing true will prevent that
function TalentViewer:ResetTree(lockLevelingBuild)
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
    talentFrame:UpdateLevelingBuildHighlights();
    local isRecordingLevelingBuild = self:IsRecordingLevelingBuild();
    if not lockLevelingBuild then
        self:ClearLevelingBuild();
        if isRecordingLevelingBuild then
            self:StartRecordingLevelingBuild();
        end
    end
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

    if self:IsRecordingLevelingBuild() then
        self:RecordLevelingEntry(nodeID, self.purchasedRanks[nodeID]);
    end
end

function TalentViewer:RefundRank(nodeID)
    self:RestoreCurrency(nodeID);
    self.purchasedRanks[nodeID] = (self.purchasedRanks[nodeID] or 0) - 1;

    if self:IsRecordingLevelingBuild() then
        self:RemoveLastRecordedLevelingEntry(nodeID);
    end
end

function TalentViewer:SetSelection(nodeID, entryID)
    local hasPreviousSelection = self.selectedEntries[nodeID] ~= nil;

    if (entryID and hasPreviousSelection and entryID ~= self.selectedEntries[nodeID]) then
        if self:IsRecordingLevelingBuild() then
            self:UpdateRecordedLevelingChoiceEntry(nodeID, entryID);
        end
    elseif (entryID and not hasPreviousSelection) then
        self:ReduceCurrency(nodeID);

        if self:IsRecordingLevelingBuild() then
            self:RecordLevelingEntry(nodeID, 1, entryID);
        end
    elseif (not entryID and hasPreviousSelection) then
        self:RestoreCurrency(nodeID);

        if self:IsRecordingLevelingBuild() then
            self:RemoveLastRecordedLevelingEntry(nodeID);
        end
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

----------------------
--- UI Interaction ---
----------------------

function TalentViewer:InitSpecSelection()
    local _, _, classId = UnitClass('player');
    local currentSpec = GetSpecialization() or 1;
    local specId = cache.specIndexToIdMap[classId][currentSpec];
    TalentViewer:SelectSpec(classId, specId);
end

function TalentViewer:OnInitialize()
    self.db = TalentTreeViewerDB;

    if(self.ignoreRestrictionsCheckbox) then
        self.ignoreRestrictionsCheckbox:SetChecked(self.db.ignoreRestrictions);
    end
end

function TalentViewer:ImportLoadout(importString)
    --- @type TalentViewerImportExportTWW
    local ImportExport = ns.ImportExport;
    --- @type TalentViewerIcyVeinsImportTWW
    local IcyVeinsImport = ns.IcyVeinsImport;

    if TalentViewer_DF:IsShown() then
        TalentViewer_DF:Raise();
    else
        TalentViewer:ToggleTalentView();
    end
    if IcyVeinsImport:IsTalentUrl(importString) then
        IcyVeinsImport:ImportUrl(importString);
    else
        ImportExport:ImportLoadout(importString);
    end
end

function TalentViewer:ExportLoadout()
    --- @type TalentViewerImportExportTWW
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
    TalentViewer_DFInset:Hide();
    self:InitDropdown();
    self:InitCheckbox();
    self:InitSpecSelection();
    self:InitLevelingBuildUIs();
end

--- Reset the talent tree, and select the specified spec
--- @param classId number
--- @param specId number
function TalentViewer:SelectSpec(classId, specId, skipDropdownUpdate)
    assert(type(classId) == 'number', 'classId must be a number');
    assert(type(specId) == 'number', 'specId must be a number');

    self.selectedClassId = classId;
    self.selectedSpecId = specId;
    self.treeId = LibTalentTree:GetClassTreeId(classId);
    self:SetPortraitIcon(specId);

    TalentViewer_DF:SetTitle(string.format(
        '%s %s - %s',
        cache.classNames[classId],
        TALENTS,
        cache.classSpecs[classId][specId] or ''
    ));
    if not skipDropdownUpdate then
        self.dropDownButton:PickSpecID(specId);
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
    --- @type BUTTON
    self.dropDownButton = TalentViewer_DF.Talents.TV_DropdownButton;

    self.dropDownButton:SetupMenu(function(owner, rootDescription)
        rootDescription:CreateTitle(L['Select another Specialization']);
        self:BuildMenu(rootDescription);
    end);
    self.dropDownButton:SetSelectionText(function(selections)
        return selections[2].text;
    end);

    local specList = {};
    local specListReverse = {};
    local index = 1;
    for classID, _ in ipairs(cache.classSpecs) do
        for _, specID in ipairs(cache.specIndexToIdMap[classID]) do
            specList[index] = specID;
            specListReverse[specID] = index;
            index = index + 1;
        end
    end

    self.dropDownButton:EnableMouseWheel(true);
    function self.dropDownButton:Increment()
        local currentSpecIndex = specListReverse[TalentViewer.selectedSpecId];
        local nextSpecIndex = currentSpecIndex + 1;
        if nextSpecIndex > #specList then
            nextSpecIndex = 1;
        end
        self:PickSpecID(specList[nextSpecIndex]);
    end
    function self.dropDownButton:Decrement()
        local currentSpecIndex = specListReverse[TalentViewer.selectedSpecId];
        local previousSpecIndex = currentSpecIndex - 1;
        if previousSpecIndex < 1 then
            previousSpecIndex = #specList;
        end
        self:PickSpecID(specList[previousSpecIndex]);
    end
    function self.dropDownButton:PickSpecID(specID)
        MenuUtil.TraverseMenu(self:GetMenuDescription(), function(description)
            if description.data == specID then self:Pick(description, MenuInputContext.None) end
        end);
    end

    if C_AddOns.IsAddOnLoaded('ElvUI') then
        self:ApplyElvUISkin();
    end
end

function TalentViewer:BuildMenu(rootDescription)
    local function isClassSelected(classID)
        return classID == TalentViewer.selectedClassId;
    end
    local function isSpecSelected(specID)
        return specID == TalentViewer.selectedSpecId;
    end
    local function selectSpec(specID)
        self:SelectSpec(cache.specIdToClassIdMap[specID], specID, true);
    end

    for classID, _ in ipairs(cache.classSpecs) do
        local nameFormat = '|T%s:16|t %s';
        local elementDescription = rootDescription:CreateRadio(
            nameFormat:format(
                'interface/icons/classicon_' .. cache.classFiles[classID],
                cache.classNames[classID]
            ),
            isClassSelected,
            nil,
            classID
        );
        for _, specID in ipairs(cache.specIndexToIdMap[classID]) do
            elementDescription:CreateRadio(
                nameFormat:format(
                    cache.specIconId[specID],
                    cache.specNames[specID]
                ),
                isSpecSelected,
                selectSpec,
                specID
            );
        end
    end
end

function TalentViewer:ApplyElvUISkin()
    if true then return; end
    if self.skinned then return; end
    self.skinned = true;
    local S = unpack(ElvUI):GetModule('Skins');

    S:HandleButton(self.dropDownButton);

    -- loosely based on ElvUI's talent skinning code

end

-----------------------
--- Leveling builds ---
-----------------------
local defaultRecordingInfo = {
    active = true,
    buildID = 0, -- matches #levelingBuilds, effectively an auto increment
    startingOffset = { -- startingOffset = level at which entries[1] is learned - 1; so that level = startingOffset + index
        [1] = 10 - 2, -- class startingOffset
        [2] = 11 - 2, -- spec startingOffset
        -- hero spec trees are not pre-allocated
    },
    entries = {
        [1] = {}, -- class entries
        [2] = {}, -- spec entries
        -- hero spec trees are not pre-allocated
    },
    entriesCount = 0,
};
--- @type table<number, table<number, TalentViewer_LevelingBuildInfoContainer>> # [specID][buildID][specOrClass] = entries (specOrClass is 1 for class, 2 for spec)
TalentViewer.levelingBuilds = {};
TalentViewer.recordingInfo = CreateFromMixins(defaultRecordingInfo);

function TalentViewer:GetCurrentLevelingBuildID()
    return self.recordingInfo.buildID;
end

--- @return nil|table<number, table<number, TalentViewer_LevelingBuildEntry>> # [tree] = {[level] = entry}, where tree is 1 for class, 2 for spec, or tree is SubTreeID for hero specs
function TalentViewer:GetCurrentLevelingBuild()
    return self:GetCurrentLevelingBuildID() and self:GetLevelingBuild(self:GetCurrentLevelingBuildID());
end

--- @param buildID number
--- @return TalentViewer_LevelingBuild?
function TalentViewer:GetLevelingBuild(buildID)
    local build = self.levelingBuilds[self.selectedSpecId] and self.levelingBuilds[self.selectedSpecId][buildID] or nil;
    if not build then return nil; end

    local buildEntries = {};
    for tree, entries in pairs(build.entries) do
        buildEntries[tree] = {};
        local startingOffset = build.startingOffset[tree] or 70;
        local multiplier = (tree <= 2) and 2 or 1; -- class/spec nodes are earned every 2 levels, hero talents every level
        for i, entry in ipairs(entries) do
            buildEntries[tree][startingOffset + (i * multiplier)] = entry;
        end
    end

    return { entries = buildEntries, selectedSubTreeID = build.selectedSubTreeID };
end

--- @param lockLevelingBuild boolean # by default, a new leveling build is created and activated when this function is called, passing true will prevent that
function TalentViewer:ApplyLevelingBuild(buildID, level, lockLevelingBuild)
    local buildEntries = self:GetLevelingBuild(buildID);
    if (not buildEntries) then
        return;
    end
    local buildInfo = self.levelingBuilds[self.selectedSpecId][buildID];

    self.recordingInfo.buildID = buildID;
    self.recordingInfo.entries = buildInfo.entries;
    self.recordingInfo.entriesCount = buildInfo.entriesCount;
    self.recordingInfo.startingOffset = buildInfo.startingOffset;
    self.recordingInfo.active = false;
    self.recordingInfo.buildReference = buildInfo;
    self:GetTalentFrame():SetLevelingBuildID(buildID);
    self:GetTalentFrame():ApplyLevelingBuild(level, lockLevelingBuild);
    self.recordingInfo.active = true;

    self:GetTalentFrame().LevelingBuildLevelSlider:SetValue(level);
end

--- @param levelingBuild TalentViewer_LevelingBuild
function TalentViewer:ImportLevelingBuild(levelingBuild)
    local buildEntries = levelingBuild.entries;
    local selectedSubTreeID = levelingBuild.selectedSubTreeID;
    self:ClearLevelingBuild();
    for tree, entries in pairs(buildEntries) do
        local baseStartingOffset;
        local multiplier = 2;
        if tree == 1 then
            baseStartingOffset = 10;
        elseif tree == 2 then
            baseStartingOffset = 11;
        else
            baseStartingOffset = 71;
            multiplier = 1;
        end
        baseStartingOffset = baseStartingOffset - (1 * multiplier)
        local startingOffset;
        for level = 10, ns.MAX_LEVEL do
            local entry = entries[level];
            if entry then
                if not startingOffset then
                    startingOffset= level - (1 * multiplier);
                end
                self:RecordLevelingEntry(entry.nodeID, entry.targetRank, entry.entryID);
            end
        end
        self.recordingInfo.startingOffset[tree] = startingOffset or baseStartingOffset;
    end
    if selectedSubTreeID then
        local nodeID, subTreeEntryID = LibTalentTree:GetSubTreeSelectionNodeIDAndEntryIDBySpecID(self.selectedSpecId, selectedSubTreeID);
        if nodeID and subTreeEntryID then
            self:RecordLevelingEntry(nodeID, 1, subTreeEntryID);
        end
    end
end

function TalentViewer:StartRecordingLevelingBuild()
    self.recordingInfo.active = true;
    self:GetTalentFrame().StartRecordingButton:Hide();
    self:GetTalentFrame().StopRecordingButton:Show();
    if next(self:GetCurrentLevelingBuild() or {}) then
        self:ApplyLevelingBuild(self:GetCurrentLevelingBuildID(), ns.MAX_LEVEL, true);
    else
        self:RecalculateCurrentStartingOffsets();
    end
end

function TalentViewer:RecalculateCurrentStartingOffsets()
    if not self:GetTalentFrame().treeCurrencyInfo then return; end
    local classCurrencyInfo = self:GetTalentFrame().treeCurrencyInfo[1];
    if classCurrencyInfo and classCurrencyInfo.traitCurrencyID then
        local amount = classCurrencyInfo and classCurrencyInfo.quantity or 0
        local requiredLevel = 8;
        local spent = (ns.MAX_LEVEL_CLASS_CURRENCY_CAP) - amount;
        requiredLevel = math.max(defaultRecordingInfo.startingOffset[1], requiredLevel + (spent * 2));

        self.recordingInfo.startingOffset[1] = requiredLevel;
    end
    local specCurrencyInfo = self:GetTalentFrame().treeCurrencyInfo[2];
    if specCurrencyInfo and specCurrencyInfo.traitCurrencyID then
        local amount = specCurrencyInfo and specCurrencyInfo.quantity or 0
        local requiredLevel = 9;
        local spent = (ns.MAX_LEVEL_SPEC_CURRENCY_CAP) - amount;
        requiredLevel = math.max(defaultRecordingInfo.startingOffset[1], requiredLevel + (spent * 2));

        self.recordingInfo.startingOffset[2] = requiredLevel;
    end
end

function TalentViewer:StopRecordingLevelingBuild()
    self.recordingInfo.active = false;
    self:GetTalentFrame().StartRecordingButton:Show();
    self:GetTalentFrame().StopRecordingButton:Hide();
end

function TalentViewer:ClearLevelingBuild()
    for _, button in ipairs(self:GetTalentFrame().levelingOrderButtons) do
        button:SetOrder({});
    end
    self.levelingBuilds[self.selectedSpecId] = self.levelingBuilds[self.selectedSpecId] or {};
    if
        self.levelingBuilds[self.selectedSpecId][self.recordingInfo.buildID]
        and self.levelingBuilds[self.selectedSpecId][self.recordingInfo.buildID].entries == self.recordingInfo.entries
        and 0 == self.recordingInfo.entriesCount
    then -- the build is already empty, no point resetting it
        return;
    end
    self.recordingInfo = CopyTable(defaultRecordingInfo);
    --- @type TalentViewer_LevelingBuildInfoContainer
    local info = {
        entries = self.recordingInfo.entries,
        startingOffset = self.recordingInfo.startingOffset,
        entriesCount = 0,
    };
    table.insert(self.levelingBuilds[self.selectedSpecId], info);
    self.recordingInfo.buildID = #self.levelingBuilds[self.selectedSpecId];

    self:StartRecordingLevelingBuild();
end

function TalentViewer:IsRecordingLevelingBuild()
    return self.recordingInfo.active;
end

--- @param nodeID number
--- @param targetRank number
--- @param entryID ?number
function TalentViewer:RecordLevelingEntry(nodeID, targetRank, entryID)
    local nodeInfo = self:GetTalentFrame():GetAndCacheNodeInfo(nodeID);
    if nodeInfo.isSubTreeSelection then
        local button = self:GetTalentFrame():GetTalentButtonByNodeID(nodeID);
        button.LevelingOrder:SetOrder({71});
        local entryInfo = entryID and self:GetTalentFrame():GetAndCacheEntryInfo(entryID);
        self.recordingInfo.selectedSubTreeID = entryInfo and entryInfo.subTreeID;
        self.recordingInfo.buildReference.selectedSubTreeID = self.recordingInfo.selectedSubTreeID;

        return;
    end;
    self.recordingInfo.entriesCount = self.recordingInfo.entriesCount + 1;
    self.recordingInfo.buildReference.entriesCount = self.recordingInfo.entriesCount;
    local indexKey = nodeInfo.tvSubTreeID or (nodeInfo.isClassNode and 1 or 2);
    self.recordingInfo.entries[indexKey] = self.recordingInfo.entries[indexKey] or {};
    local entries = self.recordingInfo.entries[indexKey];
    table.insert(entries, {
        nodeID = nodeID,
        targetRank = targetRank,
        entryID = entryID,
    });
    local baseLevel = self.recordingInfo.startingOffset[indexKey] or 70;
    local multiplier = (indexKey <= 2) and 2 or 1; -- class/spec nodes are earned every 2 levels, hero talents every level
    local level = baseLevel + (#entries * multiplier);

    local button = self:GetTalentFrame():GetTalentButtonByNodeID(nodeID);
    if not button then
        if DevTool and DevTool.AddData then
            DevTool:AddData({
                entry = entries[#entries],
                nodeID = nodeID,
                level = level,
                nodeInfo = self:GetTalentFrame():GetAndCacheNodeInfo(nodeID),
            }, 'could not find button for NodeID when recording');
        end
        return
    end
    button.LevelingOrder:AppendToOrder(level);
end

function TalentViewer:RemoveLastRecordedLevelingEntry(nodeID)
    local nodeInfo = self:GetTalentFrame():GetAndCacheNodeInfo(nodeID);
    local indexKey = nodeInfo.tvSubTreeID or (nodeInfo.isClassNode and 1 or 2);
    local entries = self.recordingInfo.entries[indexKey];
    local removed;
    for i = #entries, 1, -1 do
        local entry = entries[i];
        if (entry and entry.nodeID == nodeID) then
            removed = i;
            table.remove(entries, i);
            self.recordingInfo.entriesCount = self.recordingInfo.entriesCount - 1;
            self.recordingInfo.buildReference.entriesCount = self.recordingInfo.entriesCount;
            local button = self:GetTalentFrame():GetTalentButtonByNodeID(nodeID);
            if not button then
                if DevTool and DevTool.AddData then
                    DevTool:AddData({
                        entry = entry,
                        nodeID = nodeID,
                        nodeInfo = self:GetTalentFrame():GetAndCacheNodeInfo(nodeID),
                    }, 'could not find button for NodeID when removing');
                end
            else
                button.LevelingOrder:RemoveLastOrder();
            end
            break;
        end
    end
    if removed then
        for i = removed, #entries do
            local entry = entries[i];
            local baseLevel = self.recordingInfo.startingOffset[indexKey];
            local level = baseLevel + (i * 2);
            local button = self:GetTalentFrame():GetTalentButtonByNodeID(entry.nodeID);
            if not button then
                if DevTool and DevTool.AddData then
                    DevTool:AddData({
                        entry = entry,
                        nodeID = nodeID,
                        nodeInfo = self:GetTalentFrame():GetAndCacheNodeInfo(nodeID),
                    }, 'could not find button for NodeID when updating after removing');
                end
            else
                button.LevelingOrder:UpdateOrder(level + 2, level);
            end
        end
    end
end

function TalentViewer:UpdateRecordedLevelingChoiceEntry(nodeID, entryID)
    local nodeInfo = self:GetTalentFrame():GetAndCacheNodeInfo(nodeID);
    local indexKey = nodeInfo.tvSubTreeID or (nodeInfo.isClassNode and 1 or 2);
    local entries = self.recordingInfo.entries[indexKey];
    for _, entry in ipairs(entries) do
        if (entry.nodeID == nodeID) then
            entry.entryID = entryID;
            return;
        end
    end
end

function TalentViewer:InitLevelingBuildUIs()
    local slider = self:GetTalentFrame().LevelingBuildLevelSlider;
    local minValue = 9;
    local maxValue = ns.MAX_LEVEL;
    local steps = maxValue - minValue;
    local formatters = {
        [MinimalSliderWithSteppersMixin.Label.Left] = function() return L['Level'] end,
        [MinimalSliderWithSteppersMixin.Label.Right] = function(value) return value end,
    };
    local currentValue = 9;
    slider:Init(currentValue, minValue, maxValue, steps, formatters);

    local callingFromSlider = false;
    local function onValueChange()
        local value = slider:GetValue();
        if callingFromSlider or value == currentValue then return; end
        currentValue = value;
        callingFromSlider = true;
        self:ApplyLevelingBuild(self:GetCurrentLevelingBuildID(), value, true);
        callingFromSlider = false;
        self:StopRecordingLevelingBuild();
    end

    slider:RegisterCallback(TalentViewer_LevelingSliderMixin.Event.OnDragStop, onValueChange);
    slider:RegisterCallback(TalentViewer_LevelingSliderMixin.Event.OnStepperClicked, onValueChange);
    slider:RegisterCallback(TalentViewer_LevelingSliderMixin.Event.OnEnter, function()
        GameTooltip:SetOwner(slider, 'ANCHOR_RIGHT', 0, 0);
        GameTooltip:SetText(L['Leveling build']);
        GameTooltip:AddLine(L['Select the level to apply the leveling build to']);
        GameTooltip:AddLine(L['This will lag out your game!']);
        GameTooltip:Show();
    end);
    slider:RegisterCallback(TalentViewer_LevelingSliderMixin.Event.OnLeave, function()
        GameTooltip:Hide();
    end);


    local dropdownButton = self:GetTalentFrame().LevelingBuildDropdownButton;
    dropdownButton:HookScript('OnEnter', function()
        GameTooltip:SetOwner(dropdownButton, 'ANCHOR_RIGHT', 0, 0);
        GameTooltip:SetText(L['Leveling build']);
        GameTooltip:AddLine(L['Select a leveling build to apply']);
        GameTooltip:AddLine(L['This will reset your current talent choices!']);
        GameTooltip:Show();
    end);
    dropdownButton:HookScript('OnLeave', function()
        GameTooltip:Hide();
    end);
    dropdownButton:OverrideText(L['Select Recorded Build']);

    local function isBuildSelected(buildID)
        return self:GetCurrentLevelingBuildID() == buildID;
    end
    local function selectBuild(buildID)
        self:ApplyLevelingBuild(buildID, currentValue, true);
        self:StopRecordingLevelingBuild();
    end
    dropdownButton:SetupMenu(function(owner, rootDescription)
        rootDescription:CreateTitle(L['Leveling builds can be saved and loaded with TalentLoadoutManager'], WHITE_FONT_COLOR);
        rootDescription:CreateTitle(L['You can also export/import leveling builds, or link them in chat'], WHITE_FONT_COLOR);

        if (not C_AddOns.IsAddOnLoaded('TalentLoadoutManager')) then
            rootDescription:CreateButton(L['Click to |cFF3333FFdownload|r TalentLoadoutManager'], function()
                StaticPopup_Show('TalentViewerExportDialog', nil, nil, 'https://www.curseforge.com/wow/addons/talent-loadout-manager');
            end);
        end
        for buildID, buildInfo in ipairs(self.levelingBuilds[self.selectedSpecId] or {}) do
            rootDescription:CreateRadio(
                string.format(
                    L['Leveling build %d (%d points spent)'],
                    buildID,
                    buildInfo.entriesCount
                ),
                isBuildSelected,
                selectBuild,
                buildID
            );
        end
    end);
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
        if ( actionButton.SpellHighlightTexture and actionButton.SpellHighlightAnim ) then
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