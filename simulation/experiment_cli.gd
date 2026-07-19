class_name ExperimentCLI
extends RefCounted

## Experiment-only CLI overrides for the dynamic-vs-static allocation sweep
## (ADR 12). Parses `--key=value` pairs from OS.get_cmdline_user_args() (the
## args after `--` on the Godot command line) on demand - cheap enough to
## call independently from each config-loading site rather than plumbing a
## single parsed-once result through the scene tree. A run launched with no
## such args behaves exactly as before: every getter falls back to whatever
## default the caller already computed from JSON config.

static func _get_raw(key: String) -> String:
	var prefix := "--%s=" % key
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


static func get_int(key: String, default_value: int) -> int:
	var raw := _get_raw(key)
	if raw.is_empty():
		return default_value
	return raw.to_int()


static func get_float(key: String, default_value: float) -> float:
	var raw := _get_raw(key)
	if raw.is_empty():
		return default_value
	return raw.to_float()


static func get_string(key: String, default_value: String) -> String:
	var raw := _get_raw(key)
	if raw.is_empty():
		return default_value
	return raw


## Presence-only flag, e.g. `--log-metrics` with no `=value`.
static func has_flag(key: String) -> bool:
	var flag := "--%s" % key
	return OS.get_cmdline_user_args().has(flag)
