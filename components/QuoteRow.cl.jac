"""One costed provider option in the comparison list."""

import from .CostBar { CostBar }

sv import from ..corridors { Quote }


def:pub QuoteRow(
    quote: Quote,
    scale: float,
    is_best: bool,
    is_trap: bool
) -> JsxElement {
    return
        <div className={"quote is-best" if is_best else "quote"}>
            <div className="quote-provider">
                <div className="quote-name">
                    {quote.provider}
                    {if is_best {
                        <span className="badge is-best">{"Cheapest"}</span>
                    }}
                    {if is_trap {
                        <span className="badge is-trap">{"Low fee, high spread"}</span>
                    }}
                </div>
                <div className="quote-product">{quote.product_label}</div>
            </div>

            <div className="quote-bar">
                <CostBar fee={quote.transfer_fee} spread={quote.fx_spread_cost} {scale} />
                <div className="quote-breakdown">
                    <span>{f"Fee {quote.transfer_fee:.2f}"}</span>
                    <span>
                        {f"Spread {quote.fx_spread_cost:.2f} ({quote.fx_margin_pct:.2f}%)"}
                    </span>
                    <span>{quote.eta_label}</span>
                </div>
            </div>

            <div className="quote-totals">
                <div className="quote-total">
                    {f"{quote.total_cost:.2f} {quote.send_currency}"}
                </div>
                <div className="quote-sub">{f"{quote.total_cost_pct:.2f}% total cost"}</div>
                <div className="quote-sub">
                    {f"{quote.receive_amount:,.2f} {quote.receive_currency} arrives"}
                </div>
            </div>
        </div>;
}
