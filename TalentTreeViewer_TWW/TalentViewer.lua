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
--- @type LibUIDropDownMenuNumy-4.0
local LibDD = LibStub("LibUIDropDownMenuNumy-4.0");

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
	for classID = 1, GetNumClasses() do
		local _;
		cache.classNames[classID], cache.classFiles[classID], _ = GetClassInfo(classID);
		cache.specIndexToIdMap[classID] = {};
		cache.classSpecs[classID] = {};
		for specIndex = 1, GetNumSpecializationsForClassID(classID) do
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
function TalentViewer:SelectSpec(classId, specId)
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

	self:ResetTree();
end

function TalentViewer:SetPortraitIcon(specId)
	local icon = cache.specIconId[specId];
	TalentViewer_DF:SetPortraitTexCoord(0, 1, 0, 1);
	TalentViewer_DF:SetPortraitToAsset(icon);
end

function TalentViewer:MakeDropDownButton()
	local mainButton = TalentViewer_DF.Talents.TV_DropdownButton;
	local dropDown = LibDD:Create_UIDropDownMenu(nil, TalentViewer_DF);

	mainButton = Mixin(mainButton, DropDownToggleButtonMixin);
	mainButton:OnLoad_Intrinsic();
	mainButton:SetScript('OnMouseDown', function(self)
		LibDD:ToggleDropDownMenu(1, nil, dropDown, self, 204, 15, TalentViewer.menuList or nil);
	end)

	dropDown:Hide();

	return mainButton, dropDown;
end

function TalentViewer:BuildMenu(setValueFunc, isCheckedFunc)
	local menu = {}
	for classId, classSpecs in pairs(cache.classSpecs) do
		local specMenuList = {}
		for specId, specName in pairs(classSpecs) do
			table.insert(specMenuList,{
				text = string.format(
					'|T%d:16|t %s',
					cache.specIconId[specId],
					specName
				),
				arg1 = specId,
				arg2 = classId,
				func = setValueFunc,
				checked = isCheckedFunc,
			});
		end

		table.insert(menu, {
			text = string.format(
				'|Tinterface/icons/classicon_%s:16|t %s',
				cache.classFiles[classId],
				cache.classNames[classId]
			),
			hasArrow = true,
			menuList = specMenuList,
			checked = isCheckedFunc,
			arg2 = classId,
		});
	end

	return menu;
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
	self.dropDownButton, self.dropDown = self:MakeDropDownButton();

	if C_AddOns.IsAddOnLoaded('ElvUI') then
		self:ApplyElvUISkin();
	end

	local function setValue(_, specId, classId)
		LibDD:CloseDropDownMenus();

		TalentViewer:SelectSpec(classId, specId);
	end

	local isChecked = function(button)
		return button.arg2 == TalentViewer.selectedClassId and (not button.arg1 or button.arg1 == TalentViewer.selectedSpecId);
	end

	self.menuList = self:BuildMenu(setValue, isChecked);
	LibDD:EasyMenu(self.menuList, self.dropDown, self.dropDown, 0, 0);
end

function TalentViewer:ApplyElvUISkin()
	if true then return; end
	if self.skinned then return; end
	self.skinned = true;
	local S = unpack(ElvUI):GetModule('Skins');

	S:HandleDropDownBox(self.dropDown);
	S:HandleButton(self.dropDownButton);

	-- loosely based on ElvUI's talent skinning code

end

-----------------------
--- Leveling builds ---
-----------------------
local defaultRecordingInfo = {
    active = true,
    buildID = 0, -- matches #levelingBuilds, effectively an auto increment
    currentIndex = {
        [1] = 0, -- class currentIndex
        [2] = 0, -- spec currentIndex
    },
    startingOffset = { -- startingOffset = level at which entries[1] is learned - 1; so that level = startingOffset + index
        [1] = 10 - 2, -- class startingOffset
        [2] = 11 - 2, -- spec startingOffset
    },
    entries = {
        [1] = {}, -- class entries
        [2] = {}, -- spec entries
    },
};
--- @type table<number, table<number, TalentViewer_LevelingBuildInfoContainer>> # [specID][buildID][specOrClass] = entries (specOrClass is 1 for class, 2 for spec)
TalentViewer.levelingBuilds = {};
TalentViewer.recordingInfo = CreateFromMixins(defaultRecordingInfo);

function TalentViewer:GetCurrentLevelingBuildID()
    return self.recordingInfo.buildID;
end

--- @return nil|table<number, TalentViewer_LevelingBuildEntry> # [level] = entry
function TalentViewer:GetCurrentLevelingBuild()
    return self:GetCurrentLevelingBuildID() and self:GetLevelingBuild(self:GetCurrentLevelingBuildID());
end

--- @param buildID number
--- @return nil|table<number, TalentViewer_LevelingBuildEntry> # [level] = entry
function TalentViewer:GetLevelingBuild(buildID)
	local build = self.levelingBuilds[self.selectedSpecId] and self.levelingBuilds[self.selectedSpecId][buildID] or nil;
	if not build then return nil; end

	local buildEntries = {};
	local classStartingOffset = build.startingOffset[1];
	local classEntries = build.entries[1];
	for i, entry in ipairs(classEntries) do
        buildEntries[classStartingOffset + (i * 2)] = entry;
	end
	local specStartingOffset = build.startingOffset[2];
	local specEntries = build.entries[2];
	for i, entry in ipairs(specEntries) do
        buildEntries[specStartingOffset + (i * 2)] = entry;
    end

    return buildEntries;
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
    self.recordingInfo.startingOffset = buildInfo.startingOffset;
    self.recordingInfo.active = false;
	self:GetTalentFrame():SetLevelingBuildID(buildID);
	self:GetTalentFrame():ApplyLevelingBuild(level, lockLevelingBuild);
    self.recordingInfo.active = true;

    self:GetTalentFrame().LevelingBuildLevelSlider:SetValue(level);
end

--- @return table<number, TalentViewer_LevelingBuildEntry> # [level] = entry
function TalentViewer:ImportLevelingBuild(buildEntries)
    self:ClearLevelingBuild();
    local classStartingOffset, specStartingOffset;
    for level = 10, ns.MAX_LEVEL do
        local isClassNode = level % 2 == 0;
        local entry = buildEntries[level];
        if entry then
            if isClassNode and not classStartingOffset then
                classStartingOffset = level - 2;
                self.recordingInfo.startingOffset[1] = classStartingOffset;
            end
            if not isClassNode and not specStartingOffset then
                specStartingOffset = level - 2;
                self.recordingInfo.startingOffset[2] = specStartingOffset;
            end
            self:RecordLevelingEntry(entry.nodeID, entry.targetRank, entry.entryID);
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
            requiredLevel = math.max(10, requiredLevel + (spent * 2));

            self.recordingInfo.startingOffset[1] = requiredLevel;
        end
        local specCurrencyInfo = self:GetTalentFrame().treeCurrencyInfo[2];
        if specCurrencyInfo and specCurrencyInfo.traitCurrencyID then
            local amount = specCurrencyInfo and specCurrencyInfo.quantity or 0
            local requiredLevel = 9;
            local spent = (ns.MAX_LEVEL_SPEC_CURRENCY_CAP) - amount;
            requiredLevel = math.max(10, requiredLevel + (spent * 2));

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
        and not next(self.recordingInfo.entries[1])
        and not next(self.recordingInfo.entries[2])
    then -- the build is already empty, no point resetting it
        return;
    end
    self.recordingInfo = CopyTable(defaultRecordingInfo);
    --- @type TalentViewer_LevelingBuildInfoContainer
    local info = {
        entries = self.recordingInfo.entries,
        startingOffset = self.recordingInfo.startingOffset,
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
        self.recordingInfo.selectedSubTreeEntryID = entryID;
        return;
    end;
    local indexKey = nodeInfo.tvSubTreeID or (nodeInfo.isClassNode and 1 or 2);
    self.recordingInfo.entries[indexKey] = self.recordingInfo.entries[indexKey] or {};
    local entries = self.recordingInfo.entries[indexKey];
    table.insert(entries, {
        nodeID = nodeID,
        targetRank = targetRank,
        entryID = entryID,
    });
    self.recordingInfo.currentIndex[indexKey] = #entries;
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
    local isClassNode = self:GetTalentFrame():GetAndCacheNodeInfo(nodeID).isClassNode;
    local indexKey = isClassNode and 1 or 2;
    local entries = self.recordingInfo.entries[indexKey];
    local removed;
    for i = #entries, 1, -1 do
        local entry = entries[i];
        if (entry and entry.nodeID == nodeID) then
            removed = i;
            table.remove(entries, i);
            self.recordingInfo.currentIndex[indexKey] = #entries;
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
    local isClassNode = self:GetTalentFrame():GetAndCacheNodeInfo(nodeID).isClassNode;
    local indexKey = isClassNode and 1 or 2;
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


    local dropDownButton = self:GetTalentFrame().LevelingBuildDropdownButton;
    dropDownButton:HookScript('OnEnter', function()
        GameTooltip:SetOwner(dropDownButton, 'ANCHOR_RIGHT', 0, 0);
        GameTooltip:SetText(L['Leveling build']);
        GameTooltip:AddLine(L['Select a leveling build to apply']);
        GameTooltip:AddLine(L['This will reset your current talent choices!']);
        GameTooltip:Show();
    end);
    dropDownButton:HookScript('OnLeave', function()
        GameTooltip:Hide();
    end);

	local dropDown = LibDD:Create_UIDropDownMenu(nil, TalentViewer_DF);

	dropDownButton = Mixin(dropDownButton, DropDownToggleButtonMixin);
	dropDownButton:OnLoad_Intrinsic();
	local function buildMenu()
	    self.menuListLevelingBuilds = {};
	    local menu = self.menuListLevelingBuilds;
	    table.insert(menu, {
	        text = L['Leveling builds can be saved and loaded with TalentLoadoutManager'],
	        notClickable = true,
            notCheckable = true,
	    });
	    table.insert(menu, {
	        text = L['You can also export/import leveling builds, or link them in chat'],
	        notClickable = true,
            notCheckable = true,
	    });
	    if (not C_AddOns.IsAddOnLoaded('TalentLoadoutManager')) then
            table.insert(menu, {
                text = L['Click to download TalentLoadoutManager'],
                notCheckable = true,
                func = function()
                    StaticPopup_Show('TalentViewerExportDialog', nil, nil, 'https://www.curseforge.com/wow/addons/talent-loadout-manager');
                end,
            });
        end
        for buildID, buildInfo in ipairs(self.levelingBuilds[self.selectedSpecId] or {}) do
            table.insert(menu, {
                text = string.format(
                    L['Leveling build %d (%d points spent)'],
                    buildID,
                    #buildInfo.entries[1] + #buildInfo.entries[2]
                ),
                func = function(_, buildID)
                    self:ApplyLevelingBuild(buildID, currentValue, true);
                    self:StopRecordingLevelingBuild();
                end,
                checked = self:GetCurrentLevelingBuildID() == buildID,
                arg1 = buildID,
            });
        end
	end
	dropDownButton:SetScript('OnMouseDown', function(self)
	    buildMenu();
		LibDD:ToggleDropDownMenu(1, nil, dropDown, self, 5, 0, TalentViewer.menuListLevelingBuilds or nil);
	end)

	dropDown:Hide();
	buildMenu();
	LibDD:EasyMenu(self.menuListLevelingBuilds, dropDown, dropDown, 0, 0);
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