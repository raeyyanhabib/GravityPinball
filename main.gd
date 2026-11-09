extends Node2D

# ---- Screen and layout ----
const W := 1080.0               # screen width
const H := 1920.0               # screen height
const CHUNK_H := 600.0          # height of one chunk of bars
const BAR_H := 40.0             # thickness of a bar
const GAP_MIN := 180.0          # narrowest gap in a bar row
const GAP_MAX := 300.0          # widest gap in a bar row
const SCROLL_SPEED := 60.0      # how fast bars move up (px/s)
const FLIPPER_Y := 1700.0       # height of the flippers
const BALL_START := Vector2(540, 300)  # start and respawn point

# ---- Steering ----
const TILT_DEAD := 0.6          # ignore tiny phone tremors
const TILT_FULL := 4.0          # this much tilt gives full steering
const TILT_SMOOTH := 0.15       # lower = smoother but slower response

# ---- Collision layers ----
const LAYER_WORLD := 1          # walls, floor, ball
const LAYER_BARS := 2           # bars only

# ---- Wedge (stuck) tuning ----
const WEDGE_SPEED := 25.0       # below this speed relative to the bar = stuck
const WARN_TIME := 0.8          # STUCK warning appears after this long
const WEDGE_TIME := 1.6         # total stuck time before the ball is pinned
const PIN_MIN_Y := 700.0        # only pin below this height, so escape time is fair
const STRUGGLE_SPEED := 140.0   # sideways movement while pinned
const BREAK_HOLD := 0.25        # how long to hold a flipper or hard tilt to break free
const BREAK_TILT := 0.6         # tilt strength that counts as a hard tilt
const KICK_SPEED := 260.0       # sideways push when the ball breaks free
const GRACE_TIME := 1.2         # time after breaking free before it can be pinned again

# One life can only be lost once per this many seconds
const LIFE_COOLDOWN := 1.0

# ---- Game state ----
var hard_mode := false          # M5 will set this from the menu
var lives := 3
var game_over := false

# ---- Nodes and runtime values ----
var ball: Ball
var chunks: Array = []          # all bar chunks currently on screen
var left_flipper: Flipper
var right_flipper: Flipper
var tilt_smoothed := 0.0        # smoothed tilt value sent to the ball
var touches := {}               # finger index -> position (-1 = mouse)
var left_down := false
var right_down := false
var wedge_timer := 0.0          # how long the ball has been stuck
var grace_timer := 0.0          # time left before the ball can be pinned again
var break_timer := 0.0          # how long the player has held a break-free input
var life_cooldown := 0.0        # time left before another life can be lost
var hud: Label

func _ready() -> void:
	randomize()                 # new random bars every run
	_make_walls()

	# Fill the screen with chunks, starting one above the top
	for i in range(-1, 4):
		_spawn_chunk(i * CHUNK_H)

	# Ball can hit the world and the bars
	ball = Ball.new()
	ball.collision_mask = LAYER_WORLD | LAYER_BARS
	add_child(ball)

	# Left flipper at the bottom left, right flipper at the bottom right
	left_flipper = Flipper.new()
	left_flipper.is_left = true
	left_flipper.position = Vector2(200, FLIPPER_Y)
	add_child(left_flipper)

	right_flipper = Flipper.new()
	right_flipper.is_left = false
	right_flipper.position = Vector2(W - 200, FLIPPER_Y)
	add_child(right_flipper)

	# On-screen text for lives and the escape timer
	hud = Label.new()
	hud.position = Vector2(30, 30)
	hud.add_theme_font_size_override("font_size", 44)
	hud.add_theme_color_override("font_color", Color("#f2f4f8"))
	add_child(hud)

	_restart()

# Runs on every touch, click, or key press
func _input(event: InputEvent) -> void:
	# After game over, R or a tap restarts
	if game_over and event.is_pressed():
		if (event is InputEventKey and event.keycode == KEY_R) \
				or event is InputEventScreenTouch or event is InputEventMouseButton:
			_restart()
		return

	# Track where each finger or the mouse is, so flippers know which side is pressed
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

# Main game loop, runs every physics frame (60 times per second)
func _physics_process(delta: float) -> void:
	if game_over:
		_update_hud()
		return

	life_cooldown = max(0.0, life_cooldown - delta)

	_read_tilt()
	_read_flippers()
	_update_chunks(delta)

	if ball.attached:
		_carry_ball(delta)      # ball is pinned to a bar
	else:
		_check_wedge(delta)     # watch for the ball getting stuck
		# Touching the top of the screen costs a life
		if ball.position.y <= Ball.RADIUS:
			_lose_life()

	_update_hud()

# Read tilt from the phone, or A and D on the laptop
func _read_tilt() -> void:
	var raw := Input.get_gravity().x
	if abs(raw) < TILT_DEAD:
		raw = 0.0               # ignore small shakes
	var key := 0.0
	if Input.is_physical_key_pressed(KEY_A):
		key -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		key += 1.0
	var target_tilt := clampf(raw / TILT_FULL + key, -1.0, 1.0)
	tilt_smoothed = lerpf(tilt_smoothed, target_tilt, TILT_SMOOTH)  # ease toward target
	ball.tilt = tilt_smoothed

# Work out which flipper should be up
func _read_flippers() -> void:
	left_down = Input.is_physical_key_pressed(KEY_Z)
	right_down = Input.is_physical_key_pressed(KEY_SLASH)
	# On touch, the left and right halves of the screen control each flipper
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
	if grace_timer > 0.0:
		wedge_timer = 0.0       # just broke free, can't be pinned yet
		return

	# Only a ball touching a bar can be stuck
	var touching := false
	for b in ball.get_colliding_bodies():
		if b.is_in_group("chunk"):
			touching = true
			break
	if not touching:
		wedge_timer = 0.0
		return

	# Stuck means the ball moves at almost the same speed as the bar
	var rel: Vector2 = ball.linear_velocity - Vector2(0.0, -SCROLL_SPEED)
	if rel.length() >= WEDGE_SPEED:
		wedge_timer = 0.0
		return

	# Too close to the top: don't pin, the player needs room to react
	if ball.position.y < PIN_MIN_Y:
		wedge_timer = 0.0
		return

	# Stuck long enough: pin the ball to the bar
	wedge_timer += delta
	if wedge_timer >= WEDGE_TIME:
		ball.attach()
		wedge_timer = 0.0
		break_timer = 0.0

# Pinned: the bar carries the ball up. Tilt lets it struggle sideways.
func _carry_ball(delta: float) -> void:
	ball.position.y -= SCROLL_SPEED * delta
	ball.position.x = clampf(
		ball.position.x + tilt_smoothed * STRUGGLE_SPEED * delta,
		Ball.RADIUS, W - Ball.RADIUS)   # keep the ball on screen

	# Carried into the top: lose a life
	if ball.position.y <= Ball.RADIUS:
		_lose_life()
		return

	# Hold a flipper or hard tilt for a moment to break free
	var breaking: bool = left_down or right_down or abs(tilt_smoothed) > BREAK_TILT
	if breaking:
		break_timer += delta
		if break_timer >= BREAK_HOLD:
			_break_free()
	else:
		break_timer = 0.0       # reset if the player lets go

# Release the ball with a kick toward the side the player pushed
func _break_free() -> void:
	var dir := 1.0 if (right_down or tilt_smoothed > 0.0) else -1.0
	if left_down and not right_down:
		dir = -1.0
	ball.release(Vector2(dir * KICK_SPEED, 60.0))
	grace_timer = GRACE_TIME
	break_timer = 0.0

# Lose one life, then respawn or end the game.
# The cooldown stops one crossing from costing more than one life.
func _lose_life() -> void:
	if life_cooldown > 0.0:
		return
	life_cooldown = LIFE_COOLDOWN
	lives -= 1
	if lives <= 0:
		game_over = true
		ball.release(Vector2.ZERO)
		return
	_respawn_ball()

# Start a fresh run
func _restart() -> void:
	lives = 1 if hard_mode else 3
	game_over = false
	life_cooldown = 0.0
	_respawn_ball()

# Put the ball back at the start point and clear its timers
func _respawn_ball() -> void:
	ball.release(Vector2.ZERO)
	ball.position = BALL_START
	wedge_timer = 0.0
	break_timer = 0.0
	grace_timer = GRACE_TIME

# Scroll bars up, delete the ones that left the top,
# and add new ones below so the loop never runs out
func _update_chunks(delta: float) -> void:
	for c in chunks:
		c.position.y -= SCROLL_SPEED * delta

	# Keep only the chunks that are still on screen
	var keep: Array = []
	for c in chunks:
		if c.position.y < -CHUNK_H:
			c.queue_free()
		else:
			keep.append(c)
	chunks = keep

	# Add chunks below the lowest one until the screen is covered
	var lowest := -INF
	for c in chunks:
		lowest = max(lowest, c.position.y)
	while lowest < H:
		lowest += CHUNK_H
		_spawn_chunk(lowest)

# Update the on-screen text
func _update_hud() -> void:
	if game_over:
		hud.text = "GAME OVER\nTap or press R to restart"
		return
	var text := "Lives: %d" % lives
	if ball.attached:
		var window := ball.position.y / SCROLL_SPEED   # seconds until the top
		text += "\nESCAPE: %.1fs" % window
		text += "\nTilt or flip to break free"
	elif wedge_timer >= WARN_TIME:
		text += "\nSTUCK!"
	hud.text = text

# Side walls and the bottom floor
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

	# Floor below the screen, so the ball can't fall out
	var floor_body := StaticBody2D.new()
	var floor_shape := RectangleShape2D.new()
	floor_shape.size = Vector2(W + 200, 20)
	var floor_col := CollisionShape2D.new()
	floor_col.shape = floor_shape
	floor_body.add_child(floor_col)
	floor_body.position = Vector2(W / 2.0, H + 10.0)
	add_child(floor_body)

# One chunk: three bands, each randomly holding a bar row or staying empty
func _spawn_chunk(y: float) -> void:
	var chunk := AnimatableBody2D.new()
	chunk.position = Vector2(0, y)
	chunk.add_to_group("chunk")       # lets the ball recognize bars
	chunk.collision_layer = LAYER_BARS
	chunk.collision_mask = 0          # bars don't need to detect anything

	var band_h := CHUNK_H / 3.0
	for band in range(3):
		if randf() < 0.8:             # 80% chance this band has a row
			var row_y := band * band_h + randf_range(20.0, band_h - 20.0 - BAR_H)
			var gap_w := randf_range(GAP_MIN, GAP_MAX)
			var gap_x := randf_range(20.0, W - gap_w - 20.0)
			_add_bar(chunk, row_y, gap_x, gap_w)

	add_child(chunk)
	chunks.append(chunk)

# One row: a bar on each side of a gap
func _add_bar(chunk: Node2D, y: float, gap_x: float, gap_w: float) -> void:
	_add_rect(chunk, 0.0, y, gap_x, BAR_H)
	_add_rect(chunk, gap_x + gap_w, y, W - gap_x - gap_w, BAR_H)

# One rectangle: a collision shape (for physics) and a ColorRect (for looks)
func _add_rect(parent: Node2D, x: float, y: float, w: float, h: float) -> void:
	if w <= 0.0:
		return
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, h)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(x + w / 2.0, y + h / 2.0)   # shape position is its center
	parent.add_child(col)
	var visual := ColorRect.new()
	visual.position = Vector2(x, y)
	visual.size = Vector2(w, h)
	visual.color = Color("#2a3a5c")
	parent.add_child(visual)
