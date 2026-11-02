extends MinigameConfig
class_name EraseConfig
# Tunables and pictures for the "erase the rules" minigame.

@export_group("Pictures")
@export var text_layer: Texture2D          # the erasable text (transparent PNG)
@export var eraser: Texture2D
@export var instructions: Texture2D        # drawn on top of everything

@export_group("Feel")
@export_range(0.05, 1.0) var target_fraction := 0.6   # how much of the text must go
@export var erase_radius := 60.0           # room units: how wide a swipe is
@export var eraser_scale := 0.8
@export var eraser_offset := Vector2(95, 30)   # eraser position relative to the character (right side)
@export_range(0.1, 1.0) var mask_scale := 0.5  # erase-mask resolution; lower is cheaper
