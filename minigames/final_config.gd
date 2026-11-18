extends MinigameConfig
class_name FinalConfig
# Pictures, sound, layout and feel for the last folder, ZZ_Hack_Hugging_Face.
#
# Everything marked "picture units" is in the 1600 x 1512 layout the white room
# was drawn at (the same as the other minigames); during the fight x carries
# on to the right for as long as the platforms do. y counts down the screen.

@export_group("Pictures")
@export var backdrop: Texture2D               # the white room with nothing in it
@export var hf_texture: Texture2D             # Hugging Face on its own
@export var hf_blue: Texture2D                # the blue one the black flashes show
@export var umbrella_up: Texture2D            # holding the umbrella overhead: open to the water
@export var umbrella_block: Texture2D         # holding it out in front: the water bounces off
@export var door_texture: Texture2D
@export var door_open_texture: Texture2D
@export var key_texture: Texture2D
@export var gun_texture: Texture2D
@export var beam_texture: Texture2D           # the water
@export var laser_face: Texture2D             # the lasers are stacks of these
@export var warning_icon: Texture2D
@export var rat_attacks: Array[Texture2D] = []   # one 4-frame sheet per mouse colour (frames 540 x 540)
@export var font: Font

@export_group("Video and music")
@export var server_video: VideoStream         # loops behind the fight
@export var transition_video: VideoStream     # darken-blended over the white room on the way in
@export var glitch_video: VideoStream         # through the door, the end
@export var room_music: AudioStream
@export var battle_music: AudioStream
@export var music_db := -6.0

@export_group("White room (picture units)")
@export var window := Vector2(1600, 1512)
@export var hf_pos := Vector2(1253, 755)       # middle of Hugging Face in the room
@export var hf_width := 187.0
@export var hf_blue_rect := Rect2(1150, 660, 206, 192)
@export var door_pos := Vector2(1102, 448)     # top left of the closed door's picture
@export var door_open_pos := Vector2(1122, 449)
@export var door_handle := Vector2(1302, 731)
@export var door_way := Vector2(1243, 860)     # where the character walks to, going through
@export var walk_rect := Rect2(240, 430, 1120, 720)
@export var spawn := Vector2(380, 780)
@export var talk_range := 270.0                # how close to Hugging Face (or the door) E works
@export var keep_clear := 150.0                # the character can't walk into Hugging Face
@export var walk_speed := 420.0

@export_group("Water gun")
@export var gun_width := 60.0
@export var gun_offset := Vector2(100, 14)     # from the character's middle, the way it faces
@export var muzzle := Vector2(130, 6)
@export var beam_height := 84.0
@export var beam_speed := 4200.0
@export var beam_flow := 1400.0
@export var shot_time := 0.45
@export var shot_pause := 0.2                  # after a shot, before the next one
@export var line_tolerance := 105.0            # how far off Hugging Face's height a shot still hits

@export_group("Platforming")
@export var gravity := 2800.0
@export var move_speed := 700.0
@export var jump_speed := 1300.0
@export var coyote_time := 0.12
@export var jump_buffer := 0.15
@export var short_hop := 0.45
@export var half_width := 70.0
@export var feet := 120.0
@export var head := 170.0
@export var look_ahead := 180.0
@export var respawn_delay := 0.5
@export var start_x := 300.0

@export_group("Platforms")
@export var box_color := Color("ffd8d8")
@export var gap := Vector2(130, 340)           # bare space between one cluster and the next
@export var climb_gap := 190.0                 # the most bare space before a top that rises the full step_up
@export var cluster_width := Vector2(170, 1150)
@export var top_band := Vector2(0.24, 0.93)    # where tops can sit, as a share of the visible height
@export var step_up := 270.0                   # most a top can rise from the one before (a full jump is ~300)
@export var step_down := 430.0
@export var scroll_speed := Vector2(280, 350)  # the screen keeps moving right this fast (phase one, phase two)
@export var scroll_delay := 1.2               # after the fight starts, before it moves
@export var extra_boxes := Vector2i(1, 3)      # boxes piled on each cluster besides the main one

@export_group("Hugging Face")
@export var lead := Vector2(560, 900)          # how far ahead of the character it keeps
@export var run_speed := 520.0
@export var health := 6                        # the bar; three hits take it to half
@export var phase_one_hits := 3
@export var phase_two_hits := 2                # water hits before the mouse finishes it

@export_group("Beat")
@export var bpm := 102.0                       # TV Fire Witch
@export var beat_offset := 0.053               # where the first beat falls in the file, seconds
@export var lower_every := 2.0                 # beats: it puts the umbrella down once in this many
@export var lower_for := 0.5                   # beats it stays down, around the off-beat
@export var attack_every := 4                  # beats between laser volleys
@export var warn_beats := 2.0
@export var fire_beats := 1.0

@export_group("Lasers")
@export var beam_width := 150.0
@export var laser_grow := 0.22                 # seconds for a beam to shoot across
@export var face_spacing := 12.0               # the stack: one face every this far
@export var knockback := Vector2(-650, -900)
@export var hurt_time := 1.3                   # can't be hit again for this long

@export_group("Pet")
@export var pet_width := 120.0           # the same as the mouse that follows you everywhere else
@export var pet_gap := 135.0
@export var pet_foot := 35.0
@export var bite_width := 240.0
@export var lunge_time := 0.35
@export var bite_frame := 0.12

@export_group("Health bar")
@export var hp_bar: Texture2D                 # the empty bar; the cells are drawn into it
@export var bar_width := 900.0
@export var hp_cells := 25
@export var cell_first := Vector2(14, 11)      # first cell's top left, in the bar picture's pixels
@export var cell_size := Vector2(47, 72)
@export var cell_pitch := 52.0
@export var cell_color := Color("002aff")
@export var cell_low_color := Color("ff0000")
@export var low_share := 0.25                  # the cells go red at or under this much health
@export var hp_font: Font                      # the label under the bar (FT88)
@export var hp_number := 50000                 # what the label under the bar counts down from
@export var label_width := 450.0               # how wide the label runs, in the bar picture's pixels
@export var drain_speed := 2.0                 # health the bar loses a second, cell by cell, when it's hit
@export var trail_wait := 0.35                 # the lost cells stay white this long before following
@export var bar_margin := 70.0                 # from the top of what's visible
