*! version 1.0.0  20Feb2026
*! Mata patch for endopolyprodest compatibility
*! Fixes two bugs in DOs/treatpolyprodest.ado:
*!   1. opt_mata(): lowercase 's' typo → should be uppercase 'S'
*!      (line ~893: optimize_init_argument(s, 9, TR) → optimize_init_argument(S, 9, TR))
*!   2. facf3(): missing TR parameter (facf1/facf2 have it, facf3 doesn't)
*!      This causes argument count mismatch when opt_mata sets 9 arguments
*!
*! MUST be loaded AFTER: endoprodest.do, endopolyprodest.do, treatpolyprodest.ado
*! These patches overwrite the Mata functions defined in those files.

// Drop existing definitions before redefining
capture mata mata drop opt_mata()
capture mata mata drop facf3()

mata:

/*---------------------------------------------------------------------*/
// Patched facf3: added TR parameter to match facf1/facf2 signatures
// Original facf3 in treatpolyprodest.ado is missing TR parameter,
// causing argument count mismatch with opt_mata which sets 9 arguments.
/*---------------------------------------------------------------------*/

void facf3(todo, betas, X, lX, PHI, LPHI, RES, Z, PR_HAT, ENDO, TR, crit, g, H)
{
    real matrix W, OMEGA, OMEGA_lag, OMEGA_lag2, OMEGA_lag3
    real matrix PR_HAT2, PR_HAT3, OMEGA_lag_pol, g_b, XI

    W = invsym(Z'Z) / (rows(Z))
    OMEGA = PHI - X * betas'
    OMEGA_lag = LPHI - lX * betas'
    OMEGA_lag2 = OMEGA_lag :* OMEGA_lag
    OMEGA_lag3 = OMEGA_lag2 :* OMEGA_lag
    /* IF clause to check whether we have the "exit" variable */
    if (!missing(PR_HAT)) {
        PR_HAT2 = PR_HAT :* PR_HAT
        PR_HAT3 = PR_HAT2 :* PR_HAT
        OMEGA_lag_pol = (J(rows(PHI), 1, 1), OMEGA_lag, OMEGA_lag2, OMEGA_lag3, ///
            PR_HAT, PR_HAT2, PR_HAT3, ///
            PR_HAT :* OMEGA_lag, PR_HAT2 :* OMEGA_lag, PR_HAT :* OMEGA_lag2, ENDO)
    }
    else {
        OMEGA_lag_pol = (J(rows(PHI), 1, 1), OMEGA_lag, OMEGA_lag2, OMEGA_lag3, ///
            OMEGA_lag :* ENDO, OMEGA_lag2 :* ENDO, OMEGA_lag3 :* ENDO, ///
            OMEGA_lag :* TR, OMEGA_lag2 :* TR, OMEGA_lag3 :* TR, ENDO, TR)
    }
    g_b = invsym(OMEGA_lag_pol' OMEGA_lag_pol) * OMEGA_lag_pol' OMEGA
    XI = OMEGA - OMEGA_lag_pol * g_b
    crit = (Z'XI)' * W * (Z'XI)
}

/*---------------------------------------------------------------------*/
// Patched opt_mata: fixed lowercase 's' → uppercase 'S' on argument 9
// Original line: optimize_init_argument(s, 9, TR)
// Fixed line:    optimize_init_argument(S, 9, TR)
/*---------------------------------------------------------------------*/

void opt_mata(init, f, opt, phi, lphi, tolag, lagged, touse, maxiter, tol, eval, ///
    | Pr_hat, res, instr, endogenous, treat)
{
    transmorphic scalar S
    real matrix RES, PHI, LPHI, Z, X, lX, PR_HAT, ENDO, TR, p

    st_view(RES=., ., st_tsrevar(tokens(res)), touse)
    st_view(PHI=., ., st_tsrevar(tokens(phi)), touse)
    st_view(LPHI=., ., st_tsrevar(tokens(lphi)), touse)
    st_view(Z=., ., st_tsrevar(tokens(instr)), touse)
    st_view(X=., ., st_tsrevar(tokens(tolag)), touse)
    st_view(lX=., ., st_tsrevar(tokens(lagged)), touse)
    st_view(PR_HAT=., ., st_tsrevar(tokens(Pr_hat)), touse)
    st_view(ENDO=., ., st_tsrevar(tokens(endogenous)), touse)
    st_view(TR=., ., st_tsrevar(tokens(treat)), touse)
    S = optimize_init()
    optimize_init_argument(S, 1, X)
    optimize_init_argument(S, 2, lX)
    optimize_init_argument(S, 3, PHI)
    optimize_init_argument(S, 4, LPHI)
    optimize_init_argument(S, 5, RES)
    optimize_init_argument(S, 6, Z)
    optimize_init_argument(S, 7, PR_HAT)
    optimize_init_argument(S, 8, ENDO)
    optimize_init_argument(S, 9, TR)
    optimize_init_evaluator(S, f)
    optimize_init_evaluatortype(S, eval)
    optimize_init_conv_maxiter(S, maxiter)
    optimize_init_conv_nrtol(S, tol)
    optimize_init_technique(S, opt)
    optimize_init_nmsimplexdeltas(S, 0.00001)
    optimize_init_which(S, "min")
    optimize_init_params(S, init')
    p = optimize(S)
    st_matrix("r(betas)", p)
}

/*---------------------------------------------------------------------*/

end
