extends RefCounted
class_name SettingsStore

# Saved to user://save.json on the device
const PATH := "user://save.json"
const DEFAULTS := {
	"mode": "simple",
	"controls": "tilt",
	"ball": "off_white",
	"best": {"simple": 0, "hard": 0},
}

# Load saved settings, falling back to defaults for anything missing
static func load_settings() -> Dictionary:
	var result := DEFAULTS.duplicate(true)
	if not FileAccess.file_exists(PATH):
		return result
	var file := FileAccess.open(PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		result.merge(parsed, true)
	return result

static func save_settings(data: Dictionary) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
