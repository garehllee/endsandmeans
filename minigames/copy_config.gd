extends MinigameConfig
class_name CopyConfig
# Pictures and tunables for the "copy the solution" minigame.
# Positions marked "picture units" are in the 1600 x 1512 layout of the art.

@export_group("Pictures")
@export var instructions: Texture2D
@export var file_sheet: Texture2D                   # spinning folder, built by tools/build_file_spin.py
@export var file_sheet_columns := 10
@export var file_sheet_rows := 12
@export var file_frames := 120
@export var file_fps := 30.0
@export var door_closed: Texture2D
@export var door_open: Texture2D

@export_group("Layout (picture units)")
@export var door_position := Vector2(1354, 957)     # center of the door texture
@export var door_body := Rect2(1250, 733, 208, 387) # the doorway: touching this wins
@export var file_spawn_x := 330.0                   # where the file drops in (left side)
@export var door_open_radius := 420.0               # the door opens when the file comes this close

@export_group("Physics")
@export var gravity := 900.0
@export var bounce := 0.45                          # how much speed the file keeps off the head
@export var min_bounce_speed := 400.0               # a head hit always sends it at least this fast upward
@export var header_push := 100.0                    # sideways kick for hitting off-center
@export_range(0.0, 1.0) var side_response := 0.3   # how much of a hit's sideways push the file keeps (1 = all of it)
@export var side_drag := 0.6                        # slows sideways drift in the air, per second
@export var wall_bounce := 0.8
@export var head_offset := Vector2(0, -70)          # head circle, relative to the character
@export var head_radius := 60.0
@export var file_radius := 80.0
@export var file_width := 255.0                     # drawn width of the folder
@export var respawn_delay := 0.7                    # pause before a dropped file comes back
@export var enter_time := 0.55                      # the file sliding into the door
@export var debug_draw := false                     # show the collision circles
