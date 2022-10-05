local _, ns = ...

--- @type TalentViewer
local TalentViewer = ns.TalentViewer
if not TalentViewer then return end

---@type LibTalentTree
local LibTalentTree = LibStub('LibTalentTree-1.0')

local MAX_LEVEL_CLASS_CURRENCY_CAP = 31
local MAX_LEVEL_SPEC_CURRENCY_CAP = 30

local deepCopy, getIncomingNodeEdges, getNodeEdges;
do
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

	local emptyTable = {}
	local nodeEdgesCache = {}
	function getNodeEdges(nodeID)
		if not nodeEdgesCache[nodeID] then
			nodeEdgesCache[nodeID] = LibTalentTree:GetNodeEdges(TalentViewer.treeId, nodeID) or emptyTable
		end
		return nodeEdgesCache[nodeID]
	end

	local incomingNodeEdgesCache = {}
	function getIncomingNodeEdges(nodeID)
		local function getIncomingNodeEdgesCallback(nodeID)
			local incomingEdges = {}
			for _, treeNodeId in ipairs(C_Traits.GetTreeNodes(TalentViewer.treeId)) do
				local edges = getNodeEdges(treeNodeId)
				for _, edge in ipairs(edges) do
					if edge.targetNode == nodeID then
						table.insert(incomingEdges, treeNodeId)
					end
				end
			end
			return incomingEdges
		end

		return GetOrCreateTableEntryByCallback(incomingNodeEdgesCache, nodeID, getIncomingNodeEdgesCallback)
	end
end


do
	local parentMixin = ClassTalentTalentsTabMixin
	--- @class TalentViewerUIMixin
	TalentViewer_ClassTalentTalentsTabMixin = deepCopy(parentMixin)

	local TalentViewerUIMixin = TalentViewer_ClassTalentTalentsTabMixin
	local function removeFromMixing(method) TalentViewerUIMixin[method] = function() end end
	removeFromMixing('UpdateConfigButtonsState')
	removeFromMixing('RefreshLoadoutOptions')
	removeFromMixing('InitializeLoadoutDropDown')
	removeFromMixing('GetInspectUnit')
	removeFromMixing('OnEvent')

	function TalentViewerUIMixin:GetClassID()
		return TalentViewer.selectedClassId
	end
	function TalentViewerUIMixin:GetSpecID()
		return TalentViewer.selectedSpecId
	end
	function TalentViewerUIMixin:IsInspecting()
		return false
	end

	function TalentViewerUIMixin:MarkEdgeRequirementCacheDirty(nodeID)
		local edges = getNodeEdges(nodeID)
		for _, edge in ipairs(edges) do
			self.edgeRequirementsCache[edge.targetNode] = nil
		end
	end

	function TalentViewerUIMixin:MeetsEdgeRequirements(nodeID)
		local function EdgeRequirementCallback(nodeID)
			local incomingEdges = getIncomingNodeEdges(nodeID)
			local hasActiveIncomingEdge = false
			local hasInactiveIncomingEdge = false
			for _, incomingNodeId in ipairs(incomingEdges) do
				local nodeInfo = LibTalentTree:GetLibNodeInfo(TalentViewer.treeId, incomingNodeId)
				if not nodeInfo then nodeInfo = LibTalentTree:GetNodeInfo(TalentViewer.treeId, incomingNodeId) end
				if nodeInfo and LibTalentTree:IsNodeVisibleForSpec(TalentViewer.selectedSpecId, incomingNodeId) then
					local isGranted = LibTalentTree:IsNodeGrantedForSpec(TalentViewer.selectedSpecId, incomingNodeId)
					local isChoiceNode = #nodeInfo.entryIDs > 1
					local selectedEntryId = isChoiceNode and TalentViewer:GetSelectedEntryId(incomingNodeId) or nil
					local activeRank = isGranted
							and nodeInfo.maxRanks
							or ((isChoiceNode and selectedEntryId and 1) or TalentViewer:GetActiveRank(incomingNodeId))
					local isEdgeActive = activeRank == nodeInfo.maxRanks

					if not isEdgeActive then
						hasInactiveIncomingEdge = true
					else
						hasActiveIncomingEdge = true
					end
				end
			end

			return not hasInactiveIncomingEdge or hasActiveIncomingEdge
		end

		return GetOrCreateTableEntryByCallback(self.edgeRequirementsCache, nodeID, EdgeRequirementCallback)
	end

	function TalentViewerUIMixin:GetAndCacheNodeInfo(nodeID)
		local function GetNodeInfoCallback(nodeID)
			local nodeInfo = LibTalentTree:GetLibNodeInfo(TalentViewer.treeId, nodeID)
			if not nodeInfo then nodeInfo = LibTalentTree:GetNodeInfo(TalentViewer.treeId, nodeID) end
			if nodeInfo.ID ~= nodeID then return nil end
			local isGranted = LibTalentTree:IsNodeGrantedForSpec(TalentViewer.selectedSpecId, nodeID)
			local isChoiceNode = #nodeInfo.entryIDs > 1
			local selectedEntryId = isChoiceNode and TalentViewer:GetSelectedEntryId(nodeID) or nil

			local meetsEdgeRequirements = TalentViewer.db.ignoreRestrictions or self:MeetsEdgeRequirements(nodeID)
			local meetsGateRequirements = true
			if not TalentViewer.db.ignoreRestrictions then
				for _, conditionId in ipairs(nodeInfo.conditionIDs) do
					local condInfo = self:GetAndCacheCondInfo(conditionId)
					if condInfo.isGate and not condInfo.isMet then meetsGateRequirements = false end
				end
			end

			local isAvailable = meetsGateRequirements

			nodeInfo.activeRank = isGranted
				and nodeInfo.maxRanks
				or ((isChoiceNode and selectedEntryId and 1) or TalentViewer:GetActiveRank(nodeID))
			nodeInfo.currentRank = nodeInfo.activeRank
			nodeInfo.ranksPurchased = not isGranted and nodeInfo.currentRank or 0
			nodeInfo.isAvailable = isAvailable
			nodeInfo.canPurchaseRank = isAvailable and meetsEdgeRequirements and not isGranted and ((TalentViewer.purchasedRanks[nodeID] or 0) < nodeInfo.maxRanks)
			nodeInfo.canRefundRank = not isGranted
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
				nodeInfo.activeEntry = entryIndex and { entryID = nodeInfo.entryIDs[entryIndex], rank = nodeInfo.activeRank } or nil
			else
				nodeInfo.activeEntry = { entryID = nodeInfo.entryIDs[1], rank = nodeInfo.activeRank }
			end
			if not isChoiceNode and nodeInfo.activeRank ~= nodeInfo.maxRanks then
				nodeInfo.nextEntry = { entryID = nodeInfo.entryIDs[1], rank = nodeInfo.activeRank + 1 }
			end

			nodeInfo.isVisible = LibTalentTree:IsNodeVisibleForSpec(TalentViewer.selectedSpecId, nodeID)

			return nodeInfo
		end
		return GetOrCreateTableEntryByCallback(self.nodeInfoCache, nodeID, GetNodeInfoCallback);
	end

	function TalentViewerUIMixin:GetAndCacheCondInfo(condID)
		local function GetCondInfoCallback(condID)
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

	function TalentViewerUIMixin:ImportLoadout(loadoutEntryInfo)
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

	function TalentViewerUIMixin:AcquireTalentButton(nodeInfo, talentType, offsetX, offsetY, initFunction)
		local talentFrame = self
		local talentButton = parentMixin.AcquireTalentButton(self, nodeInfo, talentType, offsetX, offsetY, initFunction)
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
		function talentButton:CanRefundRank()
			-- remove this method override if/when "cascaded refunds" are implemented
			return self.nodeInfo.canRefundRank and self.nodeInfo.ranksPurchased and (self.nodeInfo.ranksPurchased > 0);
		end

		function talentButton:PurchaseRank()
			self:PlaySelectSound();
			TalentViewer:PurchaseRank(self:GetNodeID());
			talentFrame:MarkEdgeRequirementCacheDirty(self:GetNodeID());
			talentFrame:MarkNodeInfoCacheDirty(self:GetNodeID())
			talentFrame:UpdateTreeCurrencyInfo()
			--self:CheckTooltip();
		end

		function talentButton:RefundRank()
			self:PlayDeselectSound();
			TalentViewer:RefundRank(self:GetNodeID());
			talentFrame:MarkEdgeRequirementCacheDirty(self:GetNodeID());
			talentFrame:MarkNodeInfoCacheDirty(self:GetNodeID())
			talentFrame:UpdateTreeCurrencyInfo()
			--self:CheckTooltip();
		end

		return talentButton
	end

	function TalentViewerUIMixin:SetSelection(nodeID, entryID)
		TalentViewer:SetSelection(nodeID, entryID)
		self:MarkEdgeRequirementCacheDirty(nodeID);
		self:MarkNodeInfoCacheDirty(nodeID)
		self:UpdateTreeCurrencyInfo()
	end

	function TalentViewerUIMixin:SetRank(nodeID, rank)
		TalentViewer:SetRank(nodeID, rank)
		self:MarkNodeInfoCacheDirty(nodeID)
		self:UpdateTreeCurrencyInfo()
	end

	function TalentViewerUIMixin:ResetTree()
		TalentViewer:ResetTree()
	end

	function TalentViewerUIMixin:GetConfigID()
		return C_ClassTalents.GetActiveConfigID()
	end

	function TalentViewerUIMixin:CanAfford(cost)
		return parentMixin.CanAfford(self, cost)
	end

	function TalentViewerUIMixin:RefreshGates()
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

	function TalentViewerUIMixin:UpdateTreeCurrencyInfo()
		self.treeCurrencyInfo = C_Traits.GetTreeCurrencyInfo(self:GetConfigID(), self:GetTalentTreeID(), self.excludeStagedChangesForCurrencies);

		self.treeCurrencyInfoMap = {};
		for i, treeCurrency in ipairs(self.treeCurrencyInfo) do
			-- hardcode currency cap to lvl 70 values
			treeCurrency.maxQuantity = i == 1 and MAX_LEVEL_CLASS_CURRENCY_CAP or MAX_LEVEL_SPEC_CURRENCY_CAP;
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

	function TalentViewerUIMixin:RefreshCurrencyDisplay()
		local classCurrencyInfo = self.treeCurrencyInfo and self.treeCurrencyInfo[1] or nil;
		local classInfo = self:GetClassInfo();
		self.ClassCurrencyDisplay:SetPointTypeText(string.upper(classInfo.className));
		self.ClassCurrencyDisplay:SetAmount(classCurrencyInfo and classCurrencyInfo.quantity or 0);

		local specCurrencyInfo = self.treeCurrencyInfo and self.treeCurrencyInfo[2] or nil;
		self.SpecCurrencyDisplay:SetPointTypeText(string.upper(self:GetSpecName()));
		self.SpecCurrencyDisplay:SetAmount((specCurrencyInfo and specCurrencyInfo.quantity or 0));
	end

	function TalentViewerUIMixin:OnLoad()
		parentMixin.OnLoad(self)

		self.edgeRequirementsCache = {}

		local setAmountOverride = function(self, amount)
			local requiredLevel = self.isClassCurrency and 8 or 9;
			local spent = (self.isClassCurrency and MAX_LEVEL_CLASS_CURRENCY_CAP or MAX_LEVEL_SPEC_CURRENCY_CAP) - amount;
			requiredLevel = math.max(10, requiredLevel + (spent * 2));

			local text = string.format('%d (level %d)', amount, requiredLevel);

			self.CurrencyAmount:SetText(text);

			local enabled = not self:IsInspecting() and (amount > 0);
			local textColor = enabled and GREEN_FONT_COLOR or GRAY_FONT_COLOR;
			self.CurrencyAmount:SetTextColor(textColor:GetRGBA());

			self:MarkDirty();
		end

		self.ClassCurrencyDisplay.SetAmount = setAmountOverride
		self.ClassCurrencyDisplay.isClassCurrency = true
		self.SpecCurrencyDisplay.SetAmount = setAmountOverride
		self.SpecCurrencyDisplay.isClassCurrency = false
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
		StaticPopup_Show("TalentViewerExportDialog", nil, nil, exportString);
	end

	function TalentViewer_DFMain_OnLoad()
		table.insert(UISpecialFrames, 'TalentViewer_DF')
		TalentViewer:InitDropDown()
		TalentViewer:InitCheckbox()
		local specId
		local _, _, classId = UnitClass('player')
		local currentSpec = GetSpecialization()
		if currentSpec then
			specId, _ = TalentViewer.cache.specIndexToIdMap[classId][currentSpec]
		end
		specId, _ = specId or TalentViewer.cache.defaultSpecs[classId]
		TalentViewer:SelectSpec(classId, specId)
	end
end
