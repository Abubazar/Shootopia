extends ItemList

var itemCounter: Array = []

func add_kill(text):
	itemCounter.append([add_item(text),6])
	print("added")


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	#for item in itemCounter:
	#	if item[1] <=0:
	#		remove_item(item[0])
	#	item[1]-=delta
	pass
