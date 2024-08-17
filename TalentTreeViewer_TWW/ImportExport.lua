local name, ns = ...

--- @class TalentViewerImportExportTWW
local ImportExport = ns.ImportExport

--- @type TalentViewerTWW
local TalentViewer = ns.TalentViewer
local L = LibStub("AceLocale-3.0"):GetLocale(name);

local LOADOUT_SERIALIZATION_VERSION = 2;
local LEVELING_BUILD_SERIALIZATION_VERSION = 2;
local LEVELING_EXPORT_STRING_PATERN = "%s-LVL-%s";
local HERO_SELECTION_NODE_LEVEL = 71;

local getNodeInfo = function(nodeId) return TalentViewer:GetTalentFrame():GetAndCacheNodeInfo(nodeId) end

function ImportExport:GetTreeID()
    return TalentViewer.treeId;
end
function ImportExport:GetSpecID()
    return TalentViewer.selectedSpecId;
end

ImportExport.levelingBitWidthVersion = 5;
ImportExport.levelingBitWidthData = 7; -- allows for 128 levels

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

--- @return TalentViewerTWW_PurchasedNode[]
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
                --- @class TalentViewerTWW_PurchasedNode
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

function ImportExport:WriteLevelingExportHeader(exportStream, serializationVersion)
    exportStream:AddValue(self.levelingBitWidthVersion, serializationVersion);
end

--- @param treeID number
--- @param levelingBuild table<number, table<number, TalentViewer_LevelingBuildEntry>> # [tree] = {[level] = entry}, where tree is 1 for class, 2 for spec, or tree is SubTreeID for hero specs
--- @param purchasedNodes table<number, TalentViewerTWW_PurchasedNode> # [orderIndex] = purchasedNode
function ImportExport:WriteLevelingBuildContent(exportStream, treeID, levelingBuild, purchasedNodes)
    local map = {};
    for tree, entries in pairs(levelingBuild) do
        for level, entry in pairs(entries) do
            map[tree] = map[tree] or {};
            map[tree][string.format('%d_%d', entry.nodeID, entry.targetRank)] = level;
        end
    end

    for _, purchasedNode in ipairs(purchasedNodes) do
        local nodeInfo = getNodeInfo(purchasedNode.nodeID);
        if nodeInfo.isSubTreeSelection then
            exportStream:AddValue(ImportExport.levelingBitWidthData, HERO_SELECTION_NODE_LEVEL);
        else
            local tree = nodeInfo.subTreeID or nodeInfo.tvSubTreeID or (nodeInfo.isClassNode and 1 or 2);
            for rank = 1, purchasedNode.ranksPurchased do
                local key = string.format('%d_%d', purchasedNode.nodeID, rank);
                local level = map[tree] and map[tree][key] or 0;
                exportStream:AddValue(ImportExport.levelingBitWidthData, level);
            end
        end
    end
end

function ImportExport:GetLoadoutExportString()
    local exportStream = ExportUtil.MakeExportDataStream();
    local currentSpecID = self:GetSpecID();
    local treeID = self:GetTreeID();

    self:WriteLoadoutHeader(exportStream, LOADOUT_SERIALIZATION_VERSION, currentSpecID);
    local purchasedNodes = self:WriteLoadoutContent(exportStream, treeID);

    local loadoutString = exportStream:GetExportString();

    local levelingBuildID = TalentViewer:GetCurrentLevelingBuildID();
    local levelingBuild = TalentViewer:GetLevelingBuild(levelingBuildID);
    if not levelingBuild or not levelingBuild.entries then
        return loadoutString;
    end
    local hasEntries = false;
    for _, entries in pairs(levelingBuild.entries) do
        if entries and next(entries) then
            hasEntries = true;
            break;
        end
    end
    if not hasEntries then
        return loadoutString;
    end

    local levelingExportStream = ExportUtil.MakeExportDataStream();
    self:WriteLevelingExportHeader(levelingExportStream, LEVELING_BUILD_SERIALIZATION_VERSION);
    self:WriteLevelingBuildContent(levelingExportStream, treeID, levelingBuild.entries, purchasedNodes);

    return LEVELING_EXPORT_STRING_PATERN:format(loadoutString, levelingExportStream:GetExportString());
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

    TalentViewer:ClearLevelingBuild()
    TalentViewer:StopRecordingLevelingBuild();

    TalentViewer:GetTalentFrame():ImportLoadout(loadoutEntryInfo);

    local _, _, _, levelingBuildString = importText:find(LEVELING_EXPORT_STRING_PATERN:format("(.*)", "(.*)"):gsub("%-", "%%-"));
    if levelingBuildString then
        local levelingImportStream = ExportUtil.MakeImportDataStream(levelingBuildString);
        local levelingHeaderValid, levelingSerializationVersion = self:ReadLevelingExportHeader(levelingImportStream);
        if levelingHeaderValid and levelingSerializationVersion == LEVELING_BUILD_SERIALIZATION_VERSION then
            local levelingBuild = self:ReadLevelingBuildContent(levelingImportStream, loadoutEntryInfo);
            TalentViewer:ImportLevelingBuild(levelingBuild);
        end
    end

    return true;
end

function ImportExport:ReadLevelingExportHeader(importStream)
    local headerBitWidth = self.levelingBitWidthVersion;
    local importStreamTotalBits = importStream:GetNumberOfBits();
    if( importStreamTotalBits < headerBitWidth) then
        return false, 0;
    end
    local serializationVersion = importStream:ExtractValue(self.levelingBitWidthVersion);
    return true, serializationVersion;
end

--- @param loadoutEntryInfo TalentViewer_LoadoutEntryInfo[]
--- @return TalentViewer_LevelingBuild
function ImportExport:ReadLevelingBuildContent(importStream, loadoutEntryInfo)
    local results = {};
    local selectedSubTreeID;

    for _, entry in ipairs(loadoutEntryInfo) do
        local nodeInfo = getNodeInfo(entry.nodeID);
        local ranksPurchased = entry.ranksPurchased;
        for rank = 1, ranksPurchased do
            local success, level = pcall(importStream.ExtractValue, importStream, ImportExport.levelingBitWidthData);
            if not success or not level then -- end of stream
                return { entries = results, selectedSubTreeID = selectedSubTreeID };
            end
            if level > 0 and not nodeInfo.isSubTreeSelection then
                local result = {};
                result.nodeID = entry.nodeID;
                result.entryID = entry.isChoiceNode and entry.selectionEntryID;
                result.targetRank = rank;

                local tree = nodeInfo.subTreeID or nodeInfo.tvSubTreeID or (nodeInfo.isClassNode and 1 or 2);
                results[tree] = results[tree] or {};
                results[tree][level] = result;
            elseif nodeInfo.isSubTreeSelection then
                local entryInfo = TalentViewer:GetTalentFrame():GetAndCacheEntryInfo(entry.selectionEntryID);
                if entryInfo and entryInfo.subTreeID then
                    selectedSubTreeID = entryInfo.subTreeID;
                end
            end
        end
    end

    return { entries = results, selectedSubTreeID = selectedSubTreeID };
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