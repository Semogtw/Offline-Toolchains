extends RefCounted

var hand: Array = []
var queue: Array = []
var next_card: String = ""

func _init(deck: Array = []) -> void:
	var clean := deck.duplicate()
	if clean.size() < 5:
		return
	hand = clean.slice(0, 4)
	queue = clean.slice(4)
	_refresh_next()

func play(card_id: String) -> bool:
	var index := hand.find(card_id)
	if index < 0 or queue.is_empty():
		return false
	hand.remove_at(index)
	var incoming = queue.pop_front()
	hand.append(incoming)
	queue.append(card_id)
	_refresh_next()
	return true

func _refresh_next() -> void:
	next_card = "" if queue.is_empty() else str(queue.front())
