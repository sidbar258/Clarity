"""Loads the market into the graph and answers corridor queries.

`corridors.sv.jac` owns the model and the pricing math; this module owns the
graph itself -- seeding it from the CSV reference data and traversing it to
answer a comparison request.

Seeding is lazy and idempotent: the first query builds the market under a
`MarketNode`, and later queries reuse it. Call `reload_market()` after editing
the CSVs to rebuild from disk.
"""

import market_data;

import from corridors {
    MarketNode, ProviderNode, CorridorNode, Serves,
    Quote, QuoteSummary, QuoteResult, CorridorInfo, CountryInfo,
    cost_offer, summarize
}


"""Sort key: cheapest all-in cost first."""
def _by_total(q: Quote) -> float {
    return q.total_cost;
}


"""Wipe the providers and corridors hanging off a market node."""
def _clear_market(market: MarketNode) {
    for provider in [market -->[?:ProviderNode]] {
        del provider;
    }
    for corridor in [market -->[?:CorridorNode]] {
        del corridor;
    }
    market.offer_count = 0;
}


"""Build the provider/corridor graph from the CSV reference data.

Returns the number of `Serves` edges written -- one per purchasable product.
"""
def _seed_market(market: MarketNode) -> int {
    _clear_market(market);

    providers: dict[str, ProviderNode] = {};
    for row in market_data.load_providers() {
        slug = row["slug"] as str;
        providers[slug] = (market ++> ProviderNode(
            slug=slug,
            name=row["name"] as str,
            blurb=row["blurb"] as str,
            network=row["network"] as str
        )) as ProviderNode;
    }

    corridors: dict[str, CorridorNode] = {};
    for pair in market_data.corridor_pairs() {
        send_code = pair["send_code"] as str;
        recv_code = pair["receive_code"] as str;
        send_cur = pair["send_currency"] as str;
        recv_cur = pair["receive_currency"] as str;
        key = f"{send_code}>{recv_code}";
        corridors[key] = (market ++> CorridorNode(
            send_country=send_code,
            receive_country=recv_code,
            send_currency=send_cur,
            receive_currency=recv_cur,
            region=pair["region"] as str,
            mid_rate=market_data.mid_market_rate(send_cur, recv_cur) as float
        )) as CorridorNode;
    }

    written = 0;
    for offer in market_data.load_offers() {
        slug = offer["provider_slug"] as str;
        send_c = offer["send_country"] as str;
        recv_c = offer["receive_country"] as str;
        corridor_key = f"{send_c}>{recv_c}";
        if slug not in providers or corridor_key not in corridors {
            continue;
        }
        provider = providers[slug];
        corridor = corridors[corridor_key];
        provider +>:Serves(
            pay_in=offer["pay_in"] as str,
            pay_out=offer["pay_out"] as str,
            fixed_fee=offer["fixed_fee"] as float,
            pct_fee_bps=offer["pct_fee_bps"] as float,
            min_fee=offer["min_fee"] as float,
            fx_margin_bps=offer["fx_margin_bps"] as float,
            eta_minutes=int(offer["eta_minutes"] as float)
        ):+> corridor;
        written += 1;
    }

    market.offer_count = written;
    return written;
}


"""Get the market node, seeding it on first use."""
def ensure_market -> MarketNode {
    found = [root -->[?:MarketNode]];
    if found {
        market = found[0];
        if market.offer_count == 0 {
            _seed_market(market);
        }
        return market;
    }
    fresh = (root ++> MarketNode()) as MarketNode;
    _seed_market(fresh);
    return fresh;
}


"""Rebuild the graph from the CSVs. Returns the offer count."""
def reload_market -> int {
    return _seed_market(ensure_market());
}


"""Find one corridor, or None when the dataset does not cover it.

Parameters are named `src`/`dst` rather than `send_country`/`receive_country`
on purpose: inside a filter comprehension a bare name resolves to the *node's*
field, so same-named parameters would silently compare a field to itself.
"""
def find_corridor(market: MarketNode, src: str, dst: str) -> CorridorNode | None {
    for corridor in [market -->[?:CorridorNode]] {
        if corridor.send_country == src and corridor.receive_country == dst {
            return corridor;
        }
    }
    return None;
}


"""Cost every offer on a corridor and rank them cheapest-first.

`pay_in` / `pay_out` are optional filters -- pass "" to include every product.
"""
def quote_corridor(
    send_country: str,
    receive_country: str,
    amount: float,
    pay_in: str = "",
    pay_out: str = ""
) -> QuoteResult {
    if amount <= 0.0 {
        return QuoteResult(
            summary=QuoteSummary(),
            quotes=[],
            ok=False,
            message="Enter an amount greater than zero."
        );
    }

    market = ensure_market();
    corridor = find_corridor(market, send_country, receive_country);
    if corridor is None {
        return QuoteResult(
            summary=QuoteSummary(),
            quotes=[],
            ok=False,
            message=f"No pricing data for {send_country} -> {receive_country} yet."
        );
    }

    quotes: list[Quote] = [];
    for provider in [market -->[?:ProviderNode]] {
        for offer in [edge provider ->:Serves:-> corridor] {
            if pay_in and offer.pay_in != pay_in {
                continue;
            }
            if pay_out and offer.pay_out != pay_out {
                continue;
            }
            quotes.append(cost_offer(provider, offer, corridor, amount));
        }
    }

    if not quotes {
        return QuoteResult(
            summary=QuoteSummary(),
            quotes=[],
            ok=False,
            message="No provider matches those payment and payout choices."
        );
    }

    ranked = sorted(quotes, key=_by_total);
    return QuoteResult(
        summary=summarize(ranked, corridor, amount),
        quotes=ranked,
        ok=True,
        message=""
    );
}


"""Every corridor the dataset covers, for populating the form."""
def list_corridors -> list[CorridorInfo] {
    market = ensure_market();
    out: list[CorridorInfo] = [];
    for corridor in [market -->[?:CorridorNode]] {
        offers = len([edge corridor <-:Serves:<-]);
        out.append(CorridorInfo(
            send_country=corridor.send_country,
            receive_country=corridor.receive_country,
            send_currency=corridor.send_currency,
            receive_currency=corridor.receive_currency,
            region=corridor.region,
            mid_rate=corridor.mid_rate,
            offer_count=offers
        ));
    }
    return out;
}


"""Countries available as a source or destination, per the CSV metadata."""
def list_countries(role: str) -> list[CountryInfo] {
    out: list[CountryInfo] = [];
    rows = market_data.send_countries() if role == "send" else market_data.receive_countries();
    for row in rows {
        out.append(CountryInfo(
            code=row["code"] as str,
            name=row["name"] as str,
            currency=row["currency"] as str,
            flag=row["flag"] as str,
            region=row["region"] as str
        ));
    }
    return out;
}
