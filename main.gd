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

# Bar colors per gravity zone: teal = floaty, slate = normal, red = heavy
const ZONE_COLORS := {0.15: "#2f5d62", 0.3: "#2a3a5c", 0.5: "#5c2f3a"}

# ---- Speed tuning ----
const BASE_SPEED := 60.0
const MAX_SPEED := 240.0
const DRIVER_CAP := 180.0

# ---- Steering ----
const TILT_DEAD := 0.6
const TILT_FULL := 4.0
const TILT_SMOOTH := 0.15

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

# ---- Game state ----
var hard_mode := false
var lives := 3
var game_over := false
var time_played := 0.0
var obstacles_passed := 0
var current_scroll_speed := BASE_SPEED

# ---- Runtime ----
var ball: Ball
var chunks: Array = []
var left_flipper: Flipper
var right_flipper: Flipper
var tilt_smoothed := 0.0
var touches := {}
var left_down := false
var right_down := false
var wedge_timer := 0.0
var grace_timer := 0.0
var break_timer := 0.0
var life_cooldown := 0.0
var hud: Label

func _ready() -> void:
	randomize()
	_make_walls()

	# Fill the screen, starting one chunk above the top
	for i in range(-1, 4):
		_spawn_chunk(i * CHUNK_H)

	ball = Ball.new()
	ball.collision_mask = LAYER_WORLD | LAYER_BARS
	add_child(ball)

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

	_restart()

# Touch, click, and key input
func _input(event: InputEvent) -> void:
	# After game over, R or a tap restarts
	if game_over and event.is_pressed():
		if (event is InputEventKey and event.keycode == KEY_R) \
				or event is InputEventScreenTouch or event is InputEventMouseButton:
			_restart()
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

# Main loop, runs 60 times per second
func _physics_process(delta: float) -> void:
	if game_over:
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

	_update_hud()

# Phone tilt, or A and D on the laptop
func _read_tilt() -> void:
	var raw := Input.get_gravity().x
	if abs(raw) < TILT_DEAD:
		raw = 0.0
	var key := 0.0
	if Input.is_physical_key_pressed(KEY_A):
		key -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		key += 1.0
	var target_tilt := clampf(raw / TILT_FULL + key, -1.0, 1.0)
	tilt_smoothed = lerpf(tilt_smoothed, target_tilt, TILT_SMOOTH)
	ball.tilt = tilt_smoothed

# Z and / on the laptop, screen halves on touch
func _read_flippers() -> void:
	left_down = Input.is_physical_key_pressed(KEY_Z)
	right_down = Input.is_physical_key_pressed(KEY_SLASH)
	for pos in touches.values():
		if pos.x < W / 2.0:
			left_down = true
		else:
			right_down = true
	left_flipper.pressed = left_down
	right_flipper.pressed = right_down

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

# Lose a life, then respawn or end the game
func _lose_life() -> void:
	if not PinballLogic.can_lose_life(life_cooldown):
		return
	life_cooldown = LIFE_COOLDOWN
	lives -= 1
	if lives <= 0:
		game_over = true
		ball.release(Vector2.ZERO)
		return
	_respawn_ball()

func _restart() -> void:
	lives = 1 if hard_mode else 3
	game_over = false
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
	if game_over:
		hud.text = "GAME OVER\nTap or press R to restart"
		return
	var text := "Lives: %d | Speed: %d" % [lives, int(current_scroll_speed)]
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
