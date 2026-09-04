extends SceneTree

func _init() -> void:
    var suite_script := load("res://tests/test_core.gd")
    if suite_script == null:
        printerr("Unable to load test suite")
        quit(1)
        return
    var suite = suite_script.new()
    var failures: Array[String] = suite.run_all()
    if failures.is_empty():
        print("CROWNFALL TESTS: PASS")
        quit(0)
        return
    printerr("CROWNFALL TESTS: %d FAILURE(S)" % failures.size())
    for failure in failures:
        printerr(" - " + failure)
    quit(1)
