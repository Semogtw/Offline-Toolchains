extends SceneTree

var failures := 0
var assertions := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var suite_script = load("res://tests/test_core.gd")
	if suite_script == null:
		push_error("Could not load test suite")
		quit(1)
		return
	var suite = suite_script.new()
	for method in suite.get_method_list():
		var name: String = method.name
		if not name.begins_with("test_"):
			continue
		print("[TEST] ", name)
		var result = suite.call(name)
		assertions += int(result.get("assertions", 0))
		var errors: Array = result.get("errors", [])
		if errors.is_empty():
			print("  PASS")
		else:
			failures += errors.size()
			for error in errors:
				push_error("  FAIL: %s" % error)
	print("[RESULT] %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
