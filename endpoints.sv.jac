"""Public API for the remittance comparison service.

Two shapes are exposed on purpose:

* **Function endpoints** (`def:pub`) -- what the browser client calls. Typed
  objects cross the wire, so the UI gets real `Quote` instances back rather than
  untyped dicts.
* **A walker endpoint** (`walker:pub`) -- the same comparison over plain REST,
  for anyone driving the service with `curl` or from another language.

Everything here is `:pub`: comparing remittance prices needs no account.
"""

import from corridors { QuoteResult, CorridorInfo, CountryInfo }
import from market { quote_corridor, list_corridors, list_countries, reload_market }


"""Compare every provider on one corridor, ranked by true total cost.

`pay_in` and `pay_out` are optional filters -- pass "" to see every product.
"""
def:pub compare(
    send_country: str,
    receive_country: str,
    amount: float,
    pay_in: str,
    pay_out: str
) -> QuoteResult {
    return quote_corridor(send_country, receive_country, amount, pay_in, pay_out);
}


"""Every send/receive pair the dataset covers."""
def:pub corridors -> list[CorridorInfo] {
    return list_corridors();
}


"""Countries available for the form. `role` is "send" or "receive"."""
def:pub countries(role: str) -> list[CountryInfo] {
    return list_countries(role);
}


"""Rebuild the market graph from the CSVs. Returns the offer count."""
def:pub refresh_data -> int {
    return reload_market();
}


walker:pub CompareCorridor {
    """REST comparison endpoint.

    POST /walker/CompareCorridor
      {"send_country": "US", "receive_country": "MX", "amount": 200}
    """

    has send_country: str,
        receive_country: str,
        amount: float,
        pay_in: str = "",
        pay_out: str = "",
        reports: list[QuoteResult] = [];

    can run with Root entry {
        report quote_corridor(
            self.send_country,
            self.receive_country,
            self.amount,
            self.pay_in,
            self.pay_out
        );
    }
}
