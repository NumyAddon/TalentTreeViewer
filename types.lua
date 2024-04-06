--- inherits ClassTalentTalentsTabMixin
--- @class TalentViewerUIMixin: FRAME
--- @field EnumerateAllTalentButtons fun(): fun(): TalentViewer_TalentButtonMixin
--- @field GetTalentButtonByNodeID fun(self: TalentViewerUIMixin, nodeID: number): TalentViewer_TalentButtonMixin
--- @field StartRecordingButton BUTTON
--- @field StopRecordingButton BUTTON
--- @field LevelingBuildLevelSlider SLIDER
--- @field LevelingBuildDropDownButton BUTTON

--- @class TalentViewer_TalentButtonMixin: BUTTON
--- @field talentFrame TalentViewerUIMixin
--- @field LevelingOrder TalentViewer_LevelingOrderFrame
--- @field GetNodeID fun(): number

--- @class TalentViewer_LevelingOrderFrame: FRAME
--- @field Text FontString
--- @field order number[]
--- @field GetParent fun(): TalentViewer_TalentButtonMixin

--- @class TalentViewer_LevelingBuildEntry
--- @field nodeID number
--- @field entryID ?number # Only present for choice nodes
--- @field targetRank number

--- @class TalentViewer_LoadoutEntryInfo
--- @field nodeID number
--- @field ranksPurchased number
--- @field selectionEntryID number
--- @field isChoiceNode boolean

