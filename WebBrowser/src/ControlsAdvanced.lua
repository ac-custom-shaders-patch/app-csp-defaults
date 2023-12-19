local ControlsInputFeatures = require('src/ControlsInputFeatures')
local Icons = require('src/Icons')

---@param label string
---@param value string?
---@param hintTab WebBrowser?
---@return string
local function searchBar(label, value, hintTab)
  ui.setNextItemWidth(-0.1)

  ui.pushStyleColor(ui.StyleColor.FrameBg, rgbm(0, 0, 0, 0.4))
  ui.pushStyleVar(ui.StyleVar.FrameRounding, 20)
  ui.pushStyleVar(ui.StyleVar.FramePadding, vec2(20, 8))
  value = ui.inputText(label, value or '', ui.InputTextFlags.Placeholder)
  ui.popStyleColor()
  ui.popStyleVar(2)
  ControlsInputFeatures.inputContextMenu(hintTab)

  if value ~= '' then
    ui.sameLine(0, 0)
    ui.offsetCursorX(-32)
    ui.setItemAllowOverlap()
    ui.offsetCursorY(4)
    ui.pushStyleColor(ui.StyleColor.Button, rgbm.colors.transparent)
    ui.pushStyleVar(ui.StyleVar.FrameRounding, 11)
    if ui.iconButton(Icons.Cancel, 22, 7, true, ui.ButtonFlags.PressedOnClick) then
      value = ''
      ui.setKeyboardFocusHere(-1)
    end
    if ui.itemHovered() then
      ui.setMouseCursor(ui.MouseCursor.Arrow)
    end
    ui.offsetCursorY(-4)
    ui.popStyleColor()
    ui.popStyleVar()
  end
  return value
end

return {
  searchBar = searchBar
}
