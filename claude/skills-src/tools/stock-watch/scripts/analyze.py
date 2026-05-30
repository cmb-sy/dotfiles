#!/usr/bin/env python3
"""Compute technical + fundamental scores from raw fetch data.

Sentiment and Recommendation are LLM-driven and handled by the orchestrator,
not this script. This script outputs deterministic sub-scores only.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Score stocks from raw fetch data")
    p.add_argument("--input", type=Path, required=True, help="raw.json from fetch.py")
    p.add_argument("--output", type=Path, required=True, help="analysis.json path")
    return p.parse_args()


def rsi(close: pd.Series, period: int = 14) -> float:
    if len(close) < period + 1:
        return float("nan")
    delta = close.diff()
    gain = delta.clip(lower=0).rolling(period).mean()
    loss = (-delta.clip(upper=0)).rolling(period).mean()
    rs = gain / loss.replace(0, np.nan)
    rsi_series = 100 - (100 / (1 + rs))
    return float(rsi_series.iloc[-1])


def macd_hist(close: pd.Series) -> float:
    if len(close) < 35:
        return float("nan")
    ema12 = close.ewm(span=12, adjust=False).mean()
    ema26 = close.ewm(span=26, adjust=False).mean()
    macd_line = ema12 - ema26
    signal = macd_line.ewm(span=9, adjust=False).mean()
    return float((macd_line - signal).iloc[-1])


def bollinger_position(close: pd.Series, period: int = 20, sigma: int = 2) -> str:
    if len(close) < period:
        return "n/a"
    ma = close.rolling(period).mean().iloc[-1]
    std = close.rolling(period).std().iloc[-1]
    upper = ma + sigma * std
    lower = ma - sigma * std
    price = close.iloc[-1]
    if price >= upper:
        return "above_upper"
    if price <= lower:
        return "below_lower"
    return "within"


def technical_score(history: list[dict]) -> tuple[float | None, dict]:
    """Return (score 0-50 or None, detail dict)."""
    if not history or len(history) < 30:
        return None, {"error": "insufficient history"}
    df = pd.DataFrame(history)
    close = df["close"]
    ma25 = close.rolling(25).mean().iloc[-1]
    ma75 = close.rolling(min(75, len(close))).mean().iloc[-1]
    latest = close.iloc[-1]

    score = 0.0
    detail: dict = {
        "ma25": round(float(ma25), 2),
        "ma75": round(float(ma75), 2),
        "latest": round(float(latest), 2),
    }

    if ma25 > ma75 and latest > ma25:
        score += 20
        detail["trend"] = "uptrend"
    elif ma25 < ma75 and latest < ma25:
        score += 0
        detail["trend"] = "downtrend"
    else:
        score += 10
        detail["trend"] = "mixed"

    rsi_val = rsi(close)
    detail["rsi"] = round(rsi_val, 1) if not np.isnan(rsi_val) else None
    if not np.isnan(rsi_val):
        if rsi_val < 30:
            score += 15
        elif rsi_val > 70:
            score -= 10
        else:
            score += 10

    macd_val = macd_hist(close)
    detail["macd_hist"] = round(macd_val, 3) if not np.isnan(macd_val) else None
    if not np.isnan(macd_val) and macd_val > 0:
        score += 5

    boll = bollinger_position(close)
    detail["bollinger"] = boll
    if boll == "below_lower":
        score += 10
    elif boll == "above_upper":
        score -= 10

    score = max(0.0, min(50.0, score))
    return round(score, 1), detail


def fundamental_score(fundamentals: dict) -> tuple[float | None, dict]:
    if not fundamentals:
        return None, {"error": "no fundamentals"}
    score = 0.0
    detail: dict = {}
    have_data = False

    per = fundamentals.get("per")
    detail["per"] = per
    if per is not None and per > 0:
        have_data = True
        if per < 15:
            score += 15
        elif per < 25:
            score += 10
        elif per < 40:
            score += 5

    pbr = fundamentals.get("pbr")
    detail["pbr"] = pbr
    if pbr is not None and pbr > 0:
        have_data = True
        if pbr < 1.5:
            score += 5

    roe = fundamentals.get("roe")
    detail["roe"] = roe
    if roe is not None:
        have_data = True
        if roe > 0.15:
            score += 15
        elif roe > 0.10:
            score += 10
        elif roe > 0.05:
            score += 5

    rev_growth = fundamentals.get("revenue_growth")
    detail["revenue_growth"] = rev_growth
    if rev_growth is not None:
        have_data = True
        if rev_growth > 0.10:
            score += 10
        elif rev_growth > 0:
            score += 5

    dividend = fundamentals.get("dividend_yield")
    detail["dividend_yield"] = dividend
    if dividend is not None and dividend > 0.03:
        score += 5
        have_data = True

    if not have_data:
        return None, detail
    return round(min(50.0, score), 1), detail


def main() -> int:
    args = parse_args()
    raw = json.loads(args.input.read_text(encoding="utf-8"))

    results: dict = {"analyzed_at": raw.get("fetched_at"), "tickers": {}}
    for tk, data in raw.get("data", {}).items():
        if "error" in data:
            results["tickers"][tk] = {
                "error": data["error"],
                "technical_score": "N/A",
                "fundamental_score": "N/A",
                "name": data.get("fundamentals", {}).get("name", tk),
            }
            continue

        tech_score, tech_detail = technical_score(data.get("history", []))
        fund_score, fund_detail = fundamental_score(data.get("fundamentals", {}))

        results["tickers"][tk] = {
            "name": data.get("fundamentals", {}).get("name", tk),
            "latest_price": data.get("latest_price"),
            "currency": data.get("fundamentals", {}).get("currency"),
            "technical_score": "N/A" if tech_score is None else tech_score,
            "technical_detail": tech_detail,
            "fundamental_score": "N/A" if fund_score is None else fund_score,
            "fundamental_detail": fund_detail,
            "news": data.get("news", []),
        }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"analyzed: {len(results['tickers'])} tickers → {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
