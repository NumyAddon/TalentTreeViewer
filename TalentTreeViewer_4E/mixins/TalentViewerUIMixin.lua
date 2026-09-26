local name = ...;
--- @class TTV_4E_NS
local ns = select(2, ...);

ns.mixins = ns.mixins or {};

--- @type TalentViewer4E
local TalentViewer = ns.TalentViewer;
if not TalentViewer then return; end

--- @type TalentViewer_Cache4E
local tvCache = TalentViewer.cache;

---@type LibTalentTree-1.0
local LibTalentTree = LibStub('LibTalentTree-1.0');

local L = ns.L;

local SELECTION_NODE_POS_X = 6700;
local SELECTION_NODE_POS_Y = 4200;
local SUB_TREE_OFFSET_X = 7600;
local SUB_TREE_OFFSET_Y_TOP_TREE = 1500;
local SUB_TREE_OFFSET_Y_BOTTOM_TREE = 4500;
do
    TALENT_TREE_VIEWER_LOCALE_EXPORT = L['Export'];
    TALENT_TREE_VIEWER_LOCALE_SELECT_SPECIALIZATION = L['Select another Specialization'];
end

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

    local emptyTable = {};
    local nodeEdgesCache = {};
    function getNodeEdges(nodeID)
        if not nodeEdgesCache[nodeID] then
            nodeEdgesCache[nodeID] = LibTalentTree:GetNodeEdges(nodeID) or emptyTable;
        end
        return nodeEdgesCache[nodeID];
    end

    local incomingNodeEdgesCache = {};
    function getIncomingNodeEdges(nodeID)
        local function getIncomingNodeEdgesCallback(nodeID)
            local incomingEdges = {};
            for _, treeNodeId in ipairs(C_Traits.GetTreeNodes(TalentViewer.treeId)) do
                local edges = getNodeEdges(treeNodeId);
                for _, edge in ipairs(edges) do
                    if edge.targetNode == nodeID then
                        table.insert(incomingEdges, treeNodeId);
                    end
                end
            end
            return incomingEdges;
        end

        return GetOrCreateTableEntryByCallback(incomingNodeEdgesCache, nodeID, getIncomingNodeEdgesCallback);
    end
end


--- @type ClassTalentsFrameMixin
local parentMixin = ClassTalentsFrameMixin;
--- @class TalentViewer_ClassTalentsFrameTemplate4E: ClassTalentsFrameMixin, Frame
TalentViewer_ClassTalentsFrameMixin4E = deepCopy(parentMixin);

--- @class TalentViewer_ClassTalentsFrameTemplate4E
local TalentViewerUIMixin = TalentViewer_ClassTalentsFrameMixin4E;
--- @type table<number, TVNodeInfo> # [nodeID] = nodeInfo
TalentViewerUIMixin.purchasesWithRequiredLevel = {};

local function removeFromMixin(method) TalentViewerUIMixin[method] = function() end; end
removeFromMixin('UpdateConfigButtonsState');
removeFromMixin('RefreshLoadoutOptions');
removeFromMixin('InitializeLoadSystem');
removeFromMixin('GetInspectUnit');
removeFromMixin('OnEvent');
removeFromMixin('RefreshConfigID');
removeFromMixin('UpdateInspecting');
removeFromMixin('InitializeTabSystem');
removeFromMixin('InitializeActiveSpec');

function TalentViewerUIMixin:IsChoiceNode(nodeInfo)
    return nodeInfo.type == Enum.TraitNodeType.Selection or nodeInfo.type == Enum.TraitNodeType.SubTreeSelection;
end

--- @return TalentViewer4E
function TalentViewerUIMixin:GetTalentViewer()
    return TalentViewer;
end

function TalentViewerUIMixin:IsLocked()
    return false, '';
end

function TalentViewerUIMixin:GetConfigID()
    -- if nil, then we fully depend on LibTalentTree to provide all required data
    -- it will be nil if the player hasn't selected a spec yet (e.g. isn't level 10 yet)
    return C_ClassTalents.GetActiveConfigID() or nil;
end
function TalentViewerUIMixin:GetClassID()
    return self:GetTalentViewer().selectedClassId;
end
function TalentViewerUIMixin:GetClassName()
    local classID = self:GetClassID();
    local classInfo = C_CreatureInfo.GetClassInfo(classID);

    return classInfo.className;
end
function TalentViewerUIMixin:GetSpecID()
    return TalentViewer.selectedSpecId;
end
function TalentViewerUIMixin:GetSpecName()
    local specID = self:GetSpecID();

    return select(2, GetSpecializationInfoByID(specID));
end
function TalentViewerUIMixin:GetTalentTreeID()
    return TalentViewer.treeId;
end
function TalentViewerUIMixin:IsInspecting()
    return false;
end
function TalentViewerUIMixin:IsPreviewingSubTree()
    return false;
end

--- Various checks are disabled when the restrictions are disabled, improving performance of bulk actions substantially
function TalentViewerUIMixin:RunWithRestrictionsDisabled(func)
    local backup = TalentViewer.db.ignoreRestrictions;
    RunNextFrame(function() TalentViewer.db.ignoreRestrictions = backup end);
    TalentViewer.db.ignoreRestrictions = true;
    securecallfunction(func);
    TalentViewer.db.ignoreRestrictions = backup;
end

function TalentViewerUIMixin:ShowSelections(...)
    parentMixin.ShowSelections(self, ...);
    for _, button in ipairs(self.SelectionChoiceFrame.selectionFrameArray) do
        button.ShowActionBarHighlights = ns.mixins.TalentButtonMixin.ShowActionBarHighlights;
        button.HideActionBarHighlights = ns.mixins.TalentButtonMixin.HideActionBarHighlights;
    end
end

function TalentViewerUIMixin:UpdateTreeInfo(skipButtonUpdates)
    self.talentTreeInfo = {};
    self:RefreshTreeHeaders();
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
            local nodeInfo = LibTalentTree:GetLibNodeInfo(incomingNodeId)
            if not nodeInfo then nodeInfo = LibTalentTree:GetNodeInfo(incomingNodeId) end
            if nodeInfo and LibTalentTree:IsNodeVisibleForSpec(TalentViewer.selectedSpecId, incomingNodeId) then
                local isGranted = LibTalentTree:IsNodeGrantedForSpec(TalentViewer.selectedSpecId, incomingNodeId)
                local isChoiceNode = self:IsChoiceNode(nodeInfo)
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

--- @return TVNodeInfo nodeInfo
--- @return boolean isNewValue
function TalentViewerUIMixin:GetAndCacheNodeInfo(nodeID)
    local function GetNodeInfoCallback(nodeID)
        --- @class TVNodeInfo: libNodeInfo
        local nodeInfo = LibTalentTree:GetLibNodeInfo(nodeID)
        if not nodeInfo then
            --- @class TVNodeInfo: libNodeInfo
            nodeInfo = LibTalentTree:GetNodeInfo(nodeID)
            if DevTool and DevTool.AddData then
                DevTool:AddData(
                    {
                        nodeID = nodeID,
                        treeID = TalentViewer.treeId,
                        specID = self:GetSpecID(),
                        nodeInfo = nodeInfo,
                    },
                    'outdated warning trigger, nodeID ' .. nodeID
                );
            end
            if not nodeInfo then
                error('no nodeinfo for nodeID ' .. nodeID .. ' treeID ' .. TalentViewer.treeId .. ' specID ' .. self:GetSpecID());
            end
            return nodeInfo;
        end

        local isGranted = LibTalentTree:IsNodeGrantedForSpec(TalentViewer.selectedSpecId, nodeID);
        local isChoiceNode = self:IsChoiceNode(nodeInfo);
        local selectedEntryId = isChoiceNode and TalentViewer:GetSelectedEntryId(nodeID) or nil;

        local meetsEdgeRequirements = TalentViewer.db.ignoreRestrictions or self:MeetsEdgeRequirements(nodeID);
        local meetsGateRequirements = true;
        if meetsGateRequirements and not TalentViewer.db.ignoreRestrictions and nodeInfo.spentAmountRequired then
            -- check spending amount
            local requiredAmount = nodeInfo.spentAmountRequired.amount;
            local specGroupID;
            for _, groupID in pairs(nodeInfo.groupIDs) do
                if tvCache.groupDisplayInfoByClass[self:GetClassID()][groupID] then
                    specGroupID = groupID;
                    break;
                end
            end
            local spent = self:GetTalentViewer().currencyGroupSpending[specGroupID or 0] or 0;
            if spent < requiredAmount then
                meetsGateRequirements = false;
            end
        end

        local isAvailable = meetsGateRequirements;

        nodeInfo.activeRank = isGranted
            and nodeInfo.maxRanks
            or ((isChoiceNode and selectedEntryId and 1) or TalentViewer:GetActiveRank(nodeID));
        nodeInfo.currentRank = nodeInfo.activeRank;
        nodeInfo.ranksPurchased = not isGranted and nodeInfo.currentRank or 0;
        nodeInfo.ranksIncreased = 0; -- only applicable to legion remix artifacts currently
        nodeInfo.isAvailable = isAvailable;
        nodeInfo.canPurchaseRank = isAvailable and meetsEdgeRequirements and not isGranted and ((TalentViewer.purchasedRanks[nodeID] or 0) < nodeInfo.maxRanks)
        nodeInfo.canRefundRank = not isGranted;
        nodeInfo.meetsEdgeRequirements = meetsEdgeRequirements;

        for _, edge in ipairs(nodeInfo.visibleEdges) do
            edge.isActive = nodeInfo.activeRank == nodeInfo.maxRanks;
        end

        if isChoiceNode then
            if nodeInfo.type == Enum.TraitNodeType.SubTreeSelection then
                nodeInfo.type = Enum.TraitNodeType.Selection;
                nodeInfo.isSubTreeSelection = true;
            end
            local entryIndex
            for i, entryId in ipairs(nodeInfo.entryIDs) do
                if entryId == selectedEntryId then
                    entryIndex = i
                    break
                end
            end
            nodeInfo.activeEntry = entryIndex and { entryID = nodeInfo.entryIDs[entryIndex], rank = nodeInfo.activeRank, } or nil
        else
            nodeInfo.activeEntry = { entryID = nodeInfo.entryIDs[1], rank = nodeInfo.activeRank, }
        end
        if not isChoiceNode and nodeInfo.activeRank ~= nodeInfo.maxRanks then
            nodeInfo.nextEntry = { entryID = nodeInfo.entryIDs[1], rank = nodeInfo.activeRank + 1, }
        end
        nodeInfo.tvSubTreeID = nodeInfo.subTreeID;
        nodeInfo.subTreeID = nil;

        nodeInfo.isVisible = LibTalentTree:IsNodeVisibleForSpec(TalentViewer.selectedSpecId, nodeID)

        if nodeInfo.requiredPlayerLevel and nodeInfo.ranksPurchased > 0 then
            self.purchasesWithRequiredLevel[nodeID] = nodeInfo;
        else
            self.purchasesWithRequiredLevel[nodeID] = nil;
        end

        return nodeInfo
    end

    return GetOrCreateTableEntryByCallback(self.nodeInfoCache, nodeID, GetNodeInfoCallback);
end

--- @return subTreeInfo subTreeInfo
--- @return boolean isNewValue
function TalentViewerUIMixin:GetAndCacheSubTreeInfo(subTreeID)
    local function GetSubTreeInfoCallback()
        self.dirtySubTreeIDSet[subTreeID] = nil;
        return LibTalentTree:GetSubTreeInfo(subTreeID)
    end

    return GetOrCreateTableEntryByCallback(self.subTreeInfoCache, subTreeID, GetSubTreeInfoCallback);
end

--- @return TraitCondInfo conditionInfo
--- @return boolean isNewValue
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

--- @return entryInfo entryInfo
--- @return boolean isNewValue
function TalentViewerUIMixin:GetAndCacheEntryInfo(entryID)
    local function GetEntryInfoCallback(entryID)
        local entryInfo = LibTalentTree:GetEntryInfo(entryID);
        if entryInfo then
            entryInfo.entryCost = {};
        else
            entryInfo = parentMixin.GetAndCacheEntryInfo(self, entryID);
        end

        return entryInfo;
    end

    return GetOrCreateTableEntryByCallback(self.entryInfoCache, entryID, GetEntryInfoCallback);
end

--- @return { [1]: { ID: number, amount: number } } costInfo
--- @return boolean isNewValue
function TalentViewerUIMixin:GetNodeCost(nodeID)
    local function GetNodeCostCallback(nodeID)
        local currencyInfo = self:GetAndCacheTreeCurrencyInfo(self:GetSpecID());
        local nodeInfo = LibTalentTree:GetLibNodeInfo(nodeID);
        local currencyID = currencyInfo[1].traitCurrencyID;
        local specGroupID;
        local groupDisplayInfo = tvCache.groupDisplayInfoByClass[self:GetClassID()];
        for _, groupID in pairs(nodeInfo.groupIDs) do
            if groupDisplayInfo[groupID]then
                specGroupID = groupID;
                break;
            end
        end

        return {
            {
                ID = currencyID,
                amount = 1,
                groupID = specGroupID,
            },
        };
    end
    return GetOrCreateTableEntryByCallback(self.nodeCostCache, nodeID, GetNodeCostCallback);
end

function TalentViewerUIMixin:ImportLoadout(loadoutEntryInfo)
    self:RunWithRestrictionsDisabled(function()
        self:ResetTree();
        for _, entry in ipairs(loadoutEntryInfo) do
            if entry.isChoiceNode then
                self:SetSelection(entry.nodeID, entry.selectionEntryID);
            else
                self:SetRank(entry.nodeID, entry.ranksPurchased);
            end
        end
    end);
    RunNextFrame(function() self:OnSubTreeSelectionChange(); end);

    return true;
end

function TalentViewerUIMixin:ShouldInstantiateNode(nodeID, nodeInfo)
    -- by default, subtree selection nodes are not instantiated
    return true;
end

function TalentViewerUIMixin:AcquireTalentButton(nodeInfo, talentType, offsetX, offsetY, initFunction)
    --- @class TalentViewer_TalentButtonMixin4E
    local talentButton = parentMixin.AcquireTalentButton(self, nodeInfo, talentType, offsetX, offsetY, initFunction);
    talentButton.talentFrame = self;
    Mixin(talentButton, ns.mixins.TalentButtonMixin);
    local subTreeID = nodeInfo.tvSubTreeID or nodeInfo.subTreeID;
    if subTreeID then
        local isActive = self:GetActiveSubTreeID() == subTreeID;
        talentButton:UpdateSubTreeActiveVisual(isActive);
    end

    return talentButton;
end

function TalentViewerUIMixin:UpdateTalentButtonPosition(talentButton)
    parentMixin.UpdateTalentButtonPosition(self, talentButton);
    local nodeInfo = talentButton:GetNodeInfo();
    local subTreeIDs = LibTalentTree:GetSubTreeIDsForSpecID(self:GetSpecID());
    local subTreeID = nodeInfo.tvSubTreeID or nodeInfo.subTreeID;
    local posX, posY;
    if nodeInfo.isSubTreeSelection then
        posX = SELECTION_NODE_POS_X;
        posY = SELECTION_NODE_POS_Y;
    elseif subTreeID then
        posX = nodeInfo.posX;
        posY = nodeInfo.posY;

        local isTopSubTree = subTreeIDs[1] == subTreeID;
        local subTreeInfo = LibTalentTree:GetSubTreeInfo(subTreeID);
        if subTreeInfo and subTreeInfo.posX and subTreeInfo.posY then
            posX = posX - subTreeInfo.posX;
            posY = posY - subTreeInfo.posY;
        end
        posX = posX + SUB_TREE_OFFSET_X;
        posY = posY + (isTopSubTree and SUB_TREE_OFFSET_Y_TOP_TREE or SUB_TREE_OFFSET_Y_BOTTOM_TREE);
    end
    if posX and posY then
        local basePanOffsetX = self.basePanOffsetX or 0;
        local basePanOffsetY = self.basePanOffsetY or 0;
        local panOffsetMultiplier = 10;
        posX = posX + basePanOffsetX * panOffsetMultiplier;
        posY = posY + basePanOffsetY * panOffsetMultiplier;
        TalentButtonUtil.ApplyPosition(talentButton, self, posX, posY);
    end
end

function TalentViewerUIMixin:SetSelection(nodeID, entryID)
    local nodeInfo = self:GetAndCacheNodeInfo(nodeID);
    TalentViewer:SetSelection(nodeID, entryID);
    self:AfterRankChange(nodeID);
    if nodeInfo.isSubTreeSelection then
        self:SelectSubTree(entryID and self:GetAndCacheEntryInfo(entryID).subTreeID);
    end
end

function TalentViewerUIMixin:PurchaseRank(nodeID)
    TalentViewer:PurchaseRank(nodeID);
    self:AfterRankChange(nodeID);
end

function TalentViewerUIMixin:RefundRank(nodeID)
    TalentViewer:RefundRank(nodeID);
    self:AfterRankChange(nodeID);
end

function TalentViewerUIMixin:SetRank(nodeID, rank)
    TalentViewer:SetRank(nodeID, rank);
    self:AfterRankChange(nodeID);
end

function TalentViewerUIMixin:AfterRankChange(nodeID)
    self.purchasesWithRequiredLevel[nodeID] = nil;
    self:MarkNodeInfoCacheDirty(nodeID);
    local nodeInfo = self:GetAndCacheNodeInfo(nodeID);
    self:MarkEdgeRequirementCacheDirty(nodeID);
    self:RefreshTreeHeaders();
    self:UpdateEdgeSiblings(nodeID);

    local subTreeID = nodeInfo.tvSubTreeID or nodeInfo.subTreeID;
    if subTreeID then
        RunNextFrame(function()
            local talentButton = self:GetTalentButtonByNodeID(nodeID);
            if not talentButton then return; end
            local isActive = self:GetActiveSubTreeID() == subTreeID;
            talentButton:UpdateSubTreeActiveVisual(isActive);
        end);
    end
end

function TalentViewerUIMixin:UpdateEdgeSiblings(nodeID)
    if TalentViewer.db.ignoreRestrictions then return; end
    local nodeInfo = self:GetAndCacheNodeInfo(nodeID);
    local edges = nodeInfo.visibleEdges;

    if not edges or not edges[1] or edges[1].isActive then return end
    for _, edge in ipairs(edges) do
        local siblingNodeID = edge.targetNode;
        local siblingNodeInfo = self:GetAndCacheNodeInfo(siblingNodeID);
        if not siblingNodeInfo.meetsEdgeRequirements and siblingNodeInfo.ranksPurchased > 0 then
            if #siblingNodeInfo.entryIDs > 1 then
                self:SetSelection(siblingNodeID, nil);
            else
                self:SetRank(siblingNodeID, 0);
            end
        end
    end
end

function TalentViewerUIMixin:ResetTree()
    TalentViewer:ResetTree();
end

function TalentViewerUIMixin:ResetByGroupID(groupID)
    self:RunWithRestrictionsDisabled(function()
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(TalentViewer.treeId)) do
            local nodeInfo = self:GetAndCacheNodeInfo(nodeID);
            for _, nodeGroupID in ipairs(nodeInfo.groupIDs) do
                if nodeGroupID == groupID then
                    self:SetRank(nodeID, 0);
                    self:SetSelection(nodeID, nil);
                end
            end
        end
    end);
end

function TalentViewerUIMixin:CanAfford(cost)
    return parentMixin.CanAfford(self, cost);
end

--- @return table<number, treeCurrencyInfo> treeCurrencyInfos # [index or SubTreeID] = treeCurrencyInfo
--- @return boolean isNewValue
function TalentViewerUIMixin:GetAndCacheTreeCurrencyInfo(specID)
    local function GetTreeCurrencyInfoCallback(specID)
        local treeCurrencyInfo = {};
        local treeID = LibTalentTree:GetClassTreeID(tvCache.specIdToClassIdMap[specID]);
        local currencies = LibTalentTree:GetTreeCurrencies(treeID);
        for i, currencyInfo in ipairs(currencies) do
            if currencyInfo.isClassCurrency then
                treeCurrencyInfo[i] = {
                    maxQuantity = ns.TOTAL_CURRENCY_CAP,
                    quantity = ns.TOTAL_CURRENCY_CAP,
                    spent = 0,
                    traitCurrencyID = currencyInfo.traitCurrencyID,
                };
            else
                error('unexpected currency, currencyID: ' .. currencyInfo.traitCurrencyID .. ' treeID: ' .. treeID);
            end
        end

        return treeCurrencyInfo;
    end
    return GetOrCreateTableEntryByCallback(self.treeCurrencyInfoCache, specID, GetTreeCurrencyInfoCallback);
end

local TREE_HEADER_OFFSET_X = 140;
local TREE_HEADER_OFFSET_Y = -100;
local TREE_HEADER_SPACING_X = 400;
function TalentViewerUIMixin:RefreshTreeHeaders()
    self:ProcessGroupSpendingMandatedRefunds();

    --- @type table<number, treeCurrencyInfo> # [index or SubTreeID] = treeCurrencyInfo
    self.treeCurrencyInfo = self:GetAndCacheTreeCurrencyInfo(self:GetSpecID());

    self.treeCurrencyInfoMap = {};
    for _, treeCurrency in ipairs(self.treeCurrencyInfo) do
        self.treeCurrencyInfoMap[treeCurrency.traitCurrencyID] = TalentViewer:ApplyCurrencySpending(treeCurrency);
    end

    self:RefreshCurrencyDisplay();

    for condID, condInfo in pairs(self.condInfoCache) do
        if condInfo.isGate then
            self:MarkCondInfoCacheDirty(condID);
            self:ForceCondInfoUpdate(condID);
        end
    end

    local groupInfos = {};
    for groupID, spent in pairs(self:GetTalentViewer().currencyGroupSpending) do
        groupInfos[groupID] = { currencyInfos = { { spent = spent } } };
    end

    for talentButton in self:EnumerateAllTalentButtons() do
        self:MarkNodeInfoCacheDirty(talentButton:GetNodeID());
    end

    self.treeHeaderPool:ReleaseAll();
    self.treeHeaders = {};
    local groupIDs = {};

    local function GroupCurrencyInfoForGroupID(groupInfos, groupID)
        for i, groupInfo in ipairs(groupInfos) do
            if groupInfo.traitNodeGroupID == groupID then
                return groupInfo;
            end
        end
    end

    local displayInfos = C_Traits.GetGroupDisplayInfoByTreeID(self:GetTalentTreeID());
    for i, displayInfo in ipairs(displayInfos) do
        table.insert(groupIDs, displayInfo.groupID);
    end

    for i, displayInfo in ipairs(displayInfos) do
        local header = self.treeHeaderPool:Acquire("ClassTalentTreeHeaderTemplate");
        header:Setup(displayInfo, groupInfos[displayInfo.groupID]);
        header:SetPoint("CENTER", self.BackgroundBorder, "TOPLEFT", TREE_HEADER_OFFSET_X + ((i-1) * TREE_HEADER_SPACING_X), TREE_HEADER_OFFSET_Y);
        header:Show();
        table.insert(self.treeHeaders, header);
    end
end

function TalentViewerUIMixin:ProcessGroupSpendingMandatedRefunds()
    if TalentViewer.db.ignoreRestrictions then return; end
    self:RunWithRestrictionsDisabled(function()
        local classID = self:GetClassID();
        local spendingPerGroup = { 0, 0, 0 };
        for row = 1, ns.MAX_ROWS do
            for groupIndex = 1, 3 do
                for col = 1, 4 do
                    local column = col + ((groupIndex - 1) * 4);
                    local nodeID = LibTalentTree:GetNodeIDsForGridPosition(classID, column, row);
                    local nodeInfo = nodeID and self:GetAndCacheNodeInfo(nodeID);
                    if nodeInfo and nodeInfo.spentAmountRequired and nodeInfo.spentAmountRequired.amount > spendingPerGroup[groupIndex] then
                        if nodeInfo.ranksPurchased > 0 then
                            if self:IsChoiceNode(nodeInfo) then
                                self:SetSelection(nodeID, nil);
                            else
                                self:SetRank(nodeID, 0);
                            end
                        end
                    elseif nodeInfo then
                        local costInfo = self:GetNodeCost(nodeID);
                        local amount = costInfo[1].amount;
                        if nodeInfo.ranksPurchased > 0 then
                            spendingPerGroup[groupIndex] = spendingPerGroup[groupIndex] + (amount * nodeInfo.ranksPurchased);
                        end
                    end
                end
            end
        end
    end);
end

function TalentViewerUIMixin:RefreshCurrencyDisplay()
    local classCurrencyInfo = self.treeCurrencyInfo and self.treeCurrencyInfo[1] or nil;
    self.ClassCurrencyDisplay:SetAmount(classCurrencyInfo and classCurrencyInfo.quantity or 0);
end

function TalentViewerUIMixin:SelectSubTree(subTreeID)
    self.activeSubTreeID = subTreeID;
    self:OnSubTreeSelectionChange();
end
function TalentViewerUIMixin:GetActiveSubTreeID()
    return self.activeSubTreeID;
end

function TalentViewerUIMixin:OnSubTreeSelectionChange()
    local subTreeIDs = LibTalentTree:GetSubTreeIDsForSpecID(self:GetSpecID());
    for _, subTreeID in ipairs(subTreeIDs) do
        local isActive = self:GetActiveSubTreeID() == subTreeID;
        local nodes = LibTalentTree:GetSubTreeNodeIDs(subTreeID);
        for _, nodeID in ipairs(nodes) do
            local button = self:GetTalentButtonByNodeID(nodeID);
            if button then
                button:UpdateSubTreeActiveVisual(isActive);
            end
        end
    end
    self:RefreshCurrencyDisplay();
end

function TalentViewerUIMixin:OnLoad()
    self.ButtonsParent:ClearAllPoints();
    self.ButtonsParent:SetPoint("TOPLEFT", 0, 43);
    self.ButtonsParent:SetPoint("BOTTOMRIGHT", self.BottomBar, "TOPRIGHT", 0, 0);
    self.ButtonsParent.SetPoint = nop;
    self.ButtonsParent.ClearAllPoints = nop;
    self.ButtonsParent:EnableMouse(false);

    local hiddenParent = CreateFrame('Frame');
    hiddenParent:Hide();
    self.HeroTalentsContainer:SetParent(hiddenParent);
    self.HeroTalentsContainer.UpdateHeroTalentInfo = nop;
    self.HeroTalentsContainer.UpdateHeroTalentButtonPosition = nop;
    self.HeroTalentsContainer.UpdateHeroTalentCurrency = nop;
    self.HeroTalentsContainer.UpdateSearchDisplay = nop;
    self.HeroTalentsContainer.Init = nop;

    self.edgeRequirementsCache = {};
    self.nodeCostCache = {};
    self.treeCurrencyInfoCache = {};
    self.treeTypeSpending = {}

    self.treeHeaderPool = CreateFramePoolCollection();
    self.treeHeaderPool:CreatePool("FRAME", self, "ClassTalentTreeHeaderTemplate");

    self.ResetButton:SetupMenu(function(dropdown, rootDescription)
        rootDescription:SetTag("MENU_CLASS_TALENT_FRAME_RESET");

        rootDescription:CreateTitle(TALENT_FRAME_RESET_BUTTON_DROPDOWN_TITLE);
        if not self:GetTalentTreeID() then return; end
        local displayInfos = C_Traits.GetGroupDisplayInfoByTreeID(self:GetTalentTreeID());
        for i, displayInfo in ipairs(displayInfos) do
            rootDescription:CreateButton(displayInfo.displayName, function() self:ResetByGroupID(displayInfo.groupID) end);
        end
        rootDescription:CreateButton(TALENT_FRAME_RESET_BUTTON_DROPDOWN_ALL, function() self:ResetTree() end);
    end);
    self.ResetButton.SetupMenu = nop;

    parentMixin.OnLoad(self);
end

----------------------
--- Script handles
----------------------
do
    --- @type TalentViewerImportExport4E
    local ImportExport = ns.ImportExport

    StaticPopupDialogs['TalentViewerExportDialog'] = {
        text = L['CTRL-C to copy'],
        button1 = CLOSE,
        --- @param dialog StaticPopupTemplate
        --- @param data string
        OnShow = function(dialog, data)
            local function HidePopup()
                dialog:Hide();
            end
            --- @type StaticPopupTemplate_EditBox
            local editBox = dialog:GetEditBox();
            editBox:SetScript('OnEscapePressed', HidePopup);
            editBox:SetScript('OnEnterPressed', HidePopup);
            editBox:SetScript('OnKeyUp', function(_, key)
                if IsControlKeyDown() and (key == 'C' or key == 'X') then
                    HidePopup();
                end
            end);
            editBox:SetMaxLetters(0);
            editBox:SetText(data);
            editBox:HighlightText();
        end,
        hasEditBox = true,
        editBoxWidth = 240,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };
    StaticPopupDialogs['TalentViewerImportDialog'] = {
        text = HUD_CLASS_TALENTS_IMPORT_DIALOG_TITLE .. '\n' .. L['Icy-veins calculator links are also supported!'],
        button1 = OKAY,
        button2 = CLOSE,
        --- @param dialog StaticPopupTemplate
        OnAccept = function(dialog)
            --- @type StaticPopupTemplate_EditBox
            local editBox = dialog:GetEditBox();
            TalentViewer:ImportLoadout(editBox:GetText());
            dialog:Hide();
        end,
        --- @param dialog StaticPopupTemplate
        OnShow = function(dialog)
            local function HidePopup()
                dialog:Hide();
            end
            local function OnEnter()
                dialog:GetButtons()[1]:Click();
            end
            --- @type StaticPopupTemplate_EditBox
            local editBox = dialog:GetEditBox();
            editBox:SetScript('OnEscapePressed', HidePopup);
            editBox:SetScript('OnEnterPressed', OnEnter);
        end,
        hasEditBox = true,
        editBoxWidth = 240,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    };

    function TalentViewer_ImportButton_OnClick()
        StaticPopup_Show('TalentViewerImportDialog');
    end
    function TalentViewer_ExportButton_OnClick()
        local exportString = ImportExport:GetLoadoutExportString();
        StaticPopup_Show('TalentViewerExportDialog', nil, nil, exportString);
    end
end
