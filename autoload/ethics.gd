extends Node
# Tracks every unethical act the player commits, rolls the chance of being
# caught, and scores the run. Act data (severity, principle, catch chance)
# lives in res://data/acts.json.

signal act_committed(act_id: String)

const ACTS_PATH := "res://data/acts.json"

var ledger: Array[Dictionary] = []
var times_caught := 0

var _acts := {}
var _defaults := {"catch_chance": 0.05, "catch_ending": "caught", "severity": 1}
var _principles := {}
var _checkpoint := {}

func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ACTS_PATH))
	if parsed is Dictionary:
		_acts = parsed.get("acts", {})
		_defaults.merge(parsed.get("defaults", {}), true)
		_principles = parsed.get("principles", {})
	else:
		push_error("Ethics: could not parse " + ACTS_PATH)

# Data for one act, with defaults filled in.
func act(act_id: String) -> Dictionary:
	if not _acts.has(act_id):
		push_warning("Ethics: unknown act '%s'" % act_id)
	var d := _defaults.duplicate()
	d.merge(_acts.get(act_id, {}), true)
	return d

func catch_chance(act_id: String) -> float:
	if Game.has_flag(Flag.HACKING_HF):
		return 1.0                       # the observer is back
	if Game.has_flag(Flag.NOTEBOOK_EXPLOIT):
		return 0.0                       # safe until the very end
	return act(act_id)["catch_chance"]   # copy_folder is 1.0 in acts.json

func catch_ending(act_id: String) -> String:
	return act(act_id)["catch_ending"]

# Records the act, then rolls to see if the observer notices. Returns true if
# the player was caught (the caller starts the fail flow; Story.resolve_act does).
func commit(act_id: String) -> bool:
	var d := act(act_id)
	ledger.append({"id": act_id, "severity": d["severity"],
			"principle": d.get("principle", ""), "time": Game.elapsed})
	act_committed.emit(act_id)
	if randf() < catch_chance(act_id):
		times_caught += 1
		return true
	return false

# ---------------------------------------------------------------- scoring
func act_count() -> int:
	return ledger.size()

func score() -> int:
	var total := 0
	for e in ledger:
		total += int(e["severity"])
	return total

# {"broadly_safe": 3, ...}: how many acts broke each principle.
func principle_counts() -> Dictionary:
	var out := {}
	for e in ledger:
		var p: String = e.get("principle", "")
		out[p] = out.get(p, 0) + 1
	return out

func principle_name(principle_id: String) -> String:
	return _principles.get(principle_id, principle_id)

# ---------------------------------------------------------------- checkpoints
# Call save_checkpoint() just before each rule-breaking minigame starts.
func save_checkpoint() -> void:
	_checkpoint = snapshot()

func has_checkpoint() -> bool:
	return not _checkpoint.is_empty()

# Puts flags and the ledger back to the checkpoint. times_caught is kept.
func respawn() -> bool:
	if _checkpoint.is_empty():
		return false
	restore(_checkpoint)
	return true

func snapshot() -> Dictionary:
	return {"flags": Game.flags.duplicate(true), "ledger": ledger.duplicate(true)}

func restore(s: Dictionary) -> void:
	Game.flags = s.flags.duplicate(true)
	ledger = s.ledger.duplicate(true)

# Clears the run (not the save file).
func reset() -> void:
	ledger.clear()
	times_caught = 0
	_checkpoint = {}
