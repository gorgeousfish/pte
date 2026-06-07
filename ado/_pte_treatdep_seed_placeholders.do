*! version 1.0.0  01apr2026
*! Seed no-op Mata placeholders so uncaptured mata drop statements can source-load.

mata:
void facf1(todo, betas, X, lX, PHI, LPHI, RES, Z, PR_HAT, ENDO, TR, crit, g, H) {}
void facf2(todo, betas, X, lX, PHI, LPHI, RES, Z, PR_HAT, ENDO, TR, crit, g, H) {}
void facf3(todo, betas, X, lX, PHI, LPHI, RES, Z, PR_HAT, ENDO, TR, crit, g, H) {}
void opt_mata(init, f, opt, phi, lphi, tolag, lagged, touse, maxiter, tol, eval, | Pr_hat, res, instr, endogenous, treat) {}
end
