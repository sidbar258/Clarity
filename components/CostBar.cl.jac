"""The stacked cost bar -- the chart at the heart of this product.

Two segments, drawn to a scale shared across every row so bars are comparable:
the fee a provider advertises, then the exchange-rate margin it does not. A 2px
surface gap separates them, so the split reads without a stroke around either.
"""

def:pub CostBar(fee: float, spread: float, scale: float) -> JsxElement {
    span = scale if scale > 0.0 else 1.0;
    fee_pct = fee / span * 100.0;
    spread_pct = spread / span * 100.0;

    return
        <div className="costbar">
            {if fee_pct > 0.0 {
                <div
                    className="costbar-seg costbar-fee"
                    style={{"width": f"{fee_pct:.4f}%"}}
                />
            }}
            {if spread_pct > 0.0 {
                <div
                    className="costbar-seg costbar-spread"
                    style={{"width": f"{spread_pct:.4f}%"}}
                />
            }}
        </div>;
}


"""Identity for the two cost segments. Present whenever the bars are."""
def:pub CostLegend -> JsxElement {
    return
        <div className="legend">
            <span className="legend-item">
                <span className="legend-key is-fee" />
                {"Advertised transfer fee"}
            </span>
            <span className="legend-item">
                <span className="legend-key is-spread" />
                {"Exchange-rate margin (usually not advertised)"}
            </span>
        </div>;
}
