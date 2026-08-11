"""The AI advisor panel.

Takes a request in plain English, and renders the recommendation the agent wrote from the computed quotes. The `ai_generated` flag drives the footer note so it is always 
clear whether a model or the deterministic fallback produced the text.
"""

sv import from ..advisor { Advice }

def:pub AdvisorPanel(
    prompt_text: str,
    busy: bool,
    advice: Advice | None,
    onPrompt: Callable[[str], None],
    onAsk: Callable[[], None]
) -> JsxElement {
    def handle_submit(e: FormEvent) {
        e.preventDefault();
        onAsk();
    }

    return
        <section className="card">
            <h2>{"Ask the advisor"}</h2>
            <p className="section-note">
                {"Describe the transfer in your own words. The agent works out the corridor, "
                    + "prices every provider from the data, and explains which one to use."}
            </p>

            <form className="advisor-input" onSubmit={handle_submit}>
                <input
                    type="text"
                    value={prompt_text}
                    placeholder="I need to send $300 from US to my mum in the Philippines for rent"
                    onChange={lambda (e: ChangeEvent) { onPrompt(e.target.value); }}
                />
                <button className="btn" type="submit" disabled={busy}>
                    {"Thinking..." if busy else "Ask"}
                </button>
            </form>

            {if advice is not None {
                <div className="advice">
                    <div className="advice-headline">{advice.headline}</div>
                    {if advice.why {
                        <p>{advice.why}</p>
                    }}
                    {if advice.watch_out {
                        <p>{"Watch out: " + advice.watch_out}</p>
                    }}
                    {if advice.savings_note {
                        <p>{advice.savings_note}</p>
                    }}
                    <div className="advice-tag">
                        {"Written by the AI advisor from the computed quotes"
                            if advice.ai_generated
                            else "No model configured — deterministic summary from the same figures"}
                    </div>
                </div>
            }}
        </section>;
}
