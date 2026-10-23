class_name CardCycle
extends RefCounted

var _hand: Array[String] = []
var _queue: Array[String] = []

func _init(deck: Array) -> void:
    assert(deck.size() == 8, "Crownfall decks must contain 8 cards")
    for i in 4:
        _hand.append(String(deck[i]))
    for i in range(4, 8):
        _queue.append(String(deck[i]))

func hand() -> Array[String]:
    return _hand.duplicate()

func next_card() -> String:
    return _queue[0] if not _queue.is_empty() else ""

func play(index: int) -> String:
    if index < 0 or index >= _hand.size() or _queue.is_empty():
        return ""
    var played := _hand[index]
    var incoming := _queue.pop_front()
    _hand[index] = incoming
    _queue.append(played)
    return played
