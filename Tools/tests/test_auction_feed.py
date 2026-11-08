"""Tests for Tools/build/auction_feed.py, offline. From the repo root:

    python -m unittest discover -s Tools/tests
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths  # noqa: E402,F401
import auction_feed  # noqa: E402


class AuctionFeedTest(unittest.TestCase):
    def test_lowest_price_for_one(self):
        auctions = [{"item": {"id": 2589}, "quantity": 20, "buyout": 600},
                    {"item": {"id": 2589}, "quantity": 5, "buyout": 125},
                    {"item": {"id": 2770}, "quantity": 1, "bid": 50},
                    {"item": {"id": 4306}, "quantity": 1, "buyout": 900}]
        commodities = [{"item": {"id": 2589}, "quantity": 100, "unit_price": 24},
                       {"item": {"id": 2770}, "quantity": 3, "unit_price": 68}]
        prices = auction_feed.lowest(commodities, auction_feed.lowest(auctions, {}))
        self.assertEqual(prices, {2589: 24, 2770: 68, 4306: 900})

    def test_no_listings(self):
        self.assertEqual(auction_feed.lowest(None, {}), {})

    def test_encode_steps_in_base_36(self):
        self.assertEqual(auction_feed.encode({2770: 68, 2589: 26, 2592: 1296}), "1zx:q,3:100,4y:1w")
        self.assertEqual(auction_feed.encode({}), "")

    def test_lua(self):
        feed = {"us": {110: {"faction": "Alliance", "prices": {10: 35}}, 112: {"faction": "Alliance", "prices": {}}}}
        text = auction_feed.lua(feed, 1794114010)
        self.assertIn("    time = 1794114010,\r\n", text)
        self.assertIn('        [1] = {\r\n            [110] = { faction = "Alliance", prices = "a:z" },\r\n', text)
        self.assertIn('            [112] = { faction = "Alliance", prices = "" },\r\n', text)
        self.assertTrue(text.isascii())


if __name__ == "__main__":
    unittest.main()
