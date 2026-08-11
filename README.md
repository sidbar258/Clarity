## The idea in one screen

```
Send 200 USD to Mexico

Wise            Bank account → Bank deposit   ▇▏             1.69 USD   0.85%
Remitly         Bank account → Bank deposit   ▇▇▇▇▇▇         3.54 USD   1.77%
Western Union   Bank account → Bank deposit   ▏▇▇▇▇▇▇▇▇▇▇▇   7.70 USD   3.85%
                                              ↑      ↑
                                       fee ───┘      └─── exchange-rate margin
```

Western Union advertises a **$0 fee** and is the most expensive option shown. That gap is the product.

[![Clarity](https://github.com/user-attachments/assets/7202e2b5-f627-422a-9f30-50434ce7bf86)](https://www.youtube.com/watch?v=N_5Vo4DbBEQ)

## What's in it

| Feature | Where |
|---|---|
| Providers, corridors and products modelled as a graph | `corridors.sv.jac` |
| World-Bank-method cost engine (fee + spread, effective rate, ETA) | `corridors.sv.jac` |
| Graph seeding and corridor queries | `market.sv.jac` |
| REST + RPC API | `endpoints.sv.jac` |
| AI advisor: natural-language intent → grounded recommendation | `advisor.sv.jac` |
| React UI (form, status tiles, stacked cost bars, advisor panel) | `frontend.cl.jac`, `components/` |
| Reference-data loader | `market_data.py` |
| Pricing tests | `pricing_tests.jac` |

## What it does
Clarity compares remittance providers side-by-side for any amount, currency corridor, and payment method. Instead of just showing an advertised "fee," it breaks down the 
true total cost — the fee and the hidden exchange-rate spread — so users can see exactly where their money goes. An AI agent takes the user's request, reasons over the 
tradeoffs (cheapest vs. fastest), and gives a clear recommendation with an explanation, not just a raw list of numbers.

<img width="831" height="887" alt="image" src="https://github.com/user-attachments/assets/324328c2-d377-4baa-ad42-de9e448f0387" /><br><br><br>
<img width="1080" height="624" alt="image" src="https://github.com/user-attachments/assets/218e889e-067d-4518-80f0-e9cf74bbcf8a" /><br><br><br>
<img width="1030" height="103" alt="image" src="https://github.com/user-attachments/assets/ac39e1a4-fc1c-4468-9777-70afe9790915" /><br><br><br>
<img width="1081" height="301" alt="image" src="https://github.com/user-attachments/assets/c907b731-1868-4e5d-8542-d46329514936" /><br><br><br>
<img width="1710" height="1074" alt="image" src="https://github.com/user-attachments/assets/0e2627a5-87dd-4b52-9aa6-2408a3377222" /><br><br><br>
<img width="184" height="116" alt="image" src="https://github.com/user-attachments/assets/8ddfa075-72df-458d-b59f-417fe811feec" /><br><br><br>
<img width="831" height="694" alt="image" src="https://github.com/user-attachments/assets/6bef1cde-92eb-48b6-9e82-6e2ac9d7021b" /><br><br><br>
<img width="1710" height="982" alt="image" src="https://github.com/user-attachments/assets/6c85d78c-f1cf-47c3-891f-0185f5f22971" />

## The cost model

Fee is deducted first, then the remainder is converted at the provider's rate — the order every major provider uses:

```
fee            = fixed_fee + amount × pct_fee_bps/10000 (floored at min_fee)
converted      = amount − fee
offered_rate   = mid_market_rate × (1 − fx_margin_bps/10000)
received       = converted × offered_rate
fx_spread_cost = converted × fx_margin_bps/10000 ← the hidden part
total_cost     = fee + fx_spread_cost
total_cost_pct = total_cost / amount × 100
```

`pricing_tests.jac` pins this against hand-computed values, including the case that matters most — a zero-fee provider losing to an honest one.

## How we built it
We used Jac to create the API, graph model, pricing logic, React UI, AI assistant, and website tests; Python to load CSV reference data; CSS for style. First, the website 
loads CSV reference data into memory with Python's assistance. Then, it seeds a Jac graph of providers, corridors, and offer edges containing distinct payment methods to 
create a model of all the data. Later, the website converts the starting currency and destination currency selected on the front page into a corridor and stores the user's 
preferred payment and receipt method too. If the AI assistant is used instead, it deconstructs the prompt into a corridor and preferred payment and receipt methods too. 
Finally, the input is packaged into a corridor query and the cheapest providers are ranked. This ranking is output on the results page with each provider's official fee 
and their hidden markup too.

## The AI advisor

The model chooses and explains; **it never invents a fee or a rate**. Every figure it can cite is computed by the pricing engine and handed to it as context. That is 
deliberate: a tool about hidden costs cannot afford hallucinated numbers. If no model is configured the app falls back to Jac, allowing it to run end-to-end with no API 
key needed.

(Optional) Set a key for the provider configured in `jac.toml` under `[byllm.model]`:

```bash
export (ANTHROPIC_API_KEY/OPENAI_API_KEY/etc.) =...
default_model=...
```

For local model:
```bash
jac install 'byllm[local]' && jac model pull gemma-4-e4b
default_model=local:gemma-4-e4b
```

## Challenges we ran into
Real-time provider fee/rate data isn't publicly accessible via free APIs, so we had to design a realistic synthetic dataset that reflects genuine market patterns instead. 
We also had to balance the agent's response — deciding how much reasoning/comparison data to surface without overwhelming the user, while still keeping the recommendation 
transparent and trustworthy rather than a "just trust me" black box.

## Accomplishments that we're proud of
We are proud of building a graph-based model connecting providers, corridors, and payment/receipt methods in Jac despite neither of us having used this language before. We 
are also proud that our website is **72% Jac**, showcasing our ability to condense multiple programming languages into one language. Finally, we are proud of building a 
grounded AI assistant by connecting it to our graph inside of Jac.

## What we learned
Siddharth and I learned how to model a real-world market as a graph, and use it to build a grounded AI assistant from scratch; producing deterministic responses. We also 
learned how to obtain trust from our users by highlighting the providers' spreads. Finally, we learned how to ramp-up quickly on a new programming language such as Jac.

## API

Go to /docs.

## Running it

```bash
git clone git@github.com:sidbar258/jachacks-fintech.git
cd jachacks-fintech
curl -fSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash -s -- --version 0.34.5
jac start main.jac
jac test pricing_tests.jac (optional command)
jac check .                (optional command)
```

## Accessibility & design notes

The fee/spread palette is validated for contrast and color-vision separation against both the light and dark surfaces (worst-pair ΔE 24.7 protan / 33.6 normal
in light mode). The two cost segments always carry a legend, so identity is never color-alone, and the numeric breakdown is printed beside every bar as well.

## What's next for Clarity
Next, we’d integrate live provider APIs like Wise, Remitly, and Western Union to replace our synthetic dataset with real-time data. We’d also expand our rate-watching 
feature so the agent can monitor exchange rates over a flexible time window and proactively recommend the best time to send, not just the best provider right now. Longer 
term, we plan to improve the product with saved preferences, account creation, and theme customization to make it more personalized and easier to use over time.

## Reference data

`difficulty` scales how wide a spread providers charge on a corridor (1.0 = dense and competitive; thin corridors run higher). Fees are in the send currency; `*_bps` 
columns are basis points (100 bps = 1 percent).

Built for [JacHacks SF 2026](https://jachacks-sf.devpost.com/project-gallery).
