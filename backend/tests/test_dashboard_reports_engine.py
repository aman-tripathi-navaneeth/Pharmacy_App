from datetime import date

import pytest

from app.modules.today_dashboard_reports.engine import (
    build_task, compute_score, format_rupees, indian_group, rank,
)
from app.modules.today_dashboard_reports.facts import (
    CloseFact, CreditFact, DeliveryFact, ExpiryFact, LowStockFact, RefillFact, SyncFact,
)
from app.modules.today_dashboard_reports.schemas import Category, Urgency


def expiry(days, rw=None):
    return ExpiryFact(key="expiry:b1", medicine="Augmentin 625", batch_no="AB1", quantity_text="18 strips",
                      days_to_expiry=days, value_paise=100000, return_days_left=rw, supplier="Sri Sai")


@pytest.mark.parametrize("days,expected", [
    (-1, Urgency.URGENT), (0, Urgency.URGENT), (30, Urgency.URGENT), (31, Urgency.SOON), (60, Urgency.SOON),
    (61, Urgency.ROUTINE), (90, Urgency.ROUTINE), (91, None),
])
def test_expiry_boundaries(days, expected):
    task = build_task(expiry(days))
    assert (task.urgency if task else None) == expected


def test_expiry_return_window_makes_it_urgent_and_offers_return():
    task = build_task(expiry(75, rw=14))
    assert task.urgency is Urgency.URGENT
    assert task.action.type == "plan_return"
    assert "14 days" in task.reason


def test_expiry_closed_window_is_not_a_return_task():
    task = build_task(expiry(45, rw=-2))
    assert task.urgency is Urgency.SOON
    assert task.reason == "Return window closed"
    assert task.action.type == "view_batch"


def test_expired_title():
    assert build_task(expiry(0)).title == "Augmentin 625 has expired"


def test_out_of_stock_is_urgent():
    t = build_task(LowStockFact(key="low_stock:m", medicine="Telma 40", out_of_stock=True, value_paise=1))
    assert t.urgency is Urgency.URGENT and t.reason == "Out of stock"


@pytest.mark.parametrize("cover,expected", [(1.0, Urgency.SOON), (3, Urgency.SOON), (3.1, Urgency.ROUTINE), (None, Urgency.ROUTINE)])
def test_low_stock_cover(cover, expected):
    t = build_task(LowStockFact(key="low_stock:m", medicine="Dolo", out_of_stock=False, value_paise=1,
                                stock_text="6 strips", minimum_text="20", days_of_cover=cover))
    assert t.urgency is expected


@pytest.mark.parametrize("overdue,expected", [(30, Urgency.URGENT), (7, Urgency.URGENT), (6, Urgency.SOON), (0, Urgency.SOON),
                                              (-1, Urgency.ROUTINE), (-3, Urgency.ROUTINE), (-4, None)])
def test_refill_boundaries(overdue, expected):
    t = build_task(RefillFact(key="refill:c", customer="Lakshmi", purpose="BP", medicine_text="Amlodipine",
                              days_overdue=overdue))
    assert (t.urgency if t else None) == expected


def test_refill_failed_reminder_changes_label():
    t = build_task(RefillFact(key="refill:c", customer="L", purpose="BP", medicine_text="x", days_overdue=3, reminder_failed=True))
    assert t.action.label == "Resend reminder" and "failed" in t.detail


def credit(days, balance=100000, limit=None):
    return CreditFact(key="credit:c", customer="Venkata Rao", balance_paise=balance, days_since_payment=days, credit_limit_paise=limit)


def test_credit_rules():
    assert build_task(credit(5)) is None
    assert build_task(credit(8)).urgency is Urgency.ROUTINE
    assert build_task(credit(31)).urgency is Urgency.URGENT
    over = build_task(credit(5, balance=425000, limit=300000))
    assert over.urgency is Urgency.URGENT and "credit limit" in over.detail
    assert over.title == "Venkata Rao owes \u20b94,250"


@pytest.mark.parametrize("late,expected", [(5, Urgency.URGENT), (4, Urgency.URGENT), (3, Urgency.SOON), (1, Urgency.SOON), (0, Urgency.ROUTINE), (-1, None)])
def test_delivery(late, expected):
    t = build_task(DeliveryFact(key="delivery:p", order_no="PO-1", supplier="S", days_late=late, item_count=3, value_paise=100))
    assert (t.urgency if t else None) == expected


def test_sync_is_always_urgent():
    t = build_task(SyncFact(key="sync:u", label="Invoice photo", reference="INV-1", attempts=2))
    assert t.urgency is Urgency.URGENT and "Stock is not updated" in t.detail


def test_close_rules():
    assert build_task(CloseFact(key="close:daily_report", report_confirmed_today=True, past_usual_time=True)) is None
    assert build_task(CloseFact(key="close:daily_report", report_confirmed_today=False, past_usual_time=False)) is None
    assert build_task(CloseFact(key="close:daily_report", report_confirmed_today=False, past_usual_time=True)).urgency is Urgency.SOON
    missed = build_task(CloseFact(key="close:daily_report", report_confirmed_today=True, past_usual_time=True,
                                  missed_dates=(date(2026, 10, 10),)))
    assert missed.urgency is Urgency.URGENT and missed.title == "Sales report missing for 10 Oct"


def test_score_formula_matches_the_guide():
    assert compute_score(Urgency.URGENT, 45, 425000) == 168.5  # 100 + 3*20 + 8.5
    assert compute_score(Urgency.ROUTINE, 0, 0) == 30
    assert compute_score(Urgency.SOON, 3, 10_000_000) == 60 + 9 + 20  # value points capped at 20


def test_ranking_is_by_score_then_key():
    a = build_task(credit(45, 425000, 300000))
    b = build_task(CloseFact(key="close:daily_report", report_confirmed_today=False, past_usual_time=True))
    c = build_task(expiry(12))
    assert [t.key for t in rank([b, c, a])][0] == a.key
    assert [t.key for t in rank([b, c, a])] == [t.key for t in rank([a, b, c])]


def test_money_formatting():
    assert indian_group(12345678) == "1,23,45,678"
    assert format_rupees(425000) == "\u20b94,250"
    assert format_rupees(425050) == "\u20b94,250.50"
    assert format_rupees(0) == "\u20b90"
