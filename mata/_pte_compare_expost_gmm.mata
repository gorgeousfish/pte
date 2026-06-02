*! _pte_compare_expost_gmm.mata
*! Ex-post ACF GMM estimator (no interaction terms, full sample)
*! US-E7-008: Method I - Exogenous productivity process
*!
*! Theory: Equation (19) - omega = rho0 + rho1*omega_lag + rho2*omega_lag^2 + rho3*omega_lag^3 + eps
*! Key difference from CLK: NO interaction terms, NO transition period exclusion
*! Reference: DOs/prodest_acf_trlg_exog.do

version 14.0

mata:
mata set matastrict on

// =========================================================================
// GMM objective function for Ex-post ACF estimation
// Identical to CLK GMM but with 4-column OMEGA_lag_pol (no interaction terms)
// =========================================================================
void _pte_gmm_expost(todo, betas, crit, g, H)
{
    real matrix PHI, PHI_LAG, Z, W, X, X_lag, C
    real matrix OMEGA, OMEGA_lag, OMEGA2_lag, OMEGA3_lag
    real matrix OMEGA_lag_pol, g_b, XI

    // Read data from Stata
    PHI     = st_data(., "phi")
    PHI_LAG = st_data(., "phi_lag")
    Z       = st_data(., ("const", "lnl_lag", "lnk", "l2_lag", "k2", "kl_lag", "t"))
    X       = st_data(., ("lnl", "lnk", "l2", "k2", "l1k1"))
    X_lag   = st_data(., ("lnl_lag", "lnk_lag", "l2_lag", "k2_lag", "l1k1_lag"))
    C       = st_data(., "const")

    // Weight matrix
    W = invsym(Z'Z) / rows(Z)

    // Compute omega and lagged omega
    OMEGA     = PHI - X * betas'
    OMEGA_lag = PHI_LAG - X_lag * betas'

    // Evolution polynomial: 4 columns (NO interaction terms)
    // This is the KEY difference from CLK which has 8 columns
    OMEGA2_lag = OMEGA_lag :* OMEGA_lag
    OMEGA3_lag = OMEGA2_lag :* OMEGA_lag
    OMEGA_lag_pol = (C, OMEGA_lag, OMEGA2_lag, OMEGA3_lag)

    // Concentrated-out: estimate evolution params via OLS
    g_b = invsym(OMEGA_lag_pol' * OMEGA_lag_pol) * OMEGA_lag_pol' * OMEGA

    // Innovation
    XI = OMEGA - OMEGA_lag_pol * g_b

    // GMM criterion
    crit = (Z'XI)' * W * (Z'XI)
}

// =========================================================================
// Model runner: initialize optimizer and run
// =========================================================================
void _pte_model_expost()
{
    real scalar S, fval
    real matrix p, beta_ols

    // Get OLS initial values from Stata
    beta_ols = st_matrix("e(b)")[1, 1..5]

    // Configure optimizer
    S = optimize_init()
    optimize_init_evaluator(S, &_pte_gmm_expost())
    optimize_init_evaluatortype(S, "d0")
    optimize_init_technique(S, "nm")
    optimize_init_conv_maxiter(S, 10000)
    optimize_init_conv_nrtol(S, 1e-6)
    optimize_init_nmsimplexdeltas(S, 0.00001)
    optimize_init_which(S, "min")
    optimize_init_params(S, beta_ols)

    // Run optimization
    p = optimize(S)
    fval = optimize_result_value(S)

    // Store results back to Stata
    st_matrix("_pte_beta_expost", p)
    st_numscalar("_pte_fval_expost", fval)
}

end
