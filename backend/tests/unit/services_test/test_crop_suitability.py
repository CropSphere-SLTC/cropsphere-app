"""Unit tests for the per-crop agronomic suitability flags.

The point of these flags is that they DIFFERENTIATE between crops. The
implementation they replaced returned model-telemetry flags that were identical
for all six crops in every scenario and, because one of the three was the
negation of the other two, made the UI's "Good match" branch unreachable. The
differentiation test below is the regression guard for that.
"""

import pytest

from app.user.services import crop_suitability

# The Monaragala / Yala scenario from the field report: forecast weather for
# week 34 with the farmer's own soil pH.
MONARAGALA_YALA = dict(
    temp_min_c=19.6,
    temp_max_c=29.8,
    rainfall_mm=33.7,
    humidity_pct=78.2,
    soil_ph=6.5,
)


def test_bands_cover_every_crop():
    from app.models.schemas import CropEnum

    bands = crop_suitability.load_bands()
    assert {c.value for c in CropEnum} == set(bands)


def test_flags_differentiate_between_crops():
    """The whole reason this module exists — identical output is the bug."""
    scores = {
        crop: sum(crop_suitability.evaluate(crop, **MONARAGALA_YALA).values())
        for crop in crop_suitability.load_bands()
    }
    assert len(set(scores.values())) > 1, (
        f"every crop scored identically ({scores}) — the check is not "
        "differentiating, which is exactly the bug this replaced"
    )


def test_carrot_fails_on_temperature_in_the_low_country():
    """Carrot's 28 C ceiling is below a Monaragala afternoon (29.8 C)."""
    flags = crop_suitability.evaluate("Carrot", **MONARAGALA_YALA)
    assert flags["temp_suitable"] is False
    # ...and it is specifically temperature, not a blanket failure.
    assert flags["rain_suitable"] is True
    assert flags["humidity_suitable"] is True
    assert flags["ph_suitable"] is True


def test_carrot_passes_in_its_own_hill_country_conditions():
    """Same crop, up-country weather — the band must not be a constant 'no'."""
    flags = crop_suitability.evaluate(
        "Carrot",
        temp_min_c=12.0,
        temp_max_c=24.0,
        rainfall_mm=30.0,
        humidity_pct=80.0,
        soil_ph=6.5,
    )
    assert all(flags.values()), flags


@pytest.mark.parametrize("crop", ["Cowpea", "Finger millet", "Maize"])
def test_low_country_crops_pass_all_four(crop):
    assert all(crop_suitability.evaluate(crop, **MONARAGALA_YALA).values())


def test_good_match_threshold_is_now_reachable():
    """The UI calls it a good match at >= 70% of flags true.

    Under the old telemetry flags the maximum achievable ratio was 2/3 = 0.667,
    so this was false in all four reachable states.
    """
    flags = crop_suitability.evaluate("Maize", **MONARAGALA_YALA)
    ratio = sum(flags.values()) / len(flags)
    assert ratio >= 0.7


def test_temperature_rule_is_containment_not_midpoint():
    """A cold night must fail the crop even when the day is comfortable."""
    flags = crop_suitability.evaluate(
        "Green gram",  # band is 20-38 C
        temp_min_c=15.0,
        temp_max_c=30.0,
        rainfall_mm=20.0,
        humidity_pct=70.0,
        soil_ph=6.5,
    )
    assert flags["temp_suitable"] is False


def test_bands_are_inclusive_at_both_ends():
    """Matches the dataset's own rules, which validated at 1.0 agreement."""
    band = crop_suitability.load_bands()["Maize"]
    flags = crop_suitability.evaluate(
        "Maize",
        temp_min_c=band["temp_min_c"],
        temp_max_c=band["temp_max_c"],
        rainfall_mm=band["rain_max_mm"],
        humidity_pct=band["humidity_min_pct"],
        soil_ph=band["ph_max"],
    )
    assert all(flags.values()), flags


def test_unknown_crop_degrades_instead_of_raising():
    """A missing band must never fail the whole recommendation request."""
    flags = crop_suitability.evaluate("Dragonfruit", **MONARAGALA_YALA)
    assert flags == {name: False for name in crop_suitability.FLAG_NAMES}
