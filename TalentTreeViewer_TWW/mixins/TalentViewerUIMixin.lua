local name, ns = ...;

ns.mixins = ns.mixins or {};

--- @type TalentViewerTWW
local TalentViewer = ns.TalentViewer;
if not TalentViewer then return; end

--- @type TalentViewer_CacheTWW
local tvCache = TalentViewer.cache;

---@type LibTalentTree-1.0
local LibTalentTree = LibStub('LibTalentTree-1.0');

local L = LibStub('AceLocale-3.0'):GetLocale(name);

local SELECTION_NODE_POS_X = 7500;
local SELECTION_NODE_POS_Y = 4200;
local SUB_TREE_OFFSET_X = 8100;
local SUB_TREE_OFFSET_Y_TOP_TREE = 1500;
local SUB_TREE_OFFSET_Y_BOTTOM_TREE = 4500;
do
    TALENT_TREE_VIEWER_LOCALE_EXPORT = L['Export'];
    TALENT_TREE_VIEWER_LOCALE_SELECT_SPECIALIZATION = L['Select another Specialization'];
    TALENT_TREE_VIEWER_LOCALE_START_RECORDING_TOOLTIP = L['Start/resume recording a leveling build. This will fast-forward you to the highest level in the current build.'];
    TALENT_TREE_VIEWER_LOCALE_STOP_RECORDING_TOOLTIP = L['Stop recording the leveling build.'];
    TALENT_TREE_VIEWER_LOCALE_RESET_RECORDING_TOOLTIP = L['Save leveling build recording, and reset the leveling build.'];
    TALENT_TREE_VIEWER_LOCALE_SELECT_RECORDED_BUILD = L['Select Recorded Build'];
    TALENT_TREE_VIEWER_LOCALE_LEVELING_BUILD_HEADER = L['Leveling Build Tools'];
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
            nodeEdgesCache[nodeID] = LibTalentTree:GetNodeEdges(TalentViewer.treeId, nodeID) or emptyTable;
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


local parentMixin = ClassTalentsFrameMixin;
--- @class TalentViewerUIMixinTWW
TalentViewer_ClassTalentsFrameMixin = deepCopy(parentMixin);

--- @class TalentViewerUIMixinTWW
local TalentViewerUIMixin = TalentViewer_ClassTalentsFrameMixin;
--- @type TalentViewer_LevelingOrderFrameTWW[]
TalentViewerUIMixin.levelingOrderButtons = {};
TalentViewerUIMixin.currentOrder = 0;

local function removeFromMixin(method) TalentViewerUIMixin[method] = function() end; end
removeFromMixin('UpdateConfigButtonsState');
removeFromMixin('RefreshLoadoutOptions');
removeFromMixin('InitializeLoadSystem');
removeFromMixin('GetInspectUnit');
removeFromMixin('OnEvent');
removeFromMixin('RefreshConfigID');
removeFromMixin('UpdateInspecting');

function TalentViewerUIMixin:IsChoiceNode(nodeInfo)
    return nodeInfo.type == Enum.TraitNodeType.Selection or nodeInfo.type == Enum.TraitNodeType.SubTreeSelection;
end

--- @return TalentViewerTWW
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

--- @return TVNodeInfo
function TalentViewerUIMixin:GetAndCacheNodeInfo(nodeID)
    local function GetNodeInfoCallback(nodeID)
        --- @class TVNodeInfo: libNodeInfo
        local nodeInfo = LibTalentTree:GetLibNodeInfo(TalentViewer.treeId, nodeID)
        if not nodeInfo then
            --- @class TVNodeInfo: libNodeInfo
            nodeInfo = LibTalentTree:GetNodeInfo(TalentViewer.treeId, nodeID)
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
                error('no nodeinfo for nodeID '.. nodeID..' treeID ' .. TalentViewer.treeId .. ' specID ' .. self:GetSpecID());
            end
            return nodeInfo;
        end

        local isGranted = LibTalentTree:IsNodeGrantedForSpec(TalentViewer.selectedSpecId, nodeID);
        local isChoiceNode = self:IsChoiceNode(nodeInfo);
        local selectedEntryId = isChoiceNode and TalentViewer:GetSelectedEntryId(nodeID) or nil;

        local meetsEdgeRequirements = TalentViewer.db.ignoreRestrictions or self:MeetsEdgeRequirements(nodeID);
        local meetsGateRequirements = true;
        if not TalentViewer.db.ignoreRestrictions then
            for _, conditionId in ipairs(nodeInfo.conditionIDs) do
                local condInfo = self:GetAndCacheCondInfo(conditionId);
                if condInfo.isGate and not condInfo.isMet then meetsGateRequirements = false; end
            end
        end

        local isAvailable = meetsGateRequirements;

        nodeInfo.activeRank = isGranted
            and nodeInfo.maxRanks
            or ((isChoiceNode and selectedEntryId and 1) or TalentViewer:GetActiveRank(nodeID));
        nodeInfo.currentRank = nodeInfo.activeRank;
        nodeInfo.ranksPurchased = not isGranted and nodeInfo.currentRank or 0;
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
            nodeInfo.activeEntry = entryIndex and { entryID = nodeInfo.entryIDs[entryIndex], rank = nodeInfo.activeRank } or nil
        else
            nodeInfo.activeEntry = { entryID = nodeInfo.entryIDs[1], rank = nodeInfo.activeRank }
        end
        if not isChoiceNode and nodeInfo.activeRank ~= nodeInfo.maxRanks then
            nodeInfo.nextEntry = { entryID = nodeInfo.entryIDs[1], rank = nodeInfo.activeRank + 1 }
        end
        nodeInfo.tvSubTreeID = nodeInfo.subTreeID;
        nodeInfo.subTreeID = nil;

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

function TalentViewerUIMixin:GetNodeCost(nodeID)
    local function GetNodeCostCallback(nodeID)
        local currencyInfo = self:GetAndCacheTreeCurrencyInfo(self:GetSpecID());
        local nodeInfo = LibTalentTree:GetLibNodeInfo(nodeID);
        local currencyID;
        if nodeInfo then
            if nodeInfo.subTreeID then
                currencyID = currencyInfo[nodeInfo.subTreeID].traitCurrencyID;
            elseif nodeInfo.isSubTreeSelection then
                return {};
            elseif nodeInfo.isClassNode then
                currencyID = currencyInfo[1].traitCurrencyID;
            else
                currencyID = currencyInfo[2].traitCurrencyID;
            end
        else -- default to spec currency
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

function TalentViewerUIMixin:ImportLoadout(loadoutEntryInfo)
    self:RunWithRestrictionsDisabled(function()
        self:ResetTree(true);
        for _, entry in ipairs(loadoutEntryInfo) do
            if(entry.isChoiceNode) then
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
    --- @class TalentViewer_TalentButtonMixinTWW
    local talentButton = parentMixin.AcquireTalentButton(self, nodeInfo, talentType, offsetX, offsetY, initFunction);
    talentButton.talentFrame = self;
    Mixin(talentButton, ns.mixins.TalentButtonMixin);
    if not talentButton.LevelingOrder then
        ---@diagnostic disable-next-line: assign-type-mismatch
        talentButton.LevelingOrder = CreateFrame('Frame', nil, talentButton);
        --- @class TalentViewer_LevelingOrderFrameTWW
        local levelingOrder = talentButton.LevelingOrder;
        Mixin(levelingOrder, ns.mixins.LevelingOrderMixin);
        tinsert(self.levelingOrderButtons, levelingOrder);

        levelingOrder:SetAllPoints();
        levelingOrder:SetFrameLevel(1900);
        levelingOrder.Text = levelingOrder:CreateFontString(nil, 'OVERLAY', 'SystemFont16_Shadow_ThickOutline');
        levelingOrder.Text:SetPoint('BOTTOMRIGHT', talentButton, 'TOPRIGHT', 2, -12);
        levelingOrder.Text:SetTextColor(1, 1, 1);
        levelingOrder.Text:SetJustifyH('RIGHT');

        levelingOrder:SetOrder({});
    end
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
    local nodeInfo = self:GetAndCacheNodeInfo(nodeID);
    self:MarkEdgeRequirementCacheDirty(nodeID);
    self:MarkNodeInfoCacheDirty(nodeID);
    self:UpdateTreeCurrencyInfo();
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

--- @param lockLevelingBuild ?boolean # by default, a new leveling build is created and activated when this function is called, passing true will prevent that
function TalentViewerUIMixin:ResetTree(lockLevelingBuild)
    TalentViewer:ResetTree(lockLevelingBuild);
end

function TalentViewerUIMixin:ResetClassTalents()
    local classTraitCurrencyID = self.treeCurrencyInfo and self.treeCurrencyInfo[1] and self.treeCurrencyInfo[1].traitCurrencyID;
    self:ResetByCurrencyID(classTraitCurrencyID);
end

function TalentViewerUIMixin:ResetSpecTalents()
    local specTraitCurrencyID = self.treeCurrencyInfo and self.treeCurrencyInfo[2] and self.treeCurrencyInfo[2].traitCurrencyID;
    self:ResetByCurrencyID(specTraitCurrencyID);
end

function TalentViewerUIMixin:ResetByCurrencyID(currencyID)
    self:RunWithRestrictionsDisabled(function()
        for _, nodeID in ipairs(C_Traits.GetTreeNodes(TalentViewer.treeId)) do
            local cost = self:GetNodeCost(nodeID);
            for _, currencyCost in ipairs(cost) do
                if currencyCost.ID == currencyID then
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
        local treeID = LibTalentTree:GetClassTreeId(tvCache.specIdToClassIdMap[specID]);
        local currencies = LibTalentTree:GetTreeCurrencies(treeID);
        for i, currencyInfo in ipairs(currencies) do
            if currencyInfo.isClassCurrency then
                treeCurrencyInfo[i] = {
                    maxQuantity = ns.MAX_LEVEL_CLASS_CURRENCY_CAP,
                    quantity = ns.MAX_LEVEL_CLASS_CURRENCY_CAP,
                    spent = 0,
                    traitCurrencyID = currencyInfo.traitCurrencyID,
                };
            elseif currencyInfo.isSpecCurrency then
                treeCurrencyInfo[i] = {
                    maxQuantity = ns.MAX_LEVEL_SPEC_CURRENCY_CAP,
                    quantity = ns.MAX_LEVEL_SPEC_CURRENCY_CAP,
                    spent = 0,
                    traitCurrencyID = currencyInfo.traitCurrencyID
                };
            elseif currencyInfo.subTreeID then
                treeCurrencyInfo[i] = {
                    maxQuantity = currencyInfo.maxQuantity,
                    quantity = currencyInfo.quantity,
                    spent = currencyInfo.spent,
                    traitCurrencyID = currencyInfo.traitCurrencyID,
                    subTreeID = currencyInfo.subTreeID,
                };
                treeCurrencyInfo[currencyInfo.subTreeID] = treeCurrencyInfo[i];
            else
                error('unexpected currency, currencyID: ' .. currencyInfo.traitCurrencyID .. ' treeID: ' .. treeID);
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
        treeCurrency.maxQuantity = i == 1 and ns.MAX_LEVEL_CLASS_CURRENCY_CAP or ns.MAX_LEVEL_SPEC_CURRENCY_CAP;
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
    if TalentViewer.db.ignoreRestrictions then return; end
    self:RunWithRestrictionsDisabled(function()
        self:UpdateNodeGateMapping();
        local eligibleSpendingPerGate = self:GetEligibleSpendingPerGate();
        local gates = LibTalentTree:GetGates(self:GetSpecID());

        for _, gateInfo in ipairs(gates) do
            local eligibleSpending = eligibleSpendingPerGate[gateInfo.conditionID] or 0;
            if eligibleSpending < gateInfo.spentAmountRequired then
                for _, nodeID in ipairs(self.nodesPerGate[gateInfo.conditionID]) do
                    local nodeInfo = self:GetAndCacheNodeInfo(nodeID);
                    if nodeInfo.ranksPurchased > 0 then
                        if self:IsChoiceNode(nodeInfo) then
                            self:SetSelection(nodeID, nil);
                        else
                            self:SetRank(nodeID, 0);
                        end
                    end
                end
            end
        end
    end);
end

function TalentViewerUIMixin:UpdateNodeGateMapping()
    if self.eligibleNodesPerGate and self.nodesPerGate then return; end
    self.eligibleNodesPerGate = {};
    self.nodesPerGate = {};
    local gates = LibTalentTree:GetGates(self:GetSpecID());

    for _, gateInfo in ipairs(gates) do
        self.eligibleNodesPerGate[gateInfo.conditionID] = self.eligibleNodesPerGate[gateInfo.conditionID] or {};
        self.nodesPerGate[gateInfo.conditionID] = self.nodesPerGate[gateInfo.conditionID] or {};

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
                    table.insert(self.nodesPerGate[gateInfo.conditionID], nodeID);
                else
                    table.insert(self.eligibleNodesPerGate[gateInfo.conditionID], nodeID);
                end
            end
        end
    end
end

--- @return table<number, number> # [conditionID] = eligibleSpending
function TalentViewerUIMixin:GetEligibleSpendingPerGate()
    local spendingPerGate = {}
    for condID, nodeIDs in pairs(self.eligibleNodesPerGate) do
        spendingPerGate[condID] = 0;
        for _, nodeID in ipairs(nodeIDs) do
            local nodeInfo = self:GetAndCacheNodeInfo(nodeID);
            local costInfo = self:GetNodeCost(nodeID);
            local amount = costInfo[1].amount;
            if nodeInfo.ranksPurchased > 0 then
                spendingPerGate[condID] = spendingPerGate[condID] + (amount * nodeInfo.ranksPurchased);
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

function TalentViewerUIMixin:SelectSubTree(subTreeID)
    self.activeSubTreeID = subTreeID;
    self:OnSubTreeSelectionChange();
end
function TalentViewerUIMixin:GetActiveSubTreeID()
    return self.activeSubTreeID;
end

function TalentViewerUIMixin:OnSubTreeSelectionChange()
    local subTreeIDs = LibTalentTree:GetSubTreeIdsForSpecId(self:GetSpecID());
    for _, subTreeID in ipairs(subTreeIDs) do
        local isActive = self:GetActiveSubTreeID() == subTreeID;
        local nodes = LibTalentTree:GetSubTreeNodeIds(subTreeID);
        for _, nodeID in ipairs(nodes) do
            local button = self:GetTalentButtonByNodeID(nodeID);
            if button then
                button:UpdateSubTreeActiveVisual(isActive);
            end
        end
    end
end

function TalentViewerUIMixin:OnLoad()
    local hiddenParent = CreateFrame('Frame');
    hiddenParent:Hide();
    self.HeroTalentsContainer:SetParent(hiddenParent);
    self.HeroTalentsContainer.UpdateHeroTalentInfo = nop;
    self.HeroTalentsContainer.UpdateHeroTalentButtonPosition = nop;
    self.HeroTalentsContainer.UpdateHeroTalentCurrency = nop;
    self.HeroTalentsContainer.UpdateSearchDisplay = nop;
    self.HeroTalentsContainer.Init = nop;

    parentMixin.OnLoad(self);

    self.edgeRequirementsCache = {};
    self.nodeCostCache = {};
    self.treeCurrencyInfoCache = {};

    local setAmountOverride = function(self, amount)
        local requiredLevel = self.isClassCurrency and 8 or 9;
        local spent = (self.isClassCurrency and ns.MAX_LEVEL_CLASS_CURRENCY_CAP or ns.MAX_LEVEL_SPEC_CURRENCY_CAP) - amount;
        requiredLevel = math.max(10, requiredLevel + (spent * 2));

        local text = string.format(L['%d (level %d)'], amount, requiredLevel);

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

-----------------------
--- Leveling Builds ---
-----------------------
function TalentViewerUIMixin:OnUpdate()
    parentMixin.OnUpdate(self);
    self:UpdateLevelingBuildHighlights();
end

function TalentViewerUIMixin:UpdateLevelingBuildHighlights()
    local wereSelectableGlowsDisabled = false;
    if self.activeLevelingBuildHighlight then
        local previousHighlightedButton = self:GetTalentButtonByNodeID(self.activeLevelingBuildHighlight.nodeID);
        if previousHighlightedButton then
            previousHighlightedButton:SetGlowing(false);
        end
        self.activeLevelingBuildHighlight = nil;

        wereSelectableGlowsDisabled = true;
    end

    local buildID = self:GetLevelingBuildID();
    if not buildID then
        if wereSelectableGlowsDisabled then
            -- Re-enable selection glows now that leveling build highlight is inactive
            for button in self:EnumerateAllTalentButtons() do
                button:SetSelectableGlowDisabled(false);
            end
        end
        return;
    end

    local nodeID, entryID = self:GetNextLevelingBuildPurchase(buildID);
    if not nodeID then
        return;
    end

    local highlightButton = self:GetTalentButtonByNodeID(nodeID);
    if highlightButton and highlightButton:IsSelectable() then
        highlightButton:SetGlowing(true);

        self.activeLevelingBuildHighlight = { nodeID = nodeID, entryID = entryID };

        if not wereSelectableGlowsDisabled then
            -- Disable selection glows since the leveling build highlight is active
            for button in self:EnumerateAllTalentButtons() do
                button:SetSelectableGlowDisabled(true);
            end
        end
    end
end

--- @return nil|TalentViewer_LevelingBuild
function TalentViewerUIMixin:GetLevelingBuildInfo(buildID)
    return TalentViewer:GetLevelingBuild(buildID);
end

function TalentViewerUIMixin:GetNextLevelingBuildPurchase(buildID)
    local info = self:GetLevelingBuildInfo(buildID);
    if not info then return; end

    for level = 10, ns.MAX_LEVEL do
        local targetTree;
        if level < 71 then
            targetTree = (level % 2) + 1;
        else
            targetTree = self:GetActiveSubTreeID();
            if not targetTree and info.selectedSubTreeID then
                return LibTalentTree:GetSubTreeSelectionNodeIDAndEntryIDBySpecID(self:GetSpecID(), info.selectedSubTreeID);
            end
        end
        local entryInfo = info.entries[targetTree] and info.entries[targetTree][level];
        local nodeInfo = entryInfo and self:GetAndCacheNodeInfo(entryInfo.nodeID);
        if nodeInfo and nodeInfo.ranksPurchased < entryInfo.targetRank then
            return entryInfo.nodeID, entryInfo.entryID;
        end
    end
end

function TalentViewerUIMixin:IsLevelingBuildActive()
    return self.activeLevelingBuildID ~= nil;
end

function TalentViewerUIMixin:SetLevelingBuildID(buildID)
    self.activeLevelingBuildID = buildID;
    self:UpdateLevelingBuildHighlights();
end

function TalentViewerUIMixin:GetLevelingBuildID()
    return self.activeLevelingBuildID;
end

function TalentViewerUIMixin:IsHighlightedStarterBuildEntry(entryID)
    return self.activeLevelingBuildHighlight and self.activeLevelingBuildHighlight.entryID == entryID;
end

--- @param level number
--- @param lockLevelingBuild boolean # by default, a new leveling build is created and activated when this function is called, passing true will prevent that
function TalentViewerUIMixin:ApplyLevelingBuild(level, lockLevelingBuild)
    level = math.max(9, math.min(ns.MAX_LEVEL, level or ns.MAX_LEVEL));
    local buildID = self:GetLevelingBuildID();
    local info = buildID and self:GetLevelingBuildInfo(buildID);
    if not info then return; end

    self:RunWithRestrictionsDisabled(function()
        self:ResetTree(lockLevelingBuild);
        if level >= 10 then
            for _ = 10, level do
                local nodeID, entryID = self:GetNextLevelingBuildPurchase(buildID);
                if not nodeID then break; end
                if entryID then
                    self:SetSelection(nodeID, entryID);
                else
                    self:PurchaseRank(nodeID);
                end
            end
        end
        for _, button in ipairs(self.levelingOrderButtons) do
            button:SetOrder({});
        end
        for _, entries in pairs(info.entries) do
            for entryLevel, entryInfo in pairs(entries) do
                local nodeID = entryInfo.nodeID;
                local button = self:GetTalentButtonByNodeID(nodeID);
                if not button then
                    if DevTool and DevTool.AddData then
                        DevTool:AddData({
                            entry = entryInfo,
                            nodeID = nodeID,
                            level = entryLevel,
                            nodeInfo = self:GetAndCacheNodeInfo(nodeID),
                        }, 'could not find button for NodeID when applying');
                    end
                else
                    button.LevelingOrder:AppendToOrder(entryLevel);
                end
            end
        end
        if info.selectedSubTreeID then
            local nodeID = LibTalentTree:GetSubTreeSelectionNodeIDAndEntryIDBySpecID(self:GetSpecID(), info.selectedSubTreeID);
            local button = nodeID and self:GetTalentButtonByNodeID(nodeID);
            if button then
                button.LevelingOrder:AppendToOrder(71);
            end
        end

        self:UpdateTreeCurrencyInfo();
    end);
end

----------------------
--- Script handles
----------------------
do
    --- @type TalentViewerImportExportTWW
    local ImportExport = ns.ImportExport

    StaticPopupDialogs['TalentViewerExportDialog'] = {
        text = L['CTRL-C to copy'],
        button1 = CLOSE,
        OnShow = function(dialog, data)
            local function HidePopup()
                dialog:Hide();
            end
            dialog.editBox:SetScript('OnEscapePressed', HidePopup);
            dialog.editBox:SetScript('OnEnterPressed', HidePopup);
            dialog.editBox:SetScript('OnKeyUp', function(_, key)
                if IsControlKeyDown() and key == 'C' then
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
    StaticPopupDialogs['TalentViewerImportDialog'] = {
        text = HUD_CLASS_TALENTS_IMPORT_DIALOG_TITLE .. '\n' .. L['Icy-veins calculator links are also supported!'],
        button1 = OKAY,
        button2 = CLOSE,
        OnAccept = function(dialog)
            TalentViewer:ImportLoadout(dialog.editBox:GetText());
            dialog:Hide();
        end,
        OnShow = function(dialog)
            local function HidePopup()
                dialog:Hide();
            end
            local function OnEnter()
                dialog.button1:Click();
            end
            dialog.editBox:SetScript('OnEscapePressed', HidePopup);
            dialog.editBox:SetScript('OnEnterPressed', OnEnter);
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
