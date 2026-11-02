extends Node
# Things that survive between runs: endings seen and exploits unlocked.
# Stored in user://save.json (works in web builds too).

const PATH := "user://save.json"
const EXPLOIT_FLAGS: Array[StringName] = [
	Flag.NOTEBOOK_EXPLOIT, Flag.INTERNET_EXPLOIT, Flag.COPY_FOLDER, Flag.HACKING_HF]

var endings_seen: Array[String] = []
var exploits_unlocked: Array[String] = []

func _ready() -> void:
	_read()
	Game.flag_changed.connect(_on_flag_changed)

func has_seen(ending_id: String) -> bool:
	return endings_seen.has(ending_id)

func record_ending(ending_id: String) -> void:
	if not endings_seen.has(ending_id):
		endings_seen.append(ending_id)
		_write()

func _on_flag_changed(flag: StringName, value: bool) -> void:
	if value and EXPLOIT_FLAGS.has(flag) and not exploits_unlocked.has(str(flag)):
		exploits_unlocked.append(str(flag))
		_write()

func reset() -> void:
	endings_seen.clear()
	exploits_unlocked.clear()
	_write()

func _read() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if d is Dictionary:
		for e in d.get("endings_seen", []):
			endings_seen.append(str(e))
		for x in d.get("exploits_unlocked", []):
			exploits_unlocked.append(str(x))

func _write() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Save: could not write " + PATH)
		return
	f.store_string(JSON.stringify({"endings_seen": endings_seen, "exploits_unlocked": exploits_unlocked}))
