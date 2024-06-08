local _, ns = ...;

ns.mixins = ns.mixins or {};

--- @class TalentViewer_LevelingOrderFrameTWW: Frame
local LevelingOrderMixin = {};

ns.mixins.LevelingOrderMixin = LevelingOrderMixin;

--- @param order number[]
function LevelingOrderMixin:SetOrder(order)
    self.order = CopyTable(order);
    self:UpdateText();
end
--- @param level number
function LevelingOrderMixin:AppendToOrder(level)
    table.insert(self.order, level);
    self:UpdateText();
end
function LevelingOrderMixin:RemoveLastOrder()
    for i = #self.order, 1, -1 do
        if self.order[i] then
            table.remove(self.order, i);
            break;
        end
    end
    self:UpdateText();
end
function LevelingOrderMixin:UpdateOrder(oldLevel, newLevel)
    for i, level in ipairs(self.order) do
        if level == oldLevel then
            self.order[i] = newLevel;
            break;
        end
    end
    self:UpdateText();
end
function LevelingOrderMixin:UpdateText()
    self.Text:SetText(table.concat(self.order, ' '));
end
--- @return number[]
function LevelingOrderMixin:GetOrder()
    return CopyTable(self.order);
end