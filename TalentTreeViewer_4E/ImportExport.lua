local name = ...;
--- @class TTV_4E_NS
local ns = select(2, ...);

--- @class TalentViewerImportExport4E
local ImportExport = ns.ImportExport;

--- @type TalentViewer4E
local TalentViewer = ns.TalentViewer;
local L = ns.L;

local LOADOUT_SERIALIZATION_VERSION = 2;

local getNodeInfo = function(nodeId) return TalentViewer:GetTalentFrame():GetAndCacheNodeInfo(nodeId) end

function ImportExport:GetTreeID()
    return TalentViewer.treeId;
end
function ImportExport:GetSpecID()
    return TalentViewer.selectedSpecId;
end

----- copied and adapted from Blizzard_ClassTalentImportExport.lua -----

ImportExport.bitWidthHeaderVersion = 8;
ImportExport.bitWidthSpecID = 16;
ImportExport.bitWidthRanksPurchased = 6;

StaticPopupDialogs["TALENT_VIEWER_LOADOUT_IMPORT_ERROR_DIALOG"] = {
    text = "%s",
    button1 = OKAY,
    button2 = nil,
    timeout = 0,
    OnAccept = function() end,
    OnCancel = function() end,
    whileDead = 1,
    hideOnEscape = 1,
};

--- @return TalentViewer4E_PurchasedNode[]
function ImportExport:WriteLoadoutContent(exportStream, treeID)
    local purchasedNodes = {};
    local treeNodes = C_Traits.GetTreeNodes(treeID);
    for _, treeNodeID in ipairs(treeNodes) do
        local treeNode = getNodeInfo(treeNodeID);

        local isNodeGranted = treeNode.activeRank - treeNode.ranksPurchased > 0;
        local isNodePurchased = treeNode.ranksPurchased > 0;
        local isNodeSelected = isNodeGranted or isNodePurchased;
        local isPartiallyRanked = treeNode.ranksPurchased ~= treeNode.maxRanks;
        local isChoiceNode = treeNode.type == Enum.TraitNodeType.Selection or treeNode.type == Enum.TraitNodeType.SubTreeSelection;

        exportStream:AddValue(1, isNodeSelected and 1 or 0);
        if(isNodeSelected) then
            exportStream:AddValue(1, isNodePurchased and 1 or 0);

            if isNodePurchased then
                --- @class TalentViewer4E_PurchasedNode
                local purchasedNode = { nodeID = treeNode.ID, ranksPurchased = treeNode.ranksPurchased };
                table.insert(purchasedNodes, purchasedNode);
                exportStream:AddValue(1, isPartiallyRanked and 1 or 0);
                if(isPartiallyRanked) then
                    exportStream:AddValue(self.bitWidthRanksPurchased, treeNode.ranksPurchased);
                end

                exportStream:AddValue(1, isChoiceNode and 1 or 0);
                if(isChoiceNode) then
                    local entryIndex = self:GetActiveEntryIndex(treeNode);
                    if(entryIndex <= 0 or entryIndex > 4) then
                        error("Error exporting tree node " .. treeNode.ID .. ". The active choice node entry index (" .. entryIndex .. ") is out of bounds. ");
                    end

                    -- store entry index as zero-index
                    exportStream:AddValue(2, entryIndex - 1);
                end
            end
        end
    end

    return purchasedNodes;
end

function ImportExport:GetActiveEntryIndex(treeNode)
    for i, entryID in ipairs(treeNode.entryIDs) do
        if(treeNode.activeEntry and entryID == treeNode.activeEntry.entryID) then
            return i;
        end
    end

    return 0;
end

function ImportExport:ReadLoadoutContent(importStream, treeID)
    local results = {};

    local treeNodes = C_Traits.GetTreeNodes(treeID);
    for i, _ in ipairs(treeNodes) do
        local nodeSelectedValue = importStream:ExtractValue(1);
        local isNodeSelected =  nodeSelectedValue == 1;
        local isNodePurchased = false;
        local isPartiallyRanked = false;
        local partialRanksPurchased = 0;
        local isChoiceNode = false;
        local choiceNodeSelection = 0;

        if(isNodeSelected) then
            local nodePurchasedValue = importStream:ExtractValue(1);

            isNodePurchased = nodePurchasedValue == 1;
            if(isNodePurchased) then
                local isPartiallyRankedValue = importStream:ExtractValue(1);
                isPartiallyRanked = isPartiallyRankedValue == 1;
                if(isPartiallyRanked) then
                    partialRanksPurchased = importStream:ExtractValue(self.bitWidthRanksPurchased);
                end
                local isChoiceNodeValue = importStream:ExtractValue(1);
                isChoiceNode = isChoiceNodeValue == 1;
                if(isChoiceNode) then
                    choiceNodeSelection = importStream:ExtractValue(2);
                end
            end
        end

        local result = {};
        result.isNodeSelected = isNodeSelected;
        result.isNodeGranted = isNodeSelected and not isNodePurchased;
        result.isPartiallyRanked = isPartiallyRanked;
        result.partialRanksPurchased = partialRanksPurchased;
        result.isChoiceNode = isChoiceNode;
        -- entry index is stored as zero-index, so convert back to lua index
        result.choiceNodeSelection = choiceNodeSelection + 1;
        results[i] = result;

    end

    return results;
end

function ImportExport:GetLoadoutExportString()
    local exportStream = ExportUtil.MakeExportDataStream();
    local currentSpecID = self:GetSpecID();
    local treeID = self:GetTreeID();

    self:WriteLoadoutHeader(exportStream, LOADOUT_SERIALIZATION_VERSION, currentSpecID);
    self:WriteLoadoutContent(exportStream, treeID);

    return exportStream:GetExportString();
end

function ImportExport:ShowImportError(errorString)
    StaticPopup_Show("TALENT_VIEWER_LOADOUT_IMPORT_ERROR_DIALOG", errorString);
end

--- @param importText string
function ImportExport:ImportLoadout(importText)

    local importStream = ExportUtil.MakeImportDataStream(importText);

    local headerValid, serializationVersion, specID, treeHash = self:ReadLoadoutHeader(importStream);

    if(not headerValid) then
        self:ShowImportError(LOADOUT_ERROR_BAD_STRING);
        return false;
    end

    if(serializationVersion ~= LOADOUT_SERIALIZATION_VERSION) then
        self:ShowImportError(LOADOUT_ERROR_SERIALIZATION_VERSION_MISMATCH);
        return false;
    end

    if(specID ~= self:GetSpecID()) then
        TalentViewer:SelectSpec(TalentViewer.cache.specIdToClassIdMap[specID], specID);
    end

    local treeId = self:GetTreeID();

    local loadoutContent = self:ReadLoadoutContent(importStream, treeId);
    local loadoutEntryInfo = self:ConvertToImportLoadoutEntryInfo(treeId, loadoutContent);

    TalentViewer:GetTalentFrame():ImportLoadout(loadoutEntryInfo);

    return true;
end

function ImportExport:WriteLoadoutHeader(exportStream, serializationVersion, specID)
    exportStream:AddValue(self.bitWidthHeaderVersion, serializationVersion);
    exportStream:AddValue(self.bitWidthSpecID, specID);
    -- treeHash is a 128bit hash, passed as an array of 16, 8-bit values
    -- empty tree hash will disable validation on import
    exportStream:AddValue(8 * 16, 0);
end

function ImportExport:ReadLoadoutHeader(importStream)
    local headerBitWidth = self.bitWidthHeaderVersion + self.bitWidthSpecID + 128;
    local importStreamTotalBits = importStream:GetNumberOfBits();
    if( importStreamTotalBits < headerBitWidth) then
        return false, 0, 0, 0;
    end
    local serializationVersion = importStream:ExtractValue(self.bitWidthHeaderVersion);
    local specID = importStream:ExtractValue(self.bitWidthSpecID);
    -- treeHash is a 128bit hash, passed as an array of 16, 8-bit values
    local treeHash = {};
    for i=1,16,1 do
        treeHash[i] = importStream:ExtractValue(8);
    end
    return true, serializationVersion, specID, treeHash;
end

--- converts from compact bit-packing format to LoadoutEntryInfo format to pass to ImportLoadout API
--- @return TalentViewer_LoadoutEntryInfo[]
function ImportExport:ConvertToImportLoadoutEntryInfo(treeID, loadoutContent)
    local results = {};
    local treeNodes = C_Traits.GetTreeNodes(treeID);
    local count = 1;
    for i, treeNodeID in ipairs(treeNodes) do

        local indexInfo = loadoutContent[i];

        if (indexInfo.isNodeSelected and not indexInfo.isNodeGranted) then
            local treeNode = getNodeInfo(treeNodeID);
            local isChoiceNode = treeNode.type == Enum.TraitNodeType.Selection or treeNode.type == Enum.TraitNodeType.SubTreeSelection;
            local choiceNodeSelection = indexInfo.isChoiceNode and indexInfo.choiceNodeSelection or nil;
            if indexInfo.isNodeSelected and isChoiceNode ~= indexInfo.isChoiceNode then
                -- guard against corrupt import strings
                print(string.format(L["Import string is corrupt, node type mismatch at nodeID %d. First option will be selected."], treeNodeID));
                choiceNodeSelection = 1;
            end
            --- @type TalentViewer_LoadoutEntryInfo
            local result = {
                nodeID = treeNode.ID,
                ranksPurchased = indexInfo.isPartiallyRanked and indexInfo.partialRanksPurchased or treeNode.maxRanks,
                selectionEntryID = (indexInfo.isNodeSelected and isChoiceNode and treeNode.entryIDs[choiceNodeSelection]) or (treeNode.activeEntry and treeNode.activeEntry.entryID),
                isChoiceNode = isChoiceNode,
            };
            results[count] = result;
            count = count + 1;
        end

    end

    return results;
end