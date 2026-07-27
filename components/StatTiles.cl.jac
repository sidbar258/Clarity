"""Headline numbers for the current corridor.

Four figures, in the order a sender actually cares about: what the best option
costs, what choosing it saves, how much of the market's cost is hidden in the
exchange rate, and how this corridor compares to the World Bank benchmark.
"""

sv import from ..corridors { QuoteSummary }


def:pub StatTiles(summary: QuoteSummary) -> JsxElement {
    cur = summary.send_currency;
    beats_average = summary.best_total_cost_pct < summary.global_average_pct;

    return
        <div className="stat-row">
            <div className="stat">
                <div className="stat-label">{"Cheapest all-in"}</div>
                <div className="stat-value">{f"{summary.best_total_cost:.2f} {cur}"}</div>
                <div className="stat-caption">
                    {f"{summary.best_provider} · {summary.best_total_cost_pct:.2f}% of amount sent"}
                </div>
            </div>

            <div className="stat">
                <div className="stat-label">{"You save"}</div>
                <div className="stat-value is-good">
                    {f"{summary.savings_vs_worst:.2f} {cur}"}
                </div>
                <div className="stat-caption">
                    {f"vs {summary.worst_provider} at {summary.worst_total_cost:.2f} {cur}"}
                </div>
            </div>

            <div className="stat">
                <div className="stat-label">{"Hidden in the rate"}</div>
                <div className="stat-value">{f"{summary.avg_hidden_share:.0f}%"}</div>
                <div className="stat-caption">
                    {"Average share of total cost that is exchange-rate margin, not fee"}
                </div>
            </div>

            <div className="stat">
                <div className="stat-label">{"vs global average"}</div>
                <div className="stat-value">{f"{summary.global_average_pct:.1f}%"}</div>
                <div className="stat-caption">
                    {f"Best option here is {summary.best_total_cost_pct:.2f}%"
                        + (" — below average" if beats_average else " — above average")
                        + f". UN target is {summary.sdg_target_pct:.0f}%."}
                </div>
            </div>
        </div>;
}
