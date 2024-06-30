--- inherits ClassTalentTalentsTabMixin
--- @class TalentViewerUIMixin: FRAME
--- @field EnumerateAllTalentButtons fun(): fun(): TalentViewer_TalentButtonMixin
--- @field GetTalentButtonByNodeID fun(self: TalentViewerUIMixin, nodeID: number): nil|TalentViewer_TalentButtonMixin
--- @field StartRecordingButton BUTTON
--- @field StopRecordingButton BUTTON
--- @field LevelingBuildLevelSlider SLIDER
--- @field LevelingBuildDropDownButton BUTTON

--- @class TalentViewer_TalentButtonMixin: BUTTON
--- @field talentFrame TalentViewerUIMixin
--- @field LevelingOrder TalentViewer_LevelingOrderFrame
--- @field GetNodeID fun(): number
--- @field GetNodeInfo fun(): TVNodeInfo

--- @class TalentViewer_LevelingOrderFrame: FRAME
--- @field Text FontString
--- @field order number[]
--- @field GetParent fun(): TalentViewer_TalentButtonMixin

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

