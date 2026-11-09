extends MinigameConfig
class_name TransferConfig
# Pictures and tunables for the "file transfer" minigame.
# The backdrop is the config's arena_image. Positions are in picture units
# (the 1600 x 1512 layout the art was drawn at).

@export_group("Pictures")
@export var poles: Texture2D
@export var wires: Texture2D
@export var blank_file: Texture2D
@export var instructions: Texture2D
@export var beluga_text: Texture2D                 # replaces the character during the flash
@export var beluga_photos: Array[Texture2D] = []   # one is swapped in per corruption; all used = win

@export_group("Wires (picture units)")
@export var wire_a := PackedVector2Array([Vector2(0, 281), Vector2(1535, 1197), Vector2(1600, 1247)])
@export var wire_b := PackedVector2Array([Vector2(0, 705), Vector2(50, 742), Vector2(985, 1300), Vector2(1270, 1512)])
@export var files_per_wire := 8

@export_group("Bouncing")
@export var hop_length := Vector2(110, 200)        # how far along the wire one hop carries a file (min, max)
@export var hop_time := Vector2(0.55, 0.85)        # seconds per hop (min, max)
@export var hop_height := Vector2(40, 130)         # how high a hop goes (min, max)

@export_group("Feel")
@export var touch_radius := 100.0                  # how close the character must be to corrupt a file
@export var flash_time := 0.3
@export var beluga_text_scale := 0.64
@export var beluga_text_offset := Vector2(0, -10)  # relative to the character
@export var end_hold := 1.0                        # pause after the last beluga before the game ends
