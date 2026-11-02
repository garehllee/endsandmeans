class_name Lines
# Notepad line banks live in res://data/lines.json.
# Each key maps to a list. An entry is either a plain string or a dictionary:
#   {"text": "...", "needs": "notebook_exploit"}   shown only while that flag is set
#   {"text": "...", "needs": "!notebook_exploit"}  shown only while it is NOT set

const PATH := "res://data/lines.json"

static var _data := {}
static var _loaded := false

static func _load() -> void:
	_loaded = true
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("Lines: could not parse " + PATH)

# All lines for a key whose "needs" condition currently holds.
static func options(key: String) -> Array[String]:
	if not _loaded:
		_load()
	var out: Array[String] = []
	for entry in _data.get(key, []):
		if entry is String:
			out.append(entry)
		elif entry is Dictionary and condition_met(entry.get("needs", "")):
			out.append(entry.get("text", ""))
	return out

static func condition_met(needs: String) -> bool:
	if needs == "":
		return true
	if needs.begins_with("!"):
		return not Game.has_flag(StringName(needs.substr(1)))
	return Game.has_flag(StringName(needs))
