local name, ns = ...

--- @class TalentViewerIcyVeinsImportTWW
local IcyVeinsImport = ns.IcyVeinsImport

--- @type TalentViewerTWW
local TalentViewer = ns.TalentViewer

--- @type LibTalentTree-1.0
local LibTT = LibStub('LibTalentTree-1.0');

local L = LibStub('AceLocale-3.0'):GetLocale(name)

IcyVeinsImport.bitWidthSpecID = 12;
IcyVeinsImport.bitWidthNodeIndex = 6;

--- @param text string
--- @return boolean
--- @public
function IcyVeinsImport:IsTalentUrl(text)
    -- example URL https://www.icy-veins.com/wow/the-war-within-talent-calculator#seg1-seg2-seg3-seg4-seg5
    return not not text:match('^https?://www%.icy%-veins%.com/wow/the%-war%-within%-talent%-calculator%#[^-]*%-[^-]*%-[^-]*%-[^-]*%-[^-]*$');
end

--- @private
function IcyVeinsImport:ShowImportError(errorString)
    StaticPopup_Show("TALENT_VIEWER_LOADOUT_IMPORT_ERROR_DIALOG", errorString);
end

--- @param fullUrl string
--- @public
function IcyVeinsImport:ImportUrl(fullUrl)
    if not self:IsTalentUrl(fullUrl) then
        self:ShowImportError("Invalid URL");

        return nil;
    end

    local classID, specID, levelingOrder = self:ParseUrl(fullUrl);
    if not levelingOrder or not classID or not specID then
        self:ShowImportError("Invalid URL");

        return nil;
    end

    TalentViewer:SelectSpec(classID, specID); -- also clears the viewer's state
    TalentViewer:ClearLevelingBuild()
    TalentViewer:StopRecordingLevelingBuild();

    TalentViewer:ImportLevelingBuild(levelingOrder);
    TalentViewer:ApplyLevelingBuild(TalentViewer:GetCurrentLevelingBuildID(), ns.MAX_LEVEL, true);
end

--- @param url string
--- @return nil|number # classID
--- @return nil|number # specID
--- @return nil|TalentViewer_LevelingBuild
function IcyVeinsImport:ParseUrl(url)
    local dataSection = url:match('#(.*)');
    dataSection = dataSection:gsub(':', '/'); -- IcyVeins uses base64 with `:`, whereas wow uses `/`

    local specIDString, classString, specString, heroString, pvpString = string.split('-', dataSection);
    local specIDStream = ExportUtil.MakeImportDataStream(specIDString);
    local specID = tonumber(specIDStream:ExtractValue(self.bitWidthSpecID));
    local classID = specID and C_SpecializationInfo.GetClassIDFromSpecID(specID);

    local treeID = classID and LibTT:GetClassTreeId(classID);

    if not classID or not specID or not classString or not specString or not treeID then
        return nil;
    end
    local classStream = ExportUtil.MakeImportDataStream(classString);
    local specStream = ExportUtil.MakeImportDataStream(specString);
    local heroStream = ExportUtil.MakeImportDataStream(heroString);
    local selectedSubTreeID;
    if heroStream:GetNumberOfBits() > 0 then
        local heroTreeIndex = heroStream:ExtractValue(1) + 1;
        selectedSubTreeID = LibTT:GetSubTreeIDsForSpecID(specID)[heroTreeIndex];
    end

    local classNodes, specNodes, heroNodes = self:GetClassAndSpecNodeIDs(specID, treeID, selectedSubTreeID);

    local levelingBuild = { entries = {}, selectedSubTreeID = selectedSubTreeID };
    levelingBuild.entries[1] = self:ParseDataSegment(10, 2, classStream, classNodes);
    levelingBuild.entries[2] = self:ParseDataSegment(11, 2, specStream, specNodes);
    if heroNodes and selectedSubTreeID then
        levelingBuild.entries[selectedSubTreeID] = self:ParseDataSegment(71, 1, heroStream, heroNodes);
    end

    return classID, specID, levelingBuild;
end

--- @param startingLevel number
--- @param levelMultiplier number
--- @param dataStream ImportDataStreamMixin
--- @param nodes number[]
--- @return table<number, TalentViewer_LevelingBuildEntry> # [level] = entry
--- @private
function IcyVeinsImport:ParseDataSegment(startingLevel, levelMultiplier, dataStream, nodes)
    local level = startingLevel;
    local rankByNodeID = {};
    local levelingOrder = {};

    while (dataStream:GetNumberOfBits() - dataStream.currentExtractedBits) > self.bitWidthNodeIndex do
        local success, nodeIndex = pcall(function() return dataStream:ExtractValue(self.bitWidthNodeIndex); end);
        if not success or not nodeIndex then break; end

        nodeIndex = nodeIndex + 1; -- 0-based to 1-based
        local nodeID = nodes[nodeIndex];
        if not nodeID then
            print(L['Error while importing IcyVeins URL: Could not find node for index'], nodeIndex);
            if DevTool and DevTool.AddData then
                DevTool:AddData({
                    nodeIndex = nodeIndex,
                    nodes = nodes,
                }, 'Error while importing IcyVeins URL: Could not find node for index')
            end
        else
            local nodeInfo = LibTT:GetNodeInfo(nodeID);
            local isChoiceNode = nodeInfo.type == Enum.TraitNodeType.Selection or nodeInfo.type == Enum.TraitNodeType.SubTreeSelection;
            local entry
            if isChoiceNode then
                local choiceIndex = dataStream:ExtractValue(1) + 1;
                entry = nodeInfo.entryIDs and nodeInfo.entryIDs[choiceIndex] or nil;
            end
            rankByNodeID[nodeID] = (rankByNodeID[nodeID] or 0) + 1;

            levelingOrder[level] = {
                nodeID = nodeID,
                entryID = entry,
                targetRank = rankByNodeID[nodeID],
            };
            level = level + levelMultiplier;
        end
    end

    return levelingOrder;
end

--- @private
IcyVeinsImport.classAndSpecNodeCache = {};
--- @param specID number
--- @param treeID number
--- @param selectedSubTreeID number?
--- @return number[], number[], nil|number[] # classNodes, specNodes, heroNodes (if applicable)
--- @private
function IcyVeinsImport:GetClassAndSpecNodeIDs(specID, treeID, selectedSubTreeID)
    if self.classAndSpecNodeCache[specID] then
        local classNodes, specNodes, heroNodesByTree = unpack(self.classAndSpecNodeCache[specID]);
        return classNodes, specNodes, heroNodesByTree[selectedSubTreeID] or nil;
    end

    local nodes = C_Traits.GetTreeNodes(treeID);

    local classNodes = {};
    local specNodes = {};
    local heroNodesByTree = {};

    for _, nodeID in ipairs(nodes or {}) do
        local nodeInfo = LibTT:GetNodeInfo(nodeID);
        if LibTT:IsNodeVisibleForSpec(specID, nodeID) and nodeInfo.maxRanks > 0 then
            if nodeInfo.isSubTreeSelection then
                -- skip
            elseif nodeInfo.subTreeID then
                heroNodesByTree[nodeInfo.subTreeID] = heroNodesByTree[nodeInfo.subTreeID] or {};
                table.insert(heroNodesByTree[nodeInfo.subTreeID], nodeID);
            elseif nodeInfo.isClassNode then
                table.insert(classNodes, nodeID);
            else
                table.insert(specNodes, nodeID);
            end
        end
    end
    for _, subTreeNodes in pairs(heroNodesByTree) do
        table.sort(subTreeNodes);
    end

    table.sort(classNodes);
    table.sort(specNodes);

    self.classAndSpecNodeCache[specID] = {classNodes, specNodes, heroNodesByTree};

    return classNodes, specNodes, heroNodesByTree[selectedSubTreeID] or nil;
end

