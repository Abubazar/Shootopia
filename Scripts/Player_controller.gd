extends CharacterBody3D

# MOVEMENT

var SPEED := 8.0
const JUMP_VELOCITY := 8.5
const GRAVITY := Vector3(0, -20, 0)
var menu = false

@onready var head = $spine/head
@onready var camera = $spine/head/Camera3D
@onready var spine3d = $spine
@onready var rayCast = $spine/RayCast3D
@onready var hud = $spine/head/Camera3D/CanvasLayer
@onready var weapon_map = $spine/head/Camera3D/CanvasLayer/Control/PanelContainer/MarginContainer/weaponMap
@onready var pain_rect: TextureRect = $spine/head/Camera3D/CanvasLayer/TextureRect

@onready var particle = preload("res://Scenes/particle.tscn")

# PLAYER

@onready var model = $characters
var playerName = "Player"
@onready var playerLabel: Label3D = $PlayerName
@export var health = 100
var damage = 0
var waitingRespawn = false
var reloading = false
var changing = false
var weaponToChange = "Pistol"
var killCount = 0
var trappedMouse = false
var looking_aim = false

var chars = [
	"Farmer Joe",
	"King Tod",
	"Astra",
	"Swat",
	"Witch",
	"Trixie",
	"Scout",
	"Adventuress"
]

# Synced by the MultiplayerSynchronizer. The setter re-applies the model
# on every peer (including late joiners) whenever the value arrives.
var character_type := 0:
	set(value):
		character_type = value
		if skeleton != null:
			_apply_character()

@onready var skeleton = $characters/Armature_001/Skeleton3D
@onready var animTree = $characters/AnimationTree
@onready var animPlayer = $characters/AnimationPlayer
@onready var spine_ik = $characters/Armature_001/Skeleton3D/SkeletonIK3D
@onready var ragdollSkeleton = $characters/Armature_001/Skeleton3D/PhysicalBoneSimulator3D
@onready var aim_2 = $spine/head/Camera3D/CanvasLayer/aim2


func setName(cNam):
	playerLabel.text = cNam
	playerName = cNam


func _apply_character():
	for character in skeleton.get_children():
		if not chars.has(character.name):
			continue
		character.visible = character.name == chars[character_type]

		if character.name == chars[character_type] and is_multiplayer_authority():
			character.get_node("body").hide()
			playerLabel.hide()


func setup_character():
	if is_multiplayer_authority():
		character_type = Glob.character
	_apply_character()
	spine_ik.start()
	setup_weapon()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	trappedMouse = true


# WEAPONS

# Synced by the MultiplayerSynchronizer so late joiners see the right gun.
@export_enum(
	"Pistol",
	"Assault Rifle",
	"Shotgun",
	"Sniper Rifle",
	"Submachine Gun"
)
var currentWeapon := "Pistol":
	set(value):
		currentWeapon = value
		if guns != null:
			setup_weapon()

@onready var gunParent = $characters/Armature_001/Skeleton3D/BoneAttachment3D
@onready var guns = gunParent.get_node("guns")


func setGun(cNam: String):
	var item = cNam + "Img"
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
	setGun(currentWeapon)
	showWeaponInfo()


# ---------- Weapon switching / reloading (animations play on ALL peers) ----------

const WEAPON_KEYS := {
	"gun1": "Pistol",
	"gun2": "Shotgun",
	"gun3": "Sniper Rifle",
	"gun4": "Submachine Gun",
	"gun5": "Assault Rifle"
}


func _try_change_weapon():
	if reloading or changing:
		return
	for action in WEAPON_KEYS:
		var weapon = WEAPON_KEYS[action]
		if Input.is_action_just_pressed(action) and currentWeapon != weapon:
			changing = true
			start_change.rpc(weapon)
			return


@rpc("authority", "call_local", "reliable")
func start_change(weapon: String):
	weaponToChange = weapon
	animTree.set("parameters/change/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


@rpc("authority", "call_local", "reliable")
func start_reload():
	animTree.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


# Called from the animation track on every peer, but only the owner acts on it.
# The owner then tells everyone the new weapon, so remote peers don't depend on
# their own animation callbacks firing.
func changeWeapon():
	if not is_multiplayer_authority():
		return
	set_weapon.rpc(weaponToChange)


@rpc("authority", "call_local", "reliable")
func set_weapon(weapon: String):
	currentWeapon = weapon


func doneChange():
	changing = false


func doneReload():
	# Ammo bookkeeping only matters for the owner.
	if not is_multiplayer_authority():
		return
	reloading = false
	var wpn = weaponsInventory[currentWeapon]
	var needed = wpn["reload"] - wpn["magazine"]
	var taken = min(needed, wpn["ammo"])
	wpn["magazine"] += taken
	wpn["ammo"] -= taken
	showWeaponInfo()


# ---------- Shooting ----------
# The shooter's machine does the raycast, then tells everyone to play the
# effects, and tells the victim's owner about the damage.

var shootCooldown = 0


func shootSystem(delta):
	# Only the owner of this player shoots.
	if isShooting:
		var wpn = weaponsInventory[currentWeapon]
		if shootCooldown >= wpn["cooldown"] and wpn["magazine"] > 0:
			wpn["magazine"] -= 1
			shootCooldown = 0
			showWeaponInfo()
			rayCast.force_raycast_update()

			var has_hit = rayCast.is_colliding()
			var point := Vector3.ZERO
			var normal := Vector3.UP
			var damaged := false

			if has_hit:
				var hit = rayCast.get_collider()
				point = rayCast.get_collision_point()
				normal = rayCast.get_collision_normal()

				if hit.collision_layer == 2 or hit.name == "headArea":
					if hit.health > 0:
						var area = "headshot" if hit.name == "headArea" else "body"
						hit.gotHit(area, wpn["damage"], playerName)
						damaged = true

			shoot_fx.rpc(has_hit, point, normal, damaged)
	shootCooldown += delta


# Plays on every peer (including the shooter): animation + impact particles.
@rpc("authority", "call_local", "unreliable")
func shoot_fx(has_hit: bool, point: Vector3, normal: Vector3, damaged: bool):
	animTree.set("parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if not has_hit:
		return

	var parti = particle.instantiate()
	get_tree().current_scene.add_child(parti)
	parti.global_position = point
	var up = Vector3.UP if abs(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	parti.look_at(point + normal, up)
	if damaged:
		parti.set_color(Color("ff0000"))
	else:
		parti.set_color(Color("3f3f3f"))


# ---------- Taking damage ----------
# Flow:  shooter calls hit.gotHit()  ->  RPC to the victim's owner (receive_hit)
#        -> owner computes health -> apply_health RPC to everybody.

func gotHit(area, dmg, player_name):
	if is_multiplayer_authority():
		receive_hit(area, dmg, player_name)
	else:
		receive_hit.rpc_id(get_multiplayer_authority(), area, dmg, player_name)


@rpc("any_peer", "call_remote", "reliable")
func receive_hit(area: String, dmg: int, shooter_name: String):
	if not is_multiplayer_authority() or health <= 0:
		return
	var total = dmg * 2 if area == "headshot" else dmg
	pain_rect.modulate = Color(1.0, 1.0, 1.0, 1.0)
	var tween = create_tween()
	tween.tween_property(pain_rect,"modulate",Color(1.0, 1.0, 1.0, 0.0),0.2)
	apply_health.rpc(health - total)


@rpc("authority", "call_local", "reliable")
func apply_health(new_health: int):
	var was_alive = health > 0
	health = new_health
	_update_head_health()

	if health <= 0 and was_alive:
		ragdollSkeleton.physical_bones_start_simulation()
		collision_layer = 14
		if is_multiplayer_authority():
			$Timer.start()


func _update_head_health():
	var head_area = get_node_or_null("characters/Armature_001/Skeleton3D/headCollision/headArea")
	if head_area:
		head_area.health = health


# Only the owner's Timer is ever started, so this only runs on the owner.
func _on_timer_timeout() -> void:
	var children = get_parent().get_node("spawn_points").get_children()
	var spawn = children[randi() % children.size()]
	respawn.rpc(spawn.global_position)


@rpc("authority", "call_local", "reliable")
func respawn(pos: Vector3):
	ragdollSkeleton.physical_bones_stop_simulation()
	collision_layer = 2
	velocity = Vector3.ZERO
	global_position = pos
	health = 100
	_update_head_health()
	waitingRespawn = false
	$Timer.stop()

	if is_multiplayer_authority():
		for w in weaponsInventory.values():
			w["magazine"] = w["reload"]
		showWeaponInfo()


# ---------- Animation ----------
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

# Synced by the MultiplayerSynchronizer; every peer blends locally.
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
		anim_weights[anim] = lerpf(anim_weights[anim], target, blendSpeed * delta)


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
	if menu: return
	
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
	
	if menu: return
	_try_change_weapon()

	if Input.is_action_just_pressed("reload") and not reloading and not changing:
		if weaponsInventory[currentWeapon]["ammo"] > 0:
			reloading = true
			start_reload.rpc()

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

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
			velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
			velocity.z = lerp(velocity.z, 0.0, delta * 10.0)
			curAnim = IDLE
	else:
		velocity.x = lerp(velocity.x, direction.x * SPEED, delta * 5.5)
		velocity.z = lerp(velocity.z, direction.z * SPEED, delta * 5.5)
		curAnim = JUMP

	# Shoot
	if Input.is_action_just_pressed("click") and not reloading:
		if not looking_aim:
			var tween = create_tween()
			tween.tween_property(camera, "fov", 65, 0.02)
		isShooting = true
	if Input.is_action_just_released("click"):
		if not looking_aim:
			var tween = create_tween()
			tween.tween_property(camera, "fov", 75, 0.02)
		isShooting = false

	if Input.is_action_just_pressed("ctrl") and currentWeapon == "Sniper Rifle" and not looking_aim:
		looking_aim = true
		var tween = create_tween()
		tween.set_parallel()
		tween.tween_property(camera, "fov", 40, 0.02)
		tween.tween_property(aim_2, "position", Vector2(0, 22.71), 0.04)

	if Input.is_action_just_released("ctrl") and currentWeapon == "Sniper Rifle" and looking_aim:
		var tween = create_tween()
		tween.set_parallel()
		tween.tween_property(camera, "fov", 75, 0.02)
		tween.tween_property(aim_2, "position", Vector2(0, 1000), 0.04)
		looking_aim = false

	if Input.is_action_just_pressed("tab"):
		trappedMouse = not trappedMouse
		if trappedMouse:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			
			
	if Input.is_action_just_pressed("esc"):
		$spine/head/Camera3D/CanvasLayer/pause_menu.show()
		menu = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# READY
func _ready():
	camera.current = false
	# HUD is a CanvasLayer, so it would draw even for remote players' cameras.
	hud.visible = is_multiplayer_authority()

	setup_character()

	# Skin/weapon sync. Node creation order differs between peers, so we do both:
	# the owner pushes its state, and remote copies ask the owner for it.
	if multiplayer.has_multiplayer_peer():
		if is_multiplayer_authority():
			set_state.rpc(character_type, currentWeapon)
		else:
			request_state.rpc_id(get_multiplayer_authority())

	if not is_multiplayer_authority():
		return

	camera.current = true
	playerLabel.text = Glob.username
	SENSITIVITY = Glob.sensitivity


@rpc("any_peer", "call_remote", "reliable")
func request_state():
	if not is_multiplayer_authority():
		return
	set_state.rpc_id(multiplayer.get_remote_sender_id(), character_type, currentWeapon)


@rpc("authority", "call_remote", "reliable")
func set_state(char_type: int, weapon: String):
	character_type = char_type
	currentWeapon = weapon


# PHYSICS
func _physics_process(delta):
	if health <= 0:
		return

	# Everyone blends animations from the synced curAnim.
	handle_animations(delta)
	update_animation_tree()

	# Remote players are moved by the synchronizer only.
	if not is_multiplayer_authority():
		return

	shootSystem(delta)

	if not is_on_floor():
		velocity += GRAVITY * delta

	playerMovement(delta)
	move_and_slide()

	t_bob += delta * velocity.length() * float(is_on_floor())
	camera.position = _headbob(t_bob)


func _headbob(time: float) -> Vector3:
	var pos := Vector3.ZERO
	pos.y = sin(time * BOB_FREQ) * BOB_AMP
	return pos


func _on_continue_pressed() -> void:
	$spine/head/Camera3D/CanvasLayer/pause_menu.hide()
	menu = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)



func _on_exit_pressed() -> void:
	if is_multiplayer_authority(): get_tree().quit()
