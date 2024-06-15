local _, ns = ...;

ns.mixins = ns.mixins or {};

--- default UI uses this mixin to handle the dialog for selecting a hero spec, but we don't like that popup, and just show it in the main UI instead
TalentViewer_HeroSpecSelectionDialogMixin = {};
local dialogMixin = TalentViewer_HeroSpecSelectionDialogMixin;

setmetatable(dialogMixin, { __index = function() return nop end });

function dialogMixin:IsActive() return false; end
