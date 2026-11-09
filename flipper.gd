class_name Flipper
extends AnimatableBody2D

const LEN := 150.0
const THICK := 26.0
const SWING_SPEED := 14.0  # radians per second
const REST_ANGLE := 0.5    # left flipper resting, pointing down-right
const UP_ANGLE := -0.55    # left flipper raised, pointing up-right

var is_left := true
var pressed := false

func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(LEN, THICK)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(LEN / 2.0, 0.0)
	add_child(col)
	rotation = _target_angle()

func _target_angle() -> float:
	var a := UP_ANGLE if pressed else REST_ANGLE
	if not is_left:
		a = PI - a  # mirror for the right flipper
	return a

func _physics_process(delta: float) -> void:
	rotation = move_toward(rotation, _target_angle(), SWING_SPEED * delta)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0.0, -THICK / 2.0, LEN, THICK), Color("#4fd1c5"))
