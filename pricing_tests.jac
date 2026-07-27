"""Tests for the corridor pricing engine.

These build their own tiny graph fixture rather than reading `data/*.csv`, so
they stay valid whatever the reference dataset holds.
"""

import from corridors {
    ProviderNode, CorridorNode, Serves, Quote,
    cost_offer, summarize, eta_label, pay_in_label, pay_out_label
}


"""Build a corridor with a known mid-market rate."""
def _corridor(rate: float) -> CorridorNode {
    return (root ++> CorridorNode(
        send_country="US",
        receive_country="MX",
        send_currency="USD",
        receive_currency="MXN",
        region="Latin America",
        mid_rate=rate
    )) as CorridorNode;
}


"""Attach one provider product to a corridor and return the costed quote."""
def _quote(
    corridor: CorridorNode,
    name: str,
    fixed_fee: float,
    pct_fee_bps: float,
    fx_margin_bps: float,
    eta_minutes: int,
    amount: float
) -> Quote {
    provider = (root ++> ProviderNode(slug=name.lower(), name=name)) as ProviderNode;
    provider +>:Serves(
        pay_in="bank_account",
        pay_out="bank_deposit",
        fixed_fee=fixed_fee,
        pct_fee_bps=pct_fee_bps,
        fx_margin_bps=fx_margin_bps,
        eta_minutes=eta_minutes
    ):+> corridor;
    offers = [edge provider ->:Serves:-> corridor];
    assert len(offers) == 1, "expected exactly one Serves edge";
    return cost_offer(provider, offers[0], corridor, amount);
}


test "fee is deducted before conversion" {
    corridor = _corridor(17.0);
    # $4 flat fee, 3.00% exchange-rate margin, on a $200 transfer.
    q = _quote(corridor, "SpreadCo", 4.0, 0.0, 300.0, 60, 200.0);

    assert q.transfer_fee == 4.0;
    # 196 converted at 17.0 * 0.97 = 16.49
    assert abs(q.offered_rate - 16.49) < 0.0001, f"rate was {q.offered_rate}";
    assert abs(q.receive_amount - 3232.04) < 0.01, f"received {q.receive_amount}";
}


test "hidden spread is counted in the total cost" {
    corridor = _corridor(17.0);
    q = _quote(corridor, "SpreadCo", 4.0, 0.0, 300.0, 60, 200.0);

    # 196 * 3% = 5.88 lost to the exchange rate, on top of the $4 fee.
    assert abs(q.fx_spread_cost - 5.88) < 0.01, f"spread was {q.fx_spread_cost}";
    assert abs(q.total_cost - 9.88) < 0.01, f"total was {q.total_cost}";
    assert abs(q.total_cost_pct - 4.94) < 0.01, f"pct was {q.total_cost_pct}";
    # Most of what this transfer costs is invisible on the pricing page.
    assert q.hidden_cost_share > 59.0 and q.hidden_cost_share < 60.0;
}


test "a mid-market provider has no hidden cost" {
    corridor = _corridor(17.0);
    # 0.65 flat + 0.52% fee, zero margin -- the transparent pricing model.
    q = _quote(corridor, "MidMarket", 0.65, 52.0, 0.0, 1080, 200.0);

    assert abs(q.transfer_fee - 1.69) < 0.001, f"fee was {q.transfer_fee}";
    assert q.fx_spread_cost == 0.0;
    assert q.offered_rate == 17.0;
    assert q.hidden_cost_share == 0.0;
    assert abs(q.total_cost - 1.69) < 0.001;
}


test "percentage fee respects the minimum" {
    corridor = _corridor(17.0);
    # 0.52% of $10 is 5c, but the provider floors its fee at $0.90.
    provider = (root ++> ProviderNode(slug="floored", name="Floored")) as ProviderNode;
    provider +>:Serves(
        pay_in="bank_account",
        pay_out="bank_deposit",
        pct_fee_bps=52.0,
        min_fee=0.9,
        eta_minutes=60
    ):+> corridor;
    offers = [edge provider ->:Serves:-> corridor];
    q = cost_offer(provider, offers[0], corridor, 10.0);

    assert q.transfer_fee == 0.9, f"fee was {q.transfer_fee}";
}


test "the lowest advertised fee is not the cheapest option" {
    corridor = _corridor(17.0);
    amount = 200.0;

    # A zero-fee headline funded by a 3.85% spread...
    free = _quote(corridor, "ZeroFee", 0.0, 0.0, 385.0, 2880, amount);
    # ...loses to an honest fee with no spread at all.
    honest = _quote(corridor, "Honest", 0.65, 52.0, 0.0, 1080, amount);

    assert free.transfer_fee < honest.transfer_fee, "ZeroFee should look cheaper";
    assert free.total_cost > honest.total_cost, "but cost more all-in";

    ranked = [honest, free];
    summary = summarize(ranked, corridor, amount);

    assert summary.best_provider == "Honest";
    assert summary.headline_fee_provider == "ZeroFee";
    assert summary.headline_trap, "the low-fee trap should be flagged";
    assert summary.headline_trap_gap > 0.0;
    assert summary.savings_vs_worst > 0.0;
}


test "summary is empty but safe with no quotes" {
    corridor = _corridor(17.0);
    summary = summarize([], corridor, 200.0);

    assert summary.offer_count == 0;
    assert summary.best_provider == "";
    assert not summary.headline_trap;
}


test "delivery times read like a person wrote them" {
    assert eta_label(3) == "Instant";
    assert eta_label(20) == "20 min";
    assert eta_label(60) == "~1 hr";
    assert eta_label(240) == "~4 hrs";
    assert eta_label(1440) == "~1 day";
    assert eta_label(4320) == "~3 days";
}


test "payment method labels are humanised" {
    assert pay_in_label("bank_account") == "Bank account";
    assert pay_out_label("cash_pickup") == "Cash pickup";
    # Unknown methods still render readably rather than blowing up.
    assert pay_out_label("drone_drop") == "Drone Drop";
}
