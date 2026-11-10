class_name Flipper
extends AnimatableBody2D

const LEN := 150.0              # length of the flipper arm
const THICK := 26.0             # thickness of the flipper arm
const EASE_RATE := 18.0         # higher = snappier swing
const REST_ANGLE := 0.5         # resting angle (left flipper: down-right)
const UP_ANGLE := -0.55         # raised angle (left flipper: up-right)
const COLOR_HEX := "#4fd1c5"

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
	# Ease toward the target: fast start, soft landing
	var weight := 1.0 - exp(-EASE_RATE * delta)
	rotation = lerp_angle(rotation, _target_angle(), weight)
	queue_redraw()

func _draw() -> void:
	var c := Color(COLOR_HEX)
	draw_rect(Rect2(0.0, -THICK / 2.0, LEN, THICK), c)
	# Rounded ends
	draw_circle(Vector2.ZERO, THICK / 2.0, c)
	draw_circle(Vector2(LEN, 0.0), THICK / 2.0, c)
