WINDOW_MARGIN = 20

local buttonStyleColors = {
	{ ui.StyleColor.Button, rgbm(0.175, 0.175, 0.175, 1) },
	{ ui.StyleColor.ButtonHovered, rgbm(1, 0.1, 0.1, 0.7) },
	{ ui.StyleColor.ButtonActive, rgbm(0.1, 0.1, 0.1, 0.7) },
	{ ui.StyleColor.FrameBg, rgbm(0.2, 0.2, 0.2, 0.7) },
	{ ui.StyleColor.ScrollbarGrabActive, rgbm(1, 0.2, 0.7) },
}

function pushButtonStyle()
	for _i, colorStyle in pairs(buttonStyleColors) do
		ui.pushStyleColor(colorStyle[1], colorStyle[2])
	end
end

function popButtonStyle()
	ui.popStyleColor(#buttonStyleColors)
end
