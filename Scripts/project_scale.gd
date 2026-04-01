extends RefCounted

## 6,700 km diameter → 3,350 km radius; 1 game unit = 10 m (see docs).
## Preload from planet / camera rig.
const PLANET_RADIUS_GAME_UNITS: float = 335_000.0
const METERS_PER_GAME_UNIT: float = 10.0

## ~ISA troposphere: ~6.5 °C cooler per 1 km **planet** elevation.
## Signed for `temp_offset = altitude * rate` with altitude positive upward.
const STANDARD_ATMOSPHERE_LAPSE_C_PER_PLANET_KM: float = -6.5
const STANDARD_ATMOSPHERE_LAPSE_C_PER_PLANET_METER: float = (
	STANDARD_ATMOSPHERE_LAPSE_C_PER_PLANET_KM / 1000.0
)
## Lapse for vertical distance in **game units** (1 unit = [constant METERS_PER_GAME_UNIT] planet m).
const STANDARD_ATMOSPHERE_LAPSE_C_PER_GAME_UNIT: float = (
	STANDARD_ATMOSPHERE_LAPSE_C_PER_PLANET_METER * METERS_PER_GAME_UNIT
)
