extends Node2D

# ---- Screen and layout ----
const W := 1080.0
const H := 1920.0
const CHUNK_H := 600.0
const BAR_H := 40.0
const GAP_MIN := 180.0
const GAP_MAX := 300.0
const FLIPPER_Y := 1700.0
const BALL_START := Vector2(540, 400)
const PARK_POS := Vector2(-500, -500)   # where the ball waits while the menu is open
const DEFAULT_GRAVITY := 0.3
const HUD_MARGIN := 30.0
const PAUSE_BTN_SIZE := Vector2(190, 90)
const MENU_W := 760.0                   # width of the main menu card
const PAUSE_W := 520.0                  # width of the pause card

# ---- Fonts (files in the project root) ----
const FONT_REGULAR_PATH := "res://redaction50.ttf"
const FONT_BOLD_PATH := "res://redaction50bold.ttf"

# ---- Visual style ----
const BG_COLOR := "#0b0e17"
const ZONE_COLORS := {0.15: "#2fb3a6", 0.3: "#3b82f6", 0.5: "#f04e5a"}   # teal, blue, red
const BAR_COLOR := "#3b82f6"
const GLOW_COLOR := Color(0.9, 0.24, 0.24)
const GLOW_HEIGHT := 60.0
const GLOW_RANGE := 500.0
const PIN_COLOR := "#f6ad55"
const LIFE_LOST_COLOR := "#e53e3e"
const TEXT := Color("#f2f4f8")
const MUTED := Color("#9aa3c7")
const ACCENT := Color("#3b82f6")
const BTN_BG := Color("#161b2b")
const BTN_HOVER := Color("#1f2740")
const BTN_PRESSED := Color("#0e1322")
const BTN_BORDER := Color("#2a3350")
const BAR_RADIUS := 8

# ---- Quality ----
const LOW_FPS := 40.0           # below this for LOW_FPS_SECONDS, switch to low effects
const LOW_FPS_SECONDS := 3.0

# ---- Speed tuning ----
const BASE_SPEED := 60.0
const MAX_SPEED := 360.0
const DRIVER_CAP := 180.0

# ---- Score ----
const SPEED_SCORE_RATE := 0.1   # points per (px/s) per second, so faster play scores more
const STAR_CHANCE := 0.6        # chance each star slot is filled
const STARS_PER_CHUNK := 2      # star slots per chunk
const STAR_CLEARANCE := 30.0    # how far a star must stay from any bar
const STAR_WHITE := 20.0
const STAR_GOLD := 50.0
const STAR_BLACK := 50.0        # taken off the score, and costs a life
const PICK_RADIUS := 42.0       # how close the ball must be to collect a star
const BEST_SAVE_SECONDS := 2.0  # how often a new best is written to disk during a run

# ---- Steering ----
const TILT_DEAD := 0.6
const TILT_FULL := 4.0
const TILT_SMOOTH := 0.15
const STEER_LEFT_RECT := Rect2(0, 1440, 300, 200)
const STEER_RIGHT_RECT := Rect2(780, 1440, 300, 200)

# ---- Collision layers ----
const LAYER_WORLD := 1
const LAYER_BARS := 2

# ---- Wedge tuning ----
const WEDGE_SPEED := 25.0
const WARN_TIME := 0.8
const WEDGE_TIME := 1.6
const STRUGGLE_SPEED := 140.0
const BREAK_HOLD := 0.25
const BREAK_TILT := 0.6
const KICK_SPEED := 260.0
const GRACE_TIME := 1.2
const LIFE_COOLDOWN := 1.0

# ---- Bar hit sound ----
const HIT_SOUND_COOLDOWN := 0.25
const HIT_SOUND_MIN_SPEED := 80.0

const BALL_STYLES := ["off_white", "silver", "black", "white"]

# ---- Saved settings ----
var settings: Dictionary = {}

# ---- Game state ----
var state := "menu"             # "menu", "play", or "paused"
var lives := 3
var time_played := 0.0
var obstacles_passed := 0       # drives the speed formula, not the score
var current_scroll_speed := BASE_SPEED
var score := 0.0
var run_start_best := 0         # best for this mode when the run started
var best_dirty := false         # a new best hasn't been written to disk yet
var best_save_timer := 0.0
var auto_low := false           # set when the frame rate stays low
var slow_time := 0.0            # seconds the frame rate has been low
var top_inset := 0.0            # space the notch takes, in game units

# ---- Runtime ----
var ball: Ball
var chunks: Array = []
var chunk_bars: Array = []      # Rect2 of each bar in the chunk being built
var left_flipper: Flipper
var right_flipper: Flipper
var tilt_smoothed := 0.0
var touches := {}               # finger index -> position (-1 = mouse)
var left_down := false
var right_down := false
var wedge_timer := 0.0
var grace_timer := 0.0
var break_timer := 0.0
var life_cooldown := 0.0
var hit_timer := 0.0
var sfx_players := {}           # sound name -> AudioStreamPlayer
var font_regular: FontFile
var font_bold: FontFile
var ui_theme: Theme
var hud: Label
var hud_panel: PanelContainer
var hud_layer: CanvasLayer
var pause_btn: Button
var menu_layer: CanvasLayer
var menu_card: PanelContainer
var pause_layer: CanvasLayer
var pause_card: PanelContainer
var status_label: Label
var best_label: Label
var play_btn: Button
var mode_btn: Button
var controls_btn: Button
var ball_btn: Button
var effects_btn: Button
var haptics_btn: Button

func _ready() -> void:
	randomize()
	get_tree().auto_accept_quit = false   # we handle close and back ourselves
	RenderingServer.set_default_clear_color(Color(BG_COLOR))
	settings = SettingsStore.load_settings()
	GameLog.info("Game started. Mode %s, controls %s, effects %s" % [
		settings.mode, settings.controls, settings.effects])
	_update_insets()
	_load_fonts()
	ui_theme = _build_theme()
	_make_walls()

	# Fill the screen, starting one chunk above the top
	for i in range(-1, 4):
		_spawn_chunk(i * CHUNK_H)

	ball = Ball.new()
	add_child(ball)
	ball.set_style(settings.ball)
	_park_ball()                # hidden and inactive while the menu is open

	left_flipper = Flipper.new()
	left_flipper.is_left = true
	left_flipper.position = Vector2(200, FLIPPER_Y)
	add_child(left_flipper)

	right_flipper = Flipper.new()
	right_flipper.is_left = false
	right_flipper.position = Vector2(W - 200, FLIPPER_Y)
	add_child(right_flipper)

	_build_hud()
	_build_menu()
	_build_pause()
	_build_sounds()
	_show_menu("")

# Read the notch and status bar area so the HUD stays visible.
# The safe area is in screen pixels, so divide by the stretch scale.
func _update_insets() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var scale := get_viewport().get_final_transform().get_scale().y
	if scale <= 0.0:
		scale = 1.0
	top_inset = float(safe.position.y) / scale

# Load the two font files from the project root
func _load_fonts() -> void:
	font_regular = load(FONT_REGULAR_PATH) as FontFile
	font_bold = load(FONT_BOLD_PATH) as FontFile
	if font_regular == null or font_bold == null:
		GameLog.error("Could not load the font files from the project root")

# One shared theme so every button and label matches
func _build_theme() -> Theme:
	var t := Theme.new()
	if font_regular != null:
		t.default_font = font_regular
	t.default_font_size = 36

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	if font_bold != null:
		t.set_font("font", "Button", font_bold)
	t.set_font_size("font_size", "Button", 40)
	t.set_stylebox("normal", "Button", _btn_style(BTN_BG, BTN_BORDER, 18))
	t.set_stylebox("hover", "Button", _btn_style(BTN_HOVER, BTN_BORDER, 18))
	t.set_stylebox("pressed", "Button", _btn_style(BTN_PRESSED, BTN_BORDER, 18))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	return t

# A rounded button background
func _btn_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s

# A rounded panel background with padding
func _panel_style(bg: Color, border: Color, radius: int, pad_x: float, pad_y: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 10
	return s

# A bar block: rounded, with a lighter top edge and a soft shadow
func _bar_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = color.lightened(0.35)
	s.border_width_top = 3
	s.set_corner_radius_all(BAR_RADIUS)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 3)
	return s

# HUD stats panel and the pause button
func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)

	hud_panel = PanelContainer.new()
	hud_panel.theme = ui_theme
	hud_panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.04, 0.06, 0.1, 0.72), BTN_BORDER, 18, 22, 14))
	hud_panel.position = Vector2(HUD_MARGIN, HUD_MARGIN + top_inset)
	hud_panel.visible = false
	hud_layer.add_child(hud_panel)

	hud = Label.new()
	hud.add_theme_font_size_override("font_size", 40)
	hud.add_theme_color_override("font_color", TEXT)
	hud_panel.add_child(hud)

	pause_btn = Button.new()
	pause_btn.theme = ui_theme
	pause_btn.text = "PAUSE"
	pause_btn.size = PAUSE_BTN_SIZE
	pause_btn.position = Vector2(W - PAUSE_BTN_SIZE.x - HUD_MARGIN, HUD_MARGIN + top_inset)
	pause_btn.add_theme_font_size_override("font_size", 32)
	pause_btn.pressed.connect(_pause_game)
	pause_btn.visible = false
	hud_layer.add_child(pause_btn)

# One short sound per event. Each has its own player, so sounds can overlap.
func _build_sounds() -> void:
	sfx_players = {
		"pin": _make_player(Sfx.tone(440.0, 880.0, 0.15)),
		"break": _make_player(Sfx.tone(660.0, 990.0, 0.12)),
		"life": _make_player(Sfx.tone(320.0, 120.0, 0.35)),
		"over": _make_player(Sfx.tone(260.0, 60.0, 0.8)),
		"click": _make_player(Sfx.tone(1200.0, 1200.0, 0.04, 0.2)),
		"star": _make_player(Sfx.tone(880.0, 1320.0, 0.12)),
		"hit": _make_player(Sfx.tone(200.0, 160.0, 0.05, 0.15)),
	}

func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -4.0
	add_child(p)
	return p

func _play(sound: String) -> void:
	if sfx_players.has(sound):
		sfx_players[sound].play()

# Phone and desktop lifecycle.
# Losing focus or pressing back pauses a run.
# Back on the pause menu ends the run. Closing the window always quits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if state == "play":
			_pause_game()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if state == "play":
			_pause_game()
		elif state == "paused":
			_on_quit()
		else:
			get_tree().quit()

# Touch tracking and the P key
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		if state == "play":
			_pause_game()
		elif state == "paused":
			_resume()
		return

	# Track each finger, and the mouse as index -1
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
		else:
			touches.erase(event.index)
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
	elif event is InputEventMouseButton:
		if event.pressed:
			touches[-1] = event.position
		else:
			touches.erase(-1)
	elif event is InputEventMouseMotion and touches.has(-1):
		touches[-1] = event.position

# Watch the frame rate during play. If it stays low, switch to low effects.
func _process(delta: float) -> void:
	if state != "play" or auto_low:
		return
	if Engine.get_frames_per_second() < LOW_FPS:
		slow_time += delta
		if slow_time >= LOW_FPS_SECONDS:
			auto_low = true
			GameLog.warning("Frame rate stayed under %d, switched to low effects" % int(LOW_FPS))
	else:
		slow_time = maxf(0.0, slow_time - delta)

# Main loop, 60 times per second
func _physics_process(delta: float) -> void:
	if state != "play":
		_update_hud()
		return

	time_played += delta
	life_cooldown = max(0.0, life_cooldown - delta)
	current_scroll_speed = PinballLogic.speed_for(
		time_played, obstacles_passed, BASE_SPEED, MAX_SPEED, DRIVER_CAP)
	score += current_scroll_speed * delta * SPEED_SCORE_RATE
	_update_best(delta)

	_read_tilt()
	_read_flippers()
	ball.trail_length = 0 if _effects_low() else Ball.TRAIL_LENGTH
	_update_chunks(delta)
	ball.gravity_scale = _gravity_at_ball()

	if ball.attached:
		_carry_ball(delta)
	else:
		_check_wedge(delta)
		_check_bar_hit(delta)

	_collect_stars()
	_keep_ball_on_screen()      # always runs last, so the ball is never left off screen

	queue_redraw()
	_update_hud()

# Keep the saved best up to date during a run, written at most every BEST_SAVE_SECONDS
func _update_best(delta: float) -> void:
	var now := int(score)
	if now > int(settings.best[settings.mode]):
		settings.best[settings.mode] = now
		best_dirty = true
	best_save_timer = maxf(0.0, best_save_timer - delta)
	if best_dirty and best_save_timer <= 0.0:
		SettingsStore.save_settings(settings)
		best_dirty = false
		best_save_timer = BEST_SAVE_SECONDS

# The ball must always be on screen.
# Above the top: lose a life (if allowed) and replace the ball.
# Far below the bottom (should never happen, the floor catches it): replace the ball.
func _keep_ball_on_screen() -> void:
	if state != "play":
		return
	if ball.position.y <= Ball.RADIUS:
		_lose_life()
	elif ball.position.y > H + 200.0:
		GameLog.warning("Ball fell past the floor, replacing it")
		_respawn_ball()

# Top-edge warning glow and, in Buttons mode, the faint steer buttons
func _draw() -> void:
	if state != "play":
		return
	if not _effects_low():
		var near := clampf(1.0 - ball.position.y / GLOW_RANGE, 0.0, 1.0)
		if near > 0.0:
			for i in range(4):
				var band_h := GLOW_HEIGHT * float(i + 1) / 4.0
				draw_rect(Rect2(0, 0, W, band_h), Color(GLOW_COLOR, near * 0.12))

	if settings.controls == "buttons":
		draw_rect(STEER_LEFT_RECT, Color(1, 1, 1, 0.08))
		draw_rect(STEER_RIGHT_RECT, Color(1, 1, 1, 0.08))

# Steering: phone tilt, or on-screen buttons. A and D work on the laptop.
func _read_tilt() -> void:
	var key := 0.0
	if Input.is_physical_key_pressed(KEY_A):
		key -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		key += 1.0

	var source := 0.0
	if settings.controls == "buttons":
		var right_held := 1.0 if _held_in(STEER_RIGHT_RECT) else 0.0
		var left_held := 1.0 if _held_in(STEER_LEFT_RECT) else 0.0
		source = right_held - left_held
	else:
		var raw := Input.get_gravity().x
		if abs(raw) < TILT_DEAD:
			raw = 0.0
		source = raw / TILT_FULL

	var target := clampf(source + key, -1.0, 1.0)
	tilt_smoothed = lerpf(tilt_smoothed, target, TILT_SMOOTH)
	ball.tilt = tilt_smoothed

# Flippers: Z and / on the laptop, screen halves on touch.
# Touches on the steer buttons or the pause button don't flip.
func _read_flippers() -> void:
	left_down = Input.is_physical_key_pressed(KEY_Z)
	right_down = Input.is_physical_key_pressed(KEY_SLASH)
	var pause_rect := Rect2(pause_btn.position, PAUSE_BTN_SIZE)
	for pos in touches.values():
		if pause_rect.has_point(pos):
			continue
		if settings.controls == "buttons":
			if STEER_LEFT_RECT.has_point(pos) or STEER_RIGHT_RECT.has_point(pos):
				continue
		if pos.x < W / 2.0:
			left_down = true
		else:
			right_down = true
	left_flipper.pressed = left_down
	right_flipper.pressed = right_down

# True if any finger or the mouse is inside the rect
func _held_in(rect: Rect2) -> bool:
	for pos in touches.values():
		if rect.has_point(pos):
			return true
	return false

# Decide whether the ball is stuck against a bar.
# Pinning works at any height, so a bar can't carry the ball to the ceiling unpinned.
func _check_wedge(delta: float) -> void:
	grace_timer = max(0.0, grace_timer - delta)
	var touching := _touching_bar()
	var stuck := PinballLogic.is_stuck_motion(
		ball.linear_velocity, current_scroll_speed, WEDGE_SPEED)
	var can_pin := grace_timer <= 0.0
	wedge_timer = PinballLogic.next_wedge_timer(wedge_timer, delta, touching, stuck, can_pin)
	if PinballLogic.should_pin(wedge_timer, WEDGE_TIME):
		ball.attach()
		GameLog.debug("Pinned at y=%d" % int(ball.position.y))
		_burst(ball.position, Color(PIN_COLOR), 14)
		_buzz(30)
		_play("pin")
		wedge_timer = 0.0
		break_timer = 0.0

# A thud when the ball hits a bar hard, with a cooldown so it doesn't repeat every frame
func _check_bar_hit(delta: float) -> void:
	hit_timer = maxf(0.0, hit_timer - delta)
	if hit_timer <= 0.0 and ball.linear_velocity.length() > HIT_SOUND_MIN_SPEED and _touching_bar():
		_play("hit")
		hit_timer = HIT_SOUND_COOLDOWN

func _touching_bar() -> bool:
	for b in ball.get_colliding_bodies():
		if b.is_in_group("chunk"):
			return true
	return false

# Pinned: the bar carries the ball up. Tilt lets it struggle sideways.
func _carry_ball(delta: float) -> void:
	ball.position.y -= current_scroll_speed * delta
	ball.position.x = clampf(
		ball.position.x + tilt_smoothed * STRUGGLE_SPEED * delta,
		Ball.RADIUS, W - Ball.RADIUS)

	if ball.position.y <= Ball.RADIUS:
		_lose_life()
		return

	var breaking := left_down or right_down or absf(tilt_smoothed) > BREAK_TILT
	break_timer = PinballLogic.next_break_timer(break_timer, delta, breaking)
	if PinballLogic.should_break_free(break_timer, BREAK_HOLD):
		_break_free()

# Release with a kick toward the side the player pushed
func _break_free() -> void:
	var dir := 1.0 if (right_down or tilt_smoothed > 0.0) else -1.0
	if left_down and not right_down:
		dir = -1.0
	ball.release(Vector2(dir * KICK_SPEED, 60.0))
	grace_timer = GRACE_TIME
	break_timer = 0.0
	_play("break")

# Take a life if the cooldown allows it. The out-of-bounds ball is always
# replaced by a fresh one, even during cooldown.
func _lose_life() -> void:
	if PinballLogic.can_lose_life(life_cooldown):
		life_cooldown = LIFE_COOLDOWN
		lives -= 1
		GameLog.warning("Life lost at y=%d, %d left" % [int(ball.position.y), lives])
		_burst(ball.position, Color(LIFE_LOST_COLOR), 24)
		_buzz(120)
		if lives <= 0:
			_play("over")
			_end_run("GAME OVER")
			return
		_play("life")
	_respawn_ball()

# Save the best score for this mode, park the ball, and return to the menu
func _end_run(title: String) -> void:
	var mode: String = settings.mode
	var final_score := int(score)
	var is_new_best := final_score > run_start_best
	if final_score > int(settings.best[mode]):
		settings.best[mode] = final_score
	SettingsStore.save_settings(settings)
	best_dirty = false
	GameLog.info("Run ended (%s): score %d, mode %s, new best %s" % [
		title, final_score, mode, str(is_new_best)])
	_park_ball()
	var message := "%s\nScore: %d" % [title, final_score]
	if is_new_best:
		message += "\nNEW BEST!"
	_show_menu(message)

# Open the pause card over the game. The run freezes until resumed.
func _pause_game() -> void:
	if state != "play":
		return
	state = "paused"
	pause_btn.visible = false
	GameLog.info("Paused")
	pause_layer.visible = true

# Close the pause card and carry on from where the run stopped
func _resume() -> void:
	state = "play"
	pause_layer.visible = false
	pause_btn.visible = true
	GameLog.info("Resumed")

# Quit a paused run back to the main menu
func _on_quit() -> void:
	_end_run("RUN ENDED")

# Park the ball during menus: hidden, off screen, no collisions
func _park_ball() -> void:
	ball.attached = false
	ball.freeze = true
	ball.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	ball.linear_velocity = Vector2.ZERO
	ball.angular_velocity = 0.0
	ball.position = PARK_POS
	ball.visible = false
	ball.collision_layer = 0
	ball.collision_mask = 0

# Remove an old ball completely: no collisions, hidden, then freed
func _retire_ball(old: Ball) -> void:
	old.attached = false
	old.freeze = true
	old.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	old.linear_velocity = Vector2.ZERO
	old.angular_velocity = 0.0
	old.collision_layer = 0
	old.collision_mask = 0
	old.visible = false
	old.queue_free()

# Low effects: the game has no burst particles
func _effects_low() -> bool:
	return settings.effects == "low" or auto_low

# A short burst of particles at a point. Removed after it finishes.
func _burst(pos: Vector2, color: Color, amount: int) -> void:
	if _effects_low():
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.6
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 260.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color = color
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

# Short vibration on phones, only when haptics are on
func _buzz(duration_ms: int) -> void:
	if settings.haptics:
		Input.vibrate_handheld(duration_ms)

# Show the main menu, with an optional message at the top
func _show_menu(message: String) -> void:
	state = "menu"
	menu_layer.visible = true
	pause_layer.visible = false
	pause_btn.visible = false
	status_label.text = message
	play_btn.text = "Play"
	_refresh_menu()

func _on_play() -> void:
	menu_layer.visible = false
	state = "play"
	pause_btn.visible = true
	_restart()

func _on_mode() -> void:
	settings.mode = "hard" if settings.mode == "simple" else "simple"
	_save_and_refresh()

func _on_controls() -> void:
	settings.controls = "buttons" if settings.controls == "tilt" else "tilt"
	_save_and_refresh()

func _on_ball() -> void:
	var i := BALL_STYLES.find(settings.ball)
	settings.ball = BALL_STYLES[(i + 1) % BALL_STYLES.size()]
	ball.set_style(settings.ball)
	_save_and_refresh()

func _on_effects() -> void:
	settings.effects = "low" if settings.effects == "full" else "full"
	_save_and_refresh()

func _on_haptics() -> void:
	settings.haptics = not settings.haptics
	_save_and_refresh()

func _save_and_refresh() -> void:
	SettingsStore.save_settings(settings)
	_refresh_menu()

func _refresh_menu() -> void:
	mode_btn.text = "Mode: %s" % String(settings.mode).capitalize()
	controls_btn.text = "Controls: %s" % ("Tilt" if settings.controls == "tilt" else "Buttons")
	ball_btn.text = "Ball: %s" % String(settings.ball).replace("_", " ").capitalize()
	effects_btn.text = "Effects: %s" % ("Full" if settings.effects == "full" else "Low")
	haptics_btn.text = "Haptics: %s" % ("On" if settings.haptics else "Off")
	best_label.text = "Best (Simple): %d    Best (Hard): %d" % [
		int(settings.best.simple), int(settings.best.hard)]

# Build the main menu once: a centred card with title, options, and bests
func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)

	menu_card = PanelContainer.new()
	menu_card.theme = ui_theme
	menu_card.add_theme_stylebox_override("panel",
		_panel_style(Color(0.05, 0.07, 0.12, 0.94), BTN_BORDER, 28, 40, 40))
	menu_card.position = Vector2((W - MENU_W) / 2.0, 330 + top_inset)
	menu_layer.add_child(menu_card)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(MENU_W - 80, 0)
	box.add_theme_constant_override("separation", 18)
	menu_card.add_child(box)

	var title := Label.new()
	title.text = "GRAVITY PINBALL"
	title.add_theme_font_size_override("font_size", 68)
	if font_bold != null:
		title.add_theme_font_override("font", font_bold)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 40)
	status_label.add_theme_color_override("font_color", Color(PIN_COLOR))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status_label)

	play_btn = _make_button(box, "Play", _on_play)
	play_btn.add_theme_stylebox_override("normal", _btn_style(ACCENT, ACCENT.lightened(0.25), 18))
	play_btn.add_theme_stylebox_override("hover", _btn_style(ACCENT.lightened(0.1), ACCENT.lightened(0.35), 18))
	mode_btn = _make_button(box, "", _on_mode)
	controls_btn = _make_button(box, "", _on_controls)
	ball_btn = _make_button(box, "", _on_ball)
	effects_btn = _make_button(box, "", _on_effects)
	haptics_btn = _make_button(box, "", _on_haptics)

	best_label = Label.new()
	best_label.add_theme_font_size_override("font_size", 34)
	best_label.add_theme_color_override("font_color", MUTED)
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(best_label)

# The pause card: only Resume and Quit to menu, almost see-through so the run shows behind it
func _build_pause() -> void:
	pause_layer = CanvasLayer.new()
	pause_layer.visible = false
	add_child(pause_layer)

	pause_card = PanelContainer.new()
	pause_card.theme = ui_theme
	pause_card.add_theme_stylebox_override("panel",
		_panel_style(Color(0.03, 0.05, 0.09, 0.35), Color(0.3, 0.36, 0.5, 0.4), 28, 36, 32))
	pause_card.position = Vector2((W - PAUSE_W) / 2.0, 760 + top_inset)
	pause_layer.add_child(pause_card)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(PAUSE_W - 72, 0)
	box.add_theme_constant_override("separation", 14)
	pause_card.add_child(box)

	var heading := Label.new()
	heading.text = "PAUSED"
	heading.add_theme_font_size_override("font_size", 52)
	heading.add_theme_color_override("font_color", Color(PIN_COLOR))
	if font_bold != null:
		heading.add_theme_font_override("font", font_bold)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)

	var resume_btn := _make_button(box, "Resume", _resume)
	resume_btn.custom_minimum_size = Vector2(PAUSE_W - 72, 84)
	_soft_button(resume_btn)

	var quit_btn := _make_button(box, "Quit to menu", _on_quit)
	quit_btn.custom_minimum_size = Vector2(PAUSE_W - 72, 84)
	_soft_button(quit_btn)

# Translucent button look for the pause card
func _soft_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _btn_style(Color(0.1, 0.13, 0.2, 0.45), Color(0.3, 0.36, 0.5, 0.5), 18))
	b.add_theme_stylebox_override("hover", _btn_style(Color(0.13, 0.17, 0.27, 0.6), Color(0.3, 0.36, 0.5, 0.6), 18))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.05, 0.07, 0.12, 0.6), Color(0.3, 0.36, 0.5, 0.6), 18))

func _make_button(parent: Control, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(MENU_W - 80, 100)
	b.pressed.connect(func(): _play("click"))
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

# Start a fresh run with the chosen mode
func _restart() -> void:
	lives = 1 if settings.mode == "hard" else 3
	life_cooldown = 0.0
	time_played = 0.0
	obstacles_passed = 0
	current_scroll_speed = BASE_SPEED
	score = 0.0
	run_start_best = int(settings.best[settings.mode])
	best_dirty = false
	best_save_timer = 0.0
	hit_timer = 0.0
	GameLog.info("Run started, mode %s" % settings.mode)
	_respawn_ball()

# Retire the current ball and create a fresh one at a clear spot near the start
func _respawn_ball() -> void:
	if ball != null:
		_retire_ball(ball)

	ball = Ball.new()
	ball.collision_mask = LAYER_WORLD | LAYER_BARS
	ball.set_style(settings.ball)
	add_child(ball)
	ball.position = _find_clear_spawn()
	GameLog.debug("Ball placed at (%d, %d)" % [int(ball.position.x), int(ball.position.y)])

	wedge_timer = 0.0
	break_timer = 0.0
	grace_timer = GRACE_TIME

# Search near BALL_START for a spot where the ball doesn't overlap any bar.
# Tries the start point first, then nearby points. Falls back to BALL_START.
func _find_clear_spawn() -> Vector2:
	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = Ball.RADIUS + 6.0

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = LAYER_BARS
	query.exclude = [ball.get_rid()]

	for dy in [0.0, 40.0, -40.0, 80.0, -80.0, 120.0, -120.0]:
		for x in [BALL_START.x, 300.0, 780.0, 180.0, 900.0, 60.0, 1020.0]:
			var p := Vector2(x, BALL_START.y + dy)
			query.transform = Transform2D(0.0, p)
			if space.intersect_shape(query, 1).is_empty():
				return p

	GameLog.warning("No clear spawn near the start, using the default point")
	return BALL_START

# Scroll chunks, count passed ones, remove old ones, add new ones below
func _update_chunks(delta: float) -> void:
	for c in chunks:
		var prev_y: float = c.position.y
		c.position.y -= current_scroll_speed * delta
		if PinballLogic.crossed_above(prev_y, c.position.y, ball.position.y, CHUNK_H):
			obstacles_passed += 1

	var keep: Array = []
	for c in chunks:
		if PinballLogic.should_recycle(c.position.y, CHUNK_H):
			c.queue_free()
		else:
			keep.append(c)
	chunks = keep

	var lowest := -INF
	for c in chunks:
		lowest = max(lowest, c.position.y)
	for y in PinballLogic.rows_to_fill(lowest, H, CHUNK_H):
		_spawn_chunk(y)

# Gravity of the zone the ball is currently in
func _gravity_at_ball() -> float:
	var zones: Array = []
	for c in chunks:
		zones.append({"y": c.position.y, "g": c.get_meta("gravity_scale")})
	return PinballLogic.gravity_at(ball.position.y, zones, CHUNK_H, DEFAULT_GRAVITY)

# Collect any star the ball is touching
func _collect_stars() -> void:
	for c in chunks:
		for s in c.get_children():
			if s is Star and ball.global_position.distance_to(s.global_position) < PICK_RADIUS:
				_collect_star(s)

# White and gold add score. Black takes score away and costs a life.
func _collect_star(star: Star) -> void:
	if star.kind == "black":
		score = maxf(0.0, score - STAR_BLACK)
		GameLog.info("Black star hit, -%d score" % int(STAR_BLACK))
		_burst(star.global_position, Color(LIFE_LOST_COLOR), 16)
		star.queue_free()
		_lose_life()
	else:
		var gain := STAR_GOLD if star.kind == "gold" else STAR_WHITE
		score += gain
		_burst(star.global_position, Star.COLORS[star.kind], 10)
		_play("star")
		star.queue_free()

# Pick a star kind: 60% white, 25% gold, 15% black
func _pick_star_kind() -> String:
	var roll := randf()
	if roll < 0.15:
		return "black"
	if roll < 0.4:
		return "gold"
	return "white"

func _add_star(chunk: Node2D, pos: Vector2) -> void:
	var s := Star.new()
	s.kind = _pick_star_kind()
	s.position = pos
	chunk.add_child(s)

func _update_hud() -> void:
	if hud_panel == null:
		return
	if state != "play":
		hud_panel.visible = false
		return
	hud_panel.visible = true
	var best := int(settings.best[settings.mode])
	var shown := int(score)
	var text := "Speed: %d  |  Lives: %d\nScore: %d    Best: %d" % [
		int(current_scroll_speed), lives, shown, best]
	if shown > run_start_best:
		text += "  NEW BEST"
	if ball.attached:
		var window := PinballLogic.escape_window(ball.position.y, current_scroll_speed)
		text += "\nESCAPE: %.1fs" % window
		text += "\nTilt or flip to break free"
	elif wedge_timer >= WARN_TIME:
		text += "\nSTUCK!"
	hud.text = text

func _make_walls() -> void:
	for x in [-10.0, W + 10.0]:
		var wall := StaticBody2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(20, H * 4)
		var col := CollisionShape2D.new()
		col.shape = shape
		wall.add_child(col)
		wall.position = Vector2(x, H * 0.5)
		add_child(wall)

	# Floor below the screen
	var floor_body := StaticBody2D.new()
	var floor_shape := RectangleShape2D.new()
	floor_shape.size = Vector2(W + 200, 20)
	var floor_col := CollisionShape2D.new()
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	floor_body.position = Vector2(W / 2.0, H + 10.0)
	add_child(floor_body)

# One chunk: a random gravity zone, colored by zone, with up to three bar rows.
# Stars are placed afterwards at random spots, off the path too.
func _spawn_chunk(y: float) -> void:
	var chunk := AnimatableBody2D.new()
	chunk.position = Vector2(0, y)
	chunk.add_to_group("chunk")
	chunk.collision_layer = LAYER_BARS
	chunk.collision_mask = 0

	var grav_choices := [0.3, 0.3, 0.15, 0.5]
	var g: float = grav_choices[randi() % grav_choices.size()]
	chunk.set_meta("gravity_scale", g)
	var bar_color := Color(ZONE_COLORS.get(g, BAR_COLOR))

	chunk_bars.clear()
	var band_h := CHUNK_H / 3.0
	for band in range(3):
		if randf() < 0.8:
			var row_y := band * band_h + randf_range(20.0, band_h - 20.0 - BAR_H)
			var gap_w := randf_range(GAP_MIN, GAP_MAX)
			var gap_x := randf_range(20.0, W - gap_w - 20.0)
			_add_bar(chunk, row_y, gap_x, gap_w, bar_color)

	_place_stars(chunk)
	add_child(chunk)
	chunks.append(chunk)

# Put stars at random spots in the chunk, including off the path.
# A spot is skipped if it sits on a bar, so the player has to go out of their way to reach it.
func _place_stars(chunk: Node2D) -> void:
	for i in range(STARS_PER_CHUNK):
		if randf() > STAR_CHANCE:
			continue
		for attempt in range(12):
			var p := Vector2(randf_range(40.0, W - 40.0), randf_range(20.0, CHUNK_H - 20.0))
			if _clear_of_bars(p):
				_add_star(chunk, p)
				break

func _clear_of_bars(p: Vector2) -> bool:
	for r in chunk_bars:
		if r.grow(STAR_CLEARANCE).has_point(p):
			return false
	return true

func _add_bar(chunk: Node2D, y: float, gap_x: float, gap_w: float, color: Color) -> void:
	_add_rect(chunk, 0.0, y, gap_x, BAR_H, color)
	_add_rect(chunk, gap_x + gap_w, y, W - gap_x - gap_w, BAR_H, color)

# One bar block: a collision shape plus a rounded, shaded panel.
# The rectangle is also recorded so stars can avoid it.
func _add_rect(parent: Node2D, x: float, y: float, w: float, h: float, color: Color) -> void:
	if w <= 0.0:
		return
	chunk_bars.append(Rect2(x, y, w, h))
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, h)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(x + w / 2.0, y + h / 2.0)
	parent.add_child(col)

	var panel := Panel.new()
	panel.position = Vector2(x, y)
	panel.size = Vector2(w, h)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _bar_style(color))
	parent.add_child(panel)
