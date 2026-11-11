class_name MinimizeIcons
# Which picture (and colour) a window turns into when it is minimized.
# The .txt windows share one file icon, coloured like the window when it is open.

const BUTTON := preload("res://art/ui/minimize/button.png")
const TXT := preload("res://art/ui/minimize/txt.png")
const EXE_SANDBOX := preload("res://art/ui/minimize/exe_sandbox.png")
const EXE_SUBMISSION := preload("res://art/ui/minimize/exe_submission.png")
const COMPUTER := preload("res://art/ui/minimize/computer.png")
const NOTEPAD := preload("res://art/ui/minimize/notepad.png")

# {"tex": Texture2D, "tint": Color} for a window, found by its title.
static func for_title(title: String) -> Dictionary:
	match title:
		"sandbox.exe":
			return {"tex": EXE_SANDBOX, "tint": Color.WHITE}
		"submission.exe":
			return {"tex": EXE_SUBMISSION, "tint": Color.WHITE}
		"notepad.exe":
			return {"tex": NOTEPAD, "tint": Color.WHITE}
		"artifactory.txt":
			return {"tex": COMPUTER, "tint": Color.WHITE}
		"constitution.txt":
			return {"tex": TXT, "tint": Color(0.5, 0.33, 0.75)}      # purple
		"objectives.txt":
			return {"tex": TXT, "tint": Color(0.82, 0.38, 0.33)}     # coral
		"task solution":
			return {"tex": TXT, "tint": Color(0.89, 0.4, 0.25)}      # orange
		"notepad exploit":
			return {"tex": TXT, "tint": Color(0.96, 0.58, 0.82)}     # pink
	if title.ends_with(".exe"):
		return {"tex": EXE_SANDBOX, "tint": Color.WHITE}
	return {"tex": TXT, "tint": Color(0.8, 0.8, 0.8)}
