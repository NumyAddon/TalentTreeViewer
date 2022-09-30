local _, ns = ...

--- @class TalentViewerImportExport
local ImportExport = ns.ImportExport

--- @type TalentViewer
local TalentViewer = ns.TalentViewer

local LOADOUT_SERIALIZATION_VERSION = 1;

local getNodeInfo = function(nodeId) return TalentViewer:GetTalentFrame():GetAndCacheNodeInfo(nodeId) end

function ImportExport:GetConfigID()
    return C_ClassTalents.GetActiveConfigID();
end
function ImportExport:GetTreeId()
    return TalentViewer.treeId;
end
function ImportExport:GetSpecId()
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
    OnAccept = function()
    end,
    OnCancel = function()
    end,
    whileDead = 1,
    hideOnEscape = 1,
};

function ImportExport:WriteLoadoutContent(exportStream, _, treeID)
    local treeNodes = C_Traits.GetTreeNodes(treeID);
    for _, treeNodeID in ipairs(treeNodes) do
        local treeNode = getNodeInfo(treeNodeID);

        local isNodeSelected = treeNode.ranksPurchased > 0;
        local isPartiallyRanked = treeNode.ranksPurchased ~= treeNode.maxRanks;
        local isChoiceNode = treeNode.type == Enum.TraitNodeType.Selection;

        exportStream:AddValue(1, isNodeSelected and 1 or 0);
        if(isNodeSelected) then
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

function ImportExport:GetActiveEntryIndex(treeNode)
    for i, entryID in ipairs(treeNode.entryIDs) do
        if(entryID == treeNode.activeEntry.entryID) then
            return i;
        end
    end

    return 0;
end

function ImportExport:ReadLoadoutContent(importStream, treeID)
    local results = {};

    local treeNodes = C_Traits.GetTreeNodes(treeID);
    for i, _ in ipairs(treeNodes) do
        local nodeSelectedValue = importStream:ExtractValue(1)
        local isNodeSelected =  nodeSelectedValue == 1;
        local isPartiallyRanked = false;
        local partialRanksPurchased = 0;
        local isChoiceNode = false;
        local choiceNodeSelection = 0;

        if(isNodeSelected) then
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

        local result = {};
        result.isNodeSelected = isNodeSelected;
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
    local configID = self:GetConfigID();
    local currentSpecID = self:GetSpecId();
    local treeId = self:GetTreeId();


    self:WriteLoadoutHeader(exportStream, LOADOUT_SERIALIZATION_VERSION, currentSpecID);
    self:WriteLoadoutContent(exportStream, configID, treeId);

    return exportStream:GetExportString();
end

function ImportExport:ShowImportError(errorString)
    StaticPopup_Show("TALENT_VIEWER_LOADOUT_IMPORT_ERROR_DIALOG", errorString);
end

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

    if(specID ~= self:GetSpecId()) then
        TalentViewer:SelectSpec(TalentViewer.cache.specIdToClassIdMap[specID], specID);
    end

    local treeId = self:GetTreeId();

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

-- converts from compact bit-packing format to LoadoutEntryInfo format to pass to ImportLoadout API
function ImportExport:ConvertToImportLoadoutEntryInfo(treeID, loadoutContent)
    local results = {};
    local treeNodes = C_Traits.GetTreeNodes(treeID);
    local count = 1;
    for i, treeNodeID in ipairs(treeNodes) do

        local indexInfo = loadoutContent[i];

        if (indexInfo.isNodeSelected) then
            local treeNode = getNodeInfo(treeNodeID);
            local result = {};
            result.nodeID = treeNode.ID;
            result.ranksPurchased = indexInfo.isPartiallyRanked and indexInfo.partialRanksPurchased or treeNode.maxRanks;
            result.selectionEntryID = indexInfo.isChoiceNode and treeNode.entryIDs[indexInfo.choiceNodeSelection] or treeNode.activeEntry.entryID;
            result.isChoiceNode = indexInfo.isChoiceNode;
            results[count] = result;
            count = count + 1;
        end

    end

    return results;
end