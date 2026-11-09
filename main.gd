extends Node2D

const W := 1080.0
const H := 1920.0
const CHUNK_H := 600.0
const BAR_H := 40.0
const GAP_W := 220.0
const SCROLL_SPEED := 60.0
const BALL_START := Vector2(540, 300)
const FLIPPER_Y := 1700.0
const TILT_DEAD := 0.6     # ignore small tremors (m/s²)
const TILT_FULL := 4.0     # this much tilt gives full steering (m/s²)
const TILT_SMOOTH := 0.15  # lower = smoother, slower to respond

var ball: Ball
var chunks: Array = []
var left_flipper: Flipper
var right_flipper: Flipper
var tilt_smoothed := 0.0
var touches := {}  # touch index -> screen position

func _ready() -> void:
	randomize()
	_make_walls()
	for i in range(4):
		_spawn_chunk(i * CHUNK_H)
	ball = Ball.new()
	ball.position = BALL_START
	add_child(ball)

	left_flipper = Flipper.new()
	left_flipper.is_left = true
	left_flipper.position = Vector2(200, FLIPPER_Y)
	add_child(left_flipper)

	right_flipper = Flipper.new()
	right_flipper.is_left = false
	right_flipper.position = Vector2(W - 200, FLIPPER_Y)
	add_child(right_flipper)

func _input(event: InputEvent) -> void:
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

func _physics_process(delta: float) -> void:
	# Tilt: phone accelerometer, or A and D on the laptop
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

	# Flippers: Z and / on the laptop, left and right screen halves on touch
	var left_down := Input.is_physical_key_pressed(KEY_Z)
	var right_down := Input.is_physical_key_pressed(KEY_SLASH)
	for pos in touches.values():
		if pos.x < W / 2.0:
			left_down = true
		else:
			right_down = true
	left_flipper.pressed = left_down
	right_flipper.pressed = right_down

	# Scroll every chunk upward
	for c in chunks:
		c.position.y -= SCROLL_SPEED * delta

	# Remove chunks that have fully left the bottom of the screen
	var keep: Array = []
	for c in chunks:
		if c.position.y > H:
			c.queue_free()
		else:
			keep.append(c)
	chunks = keep

	# Add new chunks above the top until the screen is covered
	var top := INF
	for c in chunks:
		top = min(top, c.position.y)
	while top > -CHUNK_H:
		top -= CHUNK_H
		_spawn_chunk(top)

	# Reset the ball if it falls out the bottom
	if ball.position.y > H + 100:
		ball.position = BALL_START
		ball.linear_velocity = Vector2.ZERO

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

func _spawn_chunk(y: float) -> void:
	var chunk := AnimatableBody2D.new()
	chunk.position = Vector2(0, y)
	for ratio in [0.2, 0.5, 0.8]:
		var gap_x := randf_range(20.0, W - GAP_W - 20.0)
		_add_bar(chunk, ratio * CHUNK_H - BAR_H / 2.0, gap_x)
	add_child(chunk)
	chunks.append(chunk)

func _add_bar(chunk: Node2D, y: float, gap_x: float) -> void:
	_add_rect(chunk, 0.0, y, gap_x, BAR_H)
	_add_rect(chunk, gap_x + GAP_W, y, W - gap_x - GAP_W, BAR_H)

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
