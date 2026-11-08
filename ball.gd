class_name Ball
extends RigidBody2D

const RADIUS := 20.0
const MAX_SPEED := 900.0
const TILT_FORCE := 600.0

var tilt := 0.0  # -1 (full left) to 1 (full right), set by main.gd

func _ready() -> void:
	gravity_scale = 0.3
	lock_rotation = true
	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.4
	mat.friction = 0.2
	physics_material_override = mat

func _physics_process(_delta: float) -> void:
	apply_central_force(Vector2(tilt * TILT_FORCE, 0.0))
	if linear_velocity.length() > MAX_SPEED:
		linear_velocity = linear_velocity.limit_length(MAX_SPEED)

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color.WHITE)
