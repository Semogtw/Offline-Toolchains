extends RefCounted

var elapsed: float = 0.0
var phase: String = "regulation"

func _init() -> void:
	elapsed = 0.0
	phase = "regulation"

func tick(delta: float) -> void:
	if phase == "expired": return
	elapsed += maxf(0.0, delta)
	if phase == "regulation" and elapsed >= 180.0:
		phase = "overtime"
	if phase == "overtime" and elapsed >= 270.0:
		phase = "expired"

func arcana_multiplier() -> float:
	if phase == "overtime": return 2.5
	if elapsed >= 120.0: return 2.0
	return 1.0

func remaining() -> float:
	if phase == "regulation": return maxf(0.0, 180.0 - elapsed)
	if phase == "overtime": return maxf(0.0, 270.0 - elapsed)
	return 0.0
