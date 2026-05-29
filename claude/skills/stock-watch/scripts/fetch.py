#!/usr/bin/env python3
"""Fetch OHLCV + financials + news for a list of tickers via yfinance.

Cache results to ~/.stock-watch/cache/<ticker>-<YYYY-MM-DD>.json to avoid
re-fetching the same data within a single day (yfinance rate limit mitigation).
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime
from pathlib import Path

import yfinance as yf


CACHE_DIR = Path.home() / ".stock-watch" / "cache"
TODAY = date.today().isoformat()


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Fetch stock data for tickers")
    p.add_argument("--tickers", required=True, help="Comma-separated tickers (e.g. AAPL,7203.T)")
    p.add_argument("--output", type=Path, required=True, help="Output JSON path")
    p.add_argument("--force", action="store_true", help="Ignore cache, force refresh")
    return p.parse_args()


def normalize_ticker(raw: str) -> str:
    """Append .T suffix to 4-digit JP tickers if missing."""
    raw = raw.strip().upper()
    if raw.isdigit() and len(raw) == 4:
        return f"{raw}.T"
    return raw


def fetch_one(ticker: str, force: bool = False) -> dict:
    cache_path = CACHE_DIR / f"{ticker}-{TODAY}.json"
    if not force and cache_path.exists():
        return json.loads(cache_path.read_text(encoding="utf-8"))

    result: dict = {"ticker": ticker, "fetched_at": datetime.now().isoformat()}
    try:
        t = yf.Ticker(ticker)

        hist = t.history(period="3mo", interval="1d")
        if hist.empty:
            result["error"] = "no historical data"
        else:
            result["history"] = [
                {
                    "date": idx.strftime("%Y-%m-%d"),
                    "open": float(row["Open"]),
                    "high": float(row["High"]),
                    "low": float(row["Low"]),
                    "close": float(row["Close"]),
                    "volume": int(row["Volume"]) if row["Volume"] == row["Volume"] else 0,
                }
                for idx, row in hist.iterrows()
            ]
            result["latest_price"] = result["history"][-1]["close"]

        info = getattr(t, "info", {}) or {}
        result["fundamentals"] = {
            "name": info.get("longName") or info.get("shortName") or ticker,
            "sector": info.get("sector"),
            "per": info.get("trailingPE"),
            "pbr": info.get("priceToBook"),
            "roe": info.get("returnOnEquity"),
            "dividend_yield": info.get("dividendYield"),
            "revenue_growth": info.get("revenueGrowth"),
            "market_cap": info.get("marketCap"),
            "currency": info.get("currency"),
        }

        try:
            news_items = t.news or []
        except Exception:
            news_items = []
        result["news"] = [
            {
                "title": n.get("title"),
                "publisher": n.get("publisher"),
                "link": n.get("link"),
                "published_at": (
                    datetime.fromtimestamp(n["providerPublishTime"]).isoformat()
                    if n.get("providerPublishTime")
                    else None
                ),
            }
            for n in news_items[:5]
        ]
    except Exception as e:
        result["error"] = f"fetch failed: {type(e).__name__}: {e}"

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return result


def main() -> int:
    args = parse_args()
    tickers = [normalize_ticker(t) for t in args.tickers.split(",") if t.strip()]
    if not tickers:
        print("ERROR: no tickers provided", file=sys.stderr)
        return 1

    payload = {
        "fetched_at": datetime.now().isoformat(),
        "tickers": tickers,
        "data": {},
    }
    for tk in tickers:
        print(f"fetching {tk}...", file=sys.stderr)
        payload["data"][tk] = fetch_one(tk, force=args.force)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    n_ok = sum(1 for d in payload["data"].values() if "error" not in d)
    print(f"fetched: {n_ok}/{len(tickers)} → {args.output}")
    return 0 if n_ok > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
