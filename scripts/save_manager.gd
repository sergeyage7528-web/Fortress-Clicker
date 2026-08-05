class_name SaveManager
extends RefCounted

const SAVE_PATH := "user://fortress_progress.cfg"
const SECTION := "progress"

static func save_game(data: Dictionary) -> Error:
	var config := ConfigFile.new()
	for key in data:
		config.set_value(SECTION, key, data[key])
	return config.save(SAVE_PATH)

static func load_game() -> Dictionary:
	if not save_exists(): return {}
	var config := ConfigFile.new()
	var error := config.load(SAVE_PATH)
	if error != OK:
		push_warning("Не удалось загрузить прогресс: %s" % error)
		return {}
	var data: Dictionary = {}
	for key in config.get_section_keys(SECTION):
		data[key] = config.get_value(SECTION, key)
	return data

static func save_exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

static func delete_save() -> Error:
	if not save_exists(): return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
