"""The application shell.

One stateful component owns the corridor query and the results; the sections
below it are presentational and take everything as props. Handler bodies live in
`frontend.impl.jac`.
"""

import from .components.QuoteForm { QuoteForm, CorridorForm, FormField }
import from .components.StatTiles { StatTiles }
import from .components.QuoteRow { QuoteRow }
import from .components.CostBar { CostLegend }
import from .components.AdvisorPanel { AdvisorPanel }

sv import from .corridors { Quote, QuoteResult, CountryInfo }
sv import from .endpoints { compare, countries }
sv import from .advisor { Advice, AdviceResult, advise, explain_corridor }


def:pub app -> JsxElement {
    has amount_text: str = "200",
        send_country: str = "US",
        receive_country: str = "MX",
        pay_in: str = "",
        pay_out: str = "",
        prompt_text: str = "",
        send_options: list[CountryInfo] = [],
        receive_options: list[CountryInfo] = [],
        result: QuoteResult | None = None,
        advice: Advice | None = None,
        busy: bool = False,
        advising: bool = False,
        error_text: str = "";

    async can with entry {
        loadOptions();
    }

    async def loadOptions -> None;
    async def runCompare -> None;
    async def askAdvisor -> None;

    def setField(field: FormField, value: str) {
        if field == FormField.AMOUNT {
            amount_text = value;
        } elif field == FormField.SEND {
            send_country = value;
        } elif field == FormField.RECEIVE {
            receive_country = value;
        } elif field == FormField.PAY_IN {
            pay_in = value;
        } elif field == FormField.PAY_OUT {
            pay_out = value;
        }
    }

    def setPrompt(v: str) { prompt_text = v; }

    # Derived every render -- never `has`, or they drift from the data.
    form: CorridorForm = CorridorForm(
        amount_text=amount_text,
        send_country=send_country,
        receive_country=receive_country,
        pay_in=pay_in,
        pay_out=pay_out
    );
    quotes: list[Quote] = result.quotes if result is not None else [];
    scale: float = 0.0;
    for q in quotes {
        if q.total_cost > scale {
            scale = q.total_cost;
        }
    }
    trap_provider: str = "";
    if result is not None and result.summary.headline_trap {
        trap_provider = result.summary.headline_fee_provider;
    }

    return
        <main className="shell">
            <header className="masthead">
                <h1>{"What does sending money home actually cost?"}</h1>
                <p>
                    {"Remittance providers advertise the fee and earn on the exchange rate. "
                        + "This compares every provider on a corridor by total cost — fee plus "
                        + "the margin they add to the mid-market rate."}
                </p>
            </header>

            <QuoteForm
                {form}
                {send_options}
                {receive_options}
                busy={busy}
                onField={setField}
                onSubmit={runCompare}
            />

            {if error_text {
                <div className="notice is-error">{error_text}</div>
            }}

            {if result is not None and result.ok and len(quotes) > 0 {
                <StatTiles summary={result.summary} />
                <section className="card">
                    <h2>{"Every option, cheapest all-in first"}</h2>
                    <CostLegend />
                    <div className="results">
                        {for (idx, q) in enumerate(quotes) {
                            <QuoteRow
                                key={str(idx)}
                                quote={q}
                                {scale}
                                is_best={idx == 0}
                                is_trap={q.provider == trap_provider and idx != 0}
                            />
                        }}
                    </div>
                </section>
            }}

            {if result is not None and not result.ok {
                <div className="notice">{result.message}</div>
            }}

            <AdvisorPanel
                {prompt_text}
                busy={advising}
                advice={advice}
                onPrompt={setPrompt}
                onAsk={askAdvisor}
            />

            <p className="disclaimer">
                {"Pricing here is illustrative sample data modelled on the shape of published "
                    + "remittance fees — it is not a live quote and should not be used to choose "
                    + "a provider for a real transfer. Total cost follows the World Bank "
                    + "Remittance Prices Worldwide method: the advertised fee plus the margin "
                    + "over the mid-market exchange rate."}
            </p>
        </main>;
}
