extends SceneTree
## Persist workflow choices in the project settings included in the APK.

func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 2 or args[0] not in ["true", "false"] or args[1] not in ["true", "false"]:
        push_error("Expected fixed_resolution and vsync, each true or false")
        quit(1)
        return
    var config := ConfigFile.new()
    if config.load("res://project.godot") != OK:
        push_error("Cannot read project.godot")
        quit(1)
        return
    config.set_value("benchmark", "fixed_resolution", args[0] == "true")
    config.set_value("display", "window/vsync/vsync_mode", 1 if args[1] == "true" else 0)
    if config.save("res://project.godot") != OK:
        push_error("Cannot save evaluation settings")
        quit(1)
        return
    print("Evaluation configured: Native 100% locked=", args[0], ", VSync requested=", args[1])
    quit()
