@tool
extends EditorScript

const SOURCE_DIR := "res://artifactory"
const THUMB_DIR := "res://thumbs"
const TREE_IN := "res://data/tree_nested.json"    # or tree.json, whichever you use
const TREE_OUT := "res://data/tree_thumbs.json"
const MAX_H := 900
const MAX_W := 1600          # stops very wide panoramas from getting huge
const JPG_QUALITY := 0.85

var made := 0
var skipped := 0
var failed := 0

func _run() -> void:
	var text := FileAccess.get_file_as_string(TREE_IN)
	var re := RegEx.new()
	re.compile(",(\\s*[}\\]])")
	text = re.sub(text, "$1", true)          # strip trailing commas
	var tree = JSON.parse_string(text)
	if tree == null:
		push_error("Could not parse " + TREE_IN)
		return

	_walk(tree)

	var f := FileAccess.open(TREE_OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(tree, "\t"))
	f.close()
	EditorInterface.get_resource_filesystem().scan()
	print("Thumbnails made: %d, already existed: %d, failed: %d" % [made, skipped, failed])
	print("Wrote ", TREE_OUT)

func _walk(folder: Dictionary) -> void:
	for c in folder.get("children", []):
		if c.type == "folder":
			_walk(c)
		else:
			var src: String = c.get("path", "")
			if src.begins_with(SOURCE_DIR):
				var dst := THUMB_DIR + src.trim_prefix(SOURCE_DIR)
				if _make_thumb(src, dst):
					c["path"] = dst

func _make_thumb(src: String, dst: String) -> bool:
	if FileAccess.file_exists(dst):
		skipped += 1
		return true
	var img := Image.load_from_file(src)
	if img == null:
		push_warning("Could not load " + src)
		failed += 1
		return false
	var scale := minf(minf(float(MAX_H) / img.get_height(), float(MAX_W) / img.get_width()), 1.0)
	if scale < 1.0:
		img.resize(maxi(1, roundi(img.get_width() * scale)),
				maxi(1, roundi(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var err := OK
	match dst.get_extension().to_lower():
		"png":
			err = img.save_png(dst)
		"webp":
			err = img.save_webp(dst, true, JPG_QUALITY)
		_:
			err = img.save_jpg(dst, JPG_QUALITY)
	if err != OK:
		push_warning("Could not save " + dst)
		failed += 1
		return false
	made += 1
	return true
