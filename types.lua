--- @class TalentViewerUIMixin: FRAME
--- @field EnumerateAllTalentButtons fun(): fun(): TalentViewer_TalentButtonMixin
--- @field GetTalentButtonByNodeID fun(nodeID: number): TalentViewer_TalentButtonMixin
--- @field StartRecordingButton BUTTON
--- @field StopRecordingButton BUTTON

--- @class TalentViewer_TalentButtonMixin: BUTTON
--- @field talentFrame TalentViewerUIMixin
--- @field LevelingOrder TalentViewer_LevelingOrderFrame

--- @class TalentViewer_LevelingOrderFrame: FRAME
--- @field Text FontString
--- @field order number[]

--- @class TalentViewer_LevelingBuildEntry
--- @field nodeID number
--- @field entryID ?number # Only present for choice nodes
--- @field targetRank number

