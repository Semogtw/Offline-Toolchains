extends RefCounted

var value: float = 5.0

func _init(start: float = 5.0) -> void:
	value = clampf(start, 0.0, 10.0)

func tick(delta: float, multiplier: float = 1.0) -> void:
	value = minf(10.0, value + delta * 0.36 * multiplier)

func try_spend(cost: int) -> bool:
	if cost < 0 or value + 0.0001 < float(cost):
		return false
	value -= float(cost)
	return true
