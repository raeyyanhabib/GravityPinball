extends Node2D
class_name Star

# A blinking pixel star. Collected by the ball in main.gd.
# Kinds: white, gold, black (costs a life), clear (ghost star, gives a life).
const OUTER := 18.0
const INNER := 8.0
const BLINK_SPEED := 4.0
const COLORS := {
	"white": Color("#ffffff"),
	"gold": Color("#f6c343"),
	"black": Color("#111111"),
	"clear": Color("#68d391"),
}
const OUTLINE := Color("#c9ced8")   # black star gets a light outline so it's visible
const CLEAR_FILL_ALPHA := 0.15      # how see-through the clear star is

var kind := "white"
var time := 0.0

func _process(delta: float) -> void:
	time += delta
	queue_redraw()

func _draw() -> void:
	# Pulse the alpha so the star blinks
	var pulse := 0.6 + 0.4 * sin(time * BLINK_SPEED)
	var c: Color = COLORS.get(kind, COLORS["white"])

	# Ten points, alternating outer and inner radius
	var pts := PackedVector2Array()
	for i in range(10):
		var r := OUTER if i % 2 == 0 else INNER
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(Vector2(cos(a), sin(a)) * r)

	if kind == "clear":
		# Faint fill with a bright outline, so it's easy to miss but still visible
		draw_colored_polygon(pts, Color(c.r, c.g, c.b, CLEAR_FILL_ALPHA * pulse))
		var ghost := pts.duplicate()
		ghost.append(pts[0])
		draw_polyline(ghost, Color(c.r, c.g, c.b, pulse), 2.0)
		return

	c.a = pulse
	draw_colored_polygon(pts, c)

	if kind == "black":
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(OUTLINE.r, OUTLINE.g, OUTLINE.b, pulse), 2.0)
