extends CharacterBody3D

# MOVEMENT

var SPEED := 8.0
const JUMP_VELOCITY := 8.5
const GRAVITY := Vector3(0, -20, 0)

@onready var head = $spine/head
@onready var camera = $spine/head/Camera3D
@onready var spine3d = $spine
@onready var rayCast = $spine/RayCast3D
@onready var healthBar = $spine/head/Camera3D/CanvasLayer/MarginContainer/ProgressBar
@onready var weapon_map = $spine/head/Camera3D/CanvasLayer/Control/PanelContainer/MarginContainer/weaponMap
@onready var killCounter: Label = $"spine/head/Camera3D/CanvasLayer/kills label"
@onready var kill_status: ItemList = $"spine/head/Camera3D/CanvasLayer/kill status"


@onready var particle = preload("res://Scenes/particle.tscn")


# PLAYER

@onready var model = $characters
var playerName = "Player"
@onready var playerLabel: Label3D = $PlayerName
var health = 100
var damage = 0
var waitingRespawn = false
var reloading = false
var changing = false
var weaponToChange = null
var killCount = 0
var trappedMouse = false

#players
@export_enum(
	"Farmer Joe",
	"King Tod",
	"Astra",
	"Swat",
	"Adventuress",
	"Scout",
	"Witch",
	"Trixie"
)
var character_type := "Farmer Joe"

@onready var skeleton = $characters/Armature_001/Skeleton3D
@onready var animTree = $characters/AnimationTree
@onready var animPlayer = $characters/AnimationPlayer
@onready var spine_ik = $characters/Armature_001/Skeleton3D/SkeletonIK3D
@onready var ragdollSkeleton = $characters/Armature_001/Skeleton3D/PhysicalBoneSimulator3D

func setName(cNam):
	playerLabel.text = cNam
	playerName = cNam
	
func setup_character():
	for character in skeleton.get_children():
		character.visible = character.name == character_type

		if character.name == character_type and is_multiplayer_authority():
			character.get_node("body").hide()
			playerLabel.hide()

	spine_ik.start()
	setup_weapon()

# WEAPONS

@export_enum(
	"Pistol",
	"Assault Rifle",
	"Shotgun",
	"Sniper Rifle",
	"Submachine Gun"
)
var currentWeapon := "Pistol"

@onready var gunParent = $characters/Armature_001/Skeleton3D/BoneAttachment3D
@onready var guns = gunParent.get_node("guns")

func setGun(cNam: String):
	var item = cNam+"Img"
	for gun in weapon_map.get_children():
		if gun.name == item:
			gun.material.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		else:
			gun.material.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX

var weaponsInventory = {
	"Pistol": {
		"magazine": 15,
		"reload": 15,
		"ammo": 60,
		"damage": 25,
		"cooldown": 0.25
	},

	"Assault Rifle": {
		"magazine": 30,
		"reload": 30,
		"ammo": 120,
		"damage": 25,
		"cooldown": 0.09
	},

	"Shotgun": {
		"magazine": 8,
		"reload": 8,
		"ammo": 40,
		"damage": 80,
		"cooldown": 0.80
	},

	"Sniper Rifle": {
		"magazine": 5,
		"reload": 5,
		"ammo": 20,
		"damage": 100,
		"cooldown": 1.20
	},

	"Submachine Gun": {
		"magazine": 30,
		"reload": 30,
		"ammo": 120,
		"damage": 18,
		"cooldown": 0.065
	}
}

func showWeaponInfo():
	for gun in weapon_map.get_children():
		var prop = weaponsInventory[gun.name.trim_suffix("Img")]
		var item = str(prop["magazine"]) + "/" + str(prop["ammo"])
		gun.get_node("Label").text = item
	
func setup_weapon():
	gunParent.visible = true

	for gun in guns.get_children():
		gun.visible = gun.name == currentWeapon

		if gun.name == currentWeapon:
			currentWeapon = gun.name
	
	setGun(currentWeapon)
	showWeaponInfo()


#weapon shooting system
var shootCooldown = 0
func shootSystem(delta):
	if isShooting:
		if shootCooldown >= weaponsInventory[currentWeapon]["cooldown"] && weaponsInventory[currentWeapon]['magazine'] > 0:
			animTree.set("parameters/shoot/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			weaponsInventory[currentWeapon]["magazine"]-=1
			shootCooldown = 0
			showWeaponInfo()
			rayCast.force_raycast_update()
			if rayCast.is_colliding():
				var hit = rayCast.get_collider()
				
				var parti = particle.instantiate()
				get_tree().current_scene.add_child(parti)
				parti.global_position = rayCast.get_collision_point()
				var normal = rayCast.get_collision_normal()
				parti.look_at(parti.global_position + normal, Vector3.UP)
				if hit.collision_layer == 2 or hit.name == "headArea":
					if hit.health >0:
						hit.gotHit("body",weaponsInventory[currentWeapon]['damage'],playerName)
						parti.set_color(Color("ff0000"))
				else:
					parti.set_color(Color("3f3f3f"))
	shootCooldown+=delta

func gotHit(area,dmg,player_name):
	if area=="headshot":
		health -=dmg*2
	else:
		health-=dmg
	if health <=0:
		ragdollSkeleton.physical_bones_start_simulation()
		collision_layer = 14
		if player_name == playerName:
			killCount +=1
			kill_status.add_kill(playerName+" Killed "+"mortyyy")
			killCounter.text = "Kills: " + str(killCount)
			print(killCount)
		if not waitingRespawn:
			$Timer.start()
	$characters/Armature_001/Skeleton3D/headCollision/headArea.health = health
	var tween = create_tween()
	tween.tween_property(healthBar,"value",health,0.3)
# ANIMATION
enum {
	IDLE,
	RUN,
	RUNLEFT,
	RUNRIGHT,
	RUNBACK,
	SHOOT,
	SLIDE,
	RELOAD,
	JUMP,
	SPRINT,
	CHANGE
}

var curAnim := IDLE
var isShooting = false

@export var blendSpeed := 15.0

var anim_weights := {
	RUN: 0.0,
	RUNLEFT: 0.0,
	RUNRIGHT: 0.0,
	RUNBACK: 0.0,
	SHOOT: 0.0,
	SLIDE: 0.0,
	RELOAD: 0.0,
	JUMP: 0.0,
	SPRINT: 0.0,
	CHANGE: 0.0
}


func handle_animations(delta):
	for anim in anim_weights:
		var target := 1.0 if curAnim == anim else 0.0

		anim_weights[anim] = lerpf(
			anim_weights[anim],
			target,
			blendSpeed * delta
		)

func update_animation_tree():
	animTree["parameters/run/blend_amount"] = anim_weights[RUN]
	animTree["parameters/runleft/blend_amount"] = anim_weights[RUNLEFT]
	animTree["parameters/runright/blend_amount"] = anim_weights[RUNRIGHT]
	animTree["parameters/runback/blend_amount"] = anim_weights[RUNBACK]
	animTree["parameters/jump/blend_amount"] = anim_weights[JUMP]
	animTree["parameters/sprint/blend_amount"] = anim_weights[SPRINT]



# CAMERA
var SENSITIVITY := 0.016

const BOB_FREQ := 3.0
const BOB_AMP := 0.04

var t_bob := 0.0


func _unhandled_input(event):
	if not is_multiplayer_authority():
		return
	
	if event is InputEventMouseMotion and trappedMouse:
		rotate_y(-event.relative.x * SENSITIVITY)

		spine3d.rotate_x(-event.relative.y * SENSITIVITY)
		spine3d.rotation.x = clamp(
			spine3d.rotation.x,
			deg_to_rad(-40),
			deg_to_rad(40)
		)

func playerMovement(delta):
	if not is_multiplayer_authority():
		return
	
	if Input.is_action_just_pressed("gun1") and currentWeapon != "Pistol" and not reloading and not changing:
		weaponToChange = "Pistol"
		animTree.set("parameters/change/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		changing = true
	
	if Input.is_action_just_pressed("gun2") and currentWeapon != "Shotgun" and not reloading and not changing:
		weaponToChange = "Shotgun"
		animTree.set("parameters/change/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		changing = true
		
	if Input.is_action_just_pressed("gun3") and currentWeapon != "Sniper Rifle" and not reloading and not changing:
		weaponToChange = "Sniper Rifle"
		animTree.set("parameters/change/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		changing = true
		
	if Input.is_action_just_pressed("gun4") and currentWeapon != "Submachine Gun" and not reloading and not changing:
		weaponToChange = "Submachine Gun"
		animTree.set("parameters/change/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		changing = true
		
	if Input.is_action_just_pressed("gun5") and currentWeapon != "Assault Rifle" and not reloading and not changing:
		weaponToChange = "Assault Rifle"
		animTree.set("parameters/change/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		changing = true
	
	if Input.is_action_just_pressed("reload") and not reloading and not changing:
		var wpn = weaponsInventory[currentWeapon]
		if wpn["ammo"] > 0:
			animTree.set("parameters/reload/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			reloading = true
			
		
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Movement
	var input_dir := Input.get_vector(
		"left",
		"right",
		"up",
		"down"
	)

	var direction := (
		transform.basis *
		Vector3(input_dir.x, 0, input_dir.y)
	).normalized()

	if is_on_floor():

		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
			
			SPEED = 8
			if Input.is_action_pressed("left"):
				curAnim = RUNLEFT

			elif Input.is_action_pressed("right"):
				curAnim = RUNRIGHT

			elif Input.is_action_pressed("down"):
				curAnim = RUNBACK

			elif Input.is_action_pressed("up"):
				curAnim = RUN
				if Input.is_action_pressed("shift"):
					curAnim = SPRINT
					SPEED = 11
		else:
			velocity.x = lerp(
				velocity.x,
				0.0,
				delta * 10.0
			)

			velocity.z = lerp(
				velocity.z,
				0.0,
				delta * 10.0
			)
			curAnim = IDLE

	else:
		velocity.x = lerp(
			velocity.x,
			direction.x * SPEED,
			delta * 5.5
		)
		velocity.z = lerp(
			velocity.z,
			direction.z * SPEED,
			delta * 5.5
		)
		curAnim = JUMP
	# Shoot
	if Input.is_action_just_pressed("click") and not reloading:
		var tween = create_tween()
		tween.tween_property(camera,"fov",65,0.02)
		isShooting = true
	if Input.is_action_just_released("click"):
		var tween = create_tween()
		tween.tween_property(camera,"fov",75,0.02)
		isShooting = false
		
	if Input.is_action_just_pressed("tab"):
		trappedMouse = not trappedMouse
		if trappedMouse:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# READY
func _ready():
	# Every player's camera starts OFF.
	camera.current = false

	setup_character()

	# Only the player controlled by this peer gets the camera.
	if not is_multiplayer_authority():
		return

	camera.current = true

	print(
		"CAMERA ACTIVE | player = ",
		name,
		" | authority = ",
		get_multiplayer_authority(),
		" | my_id = ",
		multiplayer.get_unique_id()
	)

# PHYSICS


func _physics_process(delta):
	if health <= 0:
		return
		
	handle_animations(delta)
	update_animation_tree()
	shootSystem(delta)

	# Gravity
	if not is_on_floor():
		velocity += GRAVITY * delta
		
	playerMovement(delta)
	
	move_and_slide()

	# Head bob
	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.position = _headbob(t_bob)
	
	


func _headbob(time: float) -> Vector3:
	var pos := Vector3.ZERO

	pos.y = sin(time * BOB_FREQ) * BOB_AMP

	return pos


func _on_timer_timeout() -> void:
	health = 100
	ragdollSkeleton.physical_bones_stop_simulation()
	$characters/Armature_001/Skeleton3D/headCollision/headArea.health = health
	collision_layer = 2

func changeWeapon():
	currentWeapon = weaponToChange
	setup_weapon()
	
func doneReload():
	reloading = false
	var wpn = weaponsInventory[currentWeapon]
	if wpn["ammo"] > 0 and wpn["magazine"] < wpn["reload"]:
		var maxAdd = wpn["reload"] - wpn["magazine"]
		if wpn["ammo"] > wpn["reload"]:
			weaponsInventory[currentWeapon]['magazine'] += maxAdd
			weaponsInventory[currentWeapon]['ammo']-= maxAdd
		else:
			weaponsInventory[currentWeapon]['magazine'] += wpn["ammo"]
			weaponsInventory[currentWeapon]['ammo']-=wpn["ammo"]
	showWeaponInfo()
	
func doneChange():
	changing = false
