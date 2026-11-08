extends Node2D

const W := 1080.0
const H := 1920.0
const CHUNK_H := 600.0
const BAR_H := 40.0
const GAP_W := 220.0
const SCROLL_SPEED := 120.0
const BALL_START := Vector2(540, 300)

var ball: Ball
var chunks: Array = []

func _ready() -> void:
	randomize()
	_make_walls()
	for i in range(4):
		_spawn_chunk(i * CHUNK_H)
	ball = Ball.new()
	ball.position = BALL_START
	add_child(ball)

func _physics_process(delta: float) -> void:
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
	visual.color = Color(0.3, 0.5, 1.0)
	parent.add_child(visual)
