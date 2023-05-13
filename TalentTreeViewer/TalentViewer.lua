--- @type TalentViewer_NS
local name, ns = ...

if LE_EXPANSION_LEVEL_CURRENT <= LE_EXPANSION_SHADOWLANDS then print(name, 'requires Dragonflight to work') return end

ns.starterBuildID = Constants.TraitConsts.STARTER_BUILD_TRAIT_CONFIG_ID
ns.MAX_LEVEL_CLASS_CURRENCY_CAP = 31
ns.MAX_LEVEL_SPEC_CURRENCY_CAP = 30
ns.TOTAL_CURRENCY_CAP = ns.MAX_LEVEL_CLASS_CURRENCY_CAP + ns.MAX_LEVEL_SPEC_CURRENCY_CAP
ns.MAX_LEVEL = 9 + ns.TOTAL_CURRENCY_CAP

--- @class TalentViewer
local TalentViewer = {
	purchasedRanks = {},
	selectedEntries = {},
	currencySpending = {},
}
_G.TalentViewer = TalentViewer

ns.ImportExport = {}
ns.TalentViewer = TalentViewer

--- @class TalentViewer_Cache
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
}
TalentViewer.cache = cache
---@type LibTalentTree
local LibTalentTree = LibStub('LibTalentTree-1.0')
--- @type LibUIDropDownMenu
local LibDD = LibStub:GetLibrary("LibUIDropDownMenu-4.0")

local L = LibStub('AceLocale-3.0'):GetLocale(name)

local function wipe(table)
	if table and type(table) == 'table' then
		_G['wipe'](table)
	end
end

----------------------
--- Build class / spec cache
----------------------
do
	for classID = 1, GetNumClasses() do
		local _
		cache.classNames[classID], cache.classFiles[classID], _ = GetClassInfo(classID)
		cache.specIndexToIdMap[classID] = {}
		cache.classSpecs[classID] = {}
		for specIndex = 1, GetNumSpecializationsForClassID(classID) do
			local specID = GetSpecializationInfoForClassID(classID, specIndex)
			local specName, _, specIcon = select(2, GetSpecializationInfoForSpecID(specID))
			if specName ~= '' then
				cache.specNames[specID] = specName
				cache.classSpecs[classID][specID] = specName
				cache.specIndexToIdMap[classID][specIndex] = specID
				cache.specIconId[specID] = specIcon
				cache.specIdToClassIdMap[specID] = classID
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
			if(IsAddOnLoaded('ElvUI')) then TalentViewer:ApplyElvUISkin() end
		end
	end
end
frame:HookScript('OnEvent', OnEvent)
frame:RegisterEvent('ADDON_LOADED')

-----------------------------
--- Talent Tree Utilities ---
-----------------------------

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
	local costInfo = self:GetTalentFrame():GetNodeCost(nodeID)
	if costInfo then
		for _, cost in ipairs(costInfo) do
			self.currencySpending[cost.ID] = (self.currencySpending[cost.ID] or 0) + cost.amount
		end
	end
end

function TalentViewer:RestoreCurrency(nodeID)
	local costInfo = self:GetTalentFrame():GetNodeCost(nodeID)
	if costInfo then
		for _, cost in ipairs(costInfo) do
			self.currencySpending[cost.ID] = (self.currencySpending[cost.ID] or 0) - cost.amount
		end
	end
end

----------------------
--- UI Interaction ---
----------------------

function TalentViewer:InitSpecSelection()
	local specId
	local _, _, classId = UnitClass('player')
	local currentSpec = GetSpecialization() or 1
	specId, _ = cache.specIndexToIdMap[classId][currentSpec]
	TalentViewer:SelectSpec(classId, specId)
end

function TalentViewer:OnInitialize()
	self.db = TalentTreeViewerDB

	if(self.ignoreRestrictionsCheckbox) then
		self.ignoreRestrictionsCheckbox:SetChecked(self.db.ignoreRestrictions)
	end
end

function TalentViewer:ImportLoadout(importString)
	--- @type TalentViewerImportExport
	local ImportExport = ns.ImportExport

	if TalentViewer_DF:IsShown() then
		TalentViewer_DF:Raise()
	else
		TalentViewer:ToggleTalentView()
	end
	ImportExport:ImportLoadout(importString)
end

function TalentViewer:ExportLoadout()
	--- @type TalentViewerImportExport
	local ImportExport = ns.ImportExport

	return ImportExport:GetLoadoutExportString()
end

function TalentViewer:LinkToChat()
	local exportString = self:ExportLoadout()
	if not exportString then return end

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
	UpdateScaleForFit(TalentViewer_DF, 200, 270)
	table.insert(UISpecialFrames, 'TalentViewer_DF')
	TalentViewer_DFInset:Hide()
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
	-- starter builds are not really correct yet :/
	--self:ApplyLevelingBuild(ns.starterBuildID);
	--self:SetStarterBuildActive(false);
	--local totalCurrencySpent = 0
	--for _, currencySpent in pairs(self.currencySpending) do
	--	totalCurrencySpent = totalCurrencySpent + currencySpent;
	--end
	--if totalCurrencySpent < ns.TOTAL_CURRENCY_CAP then
	--	self:ResetTree();
	--end
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
				'|Tinterface/icons/classicon_%s:16|t %s',
				cache.classFiles[classId],
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
	checkbox.Text:SetText(L['Ignore Restrictions'])
	if self.db then
		checkbox:SetChecked(self.db.ignoreRestrictions)
	end
	checkbox:SetScript('OnEnter', function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip_AddNormalLine(GameTooltip, L['Ignore restrictions when selecting talents']);
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

function TalentViewer:ApplyElvUISkin()
	if true then return end
	if self.skinned then return end
	self.skinned = true
	local S = unpack(ElvUI):GetModule('Skins')

	S:HandleDropDownBox(self.dropDown)
	S:HandleButton(self.dropDownButton)

	-- loosely based on ElvUI's talent skinning code

end

-----------------------
--- Leveling builds ---
-----------------------
function TalentViewer:GetLevelingBuild(buildID)
	return; -- TODO
end

function TalentViewer:SetStarterBuildActive(active)
	self:GetTalentFrame():SetLevelingBuildID(active and ns.starterBuildID or nil)
end

function TalentViewer:ApplyLevelingBuild(buildID, level)
	self:GetTalentFrame():SetLevelingBuildID(buildID)
	self:GetTalentFrame():ApplyLevelingBuild(level)
end

-------------------------
--- Button highlights ---
-------------------------
function TalentViewer:SetActionBarHighlights(talentButton, shown)
	local spellID = talentButton:GetSpellID();
	if (
		spellID
		and (
			talentButton.IsMissingFromActionBar and not talentButton:IsMissingFromActionBar()
			or talentButton.GetActionBarStatus and talentButton:GetActionBarStatus() == TalentButtonUtil.ActionBarStatus.NotMissing
		)
	) then
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