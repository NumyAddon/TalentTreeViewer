if LE_EXPANSION_LEVEL_CURRENT <= LE_EXPANSION_SHADOWLANDS then print('this addon requires Dragonflight to work') return end

local name, ns = ...

TalentViewer = {
	cache = {
		classNames = {},
		classFiles = {},
		classIconId = {},
		classSpecs = {},
		nodes = {},
		tierLevel = {},
		specIndexToIdMap = {},
		specIconId = {},
		defaultSpecs = {},
	}
}
local cache = TalentViewer.cache
local LibDBIcon = LibStub('LibDBIcon-1.0')
---@type LibTalentTree
local libTalentTree = LibStub('LibTalentTree-0.1') -- should be updated to 1.0 once the library is finalized

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
				cache.specIndexToIdMap[specInfo.classId][specInfo.index] = specInfo.specId
				cache.specIconId[specInfo.specId] = specInfo.specIconId
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

	TalentViewer_ClassTalentTalentsTabMixin = deepCopy(ClassTalentTalentsTabMixin)
	TalentViewer_TalentFrameBaseMixin = deepCopy(TalentFrameBaseMixin)

	local function removeFromMixing(method) TalentViewer_ClassTalentTalentsTabMixin[method] = function() end end
	function TalentViewer_ClassTalentTalentsTabMixin:GetClassID()
		return TalentViewer.selectedClassId
	end
	function TalentViewer_ClassTalentTalentsTabMixin:GetSpecID()
		return TalentViewer.selectedSpecId
	end
	function TalentViewer_ClassTalentTalentsTabMixin:IsInspecting()
		return false
	end
	removeFromMixing('UpdateConfigButtonsState')
	removeFromMixing('RefreshLoadoutOptions')
	removeFromMixing('InitializeLoadoutDropDown')
	removeFromMixing('GetInspectUnit')

	local emptyTable = {}

	function TalentViewer_ClassTalentTalentsTabMixin:GetAndCacheNodeInfo(nodeID)
		local nodeInfo = libTalentTree:GetLibNodeInfo(TalentViewer.treeId, nodeID)

		nodeInfo.activeRank = libTalentTree:IsNodeGrantedForSpec(TalentViewer.selectedSpecId, nodeID) and nodeInfo.maxRanks or TalentViewer:GetActiveRank(nodeID)
		nodeInfo.currentRank = nodeInfo.activeRank
		nodeInfo.ranksPurchased = nodeInfo.currentRank
		nodeInfo.isAvailable = true
		nodeInfo.canPurchaseRank = true
		nodeInfo.CanRefundRank = true
		nodeInfo.meetsEdgeRequirements = true

		if #nodeInfo.entryIDs>1 then
			local entryIndex = TalentViewer:GetSelectedEntryIndex(nodeID)
			nodeInfo.activeEntry = entryIndex and { entryID = nodeInfo.entryIDs[entryIndex], rank = nodeInfo.activeRank } or emptyTable
		else
			nodeInfo.activeEntry = { entryID = nodeInfo.entryIDs[1], rank = nodeInfo.activeRank }
		end

		nodeInfo.isVisible = libTalentTree:IsNodeVisibleForSpec(TalentViewer.selectedSpecId, nodeID)

		return nodeInfo
	end

	function TalentViewer_ClassTalentTalentsTabMixin:AcquireTalentButton(nodeInfo, talentType, offsetX, offsetY, initFunction)
		local talentButton = ClassTalentTalentsTabMixin.AcquireTalentButton(self, nodeInfo, talentType, offsetX, offsetY, initFunction)
		function talentButton:OnClick(button)
			EventRegistry:TriggerEvent("TalentButton.OnClick", self, button);

			if button == "LeftButton" then
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
			self:CheckTooltip();
		end

		function talentButton:RefundRank()
			self:PlayDeselectSound();
			TalentViewer:RefundRank(self:GetNodeID());
			self:CheckTooltip();
		end

		return talentButton
	end

	function TalentViewer_ClassTalentTalentsTabMixin:SetSelection(nodeID, entryID)
		print(entryID);
		-- TalentViewer:SetSelection(nodeID, entryID)
	end
end

----------------------
--- Script handles
----------------------
do
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

	function TalentViewer_PlayerTalentButton_OnLoad(self)
		--self.icon:ClearAllPoints()
		--self.name:ClearAllPoints()
		--self.icon:SetPoint('LEFT', 35, 0)
		--self.name:SetSize(90, 35)
		--self.name:SetPoint('LEFT', self.icon, 'RIGHT', 10, 0)
		--
		--self:RegisterForClicks('LeftButtonUp')
	end

	function TalentViewer_PlayerTalentButton_OnClick(self)
		--if (IsModifiedClick('CHATLINK')) then
		--	local spellName, _, _, _ = GetSpellInfo(self:GetID())
		--	local talentLink, _ = GetSpellLink(self:GetID())
		--	if ( MacroFrameText and MacroFrameText:HasFocus() ) then
		--		if ( spellName and not IsPassiveSpell(spellName) ) then
		--			local subSpellName = GetSpellSubtext(spellName)
		--			if ( subSpellName ) then
		--				if ( subSpellName ~= '' ) then
		--					ChatEdit_InsertLink(spellName..'('..subSpellName..')')
		--				else
		--					ChatEdit_InsertLink(spellName)
		--				end
		--			else
		--				ChatEdit_InsertLink(spellName)
		--			end
		--		end
		--	elseif ( talentLink ) then
		--		ChatEdit_InsertLink(talentLink)
		--	end
		--end
	end

	function TalentViewer_PlayerTalentFrameTalent_OnEnter(self)
		--GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		--GameTooltip:SetSpellByID(self:GetID())
	end

	function TalentViewer_PlayerTalentFrameTalent_OnLeave()
		--GameTooltip_Hide()
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

		----if addonName == 'BlizzMove' then TalentViewer:RegisterToBlizzMove() end
		----if addonName == 'ElvUI' then TalentViewer:ApplyElvUISkin() end
	end
	if event == 'PLAYER_ENTERING_WORLD' then
		TalentViewer:OnPlayerEnteringWorld()
		frame:UnregisterEvent('PLAYER_ENTERING_WORLD')
	end
end
frame:HookScript('OnEvent', OnEvent)
frame:RegisterEvent('ADDON_LOADED')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')

function TalentViewer:GetActiveRank(nodeID)
	return 0;
end

function TalentViewer:GetSelectedEntryIndex(nodeID)
	return 1;
end

function TalentViewer:PurchaseRank(nodeID)
end

function TalentViewer:RefundRank(nodeID)
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
	TalentViewerDB = TalentViewerDB or {}
	self.db = TalentViewerDB

	if not self.db.ldbOptions then
		self.db.ldbOptions = {
			hide = false,
		}
	end
	local dataObject = LibStub('LibDataBroker-1.1'):NewDataObject(
		name,
		{
			type = 'data source',
			text = 'Talent Viewer',
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
				tooltip:AddLine('Talent Viewer')
				tooltip:AddLine('|cffeda55fClick|r to view the talents for any spec.')
				tooltip:AddLine('|cffeda55fShift-Click|r to hide this button. (|cffeda55f/tv reset|r to restore)')
			end,
		}
	)
	LibDBIcon:Register(name, dataObject, self.db.ldbOptions)

	SLASH_TALENT_VIEWER1 = '/tv'
	SLASH_TALENT_VIEWER2 = '/talentviewer'
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
	self.treeId = libTalentTree:GetClassTreeId(classId)
	self:SetClassIcon(classId)

	TalentViewer_DF:SetTitle(string.format(
		'%s %s - %s',
		cache.classNames[classId],
		TALENTS,
		cache.classSpecs[classId][specId]
	))


	TalentViewer_DF.Talents.talentTreeID = self.treeId;
	TalentViewer_DF.Talents:LoadTalentTree();
end

function TalentViewer:SetClassIcon(classId)
	local class = cache.classFiles[classId]

	local left, right, bottom, top = unpack(CLASS_ICON_TCOORDS[string.upper(class)]);
	TalentViewer_DF.PortraitOverlay.Portrait:SetTexCoord(left, right, bottom, top);
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
		{ [name] = {
			['TalentViewer_DF'] = { MinVersion = 100000 },
		} }
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
