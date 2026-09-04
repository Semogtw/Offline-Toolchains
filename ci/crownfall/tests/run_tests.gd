extends SceneTree

var failures := 0
var assertions := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for suite_path in ["res://tests/test_core.gd", "res://tests/test_app.gd", "res://tests/test_presentation.gd", "res://tests/test_lobby_presentation.gd"]:
		var suite_script = load(suite_path)
		if suite_script == null or not suite_script.can_instantiate():
			push_error("Could not load test suite: %s" % suite_path)
			failures += 1
			continue
		var suite = suite_script.new()
		for method in suite.get_method_list():
			var name: String = method.name
			if not name.begins_with("test_"): continue
			print("[TEST] ", name)
			var result = suite.call(name)
			assertions += int(result.get("assertions", 0))
			var errors: Array = result.get("errors", [])
			if errors.is_empty():
				print("  PASS")
			else:
				failures += errors.size()
				for error in errors: push_error("  FAIL: %s" % error)
	print("[RESULT] %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
