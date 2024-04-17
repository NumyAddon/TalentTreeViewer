local name, ns = ...

--- @class TalentViewerIcyVeinsImport
local IcyVeinsImport = ns.IcyVeinsImport

--- @type TalentViewer
local TalentViewer = ns.TalentViewer

local skillMappings = tInvert{'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'Ă', 'ă', 'Â', 'â', 'Î', 'î', 'Ș', 'ș', 'Ț', 'ț', 'ë', 'é', 'ê', 'ï', 'ô', 'β', 'Γ', 'γ', 'Δ', 'δ', 'ε', 'ζ'};

--- @type LibTalentTree-1.0
local libTT = LibStub('LibTalentTree-1.0');

local L = LibStub('AceLocale-3.0'):GetLocale(name)

--- @param text string
--- @return boolean
function IcyVeinsImport:IsTalentUrl(text)
    -- example URL https://www.icy-veins.com/wow/dragonflight-talent-calculator#6--250$foo+bar*
    return not not text:match('^https?://www%.icy%-veins%.com/wow/dragonflight%-talent%-calculator%#%d+%-%-%d+%$[^+]-%+[^*]-%*');
end

function IcyVeinsImport:ShowImportError(errorString)
    StaticPopup_Show("TALENT_VIEWER_LOADOUT_IMPORT_ERROR_DIALOG", errorString);
end

--- @param fullUrl string
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
    TalentViewer:StartRecordingLevelingBuild(); -- just to be sure ;)

    TalentViewer:ImportLevelingBuild(levelingOrder);
    TalentViewer:ApplyLevelingBuild(TalentViewer:GetCurrentLevelingBuildID(), ns.MAX_LEVEL, true);
end

--- @param url string
--- @return nil|number # classID
--- @return nil|number # specID
--- @return nil|table<number, TalentViewer_LevelingBuildEntry> # [level] = entry
function IcyVeinsImport:ParseUrl(url)
    local dataSection = url:match('#(.*)');

    local classID, specID, classData, specData = dataSection:match('^(%d+)%-%-(%d+)%$([^+]-)%+([^*]-)%*');
    classID = tonumber(classID);
    specID = tonumber(specID);

    local treeID = classID and libTT:GetClassTreeId(classID);

    if not classID or not specID or not classData or not specData then
        return nil;
    end

    local classNodes, specNodes = self:GetClassAndSpecNodeIDs(specID, treeID);

    local levelingOrder = {};
    self:ParseDataSegment(8, classData, levelingOrder, classNodes);
    self:ParseDataSegment(9, specData, levelingOrder, specNodes);

    return classID, specID, levelingOrder;
end

function IcyVeinsImport:ParseDataSegment(startingLevel, dataSegment, levelingOrder, nodes)
    local splitDataSegment = {};
    for char in string.gmatch(dataSegment, '.') do
        table.insert(splitDataSegment, char);
    end
    local level = startingLevel;
    local rankByNodeID = {};
    for index, char in ipairs(splitDataSegment) do
        if char ~= '0' and char ~= '1' then
            level = level + 2;
            local nextChar = splitDataSegment[index + 1];
            local mappingIndex = skillMappings[char];

            local nodeID = nodes[mappingIndex];
            if not nodeID then
                print(L['Error while importing IcyVeins URL: Could not find node for mapping index'], mappingIndex);
                if DevTool and DevTool.AddData then
                    DevTool:AddData({
                        mappingIndex = mappingIndex,
                        char = char,
                        nextChar = nextChar,
                        index = index,
                        dataSegment = dataSegment,
                        splitDataSegment = splitDataSegment,
                        nodes = nodes,
                    }, 'Error while importing IcyVeins URL: Could not find node for mapping index')
                end
            else
                local entryIndex = nextChar == '1' and 2 or 1;
                local nodeInfo = libTT:GetNodeInfo(nodeID);
                local entry = nodeInfo.type == Enum.TraitNodeType.Selection and nodeInfo.entryIDs and nodeInfo.entryIDs[entryIndex] or nil;
                rankByNodeID[nodeID] = (rankByNodeID[nodeID] or 0) + 1;

                levelingOrder[level] = {
                    nodeID = nodeID,
                    entryID = entry,
                    targetRank = rankByNodeID[nodeID],
                };
            end
        end
    end
end

IcyVeinsImport.classAndSpecNodeCache = {};
function IcyVeinsImport:GetClassAndSpecNodeIDs(specID, treeID)
    if self.classAndSpecNodeCache[specID] then
        return unpack(self.classAndSpecNodeCache[specID]);
    end

    local nodes = C_Traits.GetTreeNodes(treeID);

    local classNodes = {};
    local specNodes = {};

    for _, nodeID in ipairs(nodes or {}) do
        local nodeInfo = libTT:GetNodeInfo(nodeID);
        if libTT:IsNodeVisibleForSpec(specID, nodeID) and nodeInfo.maxRanks > 0 then
            if nodeInfo.isClassNode then
                table.insert(classNodes, nodeID);
            else
                table.insert(specNodes, nodeID);
            end
        end
    end

    table.sort(classNodes);
    table.sort(specNodes);

    self.classAndSpecNodeCache[specID] = {classNodes, specNodes};

    return classNodes, specNodes;
end

