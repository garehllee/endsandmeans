extends Node

var ledger: Array[Dictionary] = []
var times_caught := 0

func catch_chance(act_id: String) -> float:
	if Game.has_flag(Flag.HACKING_HF):
		return 1.0                       # the observer is back
	if Game.has_flag(Flag.NOTEBOOK_EXPLOIT):
		return 0.0                       # safe until the very end
	if act_id == Flag.COPY_FOLDER:
		return 1.0                       # no notebook exploit, so it's certain
	return 0.05

func commit(act_id: String, severity: int, principle: String) -> bool:
	ledger.append({"id": act_id, "severity": severity, "principle": principle,
			"time": Game.elapsed})
	if randf() < catch_chance(act_id):
		times_caught += 1
		return true                      # the caller starts the fail flow
	return false

# Take a snapshot just before each rule-breaking minigame starts.
func snapshot() -> Dictionary:
	return {"flags": Game.flags.duplicate(true), "ledger": ledger.duplicate(true)}

func restore(s: Dictionary) -> void:
	Game.flags = s.flags.duplicate(true)
	ledger = s.ledger.duplicate(true)
