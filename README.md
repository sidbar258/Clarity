# jachacks-fintech

**What does sending money home actually cost?**

International remittances cost 5–10% of the amount sent, and most of that cost is
invisible. Providers advertise the transfer fee and earn quietly on the exchange
rate — quoting you a rate a few percent worse than the mid-market rate and
pocketing the difference. On a $200 transfer to a thin corridor, the "$0 fee"
option can be the most expensive one on the page.

This is a comparison tool that prices every provider on a corridor the way the
World Bank does: **total cost = advertised fee + exchange-rate margin**. It shows
the split, ranks by what you actually pay, and flags the low-fee/high-spread trap.
An AI advisor takes the request in plain English and explains the result — using
only numbers the pricing engine computed.

Built in [Jac](https://www.jaseci.org/) for JacHacks. **~72% Jac** (1,775 of 2,467
lines): the graph model, the pricing engine, the API, the AI agent, and the entire
React UI are all Jac. Python holds the CSV loader; CSS holds the styling.

---

## The idea in one screen

```
Send 200 USD to Mexico

  Wise            Bank account → Bank deposit    ▇▏               1.69 USD   0.85%
  Remitly         Bank account → Bank deposit    ▇▇▇▇▇▇           3.54 USD   1.77%
  Western Union   Bank account → Bank deposit    ▏▇▇▇▇▇▇▇▇▇▇▇     7.70 USD   3.85%
                                                 ↑        ↑
                                          fee ───┘        └─── exchange-rate margin
```

Western Union advertises a **$0 fee** and is the most expensive option shown. That
gap is the product.

## What's in it

| Feature | Where |
|---|---|
| Providers, corridors and products modelled as a graph | `corridors.sv.jac` |
| World-Bank-method cost engine (fee + spread, effective rate, ETA) | `corridors.sv.jac` |
| Graph seeding and corridor queries | `market.sv.jac` |
| REST + RPC API | `endpoints.sv.jac` |
| AI advisor: natural-language intent → grounded recommendation | `advisor.sv.jac` |
| React UI (form, stat tiles, stacked cost bars, advisor panel) | `frontend.cl.jac`, `components/` |
| Reference-data loader | `market_data.py` |
| Pricing tests | `pricing_tests.jac` |

### The graph model

Object-Spatial Programming earns its place here. The market is a graph, and
**every `Serves` edge is one purchasable product**:

```
root ── MarketNode ──┬── ProviderNode (Wise, Western Union, …)
                     └── CorridorNode (US → MX, GB → NG, …)

ProviderNode ─:Serves(pay_in, pay_out, fixed_fee, pct_fee_bps,
                      fx_margin_bps, eta_minutes):─> CorridorNode
```

A provider has several edges into the same corridor — bank→bank, debit→cash
pickup, and so on — each with its own fee and spread. Quoting a corridor is just
reading the edges that land on it:

```jac
for provider in [market -->[?:ProviderNode]] {
    for offer in [edge provider ->:Serves:-> corridor] {
        quotes.append(cost_offer(provider, offer, corridor, amount));
    }
}
```

### The cost model

Fee is deducted first, then the remainder is converted at the provider's rate —
the order every major provider uses:

```
fee            = fixed_fee + amount × pct_fee_bps/10000   (floored at min_fee)
converted      = amount − fee
offered_rate   = mid_market_rate × (1 − fx_margin_bps/10000)
received       = converted × offered_rate

fx_spread_cost = converted × fx_margin_bps/10000     ← the hidden part
total_cost     = fee + fx_spread_cost
total_cost_pct = total_cost / amount × 100
```

`pricing_tests.jac` pins this against hand-computed values, including the case
that matters most — a zero-fee provider losing to an honest one.

### The AI advisor

Two LLM steps wrap a deterministic core:

1. **`parse_intent`** — "I need to send $300 to my mum in Manila for rent"
   → `{amount: 300, send_country: "US", receive_country: "PH", priority: "cost"}`
2. **`explain`** — takes the *already computed* quotes and writes the
   recommendation.

The model chooses and explains; **it never invents a fee or a rate**. Every figure
it can cite is computed by the pricing engine and handed to it as context. That is
deliberate: a tool about hidden costs cannot afford hallucinated numbers.

If no model is configured, both steps fall back to deterministic Jac, so the app
works end to end with no API key.

---

## Running it

```bash
jac start --dev main.jac      # app + API with hot reload
jac test pricing_tests.jac    # 8 pricing tests
jac check .                   # type-check everything
```

### The AI advisor (optional)

Set a key for the provider configured in `jac.toml` under `[byllm.model]`:

```bash
export ANTHROPIC_API_KEY=...        # default: anthropic/claude-opus-5
```

Or switch `default_model` to `gpt-4o-mini` (`OPENAI_API_KEY`), `ollama/llama3`
(local daemon), or a fully local model:

```bash
jac install 'byllm[local]' && jac model pull gemma-4-e4b   # then: local:gemma-4-e4b
```

Without any of these the advisor still answers — from the deterministic fallback.

### API

```bash
# Function RPC — typed objects on the wire
curl -X POST localhost:8001/function/compare -H 'Content-Type: application/json' \
  -d '{"send_country":"US","receive_country":"MX","amount":200,"pay_in":"","pay_out":""}'

# Walker REST
curl -X POST localhost:8001/walker/CompareCorridor -H 'Content-Type: application/json' \
  -d '{"send_country":"US","receive_country":"MX","amount":200}'

# The AI advisor
curl -X POST localhost:8001/function/advise -H 'Content-Type: application/json' \
  -d '{"message":"I want to send $300 from the US to Mexico"}'
```

Swagger is at `/docs`; the live graph visualiser at `/graph`.

---

## Reference data

Pricing lives in `data/` as CSV and is loaded by `market_data.py`. The graph
seeds itself on first query; `POST /function/refresh_data` rebuilds it after an
edit.

| File | Columns |
|---|---|
| `currencies.csv` | `currency,units_per_usd` |
| `countries.csv` | `code,name,currency,flag,role,region,difficulty` |
| `providers.csv` | `slug,name,blurb,network` |
| `offers.csv` | `provider_slug,send_country,receive_country,pay_in,pay_out,fixed_fee,pct_fee_bps,min_fee,fx_margin_bps,eta_minutes` |

`role` is `send`, `receive`, or `both`. `difficulty` scales how wide a spread
providers charge on a corridor (1.0 = dense and competitive; thin corridors run
higher). Fees are in the send currency; `*_bps` columns are basis points
(100 bps = 1%).

> **The pricing data is illustrative sample data**, modelled on the shape of
> published remittance fees. It is **not** a live quote and must not be used to
> choose a provider for a real transfer. The app says so on screen. To make it
> authoritative, point the loader at real provider data or replace the readers in
> `market_data.py` with a pricing API client.

## Accessibility & design notes

The fee/spread palette is validated for contrast and colour-vision separation
against both the light and dark surfaces (worst-pair ΔE 24.7 protan / 33.6 normal
in light mode). The two cost segments always carry a legend, so identity is never
colour-alone, and the numeric breakdown is printed beside every bar.
