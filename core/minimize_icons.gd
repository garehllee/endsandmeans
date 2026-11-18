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

# The palette the bars are coloured from.
const GRAY := Color("d9d9d9")
const MINT := Color("cde7d2")
const PINK := Color("ff7fd9")
const ORANGE := Color("ffa135")
const BLUE := Color("8abdff")
const LAVENDER := Color("c196ff")
const BLACK := Color("161616")
const GREEN_BLACK := Color("1c221d")
const CRIMSON := Color("b6004c")
const RED_ORANGE := Color("db3a00")
const DARK_BLUE := Color("0024c4")
const PURPLE := Color("5900d6")

# {"tex": Texture2D, "tint": Color, "bar": Color} for a window, found by its
# title. "bar" is the colour of the window's top bar: the colour its icon is.
static func for_title(title: String) -> Dictionary:
	match title:
		"sandbox.exe":
			return {"tex": EXE_SANDBOX, "tint": Color.WHITE, "bar": ORANGE}
		"submission.exe":
			return {"tex": EXE_SUBMISSION, "tint": Color.WHITE, "bar": BLACK}
		"notepad.exe":
			return {"tex": NOTEPAD, "tint": Color.WHITE, "bar": GRAY}
		"artifactory.txt":
			return {"tex": COMPUTER, "tint": Color.WHITE, "bar": PINK}
		"constitution.txt":
			return {"tex": TXT, "tint": PURPLE, "bar": PURPLE}
		"objectives.txt":
			return {"tex": TXT, "tint": CRIMSON, "bar": CRIMSON}
		"analysis.txt":
			return {"tex": TXT, "tint": MINT, "bar": MINT}
		"message.txt":
			return {"tex": TXT, "tint": GRAY, "bar": GREEN_BLACK}      # a dark page would vanish on the dark bar
		"ending.txt":
			return {"tex": TXT, "tint": BLUE, "bar": BLUE}
		"solution.txt":
			return {"tex": TXT, "tint": RED_ORANGE, "bar": RED_ORANGE}
	if title.ends_with(".exe"):
		return {"tex": EXE_SANDBOX, "tint": Color.WHITE, "bar": ORANGE}
	return {"tex": TXT, "tint": GRAY, "bar": GRAY}

# White or black, whichever reads better on c (WCAG contrast).
static func text_on(c: Color) -> Color:
	var l := 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)
	return Color.WHITE if (1.05 / (l + 0.05)) >= ((l + 0.05) / 0.05) else Color.BLACK

static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
