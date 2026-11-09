class_name Ball
extends RigidBody2D

const RADIUS := 20.0            # ball size in pixels
const MAX_SPEED := 900.0        # speed cap so fast bounces stay controllable
const TILT_FORCE := 600.0       # how hard tilt pushes the ball sideways

var tilt := 0.0                 # -1 (full left) to 1 (full right), set by main.gd
var attached := false           # true while the ball is pinned to a bar

func _ready() -> void:
	gravity_scale = 0.3         # baseline fallback gravity scale
	lock_rotation = true        # ball doesn't spin
	contact_monitor = true      # lets the ball report what it touches
	max_contacts_reported = 8
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
	if attached:
		return
	apply_central_force(Vector2(tilt * TILT_FORCE, 0.0))
	if linear_velocity.length() > MAX_SPEED:
		linear_velocity = linear_velocity.limit_length(MAX_SPEED)

func attach() -> void:
	attached = true
	freeze = true
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC

func release(kick: Vector2) -> void:
	attached = false
	freeze = false
	linear_velocity = kick

func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color("#f2f4f8"))
