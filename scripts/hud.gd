class_name PirateHud
extends CanvasLayer

signal host_pressed(port: int)
signal join_pressed(address: String, port: int)
signal quality_pressed(low: bool)

var menu: CenterContainer
var status: Label
var details: Label
var help: Label
var address_field: LineEdit
var port_field: LineEdit
var quality_button: Button
var is_low := false

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var top := PanelContainer.new()
	top.anchor_right = 1.0
	top.offset_bottom = 55.0
	top.add_theme_stylebox_override("panel", _panel(Color(0.045, 0.11, 0.17, 0.86)))
	root.add_child(top)
	var title := Label.new()
	title.text = "   ☠  GRAND SEA  •  ONE PIECE"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color(0.98, 0.81, 0.41))
	top.add_child(title)
	details = Label.new()
	details.anchor_left = 0.02
	details.anchor_top = 1.0
	details.offset_top = 8
	details.add_theme_font_size_override("font_size", 19)
	details.add_theme_color_override("font_color", Color(0.98, 0.95, 0.83))
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(details)
	help = Label.new()
	help.anchor_left = 0.02
	help.anchor_top = 1.0
	help.offset_top = -46
	help.text = "WASD • walk / sail   |   E • helm   |   F • shore / board   |   G • treasure   |   Mouse • camera   |   Esc • cursor"
	help.add_theme_color_override("font_color", Color(0.95, 0.91, 0.77))
	help.add_theme_font_size_override("font_size", 17)
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(help)
	menu = CenterContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(menu)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(430, 320)
	panel.add_theme_stylebox_override("panel", _panel(Color(0.05, 0.13, 0.20, 0.97)))
	menu.add_child(panel)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 12)
	panel.add_child(contents)
	var heading := Label.new()
	heading.text = "GRAND LINE • PIRATE ADVENTURE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 23)
	heading.add_theme_color_override("font_color", Color(0.99, 0.78, 0.31))
	contents.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "Explore an open ocean. Find the One Piece."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	contents.add_child(subtitle)
	address_field = LineEdit.new()
	address_field.text = "127.0.0.1"
	address_field.placeholder_text = "Server IP (LAN)"
	contents.add_child(address_field)
	port_field = LineEdit.new()
	port_field.text = "7777"
	port_field.placeholder_text = "UDP port"
	contents.add_child(port_field)
	var host_button := Button.new()
	host_button.text = "HOST GAME ON THIS PC"
	host_button.custom_minimum_size.y = 42
	contents.add_child(host_button)
	host_button.pressed.connect(func() -> void:
		host_pressed.emit(_port()))
	var join_button := Button.new()
	join_button.text = "JOIN FRIEND'S GAME"
	join_button.custom_minimum_size.y = 42
	contents.add_child(join_button)
	join_button.pressed.connect(func() -> void:
		join_pressed.emit(address_field.text, _port()))
	quality_button = Button.new()
	quality_button.text = "GRAPHICS: NORMAL"
	contents.add_child(quality_button)
	quality_button.pressed.connect(_toggle_quality)
	status = Label.new()
	status.text = "Native game • ENet/UDP • local multiplayer"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Color(0.82, 0.89, 0.91))
	contents.add_child(status)
	details.visible = false
	help.visible = false

func _panel(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	return style

func _port() -> int:
	var port := port_field.text.to_int()
	return clampi(port, 1024, 65535)

func _toggle_quality() -> void:
	is_low = not is_low
	quality_button.text = "GRAPHICS: LOW" if is_low else "GRAPHICS: NORMAL"
	quality_pressed.emit(is_low)

func show_error(message: String) -> void:
	status.text = message
	status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))

func show_connected() -> void:
	menu.visible = false
	details.visible = true
	help.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func show_disconnected(message: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.visible = true
	details.visible = false
	help.visible = false
	show_error(message)

func update_details(speed: float, location: String, players: int,
		distance: float, is_helm: bool, gold: int, found: bool) -> void:
	var role := "STEERING" if is_helm else "CREW"
	var treasure := "FOUND!" if found else "%.1f km" % (distance / 1000.0)
	details.text = "  %s  |  %.0f m/s  |  %d pirates  |  Gold %d  |  One Piece %s  |  %s" % [
		location, absf(speed), players, gold, treasure, role]
