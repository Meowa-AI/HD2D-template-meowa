extends RefCounted
## Central switch for the browser export profile.
## The export preset adds the `web_compat` feature; `MEOWA_WEB_COMPAT=1`
## lets headless/local checks exercise the same path.

static func enabled() -> bool:
	return OS.has_feature("web") or OS.has_feature("web_compat") or OS.get_environment("MEOWA_WEB_COMPAT") == "1"

static func grass_blade_count(requested: int) -> int:
	return mini(requested, 7000) if enabled() else requested

static func prop_scatter_count(requested: int) -> int:
	return mini(requested, 280) if enabled() else requested

static func dust_count(requested: int) -> int:
	return mini(requested, 60) if enabled() else requested

static func grass_heightmap_resolution() -> int:
	return 96 if enabled() else 192
