"""Build the Auction Prices feed: every Forever auction house's lowest price per item, from
Blizzard's auction data, into NaowhForever_AuctionData/Prices.lua (ns.AuctionFeed).

Needs a Blizzard API client in BLIZZARD_CLIENT_ID and BLIZZARD_CLIENT_SECRET. The release
workflow runs it before packaging, so every release carries the prices of that hour.

Usage: python Tools/build/auction_feed.py [--summary] [--region us] [--out path]
"""
import argparse
import base64
import gzip
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths  # noqa: E402

OUT = paths.ROOT / "NaowhForever_AuctionData" / "Prices.lua"
TOKEN_URL = "https://oauth.battle.net/token"
API = "https://{region}.api.blizzard.com/data/wow/ruleset/{ruleset}/auctions/{path}"
# Every ruleset lists the same houses, so one is enough (Normal, which every region has).
RULESET = 2
# GetCurrentRegion() in game.
REGIONS = {"us": 1, "eu": 3}
TIMEOUT = 120
DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"


def token(client_id, secret):
    auth = base64.b64encode(f"{client_id}:{secret}".encode()).decode()
    request = urllib.request.Request(TOKEN_URL, data=b"grant_type=client_credentials",
                                     headers={"Authorization": f"Basic {auth}"})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.load(response)["access_token"]


def get(access, region, path):
    query = urllib.parse.urlencode({"namespace": f"dynamic-forever-{region}", "locale": "en_US"})
    url = API.format(region=region, ruleset=RULESET, path=path) + "?" + query
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {access}",
                                                   "Accept-Encoding": "gzip"})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        body = response.read()
        if response.headers.get("Content-Encoding") == "gzip":
            body = gzip.decompress(body)
        return json.loads(body), len(body), response.headers.get("Last-Modified")


def lowest(listings, prices):
    """Fold listings into item ID -> lowest price for one, in copper; bid-only auctions skipped."""
    for listing in listings or []:
        item, quantity = listing["item"]["id"], listing.get("quantity") or 1
        each = listing.get("unit_price")
        if each is None and listing.get("buyout"):
            each = listing["buyout"] // quantity
        if each and (item not in prices or each < prices[item]):
            prices[item] = each
    return prices


def base36(number):
    text = ""
    while True:
        number, digit = divmod(number, 36)
        text = DIGITS[digit] + text
        if not number:
            return text


def encode(prices):
    """"id:price,..." in base 36, each ID as the step from the one before."""
    parts, last = [], 0
    for item in sorted(prices):
        parts.append(base36(item - last) + ":" + base36(prices[item]))
        last = item
    return ",".join(parts)


def houses(access, region, summary=False):
    index, _, _ = get(access, region, "")
    if summary:
        print(json.dumps(index, indent=1)[:4000])
    found = {}
    for house in index.get("auctions", []):
        house_id, name = house["id"], house.get("name", "")
        started = time.time()
        listed, size, modified = get(access, region, str(house_id))
        goods, goods_size, _ = get(access, region, f"{house_id}/commodities")
        prices = lowest(goods.get("auctions"), lowest(listed.get("auctions"), {}))
        found[house_id] = {"faction": name.split()[0] if name else "", "prices": prices}
        if summary:
            auctions, commodities = listed.get("auctions") or [], goods.get("auctions") or []
            print(f"{region} {house_id} {name!r}: {len(auctions)} auctions, {len(commodities)} commodities, "
                  f"{len(prices)} items, {(size + goods_size) // 1024} KB, {time.time() - started:.1f} s, "
                  f"Last-Modified {modified}")
            if auctions:
                print("  auction keys", sorted(auctions[0]), "item keys", sorted(auctions[0]["item"]))
            if commodities:
                print("  commodity keys", sorted(commodities[0]))
    return found


def lua(feed, built):
    lines = ["-- Prices.lua: every Forever auction house's lowest prices, built by Tools/build/auction_feed.py.",
             "local ns = _G.NaowhForever", "", "ns.AuctionFeed = {", f"    time = {built},", "    regions = {"]
    for region, found in feed.items():
        lines.append(f"        [{REGIONS[region]}] = {{")
        for house_id in sorted(found):
            house = found[house_id]
            lines.append(f'            [{house_id}] = {{ faction = "{house["faction"]}", prices = "{encode(house["prices"])}" }},')
        lines.append("        },")
    lines += ["    },", "}", ""]
    return "\r\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--summary", action="store_true", help="print what Blizzard sends, write nothing")
    parser.add_argument("--region", choices=sorted(REGIONS), action="append")
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()
    access = token(os.environ["BLIZZARD_CLIENT_ID"], os.environ["BLIZZARD_CLIENT_SECRET"])
    built = int(time.time())
    feed = {region: houses(access, region, args.summary) for region in args.region or sorted(REGIONS)}
    if args.summary:
        return
    args.out.write_bytes(lua(feed, built).encode("ascii"))
    counts = ", ".join(f"{region} {len(found)} houses" for region, found in feed.items())
    print(f"wrote {args.out.name}: {counts}, {args.out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
