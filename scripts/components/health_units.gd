## Canonical, serializable representation for all health-domain values.
class_name HealthUnits
extends RefCounted

const HP_SCALE: int = 100
const MAX_UNITS: int = 9223372036854775807

## Quantizes authored HP once, rounding to the nearest centi-HP (half away from zero).
## Invalid and negative authored values are rejected as zero.
static func from_hp(value: float) -> int:
	if not is_finite(value) or value <= 0.0:
		return 0
	# Check before roundi(): values close to INT64_MAX cannot be rounded safely.
	if value >= float(MAX_UNITS) / float(HP_SCALE):
		return MAX_UNITS
	var scaled := value * float(HP_SCALE)
	if not is_finite(scaled):
		return MAX_UNITS
	return mini(maxi(roundi(scaled), 0), MAX_UNITS)

static func to_hp(units: int) -> float:
	return float(maxi(units, 0)) / float(HP_SCALE)

static func saturating_add(left: int, right: int) -> int:
	if left <= 0:
		return maxi(right, 0)
	if right <= 0:
		return left
	if left > MAX_UNITS - right:
		return MAX_UNITS
	return left + right

static func saturating_multiply(value: int, multiplier: int) -> int:
	if value <= 0 or multiplier <= 0:
		return 0
	if value > MAX_UNITS / multiplier:
		return MAX_UNITS
	return value * multiplier
