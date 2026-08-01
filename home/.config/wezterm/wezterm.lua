local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder()

local is_windows = os.getenv("OS") and os.getenv("OS"):lower():find("windows")
local is_macos = wezterm.target_triple:lower():find("darwin") ~= nil

-- ui
config.color_scheme = "rose-pine-moon"
config.max_fps = 120
config.font = wezterm.font("Hack Nerd Font", { weight = "Regular" })

config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"
config.window_frame = {
	font = wezterm.font("Hack Nerd Font", { weight = "Bold" }),
}
config.inactive_pane_hsb = {
	saturation = 0.0,
	brightness = 0.5,
}

-- Dim every pane in an unfocused window so the active window is obvious.
local UNFOCUSED_FOREGROUND_TEXT_HSB = { hue = 1.0, saturation = 0.25, brightness = 0.45 }
local UNFOCUSED_WINDOW_BACKGROUND_OPACITY = 0.62

local function same_text_hsb(actual, expected)
	if actual == nil or expected == nil then
		return actual == expected
	end
	return actual.hue == expected.hue
		and actual.saturation == expected.saturation
		and actual.brightness == expected.brightness
end

wezterm.on("window-focus-changed", function(window)
	local overrides = window:get_config_overrides() or {}
	local text_hsb, opacity
	if not window:is_focused() then
		text_hsb = UNFOCUSED_FOREGROUND_TEXT_HSB
		opacity = UNFOCUSED_WINDOW_BACKGROUND_OPACITY
	end

	if same_text_hsb(overrides.foreground_text_hsb, text_hsb)
		and overrides.window_background_opacity == opacity
	then
		return
	end

	overrides.foreground_text_hsb = text_hsb
	overrides.window_background_opacity = opacity
	window:set_config_overrides(overrides)
end)

-- 启动 login zsh，默认进入 home 目录
config.default_prog = { "/bin/zsh", "-l" }
config.default_cwd = wezterm.home_dir

-- 保留更多终端历史
config.scrollback_lines = 100000

-- 使用闪烁竖线光标
config.default_cursor_style = "BlinkingBar"
config.cursor_blink_rate = 500

-- 给窗口边缘留白
config.window_padding = {
	left = 8,
	right = 8,
	top = 8,
	bottom = 8,
}

-- 使用 WezTerm 全屏以保留透明和模糊效果
config.native_macos_fullscreen_mode = false

-- 简洁标签栏
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = false
config.tab_max_width = 32
config.show_new_tab_button_in_tab_bar = false
config.prefer_to_spawn_tabs = true

-- 识别可点击链接
config.hyperlink_rules = wezterm.default_hyperlink_rules()

-- 终端响铃时弹出系统通知(用于 Claude Code 等需要人工交互或已完成的提示)
wezterm.on("bell", function(window, pane)
	window:toast_notification("WezTerm", "Bell rang - check the terminal", nil, 4000)
end)

local rename_tab = act.PromptInputLine({
	description = "输入标签名称，例如 editor、tests 或 logs",
	action = wezterm.action_callback(function(window, _, line)
		if line and line ~= "" then
			window:active_tab():set_title(line)
		end
	end),
})

-- WezTerm 没有原生固定标签。用名称标记并移到最左侧来模拟固定。
local pin_tab = act.PromptInputLine({
	description = "输入固定标签名称",
	action = wezterm.action_callback(function(window, pane, line)
		if line and line ~= "" then
			window:active_tab():set_title("📌 " .. line)
			window:perform_action(act.MoveTab(0), pane)
		end
	end),
})

local switch_workspace = act.PromptInputLine({
	description = "输入 workspace 名称",
	action = wezterm.action_callback(function(window, pane, line)
		if line and line ~= "" then
			window:perform_action(act.SwitchToWorkspace({ name = line }), pane)
		end
	end),
})

wezterm.on("update-right-status", function(window, _)
	window:set_right_status(wezterm.format({
		{ Foreground = { Color = "#89b4fa" } },
		{ Attribute = { Intensity = "Bold" } },
		{ Text = "  " .. window:active_workspace() .. "  " },
	}))
end)

wezterm.on("format-tab-title", function(tab)
	local title = tab.tab_title
	if not title or title == "" then
		title = tab.active_pane.title
	end

	local text = string.format(" %d: %s ", tab.tab_index + 1, title)
	if tab.is_active then
		return {
			{ Background = { Color = "#89b4fa" } },
			{ Foreground = { Color = "#11111b" } },
			{ Attribute = { Intensity = "Bold" } },
			{ Text = text },
		}
	end

	return {
		{ Foreground = { Color = "#bac2de" } },
		{ Text = text },
	}
end)

-- 剪贴板、分屏和 pane 移动快捷键
config.keys = {
	{
		key = "c",
		mods = "CMD",
		action = wezterm.action.CopyTo("Clipboard"),
	},
	{
		key = "v",
		mods = "CMD",
		action = wezterm.action.PasteFrom("Clipboard"),
	},
	{
		key = "f",
		mods = "CTRL|CMD",
		action = wezterm.action.ToggleFullScreen,
	},
	{
		key = "|",
		mods = "CMD|SHIFT",
		action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }),
	},
	{
		key = "_",
		mods = "CMD|SHIFT",
		action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }),
	},
	{
		key = "h",
		mods = "CMD|SHIFT",
		action = wezterm.action.ActivatePaneDirection("Left"),
	},
	{
		key = "j",
		mods = "CMD|SHIFT",
		action = wezterm.action.ActivatePaneDirection("Down"),
	},
	{
		key = "k",
		mods = "CMD|SHIFT",
		action = wezterm.action.ActivatePaneDirection("Up"),
	},
	{
		key = "l",
		mods = "CMD|SHIFT",
		action = wezterm.action.ActivatePaneDirection("Right"),
	},
	{
		key = "r",
		mods = "CMD|ALT",
		action = rename_tab,
	},
	{
		key = "p",
		mods = "CMD|ALT",
		action = pin_tab,
	},
	{
		key = "w",
		mods = "CMD|ALT",
		action = switch_workspace,
	},
	{
		key = "f",
		mods = "CMD|ALT",
		action = act.ShowLauncherArgs({
			flags = "FUZZY|TABS|WORKSPACES",
			title = "搜索标签和 workspace",
		}),
	},
	{
		key = "z",
		mods = "CMD|ALT",
		action = act.TogglePaneZoomState,
	},
	{
		key = "[",
		mods = "CMD|ALT|SHIFT",
		action = act.MoveTabRelative(-1),
	},
	{
		key = "]",
		mods = "CMD|ALT|SHIFT",
		action = act.MoveTabRelative(1),
	},
	{
		key = "o",
		mods = "CMD|ALT",
		action = act.ActivateLastTab,
	},
}

if is_windows then
	config.win32_system_backdrop = "Acrylic"
	config.window_background_opacity = 0.7
	config.window_frame.font_size = 10.0
end

if is_macos then
	config.window_background_opacity = 0.8
	config.macos_window_background_blur = 50
	config.font_size = 15.0
	config.window_frame.font_size = 13.0
end

return config
