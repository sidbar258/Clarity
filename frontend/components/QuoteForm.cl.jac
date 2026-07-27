"""The corridor input: amount, countries, and how the money moves.

The five inputs travel as one `CorridorForm` value and report back through a
single typed `onField` callback, so the shell owns the state without this
component growing a prop per input.
"""

sv import from ..corridors { CountryInfo }


# Typed-base (`: str`) on purpose. A bodyless `enum { AMOUNT, SEND, ... }`
# compiles to `{AMOUNT: null, SEND: null, ...}` on the client, so every
# `field == FormField.X` comparison in the shell is `null == null` and the first
# branch swallows every input. Giving each member a distinct string value keeps
# the discriminator intact across the prop boundary.
enum:pub FormField: str {
    AMOUNT = "amount",
    SEND = "send",
    RECEIVE = "receive",
    PAY_IN = "pay_in",
    PAY_OUT = "pay_out"
}


obj:pub CorridorForm {
    has amount_text: str,
        send_country: str,
        receive_country: str,
        pay_in: str,
        pay_out: str;
}


glob PAY_IN_CHOICES: list[dict] = [
    {"value": "", "label": "Any"},
    {"value": "bank_account", "label": "Bank account"},
    {"value": "debit_card", "label": "Debit card"},
    {"value": "credit_card", "label": "Credit card"}
];

glob PAY_OUT_CHOICES: list[dict] = [
    {"value": "", "label": "Any"},
    {"value": "bank_deposit", "label": "Bank deposit"},
    {"value": "cash_pickup", "label": "Cash pickup"},
    {"value": "mobile_wallet", "label": "Mobile wallet"}
];


def:pub QuoteForm(
    form: CorridorForm,
    send_options: list[CountryInfo],
    receive_options: list[CountryInfo],
    busy: bool,
    onField: Callable[[FormField, str], None],
    onSubmit: Callable[[], None]
) -> JsxElement {
    def handle_submit(e: FormEvent) {
        e.preventDefault();
        onSubmit();
    }

    return
        <form className="card" onSubmit={handle_submit}>
            <h2>{"What are you sending?"}</h2>
            <div className="form-grid">
                <div className="field">
                    <label htmlFor="amount">{"Amount"}</label>
                    <input
                        id="amount"
                        type="text"
                        inputMode="decimal"
                        value={form.amount_text}
                        onChange={lambda (e: ChangeEvent) {
                            onField(FormField.AMOUNT, e.target.value);
                        }}
                    />
                </div>

                <div className="field">
                    <label htmlFor="from">{"From"}</label>
                    <select
                        id="from"
                        value={form.send_country}
                        onChange={lambda (e: ChangeEvent) {
                            onField(FormField.SEND, e.target.value);
                        }}
                    >
                        {for c in send_options {
                            <option key={c.code} value={c.code}>
                                {f"{c.flag} {c.name} ({c.currency})"}
                            </option>
                        }}
                    </select>
                </div>

                <div className="field">
                    <label htmlFor="to">{"To"}</label>
                    <select
                        id="to"
                        value={form.receive_country}
                        onChange={lambda (e: ChangeEvent) {
                            onField(FormField.RECEIVE, e.target.value);
                        }}
                    >
                        {for c in receive_options {
                            <option key={c.code} value={c.code}>
                                {f"{c.flag} {c.name} ({c.currency})"}
                            </option>
                        }}
                    </select>
                </div>

                <div className="field">
                    <label htmlFor="payin">{"Pay with"}</label>
                    <select
                        id="payin"
                        value={form.pay_in}
                        onChange={lambda (e: ChangeEvent) {
                            onField(FormField.PAY_IN, e.target.value);
                        }}
                    >
                        {for choice in PAY_IN_CHOICES {
                            <option key={choice["value"]} value={choice["value"]}>
                                {choice["label"]}
                            </option>
                        }}
                    </select>
                </div>

                <div className="field">
                    <label htmlFor="payout">{"They collect via"}</label>
                    <select
                        id="payout"
                        value={form.pay_out}
                        onChange={lambda (e: ChangeEvent) {
                            onField(FormField.PAY_OUT, e.target.value);
                        }}
                    >
                        {for choice in PAY_OUT_CHOICES {
                            <option key={choice["value"]} value={choice["value"]}>
                                {choice["label"]}
                            </option>
                        }}
                    </select>
                </div>

                <div className="field">
                    <button className="btn" type="submit" disabled={busy}>
                        {"Comparing..." if busy else "Compare providers"}
                    </button>
                </div>
            </div>
        </form>;
}
