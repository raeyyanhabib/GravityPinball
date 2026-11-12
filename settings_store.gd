extends RefCounted
class_name SettingsStore

# Saved to user://save.json on the device. Only known keys are kept.
const PATH := "user://save.json"
const TMP_NAME := "save.json.tmp"
const VERSION := 2

const DEFAULTS := {
	"version": VERSION,
	"mode": "simple",
	"controls": "tilt",
	"ball": "off_white",
	"effects": "full",
	"haptics": true,
	"best": {"simple": 0, "hard": 0},
}

const VALID_MODES := ["simple", "hard"]
const VALID_CONTROLS := ["tilt", "buttons"]
const VALID_BALLS := ["off_white", "silver", "black", "white"]
const VALID_EFFECTS := ["full", "low"]

# Load the save file, or return defaults if it's missing or broken
static func load_settings() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return DEFAULTS.duplicate(true)

	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		GameLog.warning("Could not open save file, using defaults")
		return DEFAULTS.duplicate(true)

	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		GameLog.warning("Save file was not valid JSON, using defaults")
		return DEFAULTS.duplicate(true)

	return sanitize(parsed)

# Keep only known keys, fix wrong types, and fill gaps from defaults.
# Anything that can't be fixed falls back to its default.
static func sanitize(data: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate(true)
	result.version = VERSION
	result.mode = _pick(data.get("mode"), VALID_MODES, DEFAULTS.mode)
	result.controls = _pick(data.get("controls"), VALID_CONTROLS, DEFAULTS.controls)
	result.ball = _pick(data.get("ball"), VALID_BALLS, DEFAULTS.ball)
	result.effects = _pick(data.get("effects"), VALID_EFFECTS, DEFAULTS.effects)
	result.haptics = bool(data.get("haptics", DEFAULTS.haptics))

	var best = data.get("best")
	if best is Dictionary:
		for mode in VALID_MODES:
			result.best[mode] = maxi(0, int(best.get(mode, 0)))
	return result

# Use the value only if it's a string from the valid list
static func _pick(value, valid: Array, fallback: String) -> String:
	if value is String and valid.has(value):
		return value
	return fallback

# Write to a temp file first, then swap it in.
# A crash mid-write can't leave a half-written save behind.
static func save_settings(data: Dictionary) -> bool:
	var clean := sanitize(data)
	var file := FileAccess.open("user://" + TMP_NAME, FileAccess.WRITE)
	if file == null:
		GameLog.error("Could not write save file")
		return false
	file.store_string(JSON.stringify(clean, "\t"))
	file.close()

	var dir := DirAccess.open("user://")
	if dir == null:
		GameLog.error("Could not open user folder to save")
		return false
	if dir.file_exists("save.json"):
		dir.remove("save.json")
	return dir.rename(TMP_NAME, "save.json") == OK
