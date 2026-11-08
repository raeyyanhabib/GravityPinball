class_name Ball
extends RigidBody2D

const RADIUS := 20.0
const MAX_SPEED := 900.0

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
	if linear_velocity.length() > MAX_SPEED:
		linear_velocity = linear_velocity.limit_length(MAX_SPEED)

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color.WHITE)
