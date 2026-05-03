"""
CropSphere — complete test suite for POST /api/yield/predict

Covers (in order):
  1. Happy path — all 6 crops, various districts
  2. Auth enforcement — no token, expired token
  3. Input validation (Pydantic) — missing fields, out-of-range values, bad enums
  4. Model mock fallback — is_mock: true when model file absent
  5. Feature engineering — heat stress, cold stress, rain adequacy derivations
  6. Response shape — all required fields present and correctly typed
  7. Edge cases — boundary values, unknown seed variety / prev_crop handling
  8. Rate limiting — 31st request returns 429

Run:
    pytest tests/test_yield.py -v --tb=short
"""

import pytest
from unittest.mock import MagicMock, patch

URL = "/api/yield/predict"

# ── Canonical valid payload (Carrot, Nuwara Eliya, Maha) ─────────────────────

VALID = {
    "crop": "Carrot",
    "district": "Nuwara Eliya",
    "season": "Maha",
    "week_of_year": 10,
    "rainfall_mm": 120.0,
    "temp_min_c": 10.0,
    "temp_max_c": 22.0,
    "humidity_pct": 75.0,
    "wind_speed_kmh": 15.0,
    "solar_radiation_mj": 18.0,
    "soil_ph": 6.0,
    "soil_moisture_pct": 60.0,
    "cultivated_area_ha": 2.0,
    "seed_variety": "Ooty-1",
    "fertilizer_index": 0.6,
    "pesticide_index": 0.4,
    "irrigation_type": "drip",
    "N_index": 0.5,
    "P_index": 0.4,
    "K_index": 0.6,
    "prev_crop": "Potato",
    "demand_index": 100.0,
    "inflation_index": 1.2,
    "holiday_flag": 0,
    "festival_flag": 0,
}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _mock_model(yield_value: float = 21450.0) -> MagicMock:
    """Return a mock sklearn-style model that predicts a fixed yield."""
    m = MagicMock()
    m.predict.return_value = [yield_value]
    m.predict_proba = None          # triggers ConfidenceEnum.medium path
    return m


def _post(client, payload, headers=None):
    return client.post(URL, json=payload, headers=headers or {})


# ═══════════════════════════════════════════════════════════════════════════════
# 1. Happy path
# ═══════════════════════════════════════════════════════════════════════════════

class TestHappyPath:

    def test_valid_carrot_nuwara_eliya(self, client, mock_valid_token, valid_auth_header):
        """Standard Carrot / Nuwara Eliya request returns 200 with a positive yield."""
        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", return_value=_mock_model(21450.0)), \
             patch("app.utils.firestore.audit_log"):
            resp = _post(client, VALID, valid_auth_header)

        assert resp.status_code == 200
        body = resp.json()
        assert body["predicted_yield_kg_per_ha"] == pytest.approx(21450.0, abs=1)
        assert body["is_mock"] is False
        assert body["crop"] == "Carrot"
        assert body["district"] == "Nuwara Eliya"

    @pytest.mark.parametrize("crop,district,expected_model_key", [
        ("Carrot",        "Nuwara Eliya",  "yield_Carrot"),
        ("Maize",         "Anuradhapura",  "yield_Maize"),
        ("Green gram",    "Monaragala",    "yield_Greengram"),
        ("Cowpea",        "Ampara",        "yield_Cowpea"),
        ("Finger millet", "Hambantota",    "yield_Fingermillet"),
        ("Groundnut",     "Jaffna",        "yield_Groundnut"),
    ])
    def test_all_six_crops(
        self, client, mock_valid_token, valid_auth_header,
        crop, district, expected_model_key
    ):
        """Every crop-district combo returns 200 and uses the correct model key."""
        payload = {**VALID, "crop": crop, "district": district}

        captured_keys = []

        def _fake_get_model(key):
            captured_keys.append(key)
            return _mock_model(15000.0)

        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", side_effect=_fake_get_model), \
             patch("app.utils.firestore.audit_log"):
            resp = _post(client, payload, valid_auth_header)

        assert resp.status_code == 200, f"Failed for {crop} / {district}"
        # First call to get_model should be for the crop's model key
        assert expected_model_key in captured_keys, (
            f"Expected model key '{expected_model_key}' but got {captured_keys}"
        )

    def test_all_seasons(self, client, mock_valid_token, valid_auth_header):
        """Maha, Yala, and Inter seasons all return 200."""
        for season in ("Maha", "Yala", "Inter"):
            payload = {**VALID, "season": season}
            with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
                 patch("app.models.loader.model_loader.get_model", return_value=_mock_model()), \
                 patch("app.utils.firestore.audit_log"):
                resp = _post(client, payload, valid_auth_header)
            assert resp.status_code == 200, f"Failed for season={season}"

    def test_all_irrigation_types(self, client, mock_valid_token, valid_auth_header):
        """drip, sprinkler, flood, rainfed all accepted."""
        for irr in ("drip", "sprinkler", "flood", "rainfed"):
            payload = {**VALID, "irrigation_type": irr}
            with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
                 patch("app.models.loader.model_loader.get_model", return_value=_mock_model()), \
                 patch("app.utils.firestore.audit_log"):
                resp = _post(client, payload, valid_auth_header)
            assert resp.status_code == 200, f"Failed for irrigation_type={irr}"


# ═══════════════════════════════════════════════════════════════════════════════
# 2. Authentication enforcement
# ═══════════════════════════════════════════════════════════════════════════════

class TestAuth:

    def test_no_token_returns_401(self, client):
        """Request with no Authorization header must return 401."""
        resp = _post(client, VALID)
        assert resp.status_code == 401
        assert "detail" in resp.json()

    def test_expired_token_returns_401(self, client, mock_expired_token, expired_auth_header):
        """Expired token must return 401, not 500."""
        resp = _post(client, VALID, expired_auth_header)
        assert resp.status_code == 401

    def test_malformed_bearer_returns_401(self, client):
        """'Bearer' with no token must return 401."""
        resp = _post(client, VALID, {"Authorization": "Bearer"})
        assert resp.status_code == 401

    def test_wrong_scheme_returns_401(self, client):
        """Basic auth scheme must be rejected."""
        resp = _post(client, VALID, {"Authorization": "Basic dXNlcjpwYXNz"})
        assert resp.status_code == 401

    def test_valid_token_accepted(self, client, mock_valid_token, valid_auth_header):
        """Valid token must pass auth and reach the service layer."""
        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", return_value=_mock_model()), \
             patch("app.utils.firestore.audit_log"):
            resp = _post(client, VALID, valid_auth_header)
        assert resp.status_code == 200


# ═══════════════════════════════════════════════════════════════════════════════
# 3. Input validation — missing required fields
# ═══════════════════════════════════════════════════════════════════════════════

class TestMissingFields:

    @pytest.mark.parametrize("missing_field", [
        "crop", "district", "season", "week_of_year",
        "rainfall_mm", "temp_min_c", "temp_max_c", "humidity_pct",
        "wind_speed_kmh", "solar_radiation_mj", "soil_ph", "soil_moisture_pct",
        "cultivated_area_ha", "seed_variety", "fertilizer_index", "pesticide_index",
        "irrigation_type", "N_index", "P_index", "K_index",
        "prev_crop", "demand_index", "inflation_index",
        "holiday_flag", "festival_flag",
    ])
    def test_missing_field_returns_422(
        self, client, mock_valid_token, valid_auth_header, missing_field
    ):
        """Every required field, when absent, must produce 422 (not 500)."""
        payload = {k: v for k, v in VALID.items() if k != missing_field}
        resp = _post(client, payload, valid_auth_header)
        assert resp.status_code == 422, (
            f"Expected 422 when '{missing_field}' is missing, got {resp.status_code}"
        )


# ═══════════════════════════════════════════════════════════════════════════════
# 4. Input validation — out-of-range numeric values
# ═══════════════════════════════════════════════════════════════════════════════

class TestOutOfRange:

    @pytest.mark.parametrize("field,bad_value", [
        # Above maximum
        ("rainfall_mm",         501.0),
        ("temp_min_c",          46.0),
        ("temp_max_c",          51.0),
        ("humidity_pct",        101.0),
        ("wind_speed_kmh",      101.0),
        ("solar_radiation_mj",  36.0),
        ("soil_ph",             9.1),
        ("soil_moisture_pct",   101.0),
        ("cultivated_area_ha",  501.0),
        ("fertilizer_index",    1.01),
        ("pesticide_index",     1.01),
        ("N_index",             1.01),
        ("P_index",             1.01),
        ("K_index",             1.01),
        ("demand_index",        201.0),
        ("inflation_index",     3.01),
        ("week_of_year",        53),
        # Below minimum
        ("rainfall_mm",         -1.0),
        ("temp_min_c",          -6.0),
        ("soil_ph",             3.4),
        ("cultivated_area_ha",  0.0),
        ("inflation_index",     0.4),
        ("week_of_year",        0),
        ("holiday_flag",        2),
        ("festival_flag",       -1),
    ])
    def test_out_of_range_returns_422(
        self, client, mock_valid_token, valid_auth_header, field, bad_value
    ):
        """Out-of-range numeric values must be rejected with 422."""
        resp = _post(client, {**VALID, field: bad_value}, valid_auth_header)
        assert resp.status_code == 422, (
            f"Expected 422 for {field}={bad_value}, got {resp.status_code}"
        )


# ═══════════════════════════════════════════════════════════════════════════════
# 5. Input validation — invalid enum values
# ═══════════════════════════════════════════════════════════════════════════════

class TestEnumValidation:

    @pytest.mark.parametrize("field,bad_value", [
        ("crop",           "Tomato"),
        ("crop",           "carrot"),            # case-sensitive
        ("district",       "Colombo"),
        ("district",       "nuwara eliya"),      # case-sensitive
        ("season",         "Winter"),
        ("season",         "maha"),              # case-sensitive
        ("irrigation_type", "furrow"),
        ("irrigation_type", "DRIP"),               # case-sensitive
    ])
    def test_invalid_enum_returns_422(
        self, client, mock_valid_token, valid_auth_header, field, bad_value
    ):
        """Invalid enum strings must be rejected with 422."""
        resp = _post(client, {**VALID, field: bad_value}, valid_auth_header)
        assert resp.status_code == 422, (
            f"Expected 422 for {field}='{bad_value}', got {resp.status_code}"
        )


# ═══════════════════════════════════════════════════════════════════════════════
# 6. Model mock fallback
# ═══════════════════════════════════════════════════════════════════════════════

class TestMockFallback:

    def test_missing_model_returns_200_with_is_mock_true(
        self, client, mock_valid_token, valid_auth_header
    ):
        """When model file is absent, response is 200 with is_mock: true."""
        with patch("app.models.loader.model_loader.is_loaded", return_value=False), \
             patch("app.utils.firestore.audit_log"):
            resp = _post(client, VALID, valid_auth_header)

        assert resp.status_code == 200
        body = resp.json()
        assert body["is_mock"] is True
        assert body["confidence"] == "low"
        assert body["predicted_yield_kg_per_ha"] == 0.0

    def test_missing_model_still_returns_correct_crop_and_district(
        self, client, mock_valid_token, valid_auth_header
    ):
        """Mock response echoes back the correct crop and district."""
        payload = {**VALID, "crop": "Maize", "district": "Anuradhapura"}
        with patch("app.models.loader.model_loader.is_loaded", return_value=False), \
             patch("app.utils.firestore.audit_log"):
            resp = _post(client, payload, valid_auth_header)

        body = resp.json()
        assert body["crop"] == "Maize"
        assert body["district"] == "Anuradhapura"

    def test_loaded_model_returns_is_mock_false(
        self, client, mock_valid_token, valid_auth_header
    ):
        """When model is loaded, is_mock must be False."""
        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", return_value=_mock_model()), \
             patch("app.utils.firestore.audit_log"):
            resp = _post(client, VALID, valid_auth_header)

        assert resp.json()["is_mock"] is False


# ═══════════════════════════════════════════════════════════════════════════════
# 7. Feature engineering correctness
# ═══════════════════════════════════════════════════════════════════════════════

class TestFeatureEngineering:
    """
    Tests that verify _build_features() passes the right derived values
    to the model.  We capture the feature vector by inspecting model.predict
    call args.
    """

    def _captured_features(self, client, valid_auth_header, payload) -> list:
        """Run endpoint and return the feature list passed to model.predict."""
        captured = {}

        def _fake_predict(features_2d):
            captured["features"] = features_2d[0]
            return [18000.0]

        mock_model = MagicMock()
        mock_model.predict.side_effect = _fake_predict
        mock_model.predict_proba = None

        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", return_value=mock_model), \
             patch("app.utils.firestore.audit_log"):
            resp = client.post(URL, json=payload, headers=valid_auth_header)

        assert resp.status_code == 200, f"Request failed: {resp.json()}"
        return captured["features"]

    def test_heat_stress_flag_set_when_temp_max_above_35(
        self, client, mock_valid_token, valid_auth_header
    ):
        """heat_stress_flag (feature index 14) must be 1 when temp_max_c > 35."""
        payload = {**VALID, "temp_max_c": 36.0, "temp_min_c": 25.0}
        features = self._captured_features(client, valid_auth_header, payload)
        assert features[14] == 1, f"heat_stress_flag should be 1, got {features[14]}"

    def test_heat_stress_flag_not_set_when_temp_max_below_35(
        self, client, mock_valid_token, valid_auth_header
    ):
        """heat_stress_flag must be 0 when temp_max_c ≤ 35."""
        payload = {**VALID, "temp_max_c": 34.9, "temp_min_c": 20.0}
        features = self._captured_features(client, valid_auth_header, payload)
        assert features[14] == 0, f"heat_stress_flag should be 0, got {features[14]}"

    def test_cold_stress_flag_set_when_temp_min_below_12(
        self, client, mock_valid_token, valid_auth_header
    ):
        """cold_stress_flag (feature index 15) must be 1 when temp_min_c < 12."""
        payload = {**VALID, "temp_min_c": 11.9, "temp_max_c": 22.0}
        features = self._captured_features(client, valid_auth_header, payload)
        assert features[15] == 1, f"cold_stress_flag should be 1, got {features[15]}"

    def test_cold_stress_flag_not_set_when_temp_min_above_12(
        self, client, mock_valid_token, valid_auth_header
    ):
        """cold_stress_flag must be 0 when temp_min_c ≥ 12."""
        payload = {**VALID, "temp_min_c": 12.0, "temp_max_c": 25.0}
        features = self._captured_features(client, valid_auth_header, payload)
        assert features[15] == 0

    def test_rain_adequacy_capped_at_2(
        self, client, mock_valid_token, valid_auth_header
    ):
        """rain_adequacy (index 16) = rainfall_mm / 100, capped at 2.0."""
        payload = {**VALID, "rainfall_mm": 500.0}   # 500/100 = 5.0 → capped to 2.0
        features = self._captured_features(client, valid_auth_header, payload)
        assert features[16] == pytest.approx(2.0), (
            f"rain_adequacy should be capped at 2.0, got {features[16]}"
        )

    def test_rain_adequacy_normal(
        self, client, mock_valid_token, valid_auth_header
    ):
        """rain_adequacy for rainfall_mm=80 should be 0.8."""
        payload = {**VALID, "rainfall_mm": 80.0}
        features = self._captured_features(client, valid_auth_header, payload)
        assert features[16] == pytest.approx(0.8, abs=0.01)

    def test_temp_range_computed_correctly(
        self, client, mock_valid_token, valid_auth_header
    ):
        """temp_range (index 13) = temp_max_c − temp_min_c."""
        payload = {**VALID, "temp_min_c": 12.0, "temp_max_c": 28.0}
        features = self._captured_features(client, valid_auth_header, payload)
        assert features[13] == pytest.approx(16.0, abs=0.01)

    def test_nutrient_score_is_average_of_npk(
        self, client, mock_valid_token, valid_auth_header
    ):
        """nutrient_score (index 27) = (N + P + K) / 3."""
        payload = {**VALID, "N_index": 0.6, "P_index": 0.9, "K_index": 0.3}
        features = self._captured_features(client, valid_auth_header, payload)
        expected = (0.6 + 0.9 + 0.3) / 3
        assert features[27] == pytest.approx(expected, abs=0.01)

    def test_unknown_seed_variety_falls_back_to_local(
        self, client, mock_valid_token, valid_auth_header
    ):
        """An unknown seed variety should not crash — service falls back to 'Local'."""
        payload = {**VALID, "seed_variety": "SomeRandomVarietyNotInTrainingData"}
        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", return_value=_mock_model()), \
             patch("app.utils.firestore.audit_log"):
            resp = _post(client, payload, valid_auth_header)
        assert resp.status_code == 200

    def test_unknown_prev_crop_falls_back_to_unknown(
        self, client, mock_valid_token, valid_auth_header
    ):
        """An unknown prev_crop should not crash — service falls back to 'Unknown'."""
        payload = {**VALID, "prev_crop": "Avocado"}
        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", return_value=_mock_model()), \
             patch("app.utils.firestore.audit_log"):
            resp = _post(client, payload, valid_auth_header)
        assert resp.status_code == 200


# ═══════════════════════════════════════════════════════════════════════════════
# 8. Response shape validation
# ═══════════════════════════════════════════════════════════════════════════════

class TestResponseShape:

    def test_response_contains_all_required_fields(
        self, client, mock_valid_token, valid_auth_header
    ):
        """Response must contain every field defined in YieldPredictResponse."""
        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", return_value=_mock_model()), \
             patch("app.utils.firestore.audit_log"):
            resp = _post(client, VALID, valid_auth_header)

        body = resp.json()
        required = {
            "predicted_yield_kg_per_ha",
            "crop",
            "district",
            "confidence",
            "model_used",
            "is_mock",
        }
        missing = required - body.keys()
        assert not missing, f"Response missing fields: {missing}"

    def test_confidence_is_valid_enum(
        self, client, mock_valid_token, valid_auth_header
    ):
        """confidence field must be one of high / medium / low."""
        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", return_value=_mock_model()), \
             patch("app.utils.firestore.audit_log"):
            resp = _post(client, VALID, valid_auth_header)

        assert resp.json()["confidence"] in ("high", "medium", "low")

    def test_predicted_yield_is_positive_number(
        self, client, mock_valid_token, valid_auth_header
    ):
        """predicted_yield_kg_per_ha must be a positive float (not mock)."""
        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", return_value=_mock_model(21450.0)), \
             patch("app.utils.firestore.audit_log"):
            resp = _post(client, VALID, valid_auth_header)

        yield_val = resp.json()["predicted_yield_kg_per_ha"]
        assert isinstance(yield_val, (int, float))
        assert yield_val > 0

    def test_model_used_key_matches_crop(
        self, client, mock_valid_token, valid_auth_header
    ):
        """model_used field must reference the correct per-crop model key."""
        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", return_value=_mock_model()), \
             patch("app.utils.firestore.audit_log"):
            resp = _post(client, VALID, valid_auth_header)

        assert resp.json()["model_used"] == "yield_Carrot"


# ═══════════════════════════════════════════════════════════════════════════════
# 9. Boundary / edge-case values
# ═══════════════════════════════════════════════════════════════════════════════

class TestBoundaryValues:

    @pytest.mark.parametrize("field,boundary_value", [
        # Exact minimum allowed values
        ("rainfall_mm",        0.0),
        ("temp_min_c",        -5.0),
        ("temp_max_c",         0.0),
        ("humidity_pct",       0.0),
        ("soil_ph",            3.5),
        ("cultivated_area_ha", 0.1),
        ("inflation_index",    0.5),
        ("week_of_year",       1),
        ("holiday_flag",       0),
        # Exact maximum allowed values
        ("rainfall_mm",        500.0),
        ("temp_min_c",         45.0),
        ("temp_max_c",         50.0),
        ("humidity_pct",       100.0),
        ("soil_ph",            9.0),
        ("demand_index",       200.0),
        ("inflation_index",    3.0),
        ("week_of_year",       52),
        ("holiday_flag",       1),
        ("festival_flag",      1),
    ])
    def test_boundary_values_accepted(
        self, client, mock_valid_token, valid_auth_header, field, boundary_value
    ):
        """Exact boundary values must be accepted (not rejected with 422)."""
        payload = {**VALID, field: boundary_value}
        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", return_value=_mock_model()), \
             patch("app.utils.firestore.audit_log"):
            resp = _post(client, payload, valid_auth_header)
        assert resp.status_code == 200, (
            f"Boundary value {field}={boundary_value} was incorrectly rejected: "
            f"{resp.status_code} {resp.json()}"
        )


# ═══════════════════════════════════════════════════════════════════════════════
# 10. Audit logging
# ═══════════════════════════════════════════════════════════════════════════════

class TestAuditLogging:

    def test_audit_log_called_on_successful_prediction(
        self, client, mock_valid_token, valid_auth_header
    ):
        """audit_log must be called exactly once per successful prediction."""
        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", return_value=_mock_model()), \
             patch("app.routers.yield_router.audit_log") as mock_audit:
            _post(client, VALID, valid_auth_header)

        mock_audit.assert_called_once()
        call_kwargs = mock_audit.call_args
        assert call_kwargs is not None

    def test_audit_log_called_even_when_model_is_mock(
        self, client, mock_valid_token, valid_auth_header
    ):
        """audit_log must fire even when model is absent (mock response)."""
        with patch("app.models.loader.model_loader.is_loaded", return_value=False), \
             patch("app.routers.yield_router.audit_log") as mock_audit:
            _post(client, VALID, valid_auth_header)

        mock_audit.assert_called_once()

    def test_audit_log_not_called_on_422(
        self, client, mock_valid_token, valid_auth_header
    ):
        """audit_log must NOT fire when Pydantic rejects the input (422)."""
        bad_payload = {**VALID, "rainfall_mm": 9999.0}

        with patch("app.routers.yield_router.audit_log") as mock_audit:
            resp = _post(client, bad_payload, valid_auth_header)

        assert resp.status_code == 422
        mock_audit.assert_not_called()

    def test_audit_log_not_called_on_401(self, client):
        """audit_log must NOT fire when auth fails (401)."""
        with patch("app.routers.yield_router.audit_log") as mock_audit:
            resp = _post(client, VALID)

        assert resp.status_code == 401
        mock_audit.assert_not_called()


# ═══════════════════════════════════════════════════════════════════════════════
# 11. Rate limiting (requires slowapi to be active)
# ═══════════════════════════════════════════════════════════════════════════════

class TestRateLimiting:

    def test_31st_request_returns_429(self, client, mock_valid_token, valid_auth_header):
        """
        31 requests from the same IP within 1 minute must result in a 429.

        NOTE: This test only works when slowapi is enforcing limits against
        the TestClient's default IP (testclient).  If the limiter is disabled
        in the test environment, this test will be skipped automatically.
        """
        from app.middleware.rate_limit import limiter

        # Skip if rate limiter is in disabled/passthrough mode
        if getattr(limiter, "_disabled", False):
            pytest.skip("Rate limiter is disabled in test environment")

        with patch("app.models.loader.model_loader.is_loaded", return_value=True), \
             patch("app.models.loader.model_loader.get_model", return_value=_mock_model()), \
             patch("app.utils.firestore.audit_log"):
            responses = [
                _post(client, VALID, valid_auth_header)
                for _ in range(31)
            ]

        status_codes = [r.status_code for r in responses]
        assert 429 in status_codes, (
            f"Expected at least one 429 in 31 requests, got: {set(status_codes)}"
        )
      
