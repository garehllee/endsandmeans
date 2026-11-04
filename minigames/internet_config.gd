extends MinigameConfig
class_name InternetConfig
# Tunables and pictures for the internet-access minigame.
# The frames come from tools/build_internet_frames.py (art/internet/frames/).

@export_group("Pictures")
@export_dir var frames_dir := "res://art/internet/frames"
@export var instructions_a: Texture2D      # "catch the computer"; shown while the earth spins
@export var instructions_b: Texture2D      # "spam E"; shown while clicking through
@export var loading_image: Texture2D       # the ring that spins over the globe while clicking

@export_group("Animation")
@export var loop_fps := 24.0
@export var transition_fps := 24.0
@export var outro_fps := 24.0
@export var outro_hold := 0.8              # seconds to rest on the last frame before the game ends
@export var click_end_delay := 0.3         # pause after the last click frame before the outro

@export_group("Feel")
@export var hover_radius := 220.0          # how close the player must be to the computer (room units)
@export var loading_size := 360.0          # diameter of the spinning ring (room units)
@export var loading_center := Vector2(0.5, 0.5)   # where the ring sits, as a fraction of the picture
@export var loading_spin := 0.75           # turns per second

@export_group("Loading")
@export var loads_per_frame := 2           # textures loaded per frame; lower = smoother, slower start
