"""CSV loader for the remittance reference data.

This module is the project's *data access* layer only. It reads the CSV files
under ``data/`` and hands plain dicts to Jac; every piece of pricing math, the
graph model, and the API surface live in Jac (``corridors.sv.jac``,
``endpoints.sv.jac``, ``advisor.sv.jac``).

The CSVs hold ILLUSTRATIVE SAMPLE PRICING modelled on the shape of publicly
advertised remittance fees. They are not live quotes. Point ``DATA_DIR`` at real
provider data, or replace these readers with a pricing API client, to make the
numbers authoritative.

Cost methodology follows the World Bank's *Remittance Prices Worldwide*: the
total cost of a transfer is the advertised fee **plus** the exchange-rate
margin, expressed as a percentage of the amount sent.

Expected files
--------------
``data/currencies.csv``
    ``currency,units_per_usd``

``data/countries.csv``
    ``code,name,currency,flag,role,region,difficulty``
    ``role`` is ``send``, ``receive`` or ``both``. ``difficulty`` scales how
    wide a spread providers charge on that corridor (1.0 == dense/competitive).

``data/providers.csv``
    ``slug,name,blurb,network``

``data/offers.csv``
    ``provider_slug,send_country,receive_country,pay_in,pay_out,fixed_fee,``
    ``pct_fee_bps,min_fee,fx_margin_bps,eta_minutes``
    One row per purchasable product. Fees are in the SEND currency; ``*_bps``
    columns are basis points (100 bps == 1%).
"""

from __future__ import annotations

import csv
import os

# --------------------------------------------------------------------------
# Benchmarks (World Bank Remittance Prices Worldwide)
# --------------------------------------------------------------------------

#: UN Sustainable Development Goal 10.c target for remittance cost, in percent.
SDG_TARGET_PCT: float = 3.0

#: Rough global average total cost of sending USD 200, in percent.
GLOBAL_AVERAGE_PCT: float = 6.2

DATA_DIR: str = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")


def _read(filename: str) -> list[dict]:
    """Read one CSV into a list of dicts. Missing file -> empty list."""
    path = os.path.join(DATA_DIR, filename)
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8") as handle:
        return [dict(row) for row in csv.DictReader(handle)]


def _num(row: dict, key: str, fallback: float = 0.0) -> float:
    """Parse a float column, tolerating blanks and stray whitespace."""
    raw = str(row.get(key, "")).strip()
    if raw == "":
        return fallback
    try:
        return float(raw)
    except ValueError:
        return fallback


def _text(row: dict, key: str, fallback: str = "") -> str:
    raw = str(row.get(key, "")).strip()
    return raw if raw != "" else fallback


def load_currencies() -> dict[str, float]:
    """Currency code -> mid-market units per 1 USD."""
    table: dict[str, float] = {}
    for row in _read("currencies.csv"):
        code = _text(row, "currency").upper()
        rate = _num(row, "units_per_usd")
        if code and rate > 0.0:
            table[code] = rate
    return table


def load_countries() -> list[dict]:
    """Every country row, normalised and typed."""
    out: list[dict] = []
    for row in _read("countries.csv"):
        code = _text(row, "code").upper()
        if not code:
            continue
        out.append(
            {
                "code": code,
                "name": _text(row, "name", code),
                "currency": _text(row, "currency").upper(),
                "flag": _text(row, "flag"),
                "role": _text(row, "role", "both").lower(),
                "region": _text(row, "region"),
                "difficulty": _num(row, "difficulty", 1.0),
            }
        )
    return out


def send_countries() -> list[dict]:
    return [c for c in load_countries() if c["role"] in ("send", "both")]


def receive_countries() -> list[dict]:
    return [c for c in load_countries() if c["role"] in ("receive", "both")]


def load_providers() -> list[dict]:
    """The provider catalogue: slug, display name, and positioning copy."""
    out: list[dict] = []
    for row in _read("providers.csv"):
        slug = _text(row, "slug")
        if not slug:
            continue
        out.append(
            {
                "slug": slug,
                "name": _text(row, "name", slug),
                "blurb": _text(row, "blurb"),
                "network": _text(row, "network"),
            }
        )
    return out


def load_offers() -> list[dict]:
    """Every provider product, one flat dict per row of ``offers.csv``."""
    names = {p["slug"]: p["name"] for p in load_providers()}
    out: list[dict] = []
    for row in _read("offers.csv"):
        slug = _text(row, "provider_slug")
        send = _text(row, "send_country").upper()
        recv = _text(row, "receive_country").upper()
        if not slug or not send or not recv:
            continue
        out.append(
            {
                "provider_slug": slug,
                "provider_name": names.get(slug, slug),
                "send_country": send,
                "receive_country": recv,
                "pay_in": _text(row, "pay_in", "bank_account"),
                "pay_out": _text(row, "pay_out", "bank_deposit"),
                "fixed_fee": _num(row, "fixed_fee"),
                "pct_fee_bps": _num(row, "pct_fee_bps"),
                "min_fee": _num(row, "min_fee"),
                "fx_margin_bps": _num(row, "fx_margin_bps"),
                "eta_minutes": _num(row, "eta_minutes", 1440.0),
            }
        )
    return out


def offers_for(send_country: str, receive_country: str) -> list[dict]:
    """Offers on one corridor."""
    send = send_country.upper()
    recv = receive_country.upper()
    return [
        o
        for o in load_offers()
        if o["send_country"] == send and o["receive_country"] == recv
    ]


def corridor_pairs() -> list[dict]:
    """Distinct send/receive pairs that actually have at least one offer."""
    meta = {c["code"]: c for c in load_countries()}
    seen: set[tuple[str, str]] = set()
    pairs: list[dict] = []
    for offer in load_offers():
        key = (offer["send_country"], offer["receive_country"])
        if key in seen:
            continue
        seen.add(key)
        src = meta.get(key[0], {})
        dst = meta.get(key[1], {})
        pairs.append(
            {
                "send_code": key[0],
                "send_currency": str(src.get("currency", "")),
                "receive_code": key[1],
                "receive_currency": str(dst.get("currency", "")),
                "region": str(dst.get("region", "")),
                "difficulty": float(dst.get("difficulty", 1.0)),
            }
        )
    return pairs


def mid_market_rate(send_currency: str, receive_currency: str) -> float:
    """Cross-rate: units of ``receive_currency`` per 1 unit of send currency."""
    table = load_currencies()
    send_per_usd = table.get(send_currency.upper(), 0.0)
    recv_per_usd = table.get(receive_currency.upper(), 0.0)
    if send_per_usd <= 0.0 or recv_per_usd <= 0.0:
        return 0.0
    return recv_per_usd / send_per_usd
