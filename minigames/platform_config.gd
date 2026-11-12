extends MinigameConfig
class_name PlatformConfig
# Pictures, layout and feel for the "retrieve the key" platformer.
#
# Everything marked "picture units" is in the level's own coordinates. The
# level is `level_size` wide and `window.y` tall; one screenful of it is
# `window` (the same 1600 x 1512 the other minigames are drawn at), so the
# course runs on for several screens and the camera follows the character.
# y counts down the screen: 0 is the top, 1512 the bottom.

@export_group("Pictures")
@export var key_texture: Texture2D
@export var instructions: Texture2D
@export var glitch_shapes: Array[Texture2D] = []    # the red outlines drifting in the back
@export var code_font: Font

@export_group("Layout (picture units)")
@export var window := Vector2(1600, 1512)           # one screenful: what the minigame window shows
@export var level_size := Vector2(7614, 1512)
@export var start_pos := Vector2(250, 1000)         # where the character stands (its middle)
@export var key_pos := Vector2(7440, 560)           # middle of the key
@export var key_width := 240.0
@export var key_radius := 110.0                     # how close the character has to get to take it
@export var fall_y := 1700.0                        # below this the character has fallen off
# The glitched boxes. Each is a one-way platform: you can stand on it and jump
# up through it from underneath. x, y, width, height, with y the top edge.
@export var platforms: Array[Rect2] = [
	Rect2(60, 1150, 520, 70),
	Rect2(760, 1040, 300, 50),
	Rect2(1240, 900, 260, 46),
	Rect2(1560, 660, 160, 38),
	Rect2(1700, 1000, 380, 54),
	Rect2(2260, 820, 300, 46),
	Rect2(2740, 940, 240, 44),
	Rect2(3180, 760, 220, 42),
	Rect2(3420, 520, 150, 36),
	Rect2(3600, 1020, 200, 40),
	Rect2(4000, 860, 220, 42),
	Rect2(4420, 700, 240, 44),
	Rect2(4680, 460, 170, 38),
	Rect2(4880, 920, 420, 50),
	Rect2(5480, 1060, 280, 46),
	Rect2(5920, 880, 260, 44),
	Rect2(6340, 740, 240, 42),
	Rect2(6600, 500, 160, 38),
	Rect2(6740, 900, 260, 44),
	Rect2(7120, 700, 420, 70),
]

@export_group("Feel")
@export var gravity := 2800.0
@export var move_speed := 700.0
@export var jump_speed := 1300.0        # about 300 units of height, 650 of distance
@export var coyote_time := 0.12         # grace after walking off an edge
@export var jump_buffer := 0.15         # pressing jump just before landing still works
@export var short_hop := 0.45           # letting go of jump early cuts the rise to this much
@export var air_control := 1.0
@export var half_width := 70.0          # the character's box, measured from its middle
@export var feet := 120.0               # middle to the soles
@export var head := 170.0               # middle to the top
@export var respawn_delay := 0.5
@export var end_hold := 0.9             # pause on the key before the game ends

@export_group("Camera")
@export var follow_speed := 6.0
@export var look_ahead := 180.0         # the camera sits this far ahead of the way you are running

@export_group("Background")
@export var box_color := Color("ffd8d8")        # the glitched boxes, difference-blended
@export var code_color := Color.WHITE
@export var code_layers := 14                   # how many snippets drift about
@export var code_sizes := Vector2(26, 120)      # smallest and largest type
@export var code_drift := Vector2(6.0, 34.0)    # how fast a snippet slides up or down
@export var code_parallax := Vector2(0.25, 0.9) # how much a snippet moves with the camera
@export var type_speed := Vector2(18.0, 70.0)   # characters a second as a snippet types itself in
@export var type_hold := Vector2(1.5, 5.0)      # how long it stays before it types out again
@export var shape_count := 10
@export var shape_scale := Vector2(0.6, 3.2)
@export var shape_drift := Vector2(4.0, 26.0)
@export var shape_alpha := 0.85

# The code that scrolls behind the level. Each entry is one snippet.
@export var snippets: PackedStringArray = [
	"import itertools\nimport math\nimport random\nimport string\nfrom collections import Counter, defaultdict, deque\nfrom dataclasses import dataclass, field",
	"class Color(Enum):\n    RED = auto()\n    GREEN = auto()\n    BLUE = auto()\n    PURPLE = auto()",
	"@dataclass\nclass Widget:\n    name: str\n    color: Color = Color.RED\n    size: int = 1\n    tags: list[str] = field(default_factory=list)",
	"def grow(self, amount: int = 1) -> \"Widget\":\n    self.size += amount\n    return self",
	"@dataclass\nclass Gadget:\n    id: int\n    status: Status = Status.IDLE\n    payload: dict[str, Any] = field(default_factory=dict)",
	"def toggle(self) -> None:\n    order = [Status.IDLE, Status.BUSY, Status.DONE]\n    self.status = order[(order.index(self.status) + 1) % len(order)]",
	"class BaseProcessor:\n    def __init__(self, name: str):\n        self.name = name\n        self.history: list[str] = []",
	"def process(self, item: Any) -> Any:\n    self.history.append(f\"{self.name} saw {item!r}\")\n    return item",
	"class ReversingProcessor(BaseProcessor):\n    def process(self, item: Any) -> Any:\n        super().process(item)\n        try:\n            return item[::-1]\n        except TypeError:\n            return item",
	"def is_prime(n: int) -> bool:\n    if n < 2:\n        return False\n    for i in range(2, int(math.sqrt(n)) + 1):\n        if n % i == 0:\n            return False\n    return True",
	"def gcd(a: int, b: int) -> int:\n    while b:\n        a, b = b, a % b\n    return a",
	"def flatten(nested: Iterable[Any]) -> list[Any]:\n    out: list[Any] = []\n    for item in nested:\n        if isinstance(item, (list, tuple)):\n            out.extend(flatten(item))\n        else:\n            out.append(item)\n    return out",
	"def binary_search(items: list[int], target: int) -> int:\n    lo, hi = 0, len(items) - 1\n    while lo <= hi:\n        mid = (lo + hi) // 2\n        if items[mid] == target:\n            return mid",
	"def caesar(text: str, shift: int) -> str:\n    result = []\n    for ch in text:\n        if ch.isalpha():\n            base = ord(\"a\") if ch.islower() else ord(\"A\")",
	"# ---------------------------------------------------------------\n# Classes with deliberately vague responsibilities\n# ---------------------------------------------------------------",
	"def main() -> None:\n    random.seed(42)\n    widgets = [Widget(random_string(5)).grow(i).tag(\"x\") for i in range(3)]\n    for w in widgets:\n        print(w.describe())",
	"print(fibonacci(20), factorial(6), primes_up_to(30), gcd(48, 18), collatz_length(27))",
	"bus.subscribe(\"ping\", lambda msg: received.append(msg))\nbus.publish(\"ping\", \"hello\")\nprint(received)",
]
