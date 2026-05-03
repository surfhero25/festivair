"""Tests for relay.server helper classes — MessageDedup and ClientRateLimiter."""

from __future__ import annotations

import time
from unittest.mock import patch

import pytest

from relay.server import ClientRateLimiter, MessageDedup


# ── MessageDedup ──────────────────────────────────────────────────────


class TestMessageDedup:
    def test_first_seen_is_not_duplicate(self):
        d = MessageDedup()
        assert d.is_duplicate("msg1") is False

    def test_second_seen_within_ttl_is_duplicate(self):
        d = MessageDedup()
        d.is_duplicate("msg1")
        assert d.is_duplicate("msg1") is True

    def test_distinct_ids_are_independent(self):
        d = MessageDedup()
        d.is_duplicate("msg1")
        assert d.is_duplicate("msg2") is False

    def test_evicts_after_ttl_expires(self):
        d = MessageDedup(ttl_seconds=10)
        with patch("relay.server.time.monotonic", return_value=1000.0):
            d.is_duplicate("msg1")
        with patch("relay.server.time.monotonic", return_value=1011.0):
            # Past TTL — should be considered fresh
            assert d.is_duplicate("msg1") is False

    def test_capacity_eviction_drops_oldest(self):
        # NOTE: is_duplicate() has a side effect — every call also records
        # the id. So a single test can only assert ONE thing about the
        # post-eviction state without disturbing it.
        d = MessageDedup(max_entries=3)
        d.is_duplicate("a")
        d.is_duplicate("b")
        d.is_duplicate("c")
        d.is_duplicate("d")  # evicts "a" (oldest)
        assert d.is_duplicate("a") is False  # "a" was evicted

    def test_capacity_eviction_keeps_most_recent(self):
        d = MessageDedup(max_entries=3)
        d.is_duplicate("a")
        d.is_duplicate("b")
        d.is_duplicate("c")
        d.is_duplicate("d")  # evicts "a"
        # The most-recently-added entry is still tracked
        assert d.is_duplicate("d") is True

    def test_capacity_eviction_keeps_middle_entries(self):
        d = MessageDedup(max_entries=3)
        d.is_duplicate("a")
        d.is_duplicate("b")
        d.is_duplicate("c")
        d.is_duplicate("d")  # evicts "a"
        assert d.is_duplicate("b") is True


# ── ClientRateLimiter ─────────────────────────────────────────────────


class TestRateLimiter:
    def test_burst_capacity_allows_initial_requests(self):
        rl = ClientRateLimiter(rate=10, burst=5)
        # Initial bucket = burst
        for _ in range(5):
            assert rl.allow() is True
        # 6th immediate request denied
        assert rl.allow() is False

    def test_tokens_refill_over_time(self):
        rl = ClientRateLimiter(rate=10, burst=2)
        # Drain
        rl.allow()
        rl.allow()
        assert rl.allow() is False
        # Wait long enough for one token to refill (0.15s at rate=10/s)
        time.sleep(0.15)
        assert rl.allow() is True

    def test_tokens_cap_at_burst(self):
        rl = ClientRateLimiter(rate=100, burst=3)
        # Wait a long time — bucket should NOT exceed burst
        time.sleep(0.5)
        # Should allow exactly 3 (burst), then deny
        assert rl.allow() is True
        assert rl.allow() is True
        assert rl.allow() is True
        assert rl.allow() is False
