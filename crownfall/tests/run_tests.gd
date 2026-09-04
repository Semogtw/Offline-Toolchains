extends SceneTree

func _init() -> void:
    var failures: Array[String] = []
    for path in ["res://tests/test_core.gd", "res://tests/test_battle.gd"]:
        var suite_script := load(path)
        if suite_script == null:
            failures.append("Unable to load suite: " + path)
            continue
        var suite = suite_script.new()
        for failure in suite.run_all():
            failures.append(String(failure))
    if failures.is_empty():
        print("CROWNFALL TESTS: PASS")
        quit(0)
        return
    printerr("CROWNFALL TESTS: %d FAILURE(S)" % failures.size())
    for failure in failures:
        printerr(" - " + failure)
    quit(1)
