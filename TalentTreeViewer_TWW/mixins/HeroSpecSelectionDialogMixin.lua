local _, ns = ...;

ns.mixins = ns.mixins or {};

TalentViewer_HeroSpecSelectionDialogMixin = {};
local dialogMixin = TalentViewer_HeroSpecSelectionDialogMixin;

setmetatable(dialogMixin, { __index = function() return nop end });

function dialogMixin:IsActive() return false; end
