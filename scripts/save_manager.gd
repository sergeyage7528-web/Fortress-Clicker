class_name SaveManager
extends RefCounted

const SAVE_PATH := "user://fortress_progress.cfg"
const TEMP_PATH := "user://fortress_progress.tmp"
const BACKUP_PATH := "user://fortress_progress.bak"
const SECTION := "progress"

static func save_game(data: Dictionary, save_path := SAVE_PATH, temp_path := TEMP_PATH, backup_path := BACKUP_PATH) -> Error:
	var config := ConfigFile.new()
	for key in data:
		config.set_value(SECTION, key, data[key])
	var save_error := config.save(temp_path)
	if save_error != OK:
		push_warning("Не удалось записать временное сохранение: %s" % save_error)
		return save_error
	var main_absolute_path := ProjectSettings.globalize_path(save_path)
	var temp_absolute_path := ProjectSettings.globalize_path(temp_path)
	var backup_absolute_path := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(save_path):
		if FileAccess.file_exists(backup_path): DirAccess.remove_absolute(backup_absolute_path)
		var backup_error := DirAccess.copy_absolute(main_absolute_path, backup_absolute_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temp_absolute_path)
			push_warning("Не удалось создать резервную копию сохранения: %s" % backup_error)
			return backup_error
	if FileAccess.file_exists(save_path):
		var remove_error := DirAccess.remove_absolute(main_absolute_path)
		if remove_error != OK:
			DirAccess.remove_absolute(temp_absolute_path)
			push_warning("Не удалось заменить основное сохранение: %s" % remove_error)
			return remove_error
	var replace_error := DirAccess.rename_absolute(temp_absolute_path, main_absolute_path)
	if replace_error != OK:
		if FileAccess.file_exists(backup_path): DirAccess.copy_absolute(backup_absolute_path, main_absolute_path)
		push_warning("Не удалось завершить замену сохранения: %s" % replace_error)
		return replace_error
	return OK

static func load_game(save_path := SAVE_PATH, backup_path := BACKUP_PATH) -> Dictionary:
	var main_data := load_data_from_path(save_path, "основное")
	if not main_data.is_empty(): return main_data
	var backup_data := load_data_from_path(backup_path, "резервное")
	if backup_data.is_empty(): return {}
	var restore_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(save_path))
	if restore_error != OK: push_warning("Не удалось восстановить основное сохранение из резервной копии: %s" % restore_error)
	return backup_data

static func load_data_from_path(path: String, source_name: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var config := ConfigFile.new()
	var load_error := config.load(path)
	if load_error != OK:
		push_warning("Не удалось загрузить %s сохранение: %s" % [source_name, load_error])
		return {}
	if not config.has_section(SECTION) or not config.has_section_key(SECTION, "stage"):
		push_warning("%s сохранение не содержит обязательных данных." % source_name.capitalize())
		return {}
	var data: Dictionary = {}
	for key in config.get_section_keys(SECTION):
		data[key] = config.get_value(SECTION, key)
	return data

static func save_exists(save_path := SAVE_PATH) -> bool:
	return FileAccess.file_exists(save_path)

static func delete_save(save_path := SAVE_PATH, temp_path := TEMP_PATH, backup_path := BACKUP_PATH) -> Error:
	var first_error: Error = OK
	for path in [save_path, temp_path, backup_path]:
		if not FileAccess.file_exists(path): continue
		var delete_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if delete_error != OK and first_error == OK: first_error = delete_error
	return first_error
