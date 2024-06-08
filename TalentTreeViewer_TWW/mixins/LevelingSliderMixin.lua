local _, ns = ...;

ns.mixins = ns.mixins or {};

--- @type TalentViewerTWW
local TalentViewer = ns.TalentViewer;
if not TalentViewer then return; end

--- @class TalentViewer_LevelingSliderMixinTWW
TalentViewer_LevelingSliderMixin = CreateFromMixins(MinimalSliderWithSteppersMixin);
--- @class TalentViewer_LevelingSliderMixinTWW
local LevelingSliderMixin = TalentViewer_LevelingSliderMixin;
LevelingSliderMixin:GenerateCallbackEvents(
    {
        'OnDragStop',
        'OnStepperClicked',
        'OnEnter',
        'OnLeave',
    }
);

function LevelingSliderMixin:GetValue()
    return self.Slider:GetValue();
end

function LevelingSliderMixin:OnStepperClicked(...)
    MinimalSliderWithSteppersMixin.OnStepperClicked(self, ...);
    self:TriggerEvent(self.Event.OnStepperClicked, ...);
end

function LevelingSliderMixin:OnLoad()
    MinimalSliderWithSteppersMixin.OnLoad(self);

    self.Slider:HookScript('OnEnter', function() self:TriggerEvent(self.Event.OnEnter); end);
    self.Slider:HookScript('OnLeave', function() self:TriggerEvent(self.Event.OnLeave); end);
    self.Slider:HookScript('OnMouseUp', function() self:TriggerEvent(self.Event.OnDragStop); end);
end
