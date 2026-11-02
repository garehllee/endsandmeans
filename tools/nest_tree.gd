@tool
extends EditorScript

const SOURCE := "res://data/generated/tree.json"
const OUTPUT := "res://data/generated/tree_nested.json"
const SEED := 7                    # change for a different arrangement
const MAX_DEPTH := 5               # how many extra levels can be added
const MIN_FILES := 6               # folders with fewer files stay flat
const CHANCE_TOP := 0.7           # chance a top-level folder gets subfolders
const CHANCE_DEEPER := 0.5        # chance a new subfolder gets its own subfolder
const NAMES := ["old", "backup", "drafts", "misc", "untitled", "archive", "favorites",
		"maybe", "unsorted", "copy", "2019", "2021", "scans", "raw", "exports", "temp",
		"do not open", "final", "final_FINAL", "keep", "other", "stuff"]

var rng := RandomNumberGenerator.new()

func _run() -> void:
	var text := FileAccess.get_file_as_string(SOURCE)
	var re := RegEx.new()
	re.compile(",(\\s*[}\\]])")
	text = re.sub(text, "$1", true)   # remove trailing commas
	var tree = JSON.parse_string(text)
	if tree == null:
		push_error("Could not parse " + SOURCE)
		return
	rng.seed = SEED
	for c in tree.children:
		if c.type == "folder":
			_nest(c, 0)
	var f := FileAccess.open(OUTPUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(tree, "\t"))
	f.close()
	EditorInterface.get_resource_filesystem().scan()
	print("Wrote ", OUTPUT)

func _nest(folder: Dictionary, depth: int) -> void:
	if depth >= MAX_DEPTH:
		return
	var chance := CHANCE_TOP if depth == 0 else CHANCE_DEEPER
	if rng.randf() > chance:
		return
	var subfolders := rng.randi_range(1, 2) if depth == 0 else 1
	for i in subfolders:
		var files: Array = folder.children.filter(func(c): return c.type == "file")
		if files.size() < MIN_FILES:
			return
		var take := rng.randi_range(3, files.size() - 2)
		var start := rng.randi_range(0, files.size() - take)
		var chunk: Array = files.slice(start, start + take)
		for c in chunk:
			folder.children.erase(c)
		var sub := {"name": _pick_name(folder), "type": "folder", "children": chunk}
		folder.children.insert(0, sub)   # folders first, like the scanner does
		_nest(sub, depth + 1)

func _pick_name(folder: Dictionary) -> String:
	var taken := {}
	for c in folder.children:
		taken[c.name] = true
	var options: Array = NAMES.filter(func(n): return not taken.has(n))
	if options.is_empty():
		return "folder %d" % rng.randi_range(0, 9999)
	var pick: String = options[rng.randi_range(0, options.size() - 1)]
	return pick
