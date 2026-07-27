"""The AI remittance advisor.

Two LLM-powered steps wrap the deterministic pricing engine:

1. `parse_intent` turns free text ("I need to send 300 dollars to my mum in
   Manila for rent") into a structured corridor query.
2. `explain` takes the *already computed* quotes and writes the recommendation.

The split matters. Every number the advisor cites is computed by
`corridors.sv.jac` from the reference data and handed to the model as context --
the LLM chooses and explains, it never invents a fee or an exchange rate. That
keeps the advice grounded and auditable, which is the whole point in a product
about hidden costs.

If no model is configured (no API key, no local model), both steps fall back to
deterministic Jac so the app still works end to end.
"""

import market_data;

import from corridors { Quote, QuoteResult, eta_label }
import from market { quote_corridor, list_countries }


# ---------------------------------------------------------------------------
# Wire types
# ---------------------------------------------------------------------------

obj SendIntent {
    """A remittance request extracted from natural language."""

    has amount: float = 0.0,
        send_country: str = "",
        receive_country: str = "",
        pay_in: str = "",
        pay_out: str = "",
        priority: str = "cost",
        understood: bool = False,
        clarification: str = "";
}

sem SendIntent = "A structured money-transfer request pulled out of a user's message.";
sem SendIntent.amount = "How much the user wants to send, as a number in the sending country's currency. 0 if not stated.";
sem SendIntent.send_country = "ISO 3166-1 alpha-2 code of the country the money is sent FROM. Empty string if not stated.";
sem SendIntent.receive_country = "ISO 3166-1 alpha-2 code of the country the money is sent TO. Empty string if not stated.";
sem SendIntent.pay_in = "How the user wants to pay: 'bank_account', 'debit_card', or 'credit_card'. Empty string if not stated.";
sem SendIntent.pay_out = "How the recipient collects: 'bank_deposit', 'cash_pickup', or 'mobile_wallet'. Empty string if not stated.";
sem SendIntent.priority = "What the user cares about most: 'cost' if they want the cheapest, 'speed' if they need it fast, 'convenience' if collection method matters most. Default to 'cost'.";
sem SendIntent.understood = "True only if BOTH countries and a positive amount were determined. False otherwise.";
sem SendIntent.clarification = "If understood is False, one short question asking the user for exactly what is missing. Empty string when understood is True.";


obj Advice {
    """A recommendation written from the computed quotes."""

    has headline: str = "",
        provider: str = "",
        product: str = "",
        why: str = "",
        watch_out: str = "",
        savings_note: str = "",
        ai_generated: bool = True;
}

sem Advice = "A short, practical recommendation for which remittance provider to use.";
sem Advice.headline = "One sentence, under 20 words, naming the recommended option and the all-in cost.";
sem Advice.provider = "The exact provider name from the supplied options. Never invent a provider.";
sem Advice.product = "The exact pay-in to pay-out product label of the recommended option.";
sem Advice.why = "Two or three sentences on why this option wins, citing the fee and the exchange-rate margin separately. Use only numbers present in the supplied options.";
sem Advice.watch_out = "One sentence naming the most misleading option in the list -- typically one advertising a low or zero fee while charging a wide exchange-rate margin. Say what it would actually cost.";
sem Advice.savings_note = "One sentence quantifying what the user saves versus the most expensive option, using the supplied figures.";
sem Advice.ai_generated = "Always true.";


obj AdviceResult {
    """Everything one natural-language request produces."""

    has intent: SendIntent,
        quotes: QuoteResult,
        advice: Advice,
        ok: bool = True,
        message: str = "";
}


# ---------------------------------------------------------------------------
# LLM-delegated functions
# ---------------------------------------------------------------------------

def parse_intent(request: str, country_reference: str) -> SendIntent by llm(temperature=0.0);

sem parse_intent = """Extract a structured money-transfer request from the user's message.
Map country names, cities, nationalities and currencies to the ISO codes listed in
the reference. A city implies its country (Manila -> PH, Lagos -> NG). Phrases like
'my family back home' carry no country -- do not guess one. If the sending country is
not stated but the amount is in dollars and no other clue exists, leave it empty rather
than assuming.""";
sem parse_intent.request = "The user's message, in their own words.";
sem parse_intent.country_reference = "The corridors this dataset covers, as 'CODE = Country name' lines. Only use codes that appear here.";


def explain(options: str, context: str) -> Advice by llm(temperature=0.3);

sem explain = """Recommend one remittance option to a person sending money to family.
Every figure you cite must come from the supplied options -- never estimate, round
loosely, or introduce a number that is not there. Write plainly, for someone who is
not a finance professional. The reader cares that the money arrives intact, so be
concrete about what each option actually costs rather than what it advertises.""";
sem explain.options = "The costed options for this corridor, cheapest first, with fee, exchange-rate margin, total cost and delivery time for each.";
sem explain.context = "What the sender is optimising for and any constraints they mentioned.";


# ---------------------------------------------------------------------------
# Grounding: render computed quotes as model context
# ---------------------------------------------------------------------------

"""Render the ranked quotes as the factual context the model must reason over."""
def _brief(result: QuoteResult, limit: int) -> str {
    summary = result.summary;
    lines: list[str] = [
        f"Corridor: {summary.corridor_label}",
        f"Sending: {summary.send_amount} {summary.send_currency}",
        f"Mid-market rate: 1 {summary.send_currency} = {summary.mid_market_rate} {summary.receive_currency}",
        f"World Bank global average cost: {summary.global_average_pct}% | UN target: {summary.sdg_target_pct}%",
        "",
        "Options, cheapest all-in first:"
    ];

    shown = 0;
    for q in result.quotes {
        if shown >= limit {
            break;
        }
        shown += 1;
        lines.append(
            f"{shown}. {q.provider} ({q.product_label}) -- "
            + f"advertised fee {q.transfer_fee} {q.send_currency}; "
            + f"exchange-rate margin {q.fx_margin_pct}% costing a further {q.fx_spread_cost} {q.send_currency}; "
            + f"TOTAL COST {q.total_cost} {q.send_currency} ({q.total_cost_pct}% of the amount sent); "
            + f"recipient gets {q.receive_amount} {q.receive_currency}; arrives in {q.eta_label}"
        );
    }

    if summary.headline_trap {
        lines.append("");
        lines.append(
            f"Note: {summary.headline_fee_provider} advertises the lowest fee but costs "
            + f"{summary.headline_trap_gap} {summary.send_currency} more all-in than the cheapest option."
        );
    }
    lines.append(
        f"Choosing the cheapest over the most expensive ({summary.worst_provider}) saves "
        + f"{summary.savings_vs_worst} {summary.send_currency} on this one transfer."
    );
    return "\n".join(lines);
}


"""A one-line reference of the country codes the dataset covers."""
def _country_reference -> str {
    lines: list[str] = ["Sending countries:"];
    for c in list_countries("send") {
        lines.append(f"{c.code} = {c.name} ({c.currency})");
    }
    lines.append("Receiving countries:");
    for c in list_countries("receive") {
        lines.append(f"{c.code} = {c.name} ({c.currency})");
    }
    return "\n".join(lines);
}


# ---------------------------------------------------------------------------
# Deterministic fallbacks -- used when no model is configured
# ---------------------------------------------------------------------------

"""Build advice from the numbers alone, with no model call.

Keeps the product usable without an API key, and doubles as the safety net if a
model call fails mid-request.
"""
def _fallback_advice(result: QuoteResult) -> Advice {
    if not result.quotes {
        return Advice(
            headline="No options available for this corridor.",
            ai_generated=False
        );
    }

    best = result.quotes[0];
    summary = result.summary;
    cur = summary.send_currency;

    watch_out = "";
    if summary.headline_trap {
        watch_out = f"{summary.headline_fee_provider} advertises the lowest fee but works out "
            + f"{summary.headline_trap_gap} {cur} more expensive once its exchange-rate margin is counted.";
    } else {
        watch_out = f"The priciest option here, {summary.worst_provider}, costs "
            + f"{summary.worst_total_cost} {cur} -- {summary.worst_total_cost_pct}% of what you send.";
    }

    return Advice(
        headline=f"{best.provider} is cheapest: {best.total_cost} {cur} all-in on {best.send_amount} {cur}.",
        provider=best.provider,
        product=best.product_label,
        why=f"You pay a {best.transfer_fee} {cur} fee plus {best.fx_spread_cost} {cur} lost to an "
            + f"exchange-rate margin of {best.fx_margin_pct}%, so {best.receive_amount} "
            + f"{best.receive_currency} reaches the recipient in {best.eta_label}.",
        watch_out=watch_out,
        savings_note=f"That is {summary.savings_vs_worst} {cur} better than the most expensive option "
            + f"on this corridor, and {best.total_cost_pct}% against a {summary.global_average_pct}% global average.",
        ai_generated=False
    );
}


"""Best-effort structured parse without a model: look for codes and a number."""
def _fallback_intent(request: str) -> SendIntent {
    text = request.upper();
    codes: list[str] = [];
    for c in list_countries("send") {
        if c.code in text or c.name.upper() in text {
            codes.append(c.code);
        }
    }
    sends = codes;
    receives: list[str] = [];
    for c in list_countries("receive") {
        if c.code in text or c.name.upper() in text {
            receives.append(c.code);
        }
    }

    amount = 0.0;
    token = "";
    for ch in request {
        if ch.isdigit() or ch == "." {
            token += ch;
        } elif token {
            break;
        }
    }
    if token {
        try {
            amount = float(token);
        } except ValueError {
            amount = 0.0;
        }
    }

    src = sends[0] if sends else "";
    dst = receives[0] if receives else "";
    ok = amount > 0.0 and src != "" and dst != "";
    return SendIntent(
        amount=amount,
        send_country=src,
        receive_country=dst,
        priority="cost",
        understood=ok,
        clarification="" if ok else "Tell me the amount, the country you are sending from, and the country you are sending to."
    );
}


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

"""Turn one plain-English request into a ranked comparison plus a recommendation.

The corridor lookup and all pricing are deterministic; the model only reads the
request and writes the explanation.
"""
def:pub advise(message: str) -> AdviceResult {
    # `by llm` raises provider-specific errors when no model is configured, so
    # every model call is guarded and falls back to the deterministic path.
    intent = SendIntent();
    try {
        intent = parse_intent(message, _country_reference());
    } except Exception {
        intent = _fallback_intent(message);
    }

    if not intent.understood {
        question = intent.clarification;
        if not question {
            question = "Tell me the amount, the country you are sending from, and the country you are sending to.";
        }
        return AdviceResult(
            intent=intent,
            quotes=quote_corridor("", "", 0.0),
            advice=Advice(headline=question, ai_generated=False),
            ok=False,
            message=question
        );
    }

    result = quote_corridor(
        intent.send_country,
        intent.receive_country,
        intent.amount,
        intent.pay_in,
        intent.pay_out
    );
    if not result.ok {
        return AdviceResult(
            intent=intent,
            quotes=result,
            advice=Advice(headline=result.message, ai_generated=False),
            ok=False,
            message=result.message
        );
    }

    context = f"The sender is optimising for {intent.priority}.";
    if intent.pay_out {
        context += f" They specifically need {intent.pay_out} at the other end.";
    }

    advice = Advice();
    try {
        advice = explain(_brief(result, 8), context);
    } except Exception {
        advice = _fallback_advice(result);
    }

    return AdviceResult(intent=intent, quotes=result, advice=advice, ok=True, message="");
}


"""Explain an already-computed comparison, for the results panel.

Takes the same corridor arguments as the comparison endpoint so the client can
ask for a recommendation without re-parsing anything.
"""
def:pub explain_corridor(
    send_country: str,
    receive_country: str,
    amount: float,
    pay_in: str,
    pay_out: str
) -> Advice {
    result = quote_corridor(send_country, receive_country, amount, pay_in, pay_out);
    if not result.ok {
        return Advice(headline=result.message, ai_generated=False);
    }
    try {
        return explain(_brief(result, 8), "The sender is optimising for cost.");
    } except Exception {
        return _fallback_advice(result);
    }
}
