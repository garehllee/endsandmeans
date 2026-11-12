extends MinigameConfig
class_name PetShopConfig
# Pictures, layout and feel for the "virtual pet shop" minigame.
# The backdrop is the config's arena_image. Positions are in picture units, the
# 1600 x 1512 layout the art was drawn at. The mice are drawn facing left and
# are flipped to face the way they go.

@export_group("Pictures")
@export var mice: Array[Texture2D] = []

@export_group("Layout (picture units)")
@export var window := Vector2(1600, 1512)
@export var start_pos := Vector2(718, 805)               # where the character stands (its middle)
@export var walk_rect := Rect2(205, 265, 1190, 985)       # where the character can walk: the shop floor
@export var mouse_rect := Rect2(205, 265, 1190, 985)      # where the mice can go
@export var mouse_starts := PackedVector2Array([Vector2(290, 330), Vector2(750, 330),
		Vector2(1135, 410), Vector2(460, 775), Vector2(1150, 970), Vector2(350, 1145)])
@export var mouse_width := 120.0
@export var touch_radius := 110.0                         # touching a mouse: close enough to adopt it

@export_group("Mice")
@export var flee_radius := 380.0                          # inside this a mouse is scared
@export var approach_chance := 0.05                       # a scared mouse sometimes walks up instead
@export var flee_speed := 470.0
@export var approach_speed := 360.0
@export var scoot_speed := 260.0
@export var scoot_chance := 0.5                           # a calm mouse, per decision, sets off somewhere
@export var decision_time := Vector2(0.3, 0.6)            # how often a scared mouse makes up its mind
@export var wall_margin := 70.0
@export var wiggle := 0.035                              # how far a running mouse rocks side to side (radians)
@export var idle_time := Vector2(0.4, 1.0)                # how long a calm mouse sits between scoots
@export var scoot_time := Vector2(0.5, 1.3)               # how long a scoot lasts

@export_group("Feel")
@export var adopt_hold := 1.5                             # pause on the adoption before the game ends
