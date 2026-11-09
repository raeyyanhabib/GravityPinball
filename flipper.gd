class_name Flipper
extends AnimatableBody2D

const LEN := 150.0              # length of the flipper arm
const THICK := 26.0             # thickness of the flipper arm
const SWING_SPEED := 14.0       # how fast it swings (radians per second)
const REST_ANGLE := 0.5         # resting angle (left flipper: down-right)
const UP_ANGLE := -0.55         # raised angle (left flipper: up-right)

var is_left := true             # which side this flipper is on
var pressed := false            # set by main.gd when the player holds it

func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(LEN, THICK)
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(LEN / 2.0, 0.0)   # shape starts at the pivot
	add_child(col)
	rotation = _target_angle()

# The angle the flipper should be at right now
func _target_angle() -> float:
	var a := UP_ANGLE if pressed else REST_ANGLE
	if not is_left:
		a = PI - a              # mirror the angle for the right flipper
	return a

func _physics_process(delta: float) -> void:
	# Swing toward the target at a fixed speed, instead of snapping
	rotation = move_toward(rotation, _target_angle(), SWING_SPEED * delta)
	queue_redraw()              # redraw the arm at its new angle

func _draw() -> void:
	draw_rect(Rect2(0.0, -THICK / 2.0, LEN, THICK), Color("#4fd1c5"))
