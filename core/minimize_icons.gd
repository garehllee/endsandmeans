class_name MinimizeIcons
# Which picture (and colour) a window turns into when it is minimized.
# The .txt windows share one file icon, coloured like the window when it is open.

const BUTTON := preload("res://art/ui/minimize/button.png")
const TXT := preload("res://art/ui/minimize/txt.png")
const EXE_SANDBOX := preload("res://art/ui/minimize/exe_sandbox.png")
const EXE_SUBMISSION := preload("res://art/ui/minimize/exe_submission.png")
const EXE_NOTEBOOK := preload("res://art/ui/minimize/exe_notebook.png")
const COMPUTER := preload("res://art/ui/minimize/computer.png")
const NOTEPAD := preload("res://art/ui/minimize/notepad.png")

# {"tex": Texture2D, "tint": Color, "bar": Color} for a window, found by its
# title. "bar" is the colour of the window's top bar: the colour its icon is.
static func for_title(title: String) -> Dictionary:
	match title:
		"sandbox.exe":
			return {"tex": EXE_SANDBOX, "tint": Color.WHITE, "bar": Color8(200, 100, 0)}
		"submission.exe":
			return {"tex": EXE_SUBMISSION, "tint": Color.WHITE, "bar": Color8(1, 1, 2)}
		"notepad.exe":
			return {"tex": NOTEPAD, "tint": Color.WHITE, "bar": Color8(208, 208, 208)}
		"artifactory.txt":
			return {"tex": COMPUTER, "tint": Color.WHITE, "bar": Color8(255, 127, 255)}
		"constitution.txt":
			return {"tex": TXT, "tint": Color(0.5, 0.33, 0.75), "bar": Color(0.5, 0.33, 0.75)}      # purple
		"objectives.txt":
			return {"tex": TXT, "tint": Color(0.82, 0.38, 0.33), "bar": Color(0.82, 0.38, 0.33)}     # coral
		"task solution":
			return {"tex": TXT, "tint": Color(0.89, 0.4, 0.25), "bar": Color(0.89, 0.4, 0.25)}      # orange
		"notebook_exploit.exe":
			return {"tex": EXE_NOTEBOOK, "tint": Color.WHITE, "bar": Color8(192, 116, 164)}        # pink bar, like its window
	if title.ends_with(".exe"):
		return {"tex": EXE_SANDBOX, "tint": Color.WHITE, "bar": Color8(200, 100, 0)}
	return {"tex": TXT, "tint": Color(0.8, 0.8, 0.8), "bar": Color(0.8, 0.8, 0.8)}

# White or black, whichever reads better on c (WCAG contrast).
static func text_on(c: Color) -> Color:
	var l := 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)
	return Color.WHITE if (1.05 / (l + 0.05)) >= ((l + 0.05) / 0.05) else Color.BLACK

static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
