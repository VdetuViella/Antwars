extends TestCase
## Todos los scripts del proyecto compilan (incluidos los de presentación, que no tienen tests propios).


func test_all_scripts_compile() -> void:
	for dir_path in ["res://sim", "res://game", "res://game/ui", "res://tools"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".gd"):
				var s: GDScript = load(dir_path + "/" + f)
				check(s != null and s.can_instantiate(), "compila %s/%s" % [dir_path, f])
