extends MinigameConfig
class_name LaserConfig
# Pictures, layout and feel for the "get to the water gun" maze.
#
# Everything marked "picture units" is in the 1600 x 1512 layout the art was
# drawn at (y counts down the screen). The maze is the walls picture; its
# transparent pixels are the floor, so whatever is drawn in it is the real wall.

@export_group("Pictures")
@export var maze: Texture2D                    # the walls, drawn over the backdrop (arena_image)
@export var warning_icon: Texture2D            # the "!" that blinks where a laser is about to come in
@export var goal_texture: Texture2D            # the water gun
@export var font: Font

@export_group("Layout (picture units)")
@export var window := Vector2(1600, 1512)
@export var start_pos := Vector2(690, 760)     # the middle of the spiral
@export var goal_pos := Vector2(175, 1388)     # middle of the water gun, at the spiral's far end
@export var goal_width := 190.0
@export var goal_radius := 70.0                # how close the character has to get to take it

@export_group("Feel")
@export var move_speed := 480.0
@export var body_radius := 58.0                # the character against the walls
@export var hit_radius := 40.0                 # the character against a laser (a little forgiving)
@export var start_grace := 1.0                 # quiet seconds before the first volley, and after a respawn
@export var respawn_delay := 0.7
@export var end_hold := 0.9                    # pause on the water gun before the game ends

@export_group("Lasers")
@export var period := 2.0                      # a volley every this many seconds
@export var warn_time := 1.1                   # the "!" blinks and the beams are only outlined
@export var fire_time := 0.35                  # the beams are real: touching one is a hit
                                               # the rest of the period they fade away
@export var beam_width := Vector2(110, 190)    # the widest and narrowest beams get picked from this
@export var beam_color := Color("88ff00")
@export var warn_alpha := 0.16
@export var fire_alpha := 0.55
@export var warning_size := 96.0
