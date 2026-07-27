"""jachacks-fintech - Entry Point.

Registers the server API and mounts the client UI.

The plain (non-`sv`) imports below run in-process and publish the endpoints at
`/function/<name>` and `/walker/<name>`. The client's own `sv import` statements
live in `frontend.cl.jac`, not here -- an `sv import` inside this module's `cl`
block would not register anything.
"""

import from endpoints { compare, corridors, countries, refresh_data, CompareCorridor }
import from advisor { advise, explain_corridor }

# Client-side UI
cl {
    import ".styles.global.css";

    import from .frontend { app as ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
