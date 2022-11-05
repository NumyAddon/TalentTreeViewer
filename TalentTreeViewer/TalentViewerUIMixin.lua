local _, ns = ...

--- @type TalentViewer
local TalentViewer = ns.TalentViewer
if not TalentViewer then return end

--- @type TalentViewer_Cache
local tvCache = TalentViewer.cache

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

local parentMixin = ClassTalentTalentsTabMixin
--- @class TalentViewerUIMixin
TalentViewer_ClassTalentTalentsTabMixin = deepCopy(parentMixin)

local TalentViewerUIMixin = TalentViewer_ClassTalentTalentsTabMixin
local function removeFromMixin(method) TalentViewerUIMixin[method] = function() end end
removeFromMixin('UpdateConfigButtonsState')
removeFromMixin('RefreshLoadoutOptions')
removeFromMixin('InitializeLoadoutDropDown')
removeFromMixin('GetInspectUnit')
removeFromMixin('OnEvent')
removeFromMixin('RefreshConfigID')

function TalentViewerUIMixin:GetConfigID()
	-- if nil, then we fully depend on LibTalentTree to provide all required data
	-- it will be nil if the player hasn't selected a spec yet (e.g. isn't level 10 yet)
	return C_ClassTalents.GetActiveConfigID() or nil
end
function TalentViewerUIMixin:GetClassID()
	return TalentViewer.selectedClassId
end
function TalentViewerUIMixin:GetSpecID()
	return TalentViewer.selectedSpecId
end
function TalentViewerUIMixin:GetTalentTreeID()
	return TalentViewer.treeId
end
function TalentViewerUIMixin:IsInspecting()
	return false
end

function TalentViewerUIMixin:UpdateTreeInfo(skipButtonUpdates)
	self.talentTreeInfo = {}; --self:GetConfigID() and C_Traits.GetTreeInfo(self:GetConfigID(), self:GetTalentTreeID()) or {};
	self:UpdateTreeCurrencyInfo(skipButtonUpdates);

	if not skipButtonUpdates then
		self:RefreshGates();
	end
end

function TalentViewerUIMixin:MarkNodeInfoCacheDirty(nodeID)
	self.nodeInfoCache[nodeID] = nil
	parentMixin.MarkNodeInfoCacheDirty(self, nodeID)
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
		if not nodeInfo then
			self:ShowOutdatedDataWarning()
			return LibTalentTree:GetNodeInfo(TalentViewer.treeId, nodeID)
		end

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
		local condInfo = {
			condID = condID,
			isAlwaysMet = false,
			isMet = false,
			isGate = false,
		}

		local gates = LibTalentTree:GetGates(TalentViewer.selectedSpecId);
		for _, gateInfo in pairs(gates) do
			if gateInfo.conditionID == condID then
				condInfo.isGate = true;
				condInfo.traitCurrencyID = gateInfo.traitCurrencyID;
				condInfo.spentAmountRequired = gateInfo.spentAmountRequired - (TalentViewer.currencySpending[gateInfo.traitCurrencyID] or 0);
				condInfo.isMet = condInfo.spentAmountRequired <= 0
				break;
			end
		end
		return condInfo
	end
	return GetOrCreateTableEntryByCallback(self.condInfoCache, condID, GetCondInfoCallback);
end

function TalentViewerUIMixin:GetAndCacheEntryInfo(entryID)
	local function GetEntryInfoCallback(entryID)
		local entryInfo = LibTalentTree:GetEntryInfo(self:GetTalentTreeID(), entryID);
		entryInfo.entryCost = {};

		return entryInfo;
	end
	return GetOrCreateTableEntryByCallback(self.entryInfoCache, entryID, GetEntryInfoCallback);
end

function TalentViewerUIMixin:GetNodeCost(nodeID)
	local function GetNodeCostCallback(nodeID)
		local treeID = self:GetTalentTreeID();
		local currencyInfo = self:GetAndCacheTreeCurrencyInfo(self:GetSpecID());
		local nodeInfo = LibTalentTree:GetLibNodeInfo(treeID, nodeID);
		local currencyID;
		if nodeInfo and nodeInfo.isClassNode then
			currencyID = currencyInfo[1].traitCurrencyID;
		else
			currencyID = currencyInfo[2].traitCurrencyID;
		end

		return {
			{
				ID = currencyID,
				amount = 1,
			},
		};
	end
	return GetOrCreateTableEntryByCallback(self.nodeCostCache, nodeID, GetNodeCostCallback);
end

function TalentViewerUIMixin:ShowOutdatedDataWarning()
	if not self.OutdatedWarning:IsShown() then
		self.OutdatedWarning:Show()
	end
end

function TalentViewerUIMixin:ImportLoadout(loadoutEntryInfo)
	local backup = TalentViewer.db.ignoreRestrictions
	TalentViewer.db.ignoreRestrictions = true
	self:ResetTree()
	for _, entry in ipairs(loadoutEntryInfo) do
		if(entry.isChoiceNode) then
			self:SetSelection(entry.nodeID, entry.selectionEntryID)
		else
			self:SetRank(entry.nodeID, entry.ranksPurchased)
		end
	end
	TalentViewer.db.ignoreRestrictions = backup

	return true;
end

function TalentViewerUIMixin:AcquireTalentButton(nodeInfo, talentType, offsetX, offsetY, initFunction)
	local talentFrame = self
	local talentButton = parentMixin.AcquireTalentButton(self, nodeInfo, talentType, offsetX, offsetY, initFunction)
	function talentButton:OnClick(button)
		EventRegistry:TriggerEvent("TalentButton.OnClick", self, button);

		if button == "LeftButton" and self:CanPurchaseRank() then
			self:PurchaseRank();
		elseif button == "RightButton" and self:CanRefundRank() then
			self:RefundRank();
		end
	end

	function talentButton:PurchaseRank()
		self:PlaySelectSound();
		TalentViewer:PurchaseRank(self:GetNodeID());
		talentFrame:MarkEdgeRequirementCacheDirty(self:GetNodeID());
		talentFrame:MarkNodeInfoCacheDirty(self:GetNodeID());
		talentFrame:UpdateTreeCurrencyInfo();
		talentFrame:UpdateEdgeSiblings(self:GetNodeID());
	end

	function talentButton:RefundRank()
		self:PlayDeselectSound();
		TalentViewer:RefundRank(self:GetNodeID());
		talentFrame:MarkEdgeRequirementCacheDirty(self:GetNodeID());
		talentFrame:MarkNodeInfoCacheDirty(self:GetNodeID());
		talentFrame:UpdateTreeCurrencyInfo();
		talentFrame:UpdateEdgeSiblings(self:GetNodeID());
	end

	return talentButton
end

function TalentViewerUIMixin:SetSelection(nodeID, entryID)
	TalentViewer:SetSelection(nodeID, entryID);
	self:MarkEdgeRequirementCacheDirty(nodeID);
	self:MarkNodeInfoCacheDirty(nodeID);
	self:UpdateTreeCurrencyInfo();
	self:UpdateEdgeSiblings(nodeID);
end

function TalentViewerUIMixin:SetRank(nodeID, rank)
	TalentViewer:SetRank(nodeID, rank);
	self:MarkEdgeRequirementCacheDirty(nodeID);
	self:MarkNodeInfoCacheDirty(nodeID);
	self:UpdateTreeCurrencyInfo();
	self:UpdateEdgeSiblings(nodeID);
end

function TalentViewerUIMixin:UpdateEdgeSiblings(nodeID)
	if TalentViewer.db.ignoreRestrictions then return end
	local nodeInfo = self:GetAndCacheNodeInfo(nodeID)
	local edges = nodeInfo.visibleEdges

	if not edges or not edges[1] or edges[1].isActive then return end
	for _, edge in ipairs(edges) do
		local siblingNodeID = edge.targetNode
		local siblingNodeInfo = self:GetAndCacheNodeInfo(siblingNodeID)
		if not siblingNodeInfo.meetsEdgeRequirements and siblingNodeInfo.ranksPurchased > 0 then
			if #siblingNodeInfo.entryIDs > 1 then
				self:SetSelection(siblingNodeID, nil)
			else
				self:SetRank(siblingNodeID, 0)
			end
		end
	end
end

function TalentViewerUIMixin:ResetTree()
	TalentViewer:ResetTree()
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

function TalentViewerUIMixin:GetAndCacheTreeCurrencyInfo(specID)
	local function GetTreeCurrencyInfoCallback(specID)
		local treeCurrencyInfo = {};
		local gates = LibTalentTree:GetGates(specID);
		local treeID = LibTalentTree:GetClassTreeId(tvCache.specIdToClassIdMap[specID]);
		for _, gate in ipairs(gates) do
			local nodeInfo = LibTalentTree:GetLibNodeInfo(treeID, gate.topLeftNodeID);
			if nodeInfo.isClassNode then
				treeCurrencyInfo[1] = {
					maxQuantity = MAX_LEVEL_CLASS_CURRENCY_CAP,
					quantity = MAX_LEVEL_CLASS_CURRENCY_CAP,
					spent = 0,
					traitCurrencyID = gate.traitCurrencyID,
				};
			else
				treeCurrencyInfo[2] = {
					maxQuantity = MAX_LEVEL_SPEC_CURRENCY_CAP,
					quantity = MAX_LEVEL_SPEC_CURRENCY_CAP,
					spent = 0,
					traitCurrencyID = gate.traitCurrencyID
				};
			end
		end

		return treeCurrencyInfo;
	end
	return GetOrCreateTableEntryByCallback(self.treeCurrencyInfoCache, specID, GetTreeCurrencyInfoCallback);
end

function TalentViewerUIMixin:UpdateTreeCurrencyInfo()
	self:ProcessGateMandatedRefunds();

	self.treeCurrencyInfo = self:GetAndCacheTreeCurrencyInfo(self:GetSpecID());

	self.treeCurrencyInfoMap = {};
	for i, treeCurrency in ipairs(self.treeCurrencyInfo) do
		-- hardcode currency cap to lvl 70 values
		treeCurrency.maxQuantity = i == 1 and MAX_LEVEL_CLASS_CURRENCY_CAP or MAX_LEVEL_SPEC_CURRENCY_CAP;
		self.treeCurrencyInfoMap[treeCurrency.traitCurrencyID] = TalentViewer:ApplyCurrencySpending(treeCurrency);
	end

	self:RefreshCurrencyDisplay();

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

function TalentViewerUIMixin:ProcessGateMandatedRefunds()
	if TalentViewer.db.ignoreRestrictions then return end

	self:UpdateNodeGateMapping()
	local eligibleSpendingPerGate = self:GetEligibleSpendingPerGate()
	local gates = LibTalentTree:GetGates(self:GetSpecID());

	for _, gateInfo in ipairs(gates) do
		local eligibleSpending = eligibleSpendingPerGate[gateInfo.conditionID] or 0
		if eligibleSpending < gateInfo.spentAmountRequired then
			for _, nodeID in ipairs(self.nodesPerGate[gateInfo.conditionID]) do
				local nodeInfo = self:GetAndCacheNodeInfo(nodeID)
				if nodeInfo.ranksPurchased > 0 then
					if #nodeInfo.entryIDs > 1 then
						self:SetSelection(nodeID, nil)
					else
						self:SetRank(nodeID, 0)
					end
				end
			end
		end
	end
end

function TalentViewerUIMixin:UpdateNodeGateMapping()
	if self.eligibleNodesPerGate and self.nodesPerGate then return end
	self.eligibleNodesPerGate = {}
	self.nodesPerGate = {}
	local gates = LibTalentTree:GetGates(self:GetSpecID());

	for _, gateInfo in ipairs(gates) do
		self.eligibleNodesPerGate[gateInfo.conditionID] = self.eligibleNodesPerGate[gateInfo.conditionID] or {}
		self.nodesPerGate[gateInfo.conditionID] = self.nodesPerGate[gateInfo.conditionID] or {}

		for _, nodeID in ipairs(C_Traits.GetTreeNodes(TalentViewer.treeId)) do
			local nodeInfo = self:GetAndCacheNodeInfo(nodeID);
			local conditionIDs = nodeInfo.conditionIDs;
			local costInfo = self:GetNodeCost(nodeID);

			if costInfo and costInfo[1] and costInfo[1].ID and costInfo[1].ID == gateInfo.traitCurrencyID then
				local conditionMatches = false;
				for _, conditionID in ipairs(conditionIDs) do
					if conditionID == gateInfo.conditionID then
						conditionMatches = true;
						break;
					end
				end
				if conditionMatches then
					table.insert(self.nodesPerGate[gateInfo.conditionID], nodeID)
				else
					table.insert(self.eligibleNodesPerGate[gateInfo.conditionID], nodeID)
				end
			end
		end
	end
end

function TalentViewerUIMixin:GetEligibleSpendingPerGate()
	local spendingPerGate = {}
	for condID, nodeIDs in pairs(self.eligibleNodesPerGate) do
		spendingPerGate[condID] = 0
		for _, nodeID in ipairs(nodeIDs) do
			local nodeInfo = self:GetAndCacheNodeInfo(nodeID);
			local costInfo = self:GetNodeCost(nodeID);
			local amount = costInfo[1].amount;
			if nodeInfo.ranksPurchased > 0 then
				spendingPerGate[condID] = spendingPerGate[condID] + (amount * nodeInfo.ranksPurchased)
			end
		end
	end

	return spendingPerGate
end

function TalentViewerUIMixin:RefreshCurrencyDisplay()
	local classCurrencyInfo = self.treeCurrencyInfo and self.treeCurrencyInfo[1] or nil;
	self.ClassCurrencyDisplay:SetPointTypeText(string.upper(tvCache.classNames[self:GetClassID()]));
	self.ClassCurrencyDisplay:SetAmount(classCurrencyInfo and classCurrencyInfo.quantity or 0);

	local specCurrencyInfo = self.treeCurrencyInfo and self.treeCurrencyInfo[2] or nil;
	self.SpecCurrencyDisplay:SetPointTypeText(string.upper(tvCache.specNames[self:GetSpecID()]));
	self.SpecCurrencyDisplay:SetAmount((specCurrencyInfo and specCurrencyInfo.quantity or 0));
end

function TalentViewerUIMixin:OnLoad()
	parentMixin.OnLoad(self);

	self.edgeRequirementsCache = {};
	self.nodeCostCache = {};
	self.treeCurrencyInfoCache = {};

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
end
