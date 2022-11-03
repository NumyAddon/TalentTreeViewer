local name, ns = ...

if LE_EXPANSION_LEVEL_CURRENT <= LE_EXPANSION_SHADOWLANDS then print(name, 'requires Dragonflight to work') return end

--- @class TalentViewer
local TalentViewer = {
	purchasedRanks = {},
	selectedEntries = {},
	currencySpending = {},
	customConfigID = -6869888, -- arbitrary configID which hopefully nobody else will use
}
_G.TalentViewer = TalentViewer

ns.ImportExport = {}
ns.TalentViewer = TalentViewer

--- @class TalentViewer_Cache
local cache = {
	classNames = {},
	classFiles = {},
	classIconId = {},
	classSpecs = {},
	nodes = {},
	tierLevel = {},
	specNames = {},
	specIndexToIdMap = {},
	specIdToClassIdMap = {},
	specIconId = {},
	defaultSpecs = {},
}
TalentViewer.cache = cache
local LibDBIcon = LibStub('LibDBIcon-1.0')
---@type LibTalentTree
local LibTalentTree = LibStub('LibTalentTree-1.0')
--- @type LibUIDropDownMenu
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0")

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
				cache.specNames[specInfo.specId] = specName
				cache.classSpecs[specInfo.classId][specInfo.specId] = specName
				cache.specIndexToIdMap[specInfo.classId][specInfo.index + 1] = specInfo.specId
				cache.specIconId[specInfo.specId] = specInfo.specIconId
				cache.specIdToClassIdMap[specInfo.specId] = specInfo.classId
			end
		end
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
end
frame:HookScript('OnEvent', OnEvent)
frame:RegisterEvent('ADDON_LOADED')

---@return TalentViewerUIMixin
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
	local talentFrame = self:GetTalentFrame()
	talentFrame.OutdatedWarning:Hide();
	wipe(self.purchasedRanks);
	wipe(self.selectedEntries);
	wipe(self.currencySpending);
	wipe(talentFrame.edgeRequirementsCache);
	talentFrame.nodesPerGate = nil;
	talentFrame.eligibleNodesPerGate = nil;
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
	local costInfo = C_Traits.GetNodeCost(self:GetTalentFrame():GetConfigID(), nodeID)
	if costInfo then
		for _, cost in ipairs(costInfo) do
			self.currencySpending[cost.ID] = (self.currencySpending[cost.ID] or 0) + cost.amount
		end
	end
end

function TalentViewer:RestoreCurrency(nodeID)
	local costInfo = C_Traits.GetNodeCost(self:GetTalentFrame():GetConfigID(), nodeID)
	if costInfo then
		for _, cost in ipairs(costInfo) do
			self.currencySpending[cost.ID] = (self.currencySpending[cost.ID] or 0) - cost.amount
		end
	end
end

function TalentViewer:InitSpecSelection()
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

	if(self.ignoreRestrictionsCheckbox) then
		self.ignoreRestrictionsCheckbox:SetChecked(self.db.ignoreRestrictions)
	end

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
	self:InitFrame()
	if TalentViewer_DF:IsShown() then
		TalentViewer_DF:Hide()

		return
	end
	TalentViewer_DF:Show()
end

function TalentViewer:InitFrame()
	if self.frameInitialized then return end
	self.frameInitialized = true
	table.insert(UISpecialFrames, 'TalentViewer_DF')
	self:InitDropDown()
	self:InitCheckbox()
	self:InitSpecSelection()
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
	local dropDown = LibDD:Create_UIDropDownMenu(nil, TalentViewer_DF)

	mainButton = Mixin(mainButton, DropDownToggleButtonMixin)
	mainButton:OnLoad_Intrinsic()
	mainButton:SetScript('OnMouseDown', function(self)
		LibDD:ToggleDropDownMenu(1, nil, dropDown, self, 204, 15, TalentViewer.menuList or nil)
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

function TalentViewer:InitCheckbox()
	if self.ignoreRestrictionsCheckbox then return end
	self.ignoreRestrictionsCheckbox = TalentViewer_DF.Talents.IgnoreRestrictions
	local checkbox = self.ignoreRestrictionsCheckbox
	checkbox.Text:SetText('Ignore Restrictions')
	if self.db then
		checkbox:SetChecked(self.db.ignoreRestrictions)
	end
	checkbox:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip_AddNormalLine(GameTooltip, 'Ignore restrictions when selecting talents');
		GameTooltip:Show();
	end)
	checkbox:SetScript('OnLeave', function(self)
		GameTooltip:Hide();
	end)
	checkbox:SetScript('OnClick', function(button)
		self.db.ignoreRestrictions = button:GetChecked()
		self:GetTalentFrame():UpdateTreeCurrencyInfo()
	end)
end

function TalentViewer:InitDropDown()
	if self.dropDownButton then return end
	self.dropDownButton, self.dropDown = self:MakeDropDownButton()

	if IsAddOnLoaded('ElvUI') then
		self:ApplyElvUISkin()
	end

	local function setValue(_, specId, classId)
		LibDD:CloseDropDownMenus()

		TalentViewer:SelectSpec(classId, specId)
	end

	local isChecked = function(button)
		return button.arg2 == TalentViewer.selectedClassId and (not button.arg1 or button.arg1 == TalentViewer.selectedSpecId)
	end

	self.menuList = self:BuildMenu(setValue, isChecked)
	LibDD:EasyMenu(self.menuList, self.dropDown, self.dropDown, 0, 0)
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
