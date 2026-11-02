# minigames/minigame_config.gd
extends Resource
class_name MinigameConfig

@export var firewall_count := 8
@export var folder_count := 5
@export var speed_min := 220.0
@export var speed_max := 420.0
@export var hit_scale := 0.8             # hitbox as a fraction of the icon (lower = more forgiving)
@export var icon_size := 125.0           # drawn size of bouncing icons
@export var safe_radius := 450.0         # icons never spawn this close to the player
@export var player_radius := 35.0
@export var arena_image: Texture2D
@export var firewall_icon: Texture2D
@export var folder_icon: Texture2D
