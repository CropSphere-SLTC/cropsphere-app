"""The crop-recommendation branch of the chat prediction_context.

The recommendation page's starter chips are comparative ("why is X first?",
"what if I want to grow something else?"), so unlike the yield and price
handoffs this one has to carry the WHOLE ranking, not just a winning figure.
These cover that rendering plus the two gates a farmer can act on.
"""

import pytest

from app.models.schemas import (
    ChatRequest,
    PredictionContext,
    PredictionCropRecommendation,
)
from app.user.services.chatbot_service import (
    _format_prediction_context,
    _has_prediction_grounding,
    _prediction_context_terms,
)


def _rec(rank, crop, confidence, *, district_ok=True, temp_ok=True):
    return PredictionCropRecommendation(
        rank=rank,
        crop=crop,
        confidence=confidence,
        expected_yield_kg_per_ha=1307.0,
        expected_price_lkr_kg=50.0,
        district_suitable=district_ok,
        temp_suitable=temp_ok,
        rain_suitable=True,
        humidity_suitable=True,
        ph_suitable=True,
    )


@pytest.fixture
def context():
    """The Monaragala / Yala result this redesign was built against."""
    return PredictionContext(
        crop="Groundnut",  # top-ranked, not a farmer selection
        district="Monaragala",
        season="Yala",
        irrigation="rainfed",
        soil_ph=6.5,
        soil_moisture_pct=40.0,
        recommendations=[
            _rec(1, "Groundnut", 0.663, temp_ok=False),
            _rec(2, "Cowpea", 0.074),
            _rec(6, "Carrot", 0.146, district_ok=False, temp_ok=False),
        ],
    )


def test_block_is_named_a_crop_recommendation(context):
    """The block used to say "yield prediction" for anything it did not
    recognise, which invites the model to answer the wrong question."""
    out = _format_prediction_context(context)
    assert "crop recommendation" in out
    assert "yield prediction" not in out
    # Must still open with the phrase the grounding rules key on.
    assert out.startswith("Relevant context")


def test_every_crop_is_rendered_not_just_the_winner(context):
    out = _format_prediction_context(context)
    for crop in ("Groundnut", "Cowpea", "Carrot"):
        assert crop in out


def test_soil_inputs_are_rendered(context):
    out = _format_prediction_context(context)
    assert "Soil pH: 6.5" in out
    assert "Soil moisture: 40%" in out


def test_failed_condition_is_named(context):
    """"3 of 4" alone is not actionable; which one failed is."""
    out = _format_prediction_context(context)
    assert "3 of 4 growing conditions suitable (unsuitable: temperature)" in out
    assert "4 of 4 growing conditions suitable" in out


def test_district_gate_is_explained_where_it_applies(context):
    """Carrot outranks Cowpea on probability but sorts last — say why."""
    out = _format_prediction_context(context)
    carrot = next(ln for ln in out.splitlines() if "Carrot" in ln)
    cowpea = next(ln for ln in out.splitlines() if "Cowpea" in ln)
    assert "NOT normally grown in this district" in carrot
    assert "NOT normally grown in this district" not in cowpea


def test_gate_and_grounding_read_the_recommendation_context(context):
    """The saved-profile confirmation gate must resolve from this context.

    Without it a stale account-level profile would answer "which crop?" for a
    page that just ranked six of them.
    """
    req = ChatRequest(
        message="Explain these recommendations",
        user_id="u1",
        prediction_context=context,
    )
    assert _prediction_context_terms(req) == ("Groundnut", "Monaragala")
    assert _has_prediction_grounding(req) is True


def test_other_prediction_kinds_are_unaffected():
    """One model serves four screens; a price context must not grow crop rows."""
    out = _format_prediction_context(
        PredictionContext(crop="Carrot", predicted_price_lkr_kg=90.0)
    )
    assert "price prediction" in out
    assert "Ranked crop recommendations" not in out
    assert "Soil pH" not in out


def test_recommendations_are_capped_at_six():
    """Six crops exist; a longer list is a malformed client, not a big farm."""
    with pytest.raises(ValueError):
        PredictionContext(
            recommendations=[_rec(1, "Maize", 0.5) for _ in range(7)]
        )
