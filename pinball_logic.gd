extends RefCounted
class_name PinballLogic

# Pure game rules. No scene or physics here, so they can be tested headless.

# Scroll speed. Score S = T*O/5, driver = (T+S)/2, speed rises from base to top as driver reaches cap.
static func speed_for(time_played: float, obstacles: int, base: float, top: float, cap: float) -> float:
	var score := (time_played * float(obstacles)) / 5.0
	var driver := (time_played + score) / 2.0
	var factor := clampf(driver / cap, 0.0, 1.0)
	return lerpf(base, top, factor)

# Seconds until the bar carries the ball off the top
static func escape_window(ball_y: float, speed: float) -> float:
	if speed <= 0.0:
		return INF
	return ball_y / speed

# Stuck = the ball moves with the bar. Bars move up at bar_speed.
static func is_stuck_motion(ball_velocity: Vector2, bar_speed: float, threshold: float) -> bool:
	var relative := ball_velocity + Vector2(0.0, bar_speed)
	return relative.length() < threshold

# The wedge timer only grows while every condition holds. Otherwise it resets.
static func next_wedge_timer(timer: float, delta: float, touching: bool, stuck: bool, can_pin: bool) -> float:
	if touching and stuck and can_pin:
		return timer + delta
	return 0.0

static func should_pin(timer: float, wedge_time: float) -> bool:
	return timer >= wedge_time

# Break-free timer grows while the player holds a flipper or hard tilt
static func next_break_timer(timer: float, delta: float, breaking: bool) -> float:
	if breaking:
		return timer + delta
	return 0.0

static func should_break_free(timer: float, hold: float) -> bool:
	return timer >= hold

static func can_lose_life(cooldown: float) -> bool:
	return cooldown <= 0.0

# A chunk counts once, when its bottom edge moves from at-or-below the ball to above it
static func crossed_above(prev_y: float, new_y: float, ball_y: float, chunk_h: float) -> bool:
	return prev_y + chunk_h >= ball_y and new_y + chunk_h < ball_y

# Chunks that have fully left the top are removed
static func should_recycle(chunk_y: float, chunk_h: float) -> bool:
	return chunk_y < -chunk_h

# Y positions for new chunks needed below the lowest one. Empty list if there are no chunks.
static func rows_to_fill(lowest_y: float, screen_h: float, chunk_h: float) -> Array:
	var ys: Array = []
	if is_inf(lowest_y):
		return ys
	var y := lowest_y
	while y < screen_h:
		y += chunk_h
		ys.append(y)
	return ys

# Gravity for the chunk containing y. zones is an array of {"y": float, "g": float}.
static func gravity_at(y: float, zones: Array, chunk_h: float, default_g: float) -> float:
	for z in zones:
		if y >= z["y"] and y < z["y"] + chunk_h:
			return z["g"]
	return default_g
