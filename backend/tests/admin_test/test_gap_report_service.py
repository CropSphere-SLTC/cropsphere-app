"""Unit tests for app.admin.services.gap_report_service — chat_analytics
aggregation. Firestore and _dataset_capabilities are mocked."""

from unittest.mock import MagicMock, patch

import pytest

from app.admin.services import gap_report_service as svc

CAPS = {
    "crops": ["Carrot", "Maize", "Green gram", "Cowpea", "Finger millet", "Groundnut"],
    "districts": [
        "Anuradhapura",
        "Ampara",
        "Badulla",
        "Batticaloa",
        "Hambantota",
        "Jaffna",
        "Monaragala",
        "Nuwara Eliya",
    ],
}
_CAPS_TARGET = "app.user.services.chatbot_service._dataset_capabilities"


def _doc(data):
    d = MagicMock()
    d.to_dict.return_value = data
    return d


def _db_with(docs):
    db = MagicMock()
    db.collection.return_value.where.return_value.stream.return_value = docs
    return db


@pytest.fixture(autouse=True)
def _clear_cache():
    svc._cache.clear()
    yield
    svc._cache.clear()


SAMPLE = [
    {
        "response_type": "answer",
        "confidence": "High confidence",
        "knowledge_level": "intermediate",
        "crop_mentioned": "Carrot",
        "district_mentioned": "Badulla",
        "question": "carrot yield?",
        "response_time_ms": 1000,
        "session_message_count": 3,
        "followup_chip_tapped": True,
    },
    {
        "response_type": "refusal",
        "confidence": "Out of scope",
        "knowledge_level": "beginner",
        "crop_mentioned": "rice",
        "district_mentioned": "colombo",
        "question": "rice price in colombo",
        "response_time_ms": 500,
        "session_message_count": 1,
        "followup_chip_tapped": False,
    },
    {
        "response_type": "near_miss",
        "confidence": "Out of scope",
        "knowledge_level": "beginner",
        "crop_mentioned": "rice",
        "district_mentioned": "galle",
        "question": "rice price in colombo",
        "response_time_ms": 300,
        "session_message_count": 2,
        "followup_chip_tapped": False,
    },
]


def test_aggregates_sample():
    with patch(
        "app.utils.firestore.get_db", return_value=_db_with([_doc(d) for d in SAMPLE])
    ), patch(_CAPS_TARGET, return_value=CAPS):
        report = svc.get_gap_report(7)

    assert report["period"] == "last_7_days"
    assert report["total_interactions"] == 3
    assert report["response_breakdown"]["answer"] == 1
    assert report["response_breakdown"]["refusal"] == 1
    assert report["response_breakdown"]["near_miss"] == 1
    assert report["top_refused_questions"][0] == {
        "question": "rice price in colombo",
        "count": 2,
    }
    assert {"crop": "rice", "request_count": 2} in report["missing_crops"]
    assert all(m["crop"] != "Carrot" for m in report["missing_crops"])
    assert {m["district"] for m in report["missing_districts"]} == {"colombo", "galle"}
    assert report["confidence_distribution"]["Out of scope"] == 2
    assert report["knowledge_level_distribution"]["beginner"] == 2
    assert report["avg_response_time_ms"] == 600
    assert report["chip_tap_rate"] == 0.33
    assert report["avg_session_length"] == 2.0


def test_empty_collection_returns_zeroed_report():
    with patch("app.utils.firestore.get_db", return_value=_db_with([])), patch(
        _CAPS_TARGET, return_value=CAPS
    ):
        report = svc.get_gap_report(7)
    assert report["total_interactions"] == 0
    assert report["top_refused_questions"] == []
    assert report["missing_crops"] == []
    assert report["chip_tap_rate"] == 0.0
    assert report["avg_response_time_ms"] == 0
    assert report["response_breakdown"]["answer"] == 0


def test_days_clamped_to_max_30():
    with patch("app.utils.firestore.get_db", return_value=_db_with([])), patch(
        _CAPS_TARGET, return_value=CAPS
    ):
        report = svc.get_gap_report(999)
    assert report["period"] == "last_30_days"


def test_result_cached_within_ttl():
    with patch(
        "app.utils.firestore.get_db", return_value=_db_with([_doc(SAMPLE[0])])
    ) as gdb, patch(_CAPS_TARGET, return_value=CAPS):
        svc.get_gap_report(7)
        svc.get_gap_report(7)
    assert gdb.call_count == 1  # second call served from cache


def test_low_confidence_label_normalised():
    docs = [
        _doc(
            {
                "response_type": "answer",
                "knowledge_level": "advanced",
                "confidence": "Low confidence — please verify with an "
                "agricultural officer",
            }
        )
    ]
    with patch("app.utils.firestore.get_db", return_value=_db_with(docs)), patch(
        _CAPS_TARGET, return_value=CAPS
    ):
        report = svc.get_gap_report(7)
    assert report["confidence_distribution"] == {"Low confidence": 1}


def _db_multi(analytics_docs, feedback_docs):
    """Firestore double routing by collection name, so chat_analytics and
    chat_feedback return different document sets."""
    db = MagicMock()

    def _collection(name):
        col = MagicMock()
        docs = feedback_docs if name == "chat_feedback" else analytics_docs
        col.where.return_value.stream.return_value = docs
        return col

    db.collection.side_effect = _collection
    return db


def test_feedback_summary_aggregation():
    feedback = [
        _doc({"feedback": "up"}),
        _doc({"feedback": "up"}),
        _doc({"feedback": "up"}),
        _doc({"feedback": "up"}),
        _doc({"feedback": "down", "message_text": "carrot yield in badulla"}),
        _doc({"feedback": "down", "message_text": "carrot yield in badulla"}),
    ]
    db = _db_multi([_doc(SAMPLE[0])], feedback)
    with patch("app.utils.firestore.get_db", return_value=db), patch(
        _CAPS_TARGET, return_value=CAPS
    ):
        summary = svc.get_gap_report(7)["feedback_summary"]

    assert summary["total_feedback"] == 6
    assert summary["thumbs_up"] == 4
    assert summary["thumbs_down"] == 2
    assert summary["satisfaction_rate"] == 0.67
    assert summary["most_downvoted_questions"] == [
        {"question": "carrot yield in badulla", "count": 2}
    ]


def test_feedback_summary_empty_when_no_feedback():
    db = _db_multi([_doc(SAMPLE[0])], [])
    with patch("app.utils.firestore.get_db", return_value=db), patch(
        _CAPS_TARGET, return_value=CAPS
    ):
        summary = svc.get_gap_report(7)["feedback_summary"]
    assert summary["total_feedback"] == 0
    assert summary["satisfaction_rate"] == 0.0
    assert summary["most_downvoted_questions"] == []


def test_report_includes_fewshot_info():
    with patch("app.utils.firestore.get_db", return_value=_db_with([])), patch(
        _CAPS_TARGET, return_value=CAPS
    ):
        report = svc.get_gap_report(7)
    fs = report["fewshot"]
    # Keys are always present; the seed file ships with the image, so in a repo
    # checkout it exists with the manual examples.
    assert set(fs) == {"file_exists", "updated_at", "counts", "total"}
    assert isinstance(fs["total"], int)
