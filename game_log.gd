extends RefCounted
class_name GameLog

# Local log file for debugging. Nothing is sent anywhere.
# Trimmed to a fresh file when it gets too big.
const PATH := "user://game.log"
const MAX_BYTES := 200000
const LEVELS := ["DEBUG", "INFO", "WARNING", "ERROR"]

# Lowest level that gets written. 0 = debug, 1 = info.
static var min_level := 1

static func debug(message: String) -> void:
	_write(0, message)

static func info(message: String) -> void:
	_write(1, message)

static func warning(message: String) -> void:
	_write(2, message)

static func error(message: String) -> void:
	_write(3, message)

# Build one line, print it, and append it to the file
static func _write(level: int, message: String) -> void:
	if level < min_level:
		return
	var line := "[%s] [%s] %s" % [Time.get_datetime_string_from_system(), LEVELS[level], message]
	print(line)
	_rotate_if_big()

	# Append to the existing file, or create it on the first write
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(PATH) else FileAccess.WRITE_READ
	var file := FileAccess.open(PATH, mode)
	if file == null:
		return
	file.seek_end()
	file.store_line(line)
	file.close()

# Start a fresh file once the old one passes MAX_BYTES
static func _rotate_if_big() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var check := FileAccess.open(PATH, FileAccess.READ)
	if check == null:
		return
	var too_big := check.get_length() > MAX_BYTES
	check.close()
	if too_big:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
