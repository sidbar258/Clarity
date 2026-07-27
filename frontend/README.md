# Frontend files (copies)

Every client-side file in the project, collected in one place for reading.

**These are copies. The app does not run from here.** `main.jac` mounts
`../frontend.cl.jac`, so editing anything in this folder changes nothing —
edit the original alongside it and re-copy if you want this view refreshed.

| Here | Original |
|---|---|
| `frontend.cl.jac` | `../frontend.cl.jac` |
| `frontend.impl.jac` | `../frontend.impl.jac` |
| `components/*.cl.jac` | `../components/*.cl.jac` |
| `styles/global.css` | `../styles/global.css` |

588 lines of client Jac + 483 of CSS = 1,071 lines, ~43% of the codebase.

`.cl.jac` is a client module (compiles to React), `.impl.jac` holds handler
bodies for the declarations in `frontend.cl.jac`.
