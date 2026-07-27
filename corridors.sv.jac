"""Domain model and pricing engine for remittance corridors.

The market is modelled as a graph, which is what makes the comparison cheap to
express:

    root --> MarketNode --> ProviderNode
                        --> CorridorNode

    ProviderNode -:Serves:-> CorridorNode

Every `Serves` edge is one *purchasable product* -- a specific pay-in/pay-out
combination with its own fee, spread and delivery time. A provider therefore has
several edges into the same corridor (bank->bank, debit->cash pickup, ...), and
quoting a corridor is just reading the edges that land on it.

Pricing follows the World Bank's *Remittance Prices Worldwide* methodology: the
true cost of a transfer is the advertised fee **plus** the exchange-rate margin.
The second term is the one providers do not put on the marketing page, and
surfacing it is the whole point of this project.
"""

import market_data;


# ---------------------------------------------------------------------------
# Graph archetypes
# ---------------------------------------------------------------------------

node MarketNode {
    """Singleton anchor for the loaded market snapshot."""

    has offer_count: int = 0,
        source_label: str = "sample data";
}


node ProviderNode {
    """A remittance provider (Wise, Western Union, a bank wire, ...)."""

    has slug: str,
        name: str,
        blurb: str = "",
        network: str = "";
}


node CorridorNode {
    """One send-country -> receive-country lane, e.g. US -> MX."""

    has send_country: str,
        receive_country: str,
        send_currency: str,
        receive_currency: str,
        region: str = "",
        mid_rate: float = 0.0;
}


edge Serves: ProviderNode --> CorridorNode {
    """One provider product on one corridor.

    `fixed_fee` and `min_fee` are in the send currency; the `_bps` fields are
    basis points (100 bps == 1%). `fx_margin_bps` is the markup applied on top
    of the mid-market rate -- the hidden cost.
    """

    has pay_in: str,
        pay_out: str,
        fixed_fee: float = 0.0,
        pct_fee_bps: float = 0.0,
        min_fee: float = 0.0,
        fx_margin_bps: float = 0.0,
        eta_minutes: int = 1440;
}


# ---------------------------------------------------------------------------
# Wire types (plain objs -- these cross to the browser)
# ---------------------------------------------------------------------------

obj Quote {
    """A fully costed offer, ready to render in the comparison table."""

    has provider: str,
        provider_slug: str,
        blurb: str,
        network: str,
        pay_in: str,
        pay_out: str,
        product_label: str,
        send_amount: float,
        send_currency: str,
        receive_currency: str,
        transfer_fee: float,
        fx_margin_pct: float,
        fx_spread_cost: float,
        total_cost: float,
        total_cost_pct: float,
        mid_market_rate: float,
        offered_rate: float,
        receive_amount: float,
        eta_minutes: int,
        eta_label: str,
        hidden_cost_share: float;
}


obj QuoteSummary {
    """Headline numbers derived from a full set of quotes for one corridor."""

    has corridor_label: str = "",
        send_amount: float = 0.0,
        send_currency: str = "",
        receive_currency: str = "",
        mid_market_rate: float = 0.0,
        offer_count: int = 0,
        best_provider: str = "",
        best_product_label: str = "",
        best_total_cost: float = 0.0,
        best_total_cost_pct: float = 0.0,
        best_receive_amount: float = 0.0,
        worst_provider: str = "",
        worst_total_cost: float = 0.0,
        worst_total_cost_pct: float = 0.0,
        savings_vs_worst: float = 0.0,
        avg_total_cost_pct: float = 0.0,
        avg_hidden_share: float = 0.0,
        headline_fee_provider: str = "",
        headline_fee_total_cost: float = 0.0,
        headline_trap: bool = False,
        headline_trap_gap: float = 0.0,
        fastest_provider: str = "",
        fastest_eta_label: str = "",
        sdg_target_pct: float = 0.0,
        global_average_pct: float = 0.0;
}


obj QuoteResult {
    """What a comparison request returns: the ranked table plus its summary."""

    has summary: QuoteSummary,
        quotes: list[Quote] = [],
        ok: bool = True,
        message: str = "";
}


obj CountryInfo {
    has code: str,
        name: str,
        currency: str,
        flag: str = "",
        region: str = "";
}


obj CorridorInfo {
    has send_country: str,
        receive_country: str,
        send_currency: str,
        receive_currency: str,
        region: str = "",
        mid_rate: float = 0.0,
        offer_count: int = 0;
}


# ---------------------------------------------------------------------------
# Presentation helpers
# ---------------------------------------------------------------------------

glob PAY_IN_LABELS: dict[str, str] = {
    "bank_account": "Bank account",
    "debit_card": "Debit card",
    "credit_card": "Credit card",
    "cash": "Cash in store"
};

glob PAY_OUT_LABELS: dict[str, str] = {
    "bank_deposit": "Bank deposit",
    "cash_pickup": "Cash pickup",
    "mobile_wallet": "Mobile wallet",
    "home_delivery": "Home delivery"
};


"""Human-readable name for a pay-in method."""
def pay_in_label(method: str) -> str {
    return PAY_IN_LABELS.get(method, method.replace("_", " ").title());
}


"""Human-readable name for a pay-out method."""
def pay_out_label(method: str) -> str {
    return PAY_OUT_LABELS.get(method, method.replace("_", " ").title());
}


"""Turn a delivery time in minutes into something a person can read."""
def eta_label(minutes: int) -> str {
    if minutes <= 5 {
        return "Instant";
    }
    if minutes < 60 {
        return f"{minutes} min";
    }
    if minutes < 1440 {
        hours = minutes // 60;
        return f"~{hours} hr" if hours == 1 else f"~{hours} hrs";
    }
    days = minutes // 1440;
    if days == 1 {
        return "~1 day";
    }
    return f"~{days} days";
}


# ---------------------------------------------------------------------------
# The pricing math
# ---------------------------------------------------------------------------

"""Cost one provider product for a given send amount.

Fee is deducted first, then the remainder is converted at the provider's rate --
the order every major provider uses. The exchange-rate margin is charged on the
converted amount, so it is reported in the send currency to sit alongside the
advertised fee.
"""
def cost_offer(
    provider: ProviderNode,
    offer: Serves,
    corridor: CorridorNode,
    amount: float
) -> Quote {
    pct_fee = amount * offer.pct_fee_bps / 10000.0;
    fee = offer.fixed_fee + pct_fee;
    if fee < offer.min_fee {
        fee = offer.min_fee;
    }
    if fee > amount {
        fee = amount;
    }

    converted_base = amount - fee;
    margin = offer.fx_margin_bps / 10000.0;
    offered_rate = corridor.mid_rate * (1.0 - margin);
    receive_amount = converted_base * offered_rate;

    # The spread costs the sender exactly `margin` of whatever got converted.
    fx_spread_cost = converted_base * margin;
    total_cost = fee + fx_spread_cost;

    total_pct = (total_cost / amount * 100.0) if amount > 0.0 else 0.0;
    hidden_share = (fx_spread_cost / total_cost * 100.0) if total_cost > 0.0 else 0.0;

    return Quote(
        provider=provider.name,
        provider_slug=provider.slug,
        blurb=provider.blurb,
        network=provider.network,
        pay_in=offer.pay_in,
        pay_out=offer.pay_out,
        product_label=f"{pay_in_label(offer.pay_in)} -> {pay_out_label(offer.pay_out)}",
        send_amount=amount,
        send_currency=corridor.send_currency,
        receive_currency=corridor.receive_currency,
        transfer_fee=round(fee, 2),
        fx_margin_pct=round(offer.fx_margin_bps / 100.0, 3),
        fx_spread_cost=round(fx_spread_cost, 2),
        total_cost=round(total_cost, 2),
        total_cost_pct=round(total_pct, 2),
        mid_market_rate=corridor.mid_rate,
        offered_rate=offered_rate,
        receive_amount=round(receive_amount, 2),
        eta_minutes=offer.eta_minutes,
        eta_label=eta_label(offer.eta_minutes),
        hidden_cost_share=round(hidden_share, 1)
    );
}


"""Sort key: cheapest all-in cost first."""
def _by_total_cost(q: Quote) -> float {
    return q.total_cost;
}


"""Sort key: fastest delivery first."""
def _by_speed(q: Quote) -> int {
    return q.eta_minutes;
}


"""Sort key: lowest *advertised* fee first -- the number providers market on."""
def _by_headline_fee(q: Quote) -> float {
    return q.transfer_fee;
}


"""Build the headline summary from a ranked list of quotes.

`quotes` must already be sorted cheapest-first.
"""
def summarize(quotes: list[Quote], corridor: CorridorNode, amount: float) -> QuoteSummary {
    summary = QuoteSummary(
        corridor_label=f"{corridor.send_country} -> {corridor.receive_country}",
        send_amount=amount,
        send_currency=corridor.send_currency,
        receive_currency=corridor.receive_currency,
        mid_market_rate=corridor.mid_rate,
        offer_count=len(quotes),
        sdg_target_pct=market_data.SDG_TARGET_PCT as float,
        global_average_pct=market_data.GLOBAL_AVERAGE_PCT as float
    );
    if not quotes {
        return summary;
    }

    best = quotes[0];
    worst = quotes[len(quotes) - 1];
    summary.best_provider = best.provider;
    summary.best_product_label = best.product_label;
    summary.best_total_cost = best.total_cost;
    summary.best_total_cost_pct = best.total_cost_pct;
    summary.best_receive_amount = best.receive_amount;
    summary.worst_provider = worst.provider;
    summary.worst_total_cost = worst.total_cost;
    summary.worst_total_cost_pct = worst.total_cost_pct;
    summary.savings_vs_worst = round(worst.total_cost - best.total_cost, 2);

    total_pct = 0.0;
    total_hidden = 0.0;
    for q in quotes {
        total_pct += q.total_cost_pct;
        total_hidden += q.hidden_cost_share;
    }
    summary.avg_total_cost_pct = round(total_pct / len(quotes), 2);
    summary.avg_hidden_share = round(total_hidden / len(quotes), 1);

    # The "low fee" trap: the offer with the smallest advertised fee is often
    # not the cheapest once the exchange-rate margin is counted.
    by_fee = sorted(quotes, key=_by_headline_fee);
    headline = by_fee[0];
    summary.headline_fee_provider = headline.provider;
    summary.headline_fee_total_cost = headline.total_cost;
    summary.headline_trap = headline.total_cost > best.total_cost;
    summary.headline_trap_gap = round(headline.total_cost - best.total_cost, 2);

    fastest = sorted(quotes, key=_by_speed)[0];
    summary.fastest_provider = fastest.provider;
    summary.fastest_eta_label = fastest.eta_label;

    return summary;
}
