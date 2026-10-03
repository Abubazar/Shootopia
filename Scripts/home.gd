extends CanvasLayer

@onready var mainScreen: CenterContainer = $home/main
@onready var lobbyScreen: Control = $home/lobby
@onready var settingsScreen: MarginContainer = $home/settings
@onready var select_characterScreen: Control = $"home/select character"
@onready var animplayer: AnimationPlayer = $"home/select character/CenterContainer3/SubViewportContainer/SubViewport/model1/AnimationPlayer"
@onready var models: Skeleton3D = $"home/select character/CenterContainer3/SubViewportContainer/SubViewport/model1/Armature_001/Skeleton3D"
@onready var world: Node3D = $"../World"
@onready var network_manager: Network_manager = $"../Network_manager"

var charIdx = 0
var charNames = [
	"Farmer Joe",
	"King Tod",
	"Astra",
	"Swat",
	"Witch",
	"Trixie",
	"Scout",
	"Adventuress"
]

func _ready() -> void:
	charIdx = Glob.character
	mainScreen.visible = true
	animplayer.play("idle")
	setCharacter(charNames[charIdx])
	world.visible = false


func setCharacter(cNam):
	for char in models.get_children():
		char.visible = true if cNam == char.name else false
	

#home functions
func play():
	mainScreen.visible = false
	lobbyScreen.visible = true
	
func settings():
	mainScreen.visible = false
	settingsScreen.visible = true
	
func select():
	mainScreen.visible = false
	select_characterScreen.visible = true

	
#lobby functions
func host():
	network_manager.create_server()
	
func join():
	network_manager.join_server()
	
func lobby_selected(index):
	pass

func go_back():
	lobbyScreen.visible = false
	settingsScreen.visible = false
	mainScreen.visible = true


#character selection
func prev():
	charIdx = (charIdx-1+8)%8
	setCharacter(charNames[charIdx])
	
func next():
	charIdx = (charIdx+1+8)%8
	setCharacter(charNames[charIdx])
	
func confirm():
	select_characterScreen.visible = false
	mainScreen.visible = true
	Glob.character = charIdx
	Glob.save_data()



func _on_confirm_pressed() -> void:
	confirm()


func _on_prev_btn_pressed() -> void:
	prev()


func _on_next_btn_pressed() -> void:
	next()


func _on_play_btn_pressed() -> void:
	play()


func _on_settings_btn_pressed() -> void:
	settings()


func _on_exit_btn_pressed() -> void:
	get_tree().quit()


func _on_back_btn_pressed() -> void:
	go_back()


func _on_join_btn_pressed() -> void:
	join()


func _on_host_btn_pressed() -> void:
	host()


func _on_lobbies_item_selected(index: int) -> void:
	lobby_selected(index)


func _on_go_back_pressed() -> void:
	go_back()


func _on_select_btn_pressed() -> void:
	select()
