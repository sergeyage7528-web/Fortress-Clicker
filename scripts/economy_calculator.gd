class_name EconomyCalculator
extends RefCounted

static func growing_cost(base: int, growth: float, level: int, maximum_result: int, maximum_exponent: int = 100) -> int:
	var safe_level := clampi(level, 0, maximum_exponent)
	if maximum_result <= 0: return 0
	return clampi(int(minf(float(maximum_result), float(base) * pow(growth, safe_level))), 0, maximum_result)

static func capped_reward(value: float, maximum_result: int) -> int:
	if maximum_result <= 0: return 0
	if is_nan(value) or is_inf(value): return maximum_result
	return clampi(int(round(value)), 0, maximum_result)

static func format_number(value: float) -> String:
	var absolute := absf(value)
	if absolute >= 1_000_000_000.0: return "%.2fB" % (value / 1_000_000_000.0)
	if absolute >= 1_000_000.0: return "%.2fM" % (value / 1_000_000.0)
	if absolute >= 1_000.0: return "%.2fK" % (value / 1_000.0)
	return str(int(round(value)))
