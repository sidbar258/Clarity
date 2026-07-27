"""Handler bodies for the application shell.

Every server call is awaited: the `sv import` stubs are async, and assigning one
without `await` stores a promise instead of the data.
"""

impl app.loadOptions -> None {
    send_options = await countries("send");
    receive_options = await countries("receive");
    await runCompare();
}


impl app.runCompare -> None {
    error_text = "";

    # The server takes a float; the input is text, so parse and validate here.
    amount: float = 0.0;
    try {
        amount = float(amount_text.strip());
    } except ValueError {
        error_text = "Enter the amount as a number, for example 200.";
        return;
    }
    if amount <= 0.0 {
        error_text = "Enter an amount greater than zero.";
        return;
    }

    busy = True;
    try {
        # Positional, and the local names must match the server parameters.
        result = await compare(send_country, receive_country, amount, pay_in, pay_out);
        advice = None;
    } except Exception {
        error_text = "Could not reach the pricing service. Try again.";
    }
    busy = False;
}


impl app.askAdvisor -> None {
    error_text = "";
    advising = True;

    try {
        if prompt_text.strip() {
            message: str = prompt_text.strip();
            answer: AdviceResult = await advise(message);
            advice = answer.advice;
            if answer.ok {
                # The agent resolved a corridor -- move the form to match it, so
                # the table below the advice is the one it just reasoned about.
                send_country = answer.intent.send_country;
                receive_country = answer.intent.receive_country;
                amount_text = f"{answer.intent.amount:.0f}";
                pay_in = answer.intent.pay_in;
                pay_out = answer.intent.pay_out;
                result = answer.quotes;
            }
        } else {
            # Nothing typed: explain the comparison already on screen.
            fallback_amount: float = 0.0;
            try {
                fallback_amount = float(amount_text.strip());
            } except ValueError {
                fallback_amount = 0.0;
            }
            if fallback_amount > 0.0 {
                amount: float = fallback_amount;
                advice = await explain_corridor(
                    send_country, receive_country, amount, pay_in, pay_out
                );
            } else {
                error_text = "Enter an amount, or describe the transfer in words.";
            }
        }
    } except Exception {
        error_text = "The advisor is unavailable right now.";
    }

    advising = False;
}
