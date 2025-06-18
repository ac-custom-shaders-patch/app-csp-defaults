---@class StateSaver
---@field private undoStack table[]
---@field private redoStack table[]
---@field private storeCallback fun(): any
---@field private restoreCallback fun(data: any)
local StateSaver = class('StateSaver')

---@param storeCallback fun(): any
---@param restoreCallback fun(data: any)
---@return StateSaver
function StateSaver.allocate(storeCallback, restoreCallback)
  return {
    undoStack = {},
    redoStack = {},
    storeCallback = storeCallback,
    restoreCallback = restoreCallback,
  }
end

function StateSaver:reset()
  table.clear(self.undoStack)
  table.clear(self.redoStack)
end

function StateSaver:store()
  if #self.undoStack > 200 then
    table.remove(self.undoStack, 1)
  end
  table.clear(self.redoStack)
  table.insert(self.undoStack, self.storeCallback())
end

function StateSaver:undo()
  if #self.undoStack > 0 then
    table.insert(self.redoStack, self.storeCallback())
    self.restoreCallback(table.remove(self.undoStack, #self.undoStack))
  end
end

function StateSaver:canUndo()
  return #self.undoStack > 0
end

function StateSaver:redo()
  if #self.redoStack > 0 then
    table.insert(self.undoStack, self.storeCallback())
    self.restoreCallback(table.remove(self.redoStack, #self.redoStack))
  end
end

function StateSaver:canRedo()
  return #self.redoStack > 0
end

return class.emmy(StateSaver, StateSaver.allocate)