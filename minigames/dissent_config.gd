extends MinigameConfig
class_name DissentConfig
# Pictures, layout and feel for the "silence the dissenting AI" minigame.
# The backdrop is the config's arena_image (an off-colour copy of the sandbox).
# Positions are in picture units, the 1600 x 1512 layout the art was drawn at.

@export_group("Pictures")
@export var gun_texture: Texture2D
@export var beam_texture: Texture2D            # the water, drawn as a strip that flows out of the gun
@export var font: Font

@export_group("Layout (picture units)")
@export var window := Vector2(1600, 1512)
@export var orange_pos := Vector2(1145, 745)    # where the orange AI stands
@export var walk_rect := Rect2(400, 470, 800, 430)   # the part of the room the character can walk in
@export var keep_clear := 125.0                 # the character can't walk into the orange AI

@export_group("Gun")
@export var gun_width := 90.0
@export var gun_offset := Vector2(162, 23)      # from the character's middle, toward the orange AI
@export var muzzle := Vector2(206, 10)          # from the character's middle: where the water comes out
@export var beam_height := 125.0

@export_group("Feel")
@export var move_speed := 420.0
@export var line_tolerance := 70.0              # how far off the orange AI's line a shot can be and still hit
@export var beam_speed := 4200.0                # how fast the water reaches out
@export var beam_flow := 1400.0                 # how fast the water ripples along
@export var beam_hold := 0.7                    # how long it keeps firing
@export var miss_pause := 0.35                  # after a miss, before the next shot
@export var death_time := 0.8
@export var end_hold := 0.6
