if LE_EXPANSION_LEVEL_CURRENT > LE_EXPANSION_SHADOWLANDS then print('this addon does not work beyond shadowlands') return end

local name, ns = ...

TalentViewer = {
	cache = {
		classNames = {},
		classFiles = {},
		classIconId = {},
		talents = {},
		classSpecs = {},
		sortedTalents = {},
		sharedTalents = {},
		nodes = {},
		tierLevel = {},
		specIndexToIdMap = {},
		specIconId = {},
		defaultSpecs = {},
	}
}
local cache = TalentViewer.cache
local LibDBIcon = LibStub('LibDBIcon-1.0')

----------------------
--- Reorganize data
----------------------
do
	cache.specs = ns.data.specs
	cache.talents = ns.data.talents
	cache.classes = ns.data.classes

	for tier = 1, MAX_TALENT_TIERS do
		_, _, cache.tierLevel[tier] = GetTalentTierInfo(tier, 1)
	end

	for _, classInfo in pairs(cache.classes) do
		cache.classNames[classInfo.classId], cache.classFiles[classInfo.classId], _ = GetClassInfo(classInfo.classId)
		cache.sharedTalents[classInfo.classId] = {}
		cache.specIndexToIdMap[classInfo.classId] = {}
		cache.classSpecs[classInfo.classId] = {}
		cache.defaultSpecs[classInfo.classId] = classInfo.defaultSpecId
		cache.classIconId[classInfo.classId] = classInfo.iconId
	end

	for _, specInfo in pairs(cache.specs) do
		if cache.classNames[specInfo.classId] and specInfo.index < 5 then
			_, cache.classSpecs[specInfo.classId][specInfo.specId], _ = GetSpecializationInfoForSpecID(specInfo.specId)
			cache.specIndexToIdMap[specInfo.classId][specInfo.index] = specInfo.specId
			cache.specIconId[specInfo.specId] = specInfo.specIconId
		end
	end

	for _, talentInfo in pairs(cache.talents) do
		if talentInfo.specId > 0 then
			cache.sortedTalents[talentInfo.specId] = cache.sortedTalents[talentInfo.specId] or {}
			cache.sortedTalents[talentInfo.specId][talentInfo.row .. '-' .. talentInfo.column] = talentInfo
		else
			cache.sharedTalents[talentInfo.classId][talentInfo.row .. '-' .. talentInfo.column] = talentInfo
		end
	end
end

----------------------
--- Script handles
----------------------
do
	function TalentViewer_PlayerTalentFrameTalents_OnLoad()
		table.insert(UISpecialFrames, 'TalentViewer_PlayerTalentFrame')
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
		self.icon:ClearAllPoints()
		self.name:ClearAllPoints()
		self.icon:SetPoint('LEFT', 35, 0)
		self.name:SetSize(90, 35)
		self.name:SetPoint('LEFT', self.icon, 'RIGHT', 10, 0)

		self:RegisterForClicks('LeftButtonUp')
	end

	function TalentViewer_PlayerTalentButton_OnClick(self)
		if (IsModifiedClick('CHATLINK')) then
			local spellName, _, _, _ = GetSpellInfo(self:GetID())
			local talentLink, _ = GetSpellLink(self:GetID())
			if ( MacroFrameText and MacroFrameText:HasFocus() ) then
				if ( spellName and not IsPassiveSpell(spellName) ) then
					local subSpellName = GetSpellSubtext(spellName)
					if ( subSpellName ) then
						if ( subSpellName ~= '' ) then
							ChatEdit_InsertLink(spellName..'('..subSpellName..')')
						else
							ChatEdit_InsertLink(spellName)
						end
					else
						ChatEdit_InsertLink(spellName)
					end
				end
			elseif ( talentLink ) then
				ChatEdit_InsertLink(talentLink)
			end
		end
	end

	function TalentViewer_PlayerTalentFrameTalent_OnEnter(self)
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:SetSpellByID(self:GetID())
	end

	function TalentViewer_PlayerTalentFrameTalent_OnLeave()
		GameTooltip_Hide()
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

		if addonName == 'BlizzMove' then TalentViewer:RegisterToBlizzMove() end
		if addonName == 'ElvUI' then TalentViewer:ApplyElvUISkin() end
	end
end
frame:HookScript('OnEvent', OnEvent)
frame:RegisterEvent('ADDON_LOADED')

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
	if TalentViewer_PlayerTalentFrame:IsShown() then
		TalentViewer_PlayerTalentFrame:Hide()

		return
	end
	TalentViewer_PlayerTalentFrame:Show()
end

function TalentViewer:SelectSpec(classId, specId)
	assert(type(classId) == 'number', 'classId must be a number')
	assert(type(specId) == 'number', 'specId must be a number')

	self.selectedClassId = classId
	self.selectedSpecId = specId
	self:SetClassIcon(classId)

	TalentViewer_PlayerTalentFrame:SetTitle(string.format(
		'%s %s - %s',
		cache.classNames[classId],
		TALENTS,
		cache.classSpecs[classId][specId]
	))

	for tier = 1, MAX_TALENT_TIERS do
		local talentRow = TalentViewer_PlayerTalentFrameTalents['tier'..tier]
		for column = 1, NUM_TALENT_COLUMNS do
			local node = tier .. '-' .. column
			local talentInfo = self:GetTalentInfoByNode(node)
			if talentInfo then
				local spellName, _, icon, _ = GetSpellInfo(talentInfo.spellId)

				local button = talentRow['talent'..column]
				button.tier = tier
				button.column = column

				button:SetID(talentInfo.spellId)

				SetItemButtonTexture(button, icon)
				if(button.name ~= nil) then
					button.name:SetText(spellName)
				end
			end
		end

		if(talentRow.level ~= nil) then
			talentRow.level:SetText(cache.tierLevel[tier])
		end
	end
end

function TalentViewer:GetTalentInfoByNode(node)
	local talentInfo = cache.sortedTalents[self.selectedSpecId][node] or cache.sharedTalents[self.selectedClassId][node] or nil
	if not talentInfo then
		print(string.format(
			'error: could not find a talent in row-col %s, for class [%s (%d)] spec [%s (%d)]',
			node,
			cache.classNames[self.selectedClassId],
			self.selectedClassId,
			cache.classSpecs[self.selectedClassId][self.selectedSpecId],
			self.selectedSpecId
		))

		return nil
	end

	return talentInfo
end

function TalentViewer:SetClassIcon(classId)
	local class = cache.classFiles[classId]
	TalentViewer_PlayerTalentFrame:SetPortraitTextureRaw('Interface\\TargetingFrame\\UI-Classes-Circles')
	TalentViewer_PlayerTalentFrame:SetPortraitTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
end

function TalentViewer:MakeDropDownButton()
	local mainButton = CreateFrame('BUTTON', nil, TalentViewer_PlayerTalentFrame, 'UIPanelButtonTemplate')
	local dropDown = CreateFrame('FRAME', nil, TalentViewer_PlayerTalentFrame, 'UIDropDownMenuTemplate')

	mainButton = Mixin(mainButton, DropDownToggleButtonMixin)
	mainButton:OnLoad_Intrinsic()
	mainButton:SetScript('OnMouseDown', function(self)
		ToggleDropDownMenu(1, nil, dropDown, self, 204, 15, TalentViewer.menuList or nil)
	end)

	mainButton.Icon = mainButton:CreateTexture(nil, 'ARTWORK')
	local icon = mainButton.Icon
	icon:SetSize(10, 12)
	icon:SetPoint('Right', -5, 0)
	icon:SetTexture('Interface\\ChatFrame\\ChatFrameExpandArrow')

	mainButton:SetText('Select another Specialization')
	mainButton:SetSize(200, 22)
	mainButton:SetPoint('TOPRIGHT', -10, -30)

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
		{ [name] = { ['TalentViewer_PlayerTalentFrame'] = { MinVersion = 90000 } } }
	)
end

function TalentViewer:ApplyElvUISkin()
	if self.skinned then return end
	self.skinned = true
	local S = unpack(ElvUI):GetModule('Skins')

	S:HandleDropDownBox(self.dropDown)
	S:HandleButton(self.dropDownButton)

	-- loosely based on ElvUI's talent skinning code

	S:HandlePortraitFrame(TalentViewer_PlayerTalentFrame)
	TalentViewer_PlayerTalentFrameTalents:StripTextures()

	do
		for i = 1, MAX_TALENT_TIERS do
			local row = TalentViewer_PlayerTalentFrameTalents['tier'..i]
			row:StripTextures()

			row.TopLine:Point('TOP', 0, 4)
			row.BottomLine:Point('BOTTOM', 0, -4)

			for j = 1, NUM_TALENT_COLUMNS do
				local bu = row['talent'..j]

				bu:StripTextures()
				bu:SetFrameLevel(bu:GetFrameLevel() + 5)
				bu.icon:SetDrawLayer('ARTWORK', 1)
				S:HandleIcon(bu.icon, true)

				bu.bg = CreateFrame('Frame', nil, bu)
				bu.bg:SetTemplate()
				bu.bg:SetFrameLevel(bu:GetFrameLevel() - 4)
				bu.bg:Point('TOPLEFT', 15, 2)
				bu.bg:Point('BOTTOMRIGHT', -10, -2)
			end
		end
	end
end
