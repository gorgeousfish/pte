*! _pte_compare_endog_gmm.mata
*! Endogenous productivity GMM estimator (WITH interaction terms, full sample)
*! US-E7-009: Method II - Endogenous productivity process
*!
*! Theory: Equation (14) - omega = rho0 + sum_j(rho_j*omega_lag^j) + sum_j(gamma_j*omega_lag^j*D_lag) + delta*D_lag + eps
*! Key difference from Expost: HAS interaction terms with treatment
*! Key difference from CLK: Does NOT exclude transition period
*! Reference: DOs/prodest_acf_trlg_endog.do

version 14.0

mata:
mata set matastrict on

// =========================================================================
// GMM objective function for Endogenous ACF estimation
// Includes treatment interaction terms in OMEGA_lag_pol
// Supports omegapoly = 1..4 via Stata scalar _pte_omegapoly_endog
//   omegapoly=1:  4 cols = (C, OMEGA_lag, OMEGA_TP_lag, TP_lag)
//   omegapoly=2:  6 cols = + OMEGA2_lag, OMEGA2_TP_lag
//   omegapoly=3:  8 cols = + OMEGA3_lag, OMEGA3_TP_lag  [default]
//   omegapoly=4: 10 cols = + OMEGA4_lag, OMEGA4_TP_lag
// Does NOT exclude transition period observations
// Reference: DOs/prodest_acf_trlg_endog.do L54-81
// =========================================================================
void _pte_gmm_endog(todo, betas, crit, g, H)
{
    real matrix PHI, PHI_LAG, Z, W, X, X_lag, C, TP_lag
    real matrix OMEGA, OMEGA_lag, OMEGA_TP_lag, OMEGA_lag_pol, g_b, XI
    real matrix OMEGA2_lag, OMEGA2_TP_lag, OMEGA3_lag, OMEGA3_TP_lag
    real matrix OMEGA4_lag, OMEGA4_TP_lag
    real scalar omegapoly

    // Read omegapoly order from Stata scalar (default 3)
    omegapoly = st_numscalar("_pte_omegapoly_endog")
    if (omegapoly == .) omegapoly = 3

    // Read data from Stata
    PHI     = st_data(., "phi")
    PHI_LAG = st_data(., "phi_lag")
    Z       = st_data(., ("const", "lnl_lag", "lnk", "l2_lag", "k2", "kl_lag", "t"))
    X       = st_data(., ("lnl", "lnk", "l2", "k2", "l1k1"))
    X_lag   = st_data(., ("lnl_lag", "lnk_lag", "l2_lag", "k2_lag", "l1k1_lag"))
    C       = st_data(., "const")
    TP_lag  = st_data(., "treat_post_lag")

    // Weight matrix
    W = invsym(Z'Z) / rows(Z)

    // Compute omega and lagged omega
    OMEGA     = PHI - X * betas'
    OMEGA_lag = PHI_LAG - X_lag * betas'

    // Build evolution polynomial with treatment interactions
    // Base: omegapoly=1 -> (C, OMEGA_lag, OMEGA_TP_lag, TP_lag) = 4 cols
    OMEGA_TP_lag = OMEGA_lag :* TP_lag
    OMEGA_lag_pol = (C, OMEGA_lag, OMEGA_TP_lag)

    // omegapoly >= 2: add OMEGA2_lag, OMEGA2_TP_lag
    if (omegapoly >= 2) {
        OMEGA2_lag    = OMEGA_lag :* OMEGA_lag
        OMEGA2_TP_lag = OMEGA2_lag :* TP_lag
        OMEGA_lag_pol = (OMEGA_lag_pol, OMEGA2_lag, OMEGA2_TP_lag)
    }

    // omegapoly >= 3: add OMEGA3_lag, OMEGA3_TP_lag
    if (omegapoly >= 3) {
        OMEGA3_lag    = OMEGA2_lag :* OMEGA_lag
        OMEGA3_TP_lag = OMEGA3_lag :* TP_lag
        OMEGA_lag_pol = (OMEGA_lag_pol, OMEGA3_lag, OMEGA3_TP_lag)
    }

    // omegapoly >= 4: add OMEGA4_lag, OMEGA4_TP_lag
    if (omegapoly >= 4) {
        OMEGA4_lag    = OMEGA3_lag :* OMEGA_lag
        OMEGA4_TP_lag = OMEGA4_lag :* TP_lag
        OMEGA_lag_pol = (OMEGA_lag_pol, OMEGA4_lag, OMEGA4_TP_lag)
    }

    // Append TP_lag as last column (always present)
    OMEGA_lag_pol = (OMEGA_lag_pol, TP_lag)

    // Concentrated-out: estimate evolution params via OLS
    g_b = invsym(OMEGA_lag_pol' * OMEGA_lag_pol) * OMEGA_lag_pol' * OMEGA

    // Innovation
    XI = OMEGA - OMEGA_lag_pol * g_b

    // GMM criterion
    crit = (Z'XI)' * W * (Z'XI)
}

// =========================================================================
// Model runner: initialize optimizer and run
// Reference: DOs/prodest_acf_trlg_endog.do L83-105
// =========================================================================
void _pte_model_endog()
{
    real scalar S, fval
    real matrix p, beta_ols

    // Get OLS initial values from Stata
    beta_ols = st_matrix("e(b)")[1, 1..5]

    // Configure optimizer (identical settings to expost/CLK)
    S = optimize_init()
    optimize_init_evaluator(S, &_pte_gmm_endog())
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
    st_matrix("_pte_beta_endog", p)
    st_numscalar("_pte_fval_endog", fval)
}

end
