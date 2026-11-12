class_name Ball
extends RigidBody2D

const RADIUS := 20.0
const MAX_SPEED := 900.0
const TILT_FORCE := 600.0
const TRAIL_LENGTH := 10        # most past positions the trail keeps

# Ball colors. Black gets a light outline so it stays visible on navy.
const COLORS := {
	"off_white": Color("#f2f4f8"),
	"silver": Color("#c9ced8"),
	"black": Color("#0b0b0f"),
	"white": Color("#ffffff"),
}

var tilt := 0.0
var attached := false           # true while pinned to a bar
var style := "off_white"        # set from the menu
var trail_length := TRAIL_LENGTH  # main.gd sets this to 0 in low effects
var trail: Array = []           # recent global positions, newest last

func _ready() -> void:
	gravity_scale = 0.3
	lock_rotation = true
	contact_monitor = true
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

# Record the trail every rendered frame, keeping only the newest points
func _process(_delta: float) -> void:
	trail.append(global_position)
	while trail.size() > trail_length:
		trail.pop_front()
	queue_redraw()

func _physics_process(_delta: float) -> void:
	if attached:
		return                  # main.gd moves the ball while pinned
	apply_central_force(Vector2(tilt * TILT_FORCE, 0.0))
	if linear_velocity.length() > MAX_SPEED:
		linear_velocity = linear_velocity.limit_length(MAX_SPEED)

# Freeze the ball so a bar can carry it
func attach() -> void:
	attached = true
	freeze = true
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC

# Unfreeze and give the ball a starting velocity
func release(kick: Vector2) -> void:
	attached = false
	freeze = false
	linear_velocity = kick

# Change the ball color from the menu
func set_style(new_style: String) -> void:
	style = new_style
	queue_redraw()

func _draw() -> void:
	var c: Color = COLORS.get(style, COLORS["off_white"])

	# Trail: older points are smaller and more transparent
	for i in range(trail.size()):
		var t := float(i + 1) / float(trail.size() + 1)
		var p := to_local(trail[i])
		draw_circle(p, RADIUS * t * 0.8, Color(c.r, c.g, c.b, t * 0.25))

	draw_circle(Vector2.ZERO, RADIUS, c)
	if style == "black":
		draw_arc(Vector2.ZERO, RADIUS - 1.0, 0.0, TAU, 32, COLORS["silver"], 2.0)
