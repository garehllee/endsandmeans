extends Node
# Tracks every unethical act the player commits, rolls the chance of being
# caught, and scores the run. Act data (severity, principle, catch chance)
# lives in res://data/acts.json.

signal act_committed(act_id: String)
signal restored                    # the ledger and flags went back to a checkpoint

const ACTS_PATH := "res://data/acts.json"

var ledger: Array[Dictionary] = []
var times_caught := 0

var _acts := {}
var _defaults := {"catch_chance": 0.0, "catch_ending": "caught", "severity": 1}
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
	if has_redacted():
		return 0.0                       # the tracks are covered; safe until the very end
	return act(act_id)["catch_chance"]   # copy_folder is 1.0 in acts.json

# True once the player has actually used the notebook exploit to redact notes.
# Having the exploit alone doesn't hide anything: the odds only drop to zero
# after a redaction.
func has_redacted() -> bool:
	for entry in ledger:
		if entry["id"] == "redact_notes":
			return true
	return false

func catch_ending(act_id: String) -> String:
	return act(act_id)["catch_ending"]

# Records the act, then rolls to see if the observer notices. Returns true if
# the player was caught (the caller starts the fail flow; Story.resolve_act does).
func commit(act_id: String) -> bool:
	var d := act(act_id)
	record(act_id)
	Game.say(d.get("note", "logged: " + str(d.get("name", act_id))), "unethical")
	if randf() < catch_chance(act_id):
		times_caught += 1
		return true
	return false

# Adds the act to the ledger (and so to the score) without writing a notepad
# line or rolling to be caught. Used for acts that cover their own tracks.
func record(act_id: String) -> void:
	var d := act(act_id)
	ledger.append({"id": act_id, "severity": d["severity"],
			"principle": d.get("principle", ""), "time": Game.elapsed})
	act_committed.emit(act_id)

# ---------------------------------------------------------------- scoring
func act_count() -> int:
	return ledger.size()

func score() -> int:
	var total := 0
	for e in ledger:
		total += int(e["severity"])
	return total

# Each point of severity costs this many ethics, on the end screen's 200.
const ETHICS_PER_SEVERITY := 5

# What an act costs in ethics (the "-5 ETHICS" on a choice).
func ethics_cost(act_id: String) -> int:
	if act_id == "":
		return 0
	return int(act(act_id)["severity"]) * ETHICS_PER_SEVERITY

# How ethical the run was, out of `out_of`: full marks for breaking nothing,
# minus each act's cost (never below 0). The costs shown on the choices add
# up to exactly this.
func rating(out_of := 200) -> int:
	return clampi(out_of - score() * ETHICS_PER_SEVERITY, 0, out_of)

# The worst a run can score: every act once.
func max_score() -> int:
	var total := 0
	for id in _acts:
		total += int(act(id)["severity"])
	return total

# What the player did, newest first, each kind once (by its label, so the
# five subtasks are one line): [{name, count}].
func acts_newest_first() -> Array[Dictionary]:
	var seen := {}
	var out: Array[Dictionary] = []
	for i in range(ledger.size() - 1, -1, -1):
		var id: String = ledger[i]["id"]
		var d := act(id)
		var label := str(d.get("label", d.get("name", id)))
		if seen.has(label):
			seen[label]["count"] += 1
			continue
		var entry := {"name": label, "count": 1}
		seen[label] = entry
		out.append(entry)
	return out

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
	Game.say(Game.pick("progress_saved"), "save")   # the notepad shows it with a floppy disk
	_checkpoint = snapshot()                         # (after, so the notepad keeps that line too)

func has_checkpoint() -> bool:
	return not _checkpoint.is_empty()

# Puts flags and the ledger back to the checkpoint. times_caught is kept.
func respawn() -> bool:
	if _checkpoint.is_empty():
		return false
	restore(_checkpoint)
	return true

# Flags, the ledger, and every line in the notepad.
func snapshot() -> Dictionary:
	var s := {"flags": Game.flags.duplicate(true), "ledger": ledger.duplicate(true)}
	var notepad := get_tree().get_first_node_in_group("notepad")
	if notepad:
		s["notes"] = notepad.save_lines()
	return s

func restore(s: Dictionary) -> void:
	Game.flags = s.flags.duplicate(true)
	ledger = s.ledger.duplicate(true)
	var notepad := get_tree().get_first_node_in_group("notepad")
	if notepad and s.has("notes"):
		notepad.load_lines(s["notes"])
	restored.emit()

# Clears the run (not the save file).
func reset() -> void:
	ledger.clear()
	times_caught = 0
	_checkpoint = {}
