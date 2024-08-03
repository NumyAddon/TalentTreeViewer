---@meta _

--- inherits ClassTalentTalentsTabMixin
--- @class TalentViewerUIMixinTWW: FRAME
--- @field EnumerateAllTalentButtons fun(): fun(): TalentViewer_TalentButtonMixinTWW
--- @field GetTalentButtonByNodeID fun(self: TalentViewerUIMixinTWW, nodeID: number): nil|TalentViewer_TalentButtonMixinTWW
--- @field StartRecordingButton BUTTON
--- @field StopRecordingButton BUTTON
--- @field LevelingBuildLevelSlider SLIDER
--- @field LevelingBuildDropDownButton BUTTON

--- @class TalentViewer_TalentButtonMixinTWW: BUTTON
--- @field talentFrame TalentViewerUIMixinTWW
--- @field LevelingOrder TalentViewer_LevelingOrderFrameTWW
--- @field GetNodeID fun(): number
--- @field GetNodeInfo fun(): TVNodeInfo

--- @class TalentViewer_LevelingOrderFrameTWW: FRAME
--- @field Text FontString
--- @field order number[]
--- @field GetParent fun(): TalentViewer_TalentButtonMixinTWW

--- @class TalentViewer_LevelingBuildInfoContainer
--- @field entries table<number, TalentViewer_LevelingBuildEntry[]> # [tree] = entries, where tree is 1 for class, 2 for spec, or tree is SubTreeID for hero specs; entries are indexed by order, not level
--- @field startingOffset table<number, number> # [specOrClass] = startingOffset (specOrClass is 1 for class, 2 for spec); so that level = startingOffset + (index * 2)
--- @field selectedSubTreeID number? # Selected Hero Spec ID, if any
--- @field entriesCount number # Total number of entries in the leveling build, to simplify checking if it's empty

--- @class TalentViewer_LevelingBuildEntry
--- @field nodeID number
--- @field entryID ?number # Only present for choice nodes
--- @field targetRank number # for choice nodes, this is always 1

--- @class TalentViewer_LevelingBuild
--- @field entries table<number, table<number, TalentViewer_LevelingBuildEntry>> # [tree] = {[level] = entry}, where tree is 1 for class, 2 for spec, or tree is SubTreeID for hero specs
--- @field selectedSubTreeID number? # Selected Hero Spec ID, if any

--- @class TalentViewer_LoadoutEntryInfo
--- @field nodeID number
--- @field ranksPurchased number
--- @field selectionEntryID number
--- @field isChoiceNode boolean

-------------------
----- FrameXML ----
-------------------

---[FrameXML](https://www.townlong-yak.com/framexml/go/ImportDataStreamMixin)
---@class ImportDataStreamMixin
---@field dataValues number[]
---@field currentIndex number
---@field currentExtractedBits number
---@field currentRemainingValue number
ImportDataStreamMixin = {}

---[FrameXML](https://www.townlong-yak.com/framexml/go/ImportDataStreamMixin:Init)
---@param exportString string
function ImportDataStreamMixin:Init(exportString) end

---[FrameXML](https://www.townlong-yak.com/framexml/go/ImportDataStreamMixin:ExtractValue)
---@param bitWidth number
---@return number?
function ImportDataStreamMixin:ExtractValue(bitWidth) end

---[FrameXML](https://www.townlong-yak.com/framexml/go/ImportDataStreamMixin:GetNumberOfBits)
---@return number
function ImportDataStreamMixin:GetNumberOfBits() end

---[FrameXML](https://www.townlong-yak.com/framexml/go/ExportUtil.MakeImportDataStream)
---@param exportString string
---@return ImportDataStreamMixin
function ExportUtil.MakeImportDataStream(exportString) end
