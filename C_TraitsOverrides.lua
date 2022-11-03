local _, ns = ...;

--- @type TalentViewer
local TalentViewer = ns.TalentViewer;
if not TalentViewer then return; end

---@type LibTalentTree
local LibTalentTree = LibStub('LibTalentTree-1.0');

local MAX_LEVEL_CLASS_CURRENCY_CAP = 31;
local MAX_LEVEL_SPEC_CURRENCY_CAP = 30;

local function override(object, func, replacement)
    object = object or _G;
    local original = object[func];
    object[func] = function(...)
        return replacement(original, ...);
    end;
end

override(C_Traits, 'GetTreeInfo', function(originalFunc, configID, treeID)
    if configID ~= TalentViewer.customConfigID then
        return originalFunc(configID, treeID);
    end

    return {};
end);

local currencyCache = {};
override(C_Traits, 'GetTreeCurrencyInfo', function(originalFunc, ...)
    local configID, treeID, _ = ...;
    if configID ~= TalentViewer.customConfigID then
        return originalFunc(...);
    end

    local specID = TalentViewer.selectedSpecId;
    if not currencyCache[specID] then
        currencyCache[specID] = {};
        local gates = LibTalentTree:GetGates(specID);
        for _, gate in ipairs(gates) do
            local nodeInfo = LibTalentTree:GetLibNodeInfo(treeID, gate.topLeftNodeID);
            if nodeInfo.isClassNode then
                currencyCache[specID][1] = {
                    maxQuantity = MAX_LEVEL_CLASS_CURRENCY_CAP,
                    quantity = MAX_LEVEL_CLASS_CURRENCY_CAP,
                    spent = 0,
                    traitCurrencyID = gate.traitCurrencyID,
                };
            else
                currencyCache[specID][2] = {
                    maxQuantity = MAX_LEVEL_SPEC_CURRENCY_CAP,
                    quantity = MAX_LEVEL_SPEC_CURRENCY_CAP,
                    spent = 0,
                    traitCurrencyID = gate.traitCurrencyID
                };
            end
        end
    end

    return currencyCache[specID];
end);

override(C_Traits, 'GetNodeCost', function(originalFunc, ...)
    local configID, nodeID = ...;
    if configID ~= TalentViewer.customConfigID then
        return originalFunc(...);
    end

    local treeID = TalentViewer.treeId;
    local currencyInfo = C_Traits.GetTreeCurrencyInfo(configID, treeID, true);
    local nodeInfo = LibTalentTree:GetLibNodeInfo(treeID, nodeID);
    local currencyID;
    if nodeInfo.isClassNode then
        currencyID = currencyInfo[1].traitCurrencyID;
    else
        currencyID = currencyInfo[2].traitCurrencyID;
    end

    return {
        {
            ID = currencyID,
            amount = 1,
        },
    }
end);

override(C_Traits, 'GetConditionInfo', function(originalFunc, ...)
    local configID, condID = ...;
    if configID ~= TalentViewer.customConfigID then
        return originalFunc(...);
    end

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
            condInfo.spentAmountRequired = gateInfo.spentAmountRequired;
            condInfo.traitCurrencyID = gateInfo.traitCurrencyID;
            break;
        end
    end

    return condInfo;
end);
