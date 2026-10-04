extends Node

const DISCOVERY_PORT := 7778
const DISCOVERY_MESSAGE := "MY_GAME"

var listener := PacketPeerUDP.new()
var broadcaster := PacketPeerUDP.new()

var broadcasting := false
var broadcast_timer := 0.0


func _ready() -> void:
	start_listener()


func start_listener() -> void:
	var error := listener.bind(DISCOVERY_PORT)

	if error != OK:
		print("Failed to start discovery listener: ", error)
		return

	print("Discovery listener started on port ", DISCOVERY_PORT)


func _process(delta: float) -> void:

	# Check for incoming discovery packets.
	while listener.get_available_packet_count() > 0:

		var packet := listener.get_packet()

		var message := packet.get_string_from_utf8()

		var sender_ip := listener.get_packet_ip()

		print(
			"GAME FOUND!",
			" IP: ",
			sender_ip,
			" MESSAGE: ",
			message
		)

	# Broadcast every second.
	if broadcasting:

		broadcast_timer += delta

		if broadcast_timer >= 1.0:
			broadcast_timer = 0.0
			send_broadcast()



func start_broadcasting() -> void:

	if broadcasting:
		return

	broadcaster.set_broadcast_enabled(true)

	broadcasting = true

	print("Started broadcasting LAN game.")

	send_broadcast()


func send_broadcast() -> void:

	broadcaster.set_dest_address(
		"255.255.255.255",
		DISCOVERY_PORT
	)

	broadcaster.put_packet(
		DISCOVERY_MESSAGE.to_utf8_buffer()
	)

	print("Broadcast sent.")


func _on_button_pressed() -> void:
	start_broadcasting()
