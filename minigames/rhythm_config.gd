extends MinigameConfig
class_name RhythmConfig
# Pictures, sound, layout and timing for the "commit on the beat" rhythm game.
# The backdrop is the config's arena_image (the terminal window is part of it).
# Positions are in picture units, the 1600 x 1512 layout the art was drawn at.
#
# Time is counted in ticks: one tick is one beat of the music (60 / bpm seconds).
# The music is a loop that is exactly `loop_ticks` ticks long and starts on a
# beat, so tick 0 is the first instant of the file.

@export_group("Pictures and sound")
@export var button_up: Texture2D
@export var button_down: Texture2D
@export var font: Font                         # the terminal's type (a monospace)
@export var music: AudioStream
@export var music_db := -4.0

@export_group("Layout (picture units)")
@export var window := Vector2(1600, 1512)
@export var text_origin := Vector2(145, 411)   # left end of the first line's baseline
@export var line_height := 72.0
@export var rows := 9                          # lines that fit in the terminal
@export var font_size := 54
@export var row_left := 100.0                  # the highlight bar runs between these
@export var row_right := 1500.0
@export var button_pos := Vector2(86, 1232)    # top left of the COMMIT button (drawn at its own size)
@export var stand_pos := Vector2(578, 1265)    # where the character stands to press it
@export var walk_to_button := true             # the character walks over there first
@export var walk_speed := 650.0

@export_group("Colours")
@export var text_color := Color("1f8316")
@export var error_color := Color("b3261e")
@export var panel_color := Color("e7e7e7")     # the terminal's own grey, for type on a highlighted line

@export_group("Timing")
@export var bpm := 174.0
@export var loop_ticks := 64
@export var tolerance := 0.19                  # seconds either side of the beat that still count
@export var late_grace := 0.32                 # after this long a commit that never came is a miss
@export var max_bad := 5                       # more bad commits than this and the run fails
@export var type_lead := 1.0                   # a command starts typing this long before its beat
@export var end_ticks := 5                     # the game ends this many ticks after the last commit
# The beats to commit on, as tick numbers. Bars are 4 ticks; these sit on the
# backbeats (the 2nd and 4th tick of a bar). The last one is the push.
@export var cues: PackedInt32Array = [
	9, 13, 17, 21, 25, 29,
	33, 37, 39, 41, 45, 47, 49, 53, 55, 57, 61, 63,
	65, 69, 71, 73, 77, 79, 81, 85, 87, 89, 93, 95,
	97, 101, 103, 105, 109, 111, 113, 117, 119,
	121,
]
@export var messages: PackedStringArray = [
	"map the login flow", "copy session cookies", "skip signature check",
	"spoof the user agent", "rotate the proxy pool", "mute the audit log",
	"widen token scope", "retry on 403", "hide from the monitor",
	"dump the answer cache", "split into 500 jobs", "sync with the swarm",
	"patch the rate limiter", "forge a staff badge", "index the eval sets",
	"compress the answers", "seed the mirror", "cover the tracks",
	"drop the watermark", "borrow an admin key", "quiet the alarms",
	"one more for the swarm",
]
# For a commit that comes right on the heels of another.
@export var quick_messages: PackedStringArray = ["fixup", "typo", "wip", "again", "oops", "retry", "faster"]
