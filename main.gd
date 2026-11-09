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
const DEFAULT_GRAVITY := 0.3
const ZONE_COLORS := {0.15: "#2f5d62", 0.3: "#2a3a5c", 0.5: "#5c2f3a"}

# ---- Speed tuning ----
const BASE_SPEED := 60.0
const MAX_SPEED := 240.0
const DRIVER_CAP := 180.0

# ---- Steering ----
const TILT_DEAD := 0.6
const TILT_FULL := 4.0
const TILT_SMOOTH := 0.15
# On-screen steer buttons, used in Buttons mode
const STEER_LEFT_RECT := Rect2(0, 1440, 300, 200)
const STEER_RIGHT_RECT := Rect2(780, 1440, 300, 200)

# ---- Collision layers ----
const LAYER_WORLD := 1
const LAYER_BARS := 2

# ---- Wedge tuning ----
const WEDGE_SPEED := 25.0
const WARN_TIME := 0.8
const WEDGE_TIME := 1.6
const PIN_MIN_Y := 700.0
const STRUGGLE_SPEED := 140.0
const BREAK_HOLD := 0.25
const BREAK_TILT := 0.6
const KICK_SPEED := 260.0
const GRACE_TIME := 1.2
const LIFE_COOLDOWN := 1.0

const BALL_STYLES := ["off_white", "silver", "black", "white"]

# ---- Saved settings (loaded in _ready) ----
var settings: Dictionary = {}

# ---- Game state ----
var state := "menu"             # "menu", "play", or "paused"
var lives := 3
var time_played := 0.0
var obstacles_passed := 0       # also the score
var current_scroll_speed := BASE_SPEED

# ---- Runtime ----
var ball: Ball
var chunks: Array = []
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
var hud: Label
var menu_layer: CanvasLayer
var title_label: Label
var status_label: Label
var best_label: Label
var play_btn: Button
var mode_btn: Button
var controls_btn: Button
var ball_btn: Button

func _ready() -> void:
	randomize()
	settings = SettingsStore.load_settings()
	_make_walls()

	# Fill the screen, starting one chunk above the top
	for i in range(-1, 4):
		_spawn_chunk(i * CHUNK_H)

	ball = Ball.new()
	ball.collision_mask = LAYER_WORLD | LAYER_BARS
	add_child(ball)
	ball.set_style(settings.ball)
	ball.attach()               # frozen while the menu is open

	left_flipper = Flipper.new()
	left_flipper.is_left = true
	left_flipper.position = Vector2(200, FLIPPER_Y)
	add_child(left_flipper)

	right_flipper = Flipper.new()
	right_flipper.is_left = false
	right_flipper.position = Vector2(W - 200, FLIPPER_Y)
	add_child(right_flipper)

	hud = Label.new()
	hud.position = Vector2(30, 30)
	hud.add_theme_font_size_override("font_size", 44)
	hud.add_theme_color_override("font_color", Color("#f2f4f8"))
	add_child(hud)

	_build_menu()
	_show_menu("")

# Touch, click, key, and pause input
func _input(event: InputEvent) -> void:
	# P pauses and resumes during play
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		if state == "play":
			state = "paused"
		elif state == "paused":
			state = "play"
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

# Main loop, 60 times per second
func _physics_process(delta: float) -> void:
	if state != "play":
		_update_hud()
		return

	time_played += delta
	life_cooldown = max(0.0, life_cooldown - delta)
	current_scroll_speed = PinballLogic.speed_for(
		time_played, obstacles_passed, BASE_SPEED, MAX_SPEED, DRIVER_CAP)

	_read_tilt()
	_read_flippers()
	_update_chunks(delta)
	ball.gravity_scale = _gravity_at_ball()

	if ball.attached:
		_carry_ball(delta)
	else:
		_check_wedge(delta)
		# Touching the top of the screen costs a life
		if ball.position.y <= Ball.RADIUS:
			_lose_life()

	queue_redraw()              # redraws the steer buttons
	_update_hud()

func _draw() -> void:
	# Faint steer buttons, only in Buttons mode during play
	if state != "play" or settings.controls != "buttons":
		return
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
# In Buttons mode, touches on the steer buttons don't flip.
func _read_flippers() -> void:
	left_down = Input.is_physical_key_pressed(KEY_Z)
	right_down = Input.is_physical_key_pressed(KEY_SLASH)
	for pos in touches.values():
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

# Decide whether the ball is stuck against a bar
func _check_wedge(delta: float) -> void:
	grace_timer = max(0.0, grace_timer - delta)
	var touching := _touching_bar()
	var stuck := PinballLogic.is_stuck_motion(
		ball.linear_velocity, current_scroll_speed, WEDGE_SPEED)
	var can_pin := grace_timer <= 0.0 and ball.position.y >= PIN_MIN_Y
	wedge_timer = PinballLogic.next_wedge_timer(wedge_timer, delta, touching, stuck, can_pin)
	if PinballLogic.should_pin(wedge_timer, WEDGE_TIME):
		ball.attach()
		wedge_timer = 0.0
		break_timer = 0.0

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

# Lose a life, then respawn, or end the run on the last one
func _lose_life() -> void:
	if not PinballLogic.can_lose_life(life_cooldown):
		return
	life_cooldown = LIFE_COOLDOWN
	lives -= 1
	if lives <= 0:
		_end_run()
		return
	_respawn_ball()

# Save the best score for this mode and return to the menu
func _end_run() -> void:
	var mode: String = settings.mode
	if obstacles_passed > int(settings.best[mode]):
		settings.best[mode] = obstacles_passed
	SettingsStore.save_settings(settings)
	ball.attach()               # freeze the ball behind the menu
	_show_menu("GAME OVER\nScore: %d" % obstacles_passed)

# Show the menu, with an optional message at the top
func _show_menu(message: String) -> void:
	state = "menu"
	menu_layer.visible = true
	status_label.text = message
	_refresh_menu()

func _on_play() -> void:
	menu_layer.visible = false
	state = "play"
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

func _save_and_refresh() -> void:
	SettingsStore.save_settings(settings)
	_refresh_menu()

func _refresh_menu() -> void:
	mode_btn.text = "Mode: %s" % String(settings.mode).capitalize()
	controls_btn.text = "Controls: %s" % ("Tilt" if settings.controls == "tilt" else "Buttons")
	ball_btn.text = "Ball: %s" % String(settings.ball).replace("_", " ").capitalize()
	best_label.text = "Best (Simple): %d    Best (Hard): %d" % [
		int(settings.best.simple), int(settings.best.hard)]

# Build the menu UI once, then show or hide it
func _build_menu() -> void:
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)

	var box := VBoxContainer.new()
	box.position = Vector2(200, 480)
	box.custom_minimum_size = Vector2(680, 0)
	box.add_theme_constant_override("separation", 20)
	menu_layer.add_child(box)

	title_label = Label.new()
	title_label.text = "GRAVITY PINBALL"
	title_label.add_theme_font_size_override("font_size", 64)
	title_label.add_theme_color_override("font_color", Color("#f2f4f8"))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 40)
	status_label.add_theme_color_override("font_color", Color("#f6ad55"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status_label)

	play_btn = _make_button(box, "Play", _on_play)
	mode_btn = _make_button(box, "", _on_mode)
	controls_btn = _make_button(box, "", _on_controls)
	ball_btn = _make_button(box, "", _on_ball)

	best_label = Label.new()
	best_label.add_theme_font_size_override("font_size", 34)
	best_label.add_theme_color_override("font_color", Color("#9aa3c7"))
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(best_label)

func _make_button(parent: Control, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(680, 96)
	b.add_theme_font_size_override("font_size", 40)
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
	_respawn_ball()

# Return the ball to the start point and clear its state
func _respawn_ball() -> void:
	ball.attached = false
	ball.freeze = false
	ball.linear_velocity = Vector2.ZERO
	ball.angular_velocity = 0.0
	ball.position = BALL_START
	wedge_timer = 0.0
	break_timer = 0.0
	grace_timer = GRACE_TIME

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

func _update_hud() -> void:
	if state == "menu":
		hud.text = ""
		return
	if state == "paused":
		hud.text = "PAUSED (press P to resume)"
		return
	var text := "Lives: %d | Speed: %d | Score: %d" % [
		lives, int(current_scroll_speed), obstacles_passed]
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

# One chunk: a random gravity zone, tinted, with up to three bar rows
func _spawn_chunk(y: float) -> void:
	var chunk := AnimatableBody2D.new()
	chunk.position = Vector2(0, y)
	chunk.add_to_group("chunk")
	chunk.collision_layer = LAYER_BARS
	chunk.collision_mask = 0

	var grav_choices := [0.3, 0.3, 0.15, 0.5]
	var g: float = grav_choices[randi() % grav_choices.size()]
	chunk.set_meta("gravity_scale", g)

	var band_h := CHUNK_H / 3.0
	for band in range(3):
		if randf() < 0.8:
			var row_y := band * band_h + randf_range(20.0, band_h - 20.0 - BAR_H)
			var gap_w := randf_range(GAP_MIN, GAP_MAX)
			var gap_x := randf_range(20.0, W - gap_w - 20.0)
			_add_bar(chunk, row_y, gap_x, gap_w)

	_tint_chunk(chunk, g)
	add_child(chunk)
	chunks.append(chunk)

# Color the bars by gravity zone
func _tint_chunk(chunk: Node2D, g: float) -> void:
	var color: String = ZONE_COLORS.get(g, "#2a3a5c")
	for child in chunk.get_children():
		if child is ColorRect:
			child.color = Color(color)

func _add_bar(chunk: Node2D, y: float, gap_x: float, gap_w: float) -> void:
	_add_rect(chunk, 0.0, y, gap_x, BAR_H)
	_add_rect(chunk, gap_x + gap_w, y, W - gap_x - gap_w, BAR_H)

func _add_rect(parent: Node2D, x: float, y: float, w: float, h: float) -> void:
	if w <= 0.0:
		return
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, h)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(x + w / 2.0, y + h / 2.0)
	parent.add_child(col)
	var visual := ColorRect.new()
	visual.position = Vector2(x, y)
	visual.size = Vector2(w, h)
	visual.color = Color("#2a3a5c")
	parent.add_child(visual)
