---@meta _
---@diagnostic disable: duplicate-doc-field

--- inherits ClassTalentTalentsTabMixin
--- @class TalentViewer_ClassTalentsFrameTemplate: ClassTalentsFrameMixin, Frame, TalentFrameBaseTemplate
--- @field EnumerateAllTalentButtons fun(): fun(): TalentViewer_TalentButtonMixinTWW
--- @field GetTalentButtonByNodeID fun(self: TalentViewer_ClassTalentsFrameTemplate, nodeID: number): nil|TalentViewer_TalentButtonMixinTWW
--- @field heroSpecSelectionDialog TalentViewer_HeroSpecSelectionDialog
--- @field HeroTalentsContainer HeroTalentsContainerTemplate
--- @field ClassCurrencyDisplay TTV_ClassTalentCurrencyDisplayTemplate
--- @field HeroSpecCurrencyDisplay TTV_ClassTalentCurrencyDisplayTemplate
--- @field SpecCurrencyDisplay TTV_ClassTalentCurrencyDisplayTemplate
--- @field LoadSystem DropdownLoadSystemTemplate
--- @field TV_DropdownButton WowStyle1DropdownTemplate
--- @field linkButton TTV_NoTooltipButton
--- @field SearchBox SpellSearchBoxTemplate
--- @field SearchPreviewContainer SpellSearchPreviewContainerTemplate
--- @field ApplyButton TTV_NoTooltipButton
--- @field InspectCopyButton TTV_NoTooltipButton
--- @field ImportButton TTV_NoTooltipButton
--- @field ExportButton TTV_NoTooltipButton
--- @field ResetButton TTV_ResetButton
--- @field IgnoreRestrictions UICheckButtonTemplate
--- @field LevelingBuildHeader TTV_LevelingBuildHeader
--- @field StartRecordingButton IconButtonTemplate
--- @field StopRecordingButton IconButtonTemplate
--- @field ResetRecordingButton IconButtonTemplate
--- @field LevelingBuildDropdownButton WowStyle1DropdownTemplate
--- @field LevelingBuildLevelSlider TalentViewer_LevelingSlider
--- @field UndoButton IconButtonTemplate
--- @field PvPTalentSlotTray PvPTalentSlotTrayTemplate
--- @field PvPTalentList PvPTalentListTemplate

--- @class TalentViewer_DF: Frame, ButtonFrameTemplate
--- @field PortraitOverlay Frame
--- @field Talents TalentViewer_ClassTalentsFrameTemplate
TalentViewer_DF = {}

--- @class TTV_NoTooltipButton: Button, UIPanelButtonNoTooltipTemplate, UIButtonTemplate
--- @class TTV_ResetButton: DropdownButton, IconButtonTemplate

--- @class TTV_ClassTalentCurrencyDisplayTemplate: ClassTalentCurrencyDisplayTemplate
--- @field treeType TalentViewer_Enum_TreeType

--- @class TTV_LevelingBuildHeader: Frame
--- @field Text FontString

--- @class TalentViewer_TalentButtonMixinTWW: Button, TalentButtonBaseMixin
--- @field talentFrame TalentViewer_ClassTalentsFrameTemplate
--- @field LevelingOrder TalentViewer_LevelingOrderFrameTWW
--- @field GetNodeID fun(): number
--- @field GetNodeInfo fun(): TVNodeInfo

--- @class TalentViewer_LevelingOrderFrameTWW: Frame
--- @field Text FontString
--- @field order number[]
--- @field GetParent fun(): TalentViewer_TalentButtonMixinTWW

--- @class TalentViewer_LevelingBuildInfoContainer
--- @field active boolean
--- @field buildID number
--- @field entries table<number, TalentViewer_LevelingBuildEntry[]> # [tree] = entries, where tree is 1 for class, 2 for spec, or tree is SubTreeID for hero specs; entries are indexed by order, not level
--- @field currencyOffset table<number, number> # [tree] = currencyOffset, the amount of currency already spent before the first recorded entry
--- @field selectedSubTreeID number? # Selected Hero Spec ID, if any
--- @field entriesCount number # Total number of entries in the leveling build, to simplify checking if it's empty
--- @field buildReference TalentViewer_LevelingBuildInfoContainer? # Reference to the stored leveling build

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

--- @class TVNodeInfo: libNodeInfo
--- @field subTreeID nil # always nil in TVNodeInfo
--- @field tvSubTreeID number? # libNodeInfo.subTreeID
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
