class_name BattleClock
extends RefCounted

const REGULATION_SECONDS := 180.0
const OVERTIME_SECONDS := 90.0
const DOUBLE_ARCANA_AT := 120.0

var elapsed: float = 0.0
var in_overtime: bool = false
var finished: bool = false

func advance(seconds: float) -> void:
    if finished or seconds <= 0.0:
        return
    elapsed += seconds
    if elapsed >= REGULATION_SECONDS:
        in_overtime = true
    if elapsed >= REGULATION_SECONDS + OVERTIME_SECONDS:
        elapsed = REGULATION_SECONDS + OVERTIME_SECONDS
        finished = true

func arcana_multiplier() -> float:
    if in_overtime:
        return 2.5
    if elapsed >= DOUBLE_ARCANA_AT:
        return 2.0
    return 1.0

func remaining() -> float:
    if in_overtime:
        return maxf(0.0, REGULATION_SECONDS + OVERTIME_SECONDS - elapsed)
    return maxf(0.0, REGULATION_SECONDS - elapsed)

func regulation_finished() -> bool:
    return elapsed >= REGULATION_SECONDS
