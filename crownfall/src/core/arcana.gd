class_name ArcanaMeter
extends RefCounted

const MAX_VALUE := 10.0
const SECONDS_PER_POINT := 2.8
var value: float = 5.0

func _init(start_value: float = 5.0) -> void:
    value = clampf(start_value, 0.0, MAX_VALUE)

func advance(seconds: float, multiplier: float = 1.0) -> void:
    if seconds <= 0.0:
        return
    value = minf(MAX_VALUE, value + (seconds / SECONDS_PER_POINT) * maxf(multiplier, 0.0))

func spend(cost: int) -> bool:
    if cost < 0 or value + 0.0001 < float(cost):
        return false
    value -= float(cost)
    return true
