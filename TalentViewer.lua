local name, ns = ...

if LE_EXPANSION_LEVEL_CURRENT <= LE_EXPANSION_SHADOWLANDS then print(name, 'requires Dragonflight to work') return end

--- @class TalentViewer
TalentViewer = {
	purchasedRanks = {},
	selectedEntries = {},
	currencySpending = {},
	cache = {
		classNames = {},
		classFiles = {},
		classIconId = {},
		classSpecs = {},
		nodes = {},
		tierLevel = {},
		specIndexToIdMap = {},
		specIdToClassIdMap = {},
		specIconId = {},
		defaultSpecs = {},
	}
}
--- @type TalentViewer
local TalentViewer = TalentViewer

ns.ImportExport = {}
ns.TalentViewer = TalentViewer

local cache = TalentViewer.cache
local LibDBIcon = LibStub('LibDBIcon-1.0')
---@type LibTalentTree
local LibTalentTree = LibStub('LibTalentTree-1.0')

----------------------
--- Reorganize data
----------------------
do
	cache.specs = ns.data.specs
	cache.classes = ns.data.classes

	for _, classInfo in pairs(cache.classes) do
		cache.classNames[classInfo.classId], cache.classFiles[classInfo.classId], _ = GetClassInfo(classInfo.classId)
		cache.specIndexToIdMap[classInfo.classId] = {}
		cache.classSpecs[classInfo.classId] = {}
		cache.defaultSpecs[classInfo.classId] = classInfo.defaultSpecId
		cache.classIconId[classInfo.classId] = classInfo.iconId
	end

	for _, specInfo in pairs(cache.specs) do
		if cache.classNames[specInfo.classId] then
			local specName = select(2, GetSpecializationInfoForSpecID(specInfo.specId))
			if specName ~= '' then
				cache.classSpecs[specInfo.classId][specInfo.specId] = specName
				cache.specIndexToIdMap[specInfo.classId][specInfo.index + 1] = specInfo.specId
				cache.specIconId[specInfo.specId] = specInfo.specIconId
				cache.specIdToClassIdMap[specInfo.specId] = specInfo.classId
			end
		end
	end
end

do
	local deepCopy;
	function deepCopy(original)
		local originalType = type(original);
		local copy;
		if (originalType == 'table') then
			copy = {};
			for key, value in next, original, nil do
				copy[deepCopy(key)] = deepCopy(value);
			end
			setmetatable(copy, deepCopy(getmetatable(original)));
		else
			copy = original;
		end

		return copy;
	end

	--- @class TalentViewerTalentFrame
	TalentViewer_ClassTalentTalentsTabMixin = deepCopy(ClassTalentTalentsTabMixin)

	local function removeFromMixing(method) TalentViewer_ClassTalentTalentsTabMixin[method] = function() end end
	removeFromMixing('UpdateConfigButtonsState')
	removeFromMixing('RefreshLoadoutOptions')
	removeFromMixing('InitializeLoadoutDropDown')
	removeFromMixing('GetInspectUnit')
	removeFromMixing('OnEvent')

	function TalentViewer_ClassTalentTalentsTabMixin:GetClassID()
		return TalentViewer.selectedClassId
	end
	function TalentViewer_ClassTalentTalentsTabMixin:GetSpecID()
		return TalentViewer.selectedSpecId
	end
	function TalentViewer_ClassTalentTalentsTabMixin:IsInspecting()
		return false
	end

	local emptyTable = {}

	function TalentViewer_ClassTalentTalentsTabMixin:GetAndCacheNodeInfo(nodeID)
		local nodeInfo = LibTalentTree:GetLibNodeInfo(TalentViewer.treeId, nodeID)
		if not nodeInfo then nodeInfo = LibTalentTree:GetNodeInfo(TalentViewer.treeId, nodeID) end
		if nodeInfo.ID ~= nodeID then return nil end
		local isGranted = LibTalentTree:IsNodeGrantedForSpec(TalentViewer.selectedSpecId, nodeID)
		local isChoiceNode = #nodeInfo.entryIDs > 1
		local selectedEntryId = isChoiceNode and TalentViewer:GetSelectedEntryId(nodeID) or nil

		local meetsEdgeRequirements = true
		local meetsGateRequirements = true
		if not TalentViewer.db.ignoreRestrictions then
			for _, conditionId in ipairs(nodeInfo.conditionIDs) do
				local condInfo = self:GetAndCacheCondInfo(conditionId)
				if condInfo.isGate and not condInfo.isMet then meetsGateRequirements = false end
			end
		end

		local isAvailable = meetsEdgeRequirements and meetsGateRequirements

		nodeInfo.activeRank = isGranted
				and nodeInfo.maxRanks
				or ((isChoiceNode and selectedEntryId and 1) or TalentViewer:GetActiveRank(nodeID))
		nodeInfo.currentRank = nodeInfo.activeRank
		nodeInfo.ranksPurchased = not isGranted and nodeInfo.currentRank or 0
		nodeInfo.isAvailable = isAvailable
		nodeInfo.canPurchaseRank = isAvailable and not isGranted and ((TalentViewer.purchasedRanks[nodeID] or 0) < nodeInfo.maxRanks)
		nodeInfo.canRefundRank = not isGranted and ((TalentViewer.purchasedRanks[nodeID] or 0) > 0)
		nodeInfo.meetsEdgeRequirements = meetsEdgeRequirements

		for _, edge in ipairs(nodeInfo.visibleEdges) do
			edge.isActive = nodeInfo.activeRank == nodeInfo.maxRanks
		end

		if #nodeInfo.entryIDs > 1 then
			local entryIndex
			for i, entryId in ipairs(nodeInfo.entryIDs) do
				if entryId == selectedEntryId then
					entryIndex = i
					break
				end
			end
			nodeInfo.activeEntry = entryIndex and { entryID = nodeInfo.entryIDs[entryIndex], rank = nodeInfo.activeRank } or emptyTable
		else
			nodeInfo.activeEntry = { entryID = nodeInfo.entryIDs[1], rank = nodeInfo.activeRank }
		end

		nodeInfo.isVisible = LibTalentTree:IsNodeVisibleForSpec(TalentViewer.selectedSpecId, nodeID)

		return nodeInfo
	end

	function TalentViewer_ClassTalentTalentsTabMixin:GetAndCacheCondInfo(condID)
		local function GetCondInfoCallback()
			local condInfo = C_Traits.GetConditionInfo(C_ClassTalents.GetActiveConfigID(), condID)
			if condInfo.isGate then
				local gates = LibTalentTree:GetGates(self:GetSpecID())
				for _, gateInfo in pairs(gates) do
					if gateInfo.conditionID == condID then
						condInfo.spentAmountRequired = gateInfo.spentAmountRequired
						break
					end
				end
				condInfo.spentAmountRequired = condInfo.spentAmountRequired - (TalentViewer.currencySpending[condInfo.traitCurrencyID] or 0)
				condInfo.isMet = condInfo.spentAmountRequired <= 0
			end
			return condInfo
		end
		return GetOrCreateTableEntryByCallback(self.condInfoCache, condID, GetCondInfoCallback);
	end

	function TalentViewer_ClassTalentTalentsTabMixin:ImportLoadout(loadoutEntryInfo)
		self:ResetTree()
		for _, entry in ipairs(loadoutEntryInfo) do
			if(entry.isChoiceNode) then
				self:SetSelection(entry.nodeID, entry.selectionEntryID)
			else
				self:SetRank(entry.nodeID, entry.ranksPurchased)
			end
		end

		return true;
	end

	function TalentViewer_ClassTalentTalentsTabMixin:AcquireTalentButton(nodeInfo, talentType, offsetX, offsetY, initFunction)
		local talentFrame = self
		local talentButton = ClassTalentTalentsTabMixin.AcquireTalentButton(self, nodeInfo, talentType, offsetX, offsetY, initFunction)
		function talentButton:OnClick(button)
			-- TODO should we trigger that event?
			EventRegistry:TriggerEvent("TalentButton.OnClick", self, button);

			if button == "LeftButton" then
				-- TODO: if IsShiftKeyDown then link spellId to chat
				if self:CanPurchaseRank() then
					self:PurchaseRank();
				end
			elseif button == "RightButton" then
				if self:CanRefundRank() then
					self:RefundRank();
				end
			end
		end

		function talentButton:PurchaseRank()
			self:PlaySelectSound();
			TalentViewer:PurchaseRank(self:GetNodeID());
			talentFrame:MarkNodeInfoCacheDirty(self:GetNodeID())
			talentFrame:UpdateTreeCurrencyInfo()
			--self:CheckTooltip();
		end

		function talentButton:RefundRank()
			self:PlayDeselectSound();
			TalentViewer:RefundRank(self:GetNodeID());
			talentFrame:MarkNodeInfoCacheDirty(self:GetNodeID())
			talentFrame:UpdateTreeCurrencyInfo()
			--self:CheckTooltip();
		end

		return talentButton
	end

	function TalentViewer_ClassTalentTalentsTabMixin:SetSelection(nodeID, entryID)
		TalentViewer:SetSelection(nodeID, entryID)
		self:MarkNodeInfoCacheDirty(nodeID)
		self:UpdateTreeCurrencyInfo()
	end

	function TalentViewer_ClassTalentTalentsTabMixin:SetRank(nodeID, rank)
		TalentViewer:SetRank(nodeID, rank)
		self:MarkNodeInfoCacheDirty(nodeID)
		self:UpdateTreeCurrencyInfo()
	end

	function TalentViewer_ClassTalentTalentsTabMixin:ResetTree()
		TalentViewer:ResetTree()
	end

	function TalentViewer_ClassTalentTalentsTabMixin:GetConfigID()
		return C_ClassTalents.GetActiveConfigID()
	end

	function TalentViewer_ClassTalentTalentsTabMixin:CanAfford(cost)
		return ClassTalentTalentsTabMixin.CanAfford(self, cost)
	end

	function TalentViewer_ClassTalentTalentsTabMixin:RefreshGates()
		self.traitCurrencyIDToGate = {};
		self.gatePool:ReleaseAll();

		local gates = LibTalentTree:GetGates(self:GetSpecID());

		for _, gateInfo in ipairs(gates) do
			local firstButton = self:GetTalentButtonByNodeID(gateInfo.topLeftNodeID);
			local condInfo = self:GetAndCacheCondInfo(gateInfo.conditionID);
			if firstButton and self:ShouldDisplayGate(firstButton, condInfo) then
				local gate = self.gatePool:Acquire();
				gate:Init(self, firstButton, condInfo);
				self:AnchorGate(gate, firstButton);
				gate:Show();

				self:OnGateDisplayed(gate, firstButton, condInfo);
			end
		end
	end

	function TalentViewer_ClassTalentTalentsTabMixin:UpdateTreeCurrencyInfo()
		self.treeCurrencyInfo = C_Traits.GetTreeCurrencyInfo(self:GetConfigID(), self:GetTalentTreeID(), self.excludeStagedChangesForCurrencies);

		self.treeCurrencyInfoMap = {};
		for i, treeCurrency in ipairs(self.treeCurrencyInfo) do
			treeCurrency.maxQuantity = i == 1 and 31 or 30;
			self.treeCurrencyInfoMap[treeCurrency.traitCurrencyID] = TalentViewer:ApplyCurrencySpending(treeCurrency);
		end

		self:RefreshCurrencyDisplay();

		-- TODO:: Replace this pattern of updating gates.
		for condID, condInfo in pairs(self.condInfoCache) do
			if condInfo.isGate then
				self:MarkCondInfoCacheDirty(condID);
				self:ForceCondInfoUpdate(condID);
			end
		end

		self:RefreshGates();
		for talentButton in self:EnumerateAllTalentButtons() do
			self:MarkNodeInfoCacheDirty(talentButton:GetNodeID());
		end
	end

end

----------------------
--- Script handles
----------------------
do
	--- @type TalentViewerImportExport
	local ImportExport = ns.ImportExport

	StaticPopupDialogs["TalentViewerExportDialog"] = {
		text = "CTRL-C to copy",
		button1 = CLOSE,
		OnShow = function(dialog, data)
			local function HidePopup()
				dialog:Hide();
			end
			dialog.editBox:SetScript("OnEscapePressed", HidePopup);
			dialog.editBox:SetScript("OnEnterPressed", HidePopup);
			dialog.editBox:SetScript("OnKeyUp", function(_, key)
				if IsControlKeyDown() and key == "C" then
					HidePopup();
				end
			end);
			dialog.editBox:SetMaxLetters(0);
			dialog.editBox:SetText(data);
			dialog.editBox:HighlightText();
		end,
		hasEditBox = true,
		editBoxWidth = 240,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	};
	StaticPopupDialogs["TalentViewerImportDialog"] = {
		text = "Import loadout",
		button1 = OKAY,
		button2 = CLOSE,
		OnAccept = function(dialog)
			ImportExport:ImportLoadout(dialog.editBox:GetText());
			dialog:Hide();
		end,
		OnShow = function(dialog)
			local function HidePopup()
				dialog:Hide();
			end
			local function OnEnter()
				dialog.button1:Click();
			end
			dialog.editBox:SetScript("OnEscapePressed", HidePopup);
			dialog.editBox:SetScript("OnEnterPressed", OnEnter);
		end,
		hasEditBox = true,
		editBoxWidth = 240,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	};

	function TalentViewer_ImportButton_OnClick()
		StaticPopup_Show("TalentViewerImportDialog");
	end
	function TalentViewer_ExportButton_OnClick()
		local exportString = ImportExport:GetLoadoutExportString();
		StaticPopup_Show("TalentViewerExportDialog", _, _, exportString);
	end

	function TalentViewer_DFMain_OnLoad()
		table.insert(UISpecialFrames, 'TalentViewer_DF')
		TalentViewer:InitDropDown()
		local specId
		local _, _, classId = UnitClass('player')
		local currentSpec = GetSpecialization()
		if currentSpec then
			specId, _ = cache.specIndexToIdMap[classId][currentSpec]
		end
		specId, _ = specId or cache.defaultSpecs[classId]
		TalentViewer:SelectSpec(classId, specId)
	end
end

local frame = CreateFrame('FRAME')
local function OnEvent(_, event, ...)
	if event == 'ADDON_LOADED' then
		local addonName = ...
		if addonName == name then
			TalentViewer:OnInitialize()
			if(IsAddOnLoaded('BlizzMove')) then TalentViewer:RegisterToBlizzMove() end
			if(IsAddOnLoaded('ElvUI')) then TalentViewer:ApplyElvUISkin() end
		end
	end
	if event == 'PLAYER_ENTERING_WORLD' then
		TalentViewer:OnPlayerEnteringWorld()
		frame:UnregisterEvent('PLAYER_ENTERING_WORLD')
	end
end
frame:HookScript('OnEvent', OnEvent)
frame:RegisterEvent('ADDON_LOADED')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')

---@return TalentViewerTalentFrame
function TalentViewer:GetTalentFrame()
	return TalentViewer_DF.Talents
end

function TalentViewer:ApplyCurrencySpending(treeCurrency)
	local spending = self.currencySpending[treeCurrency.traitCurrencyID] or 0;
	treeCurrency.spent = spending
	treeCurrency.quantity = treeCurrency.maxQuantity - spending

	return treeCurrency
end

function TalentViewer:ResetTree()
	wipe(self.purchasedRanks)
	wipe(self.selectedEntries)
	wipe(self.currencySpending)
	TalentViewer_DF.Talents:SetTalentTreeID(self.treeId, true);
	TalentViewer_DF.Talents:UpdateClassVisuals()
	TalentViewer_DF.Talents:UpdateSpecBackground();
end

function TalentViewer:GetActiveRank(nodeID)
	return self.purchasedRanks[nodeID] or 0;
end

function TalentViewer:GetSelectedEntryId(nodeID)
	return self.selectedEntries[nodeID];
end

function TalentViewer:SetRank(nodeID, rank)
	local currentRank
	repeat
		currentRank = self.purchasedRanks[nodeID] or 0;
		if currentRank == rank then return end
		if rank > currentRank then
			TalentViewer:PurchaseRank(nodeID)
		else
			TalentViewer:RefundRank(nodeID)
		end
	until currentRank == rank
end

function TalentViewer:PurchaseRank(nodeID)
	self:ReduceCurrency(nodeID)
	self.purchasedRanks[nodeID] = (self.purchasedRanks[nodeID] or 0) + 1
end

function TalentViewer:RefundRank(nodeID)
	self:RestoreCurrency(nodeID)
	self.purchasedRanks[nodeID] = (self.purchasedRanks[nodeID] or 0) - 1
end

function TalentViewer:SetSelection(nodeID, entryID)
	if (entryID and not self.selectedEntries[nodeID]) then
		self:ReduceCurrency(nodeID)
	elseif (not entryID and self.selectedEntries[nodeID]) then
		self:RestoreCurrency(nodeID)
	end

	self.selectedEntries[nodeID] = entryID
end

function TalentViewer:ReduceCurrency(nodeID)
	local costInfo = C_Traits.GetNodeCost(C_ClassTalents.GetActiveConfigID(), nodeID)
	if costInfo then
		for _, cost in ipairs(costInfo) do
			self.currencySpending[cost.ID] = (self.currencySpending[cost.ID] or 0) + cost.amount
		end
	end
end

function TalentViewer:RestoreCurrency(nodeID)
	local costInfo = C_Traits.GetNodeCost(C_ClassTalents.GetActiveConfigID(), nodeID)
	if costInfo then
		for _, cost in ipairs(costInfo) do
			self.currencySpending[cost.ID] = (self.currencySpending[cost.ID] or 0) - cost.amount
		end
	end
end

function TalentViewer:OnPlayerEnteringWorld()
	if TalentViewer_DF:IsShown() then return end
	local specId
	local _, _, classId = UnitClass('player')
	local currentSpec = GetSpecialization()
	if currentSpec then
		specId, _ = cache.specIndexToIdMap[classId][currentSpec]
	end
	specId, _ = specId or cache.defaultSpecs[classId]
	TalentViewer:SelectSpec(classId, specId)
end

function TalentViewer:OnInitialize()
	TalentTreeViewerDB = TalentTreeViewerDB or {}
	self.db = TalentTreeViewerDB

	if not self.db.ldbOptions then
		self.db.ldbOptions = {
			hide = false,
		}
	end
	if self.db.ignoreRestrictions == nil then
		self.db.ignoreRestrictions = true
	end
	local dataObject = LibStub('LibDataBroker-1.1'):NewDataObject(
		name,
		{
			type = 'data source',
			text = 'Talent Tree Viewer',
			icon = 'interface/icons/inv_inscription_talenttome01.blp',
			OnClick = function()
				if IsShiftKeyDown() then
					TalentViewer.db.ldbOptions.hide = true
					LibDBIcon:Hide(name)
					return
				end
				TalentViewer:ToggleTalentView()
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
		TalentViewer:ToggleTalentView()
	end

	self:AddButtonToBlizzardTalentFrame()
	self:HookIntoBlizzardImport()
end

function TalentViewer:AddButtonToBlizzardTalentFrame()
	local button = CreateFrame('Button', nil, ClassTalentFrame, 'UIPanelButtonTemplate')
	button:SetText('Talent Viewer')
	button:SetSize(100, 22)
	button:SetPoint('TOPRIGHT', ClassTalentFrame, 'TOPRIGHT', -22, 0)
	button:SetScript('OnClick', function()
		TalentViewer:ToggleTalentView()
	end)
	button:SetFrameStrata('HIGH')
end

function TalentViewer:HookIntoBlizzardImport()
	--- @type TalentViewerImportExport
	local ImportExport = ns.ImportExport
	local lastError
	local importString

	StaticPopupDialogs["TalentViewerDefaultImportFailedDialog"] = {
		text = LOADOUT_ERROR_WRONG_SPEC .. "\n\n" .. "Would you like to open the build in Talent Viewer instead?",
		button1 = OKAY,
		button2 = CLOSE,
		OnAccept = function(dialog)
			ClassTalentLoadoutImportDialog:OnCancel()
			ImportExport:ImportLoadout(importString)
			if TalentViewer_DF:IsShown() then
				TalentViewer_DF:Raise()
			else
				TalentViewer:ToggleTalentView()
			end
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

function TalentViewer:ToggleTalentView()
	if TalentViewer_DF:IsShown() then
		TalentViewer_DF:Hide()

		return
	end
	TalentViewer_DF:Show()
end

function TalentViewer:SelectSpec(classId, specId)
	assert(type(classId) == 'number', 'classId must be a number')
	assert(type(specId) == 'number', 'specId must be a number')

	self.selectedClassId = classId
	self.selectedSpecId = specId
	self.treeId = LibTalentTree:GetClassTreeId(classId)
	self:SetPortraitIcon(specId)

	TalentViewer_DF:SetTitle(string.format(
		'%s %s - %s',
		cache.classNames[classId],
		TALENTS,
		cache.classSpecs[classId][specId] or ''
	))

	self:ResetTree();
end

function TalentViewer:SetPortraitIcon(specId)
	local icon = cache.specIconId[specId]
	TalentViewer_DF:SetPortraitTexCoord(0, 1, 0, 1);
	TalentViewer_DF:SetPortraitToAsset(icon);
end

function TalentViewer:MakeDropDownButton()
	local mainButton = TalentViewer_DF.Talents.TV_DropDownButton
	local dropDown = CreateFrame('FRAME', nil, TalentViewer_DF, 'UIDropDownMenuTemplate')

	mainButton = Mixin(mainButton, DropDownToggleButtonMixin)
	mainButton:OnLoad_Intrinsic()
	mainButton:SetScript('OnMouseDown', function(self)
		ToggleDropDownMenu(1, nil, dropDown, self, 204, 15, TalentViewer.menuList or nil)
	end)

	dropDown:Hide()

	return mainButton, dropDown
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
			})
		end

		table.insert(menu, {
			text = string.format(
				'|T%d:16|t %s',
				cache.classIconId[classId],
				cache.classNames[classId]
			),
			hasArrow = true,
			menuList = specMenuList,
			checked = isCheckedFunc,
			arg2 = classId,
		})
	end

	return menu
end

function TalentViewer:InitDropDown()
	if self.dropDownButton then return end
	self.dropDownButton, self.dropDown = self:MakeDropDownButton()

	if IsAddOnLoaded('ElvUI') then
		self:ApplyElvUISkin()
	end

	local function setValue(_, specId, classId)
		CloseDropDownMenus()

		TalentViewer:SelectSpec(classId, specId)
	end

	local isChecked = function(button)
		return button.arg2 == TalentViewer.selectedClassId and (not button.arg1 or button.arg1 == TalentViewer.selectedSpecId)
	end

	self.menuList = self:BuildMenu(setValue, isChecked)
	EasyMenu(self.menuList, self.dropDown, self.dropDown, 0, 0)
end

function TalentViewer:RegisterToBlizzMove()
	if not BlizzMoveAPI then return end
	BlizzMoveAPI:RegisterAddOnFrames(
		{
			[name] = {
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

function TalentViewer:ApplyElvUISkin()
	if true then return end
	if self.skinned then return end
	self.skinned = true
	local S = unpack(ElvUI):GetModule('Skins')

	S:HandleDropDownBox(self.dropDown)
	S:HandleButton(self.dropDownButton)

	-- loosely based on ElvUI's talent skinning code

end
