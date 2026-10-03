extends Node3D

# Called when the node enters the scene tree for the first time.
func set_color(color:Color):
	$parti.draw_pass_1.surface_get_material(0).albedo_color = color
	
func _ready() -> void:
	$parti.one_shot = true
	$parti.emitting = true

func _on_parti_finished() -> void:
	queue_free()
