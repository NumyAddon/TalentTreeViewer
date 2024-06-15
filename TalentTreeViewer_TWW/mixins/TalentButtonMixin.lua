local _, ns = ...;

ns.mixins = ns.mixins or {};

--- @class TalentViewer_TalentButtonMixinTWW
local TalentButtonMixin = {};
ns.mixins.TalentButtonMixin = TalentButtonMixin;

function TalentButtonMixin:IsInDeactivatedSubTree()
    return false;
end

function TalentButtonMixin:UpdateSubTreeActiveVisual(isActive)
    self:SetAlpha(isActive and 1 or 0.5);
end

function TalentButtonMixin:OnClick(button)
    EventRegistry:TriggerEvent('TalentButton.OnClick', self, button);

    if button == 'LeftButton' and self:CanPurchaseRank() then
        self:PurchaseRank();
    elseif button == 'RightButton' and self:CanRefundRank() then
        self:RefundRank();
    end
end

function TalentButtonMixin:PurchaseRank()
    --- @type TalentViewerUIMixinTWW
    local talentFrame = self.talentFrame;
    self:PlaySelectSound();
    talentFrame:PurchaseRank(self:GetNodeID());
end

function TalentButtonMixin:RefundRank()
    --- @type TalentViewerUIMixinTWW
    local talentFrame = self.talentFrame;
    self:PlayDeselectSound();
    talentFrame:RefundRank(self:GetNodeID());
end

function TalentButtonMixin:ShowActionBarHighlights()
    TalentViewer:SetActionBarHighlights(self, true);
end

function TalentButtonMixin:HideActionBarHighlights()
    TalentViewer:SetActionBarHighlights(self, false);
end
