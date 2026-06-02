*! version 1.0.0  20Feb2026
*! pte_hetero_qtest.mata - US-E11-007
*! Heterogeneity Q-Test (Cochran's Q) - Mata engine
*! Q = sum(w_g * (ATT_g - ATT_pool)^2), Q ~ chi2(G-1)
*! I2 = max(0, (Q - df) / Q) * 100
*! Reference: Cochran (1954), Higgins & Thompson (2002)

version 14.0

mata:
mata set matastrict on

// ================================================================
// _pte_hetero_qtest_compute()
// Main computation function for heterogeneity Q-test
//
// Input (from e() returns):
//   e(att_cohort)    : G x (L+1) matrix of cohort ATTs
//   e(att_cohort_se) : G x (L+1) matrix of cohort SEs
//
// Output (stored to Stata tempnames via st_local):
//   Q_mat     : 1 x (L+1) Q statistics per period
//   p_mat     : 1 x (L+1) p-values per period
//   I2_mat    : 1 x (L+1) I-squared per period
//   df_mat    : 1 x (L+1) period-specific degrees of freedom
//   G_mat     : 1 x (L+1) period-specific valid cohort counts
//   df_val    : scalar df only when period-specific df is constant; else missing
//   G_val     : scalar G only when period-specific G is constant; else missing
//   Q_pool    : scalar, pooled Q across periods (if pool==1)
//   p_pool    : scalar, pooled p-value (if pool==1)
// ================================================================

void _pte_hetero_qtest_compute(real scalar do_pool)
{
    real matrix ATT, SE, W
    real rowvector Q_vec, p_vec, I2_vec, df_vec, G_vec
    real scalar G, L_plus_1, g, l
    real scalar df, df_scalar, G_scalar
    real scalar sum_w, sum_w_att, att_pool_l, Q_l, p_l, I2_l
    real scalar Q_pooled, df_pooled, p_pooled, n_pool_valid
    real colvector valid_g, w_l, att_l, dev_l
    
    // ============================================================
    // Read input matrices from e()
    // ============================================================
    
    ATT = st_matrix("e(att_cohort)")
    SE  = st_matrix("e(att_cohort_se)")
    
    G = rows(ATT)
    L_plus_1 = cols(ATT)
    
    // Dimension check
    if (rows(SE) != G | cols(SE) != L_plus_1) {
        errprintf("\n{bf:pte error E-3016}: Dimension mismatch\n")
        errprintf("  e(att_cohort):    %g x %g\n", G, L_plus_1)
        errprintf("  e(att_cohort_se): %g x %g\n", rows(SE), cols(SE))
        exit(3016)
    }
    
    // ============================================================
    // Compute IVW weights: w_g = 1 / SE_g^2
    // A cohort-period cell is valid only when ATT and SE are both observed
    // and the SE is strictly positive. Otherwise Q would consume a missing ATT
    // as if it were a real effect estimate, which breaks the cohort contract.
    // ============================================================
    
    W = J(G, L_plus_1, .)
    for (g = 1; g <= G; g++) {
        for (l = 1; l <= L_plus_1; l++) {
            if (!missing(ATT[g, l]) & !missing(SE[g, l]) & SE[g, l] > 0) {
                W[g, l] = 1 / (SE[g, l]^2)
            }
        }
    }
    
    // ============================================================
    // Per-period Q, p, I2 computation
    // ============================================================
    
    Q_vec  = J(1, L_plus_1, .)
    p_vec  = J(1, L_plus_1, .)
    I2_vec = J(1, L_plus_1, .)
    df_vec = J(1, L_plus_1, .)
    G_vec  = J(1, L_plus_1, .)
    
    for (l = 1; l <= L_plus_1; l++) {
        // Find valid cohorts (non-missing weights)
        valid_g = selectindex(!rowmissing(W[., l]))
        G_vec[1, l] = length(valid_g)
        
        if (length(valid_g) < 2) {
            // Cannot compute Q with fewer than 2 cohorts
            Q_vec[1, l] = .
            p_vec[1, l] = .
            I2_vec[1, l] = .
            if (length(valid_g) == 0) {
                printf("{txt}Warning W-3012: Period %g: no valid cohorts\n", l-1)
            }
            else {
                printf("{txt}Warning W-3011: Period %g: only 1 valid cohort, Q-test skipped\n", l-1)
            }
            continue
        }
        
        w_l   = W[valid_g, l]
        att_l = ATT[valid_g, l]
        
        // Weighted mean ATT
        sum_w     = sum(w_l)
        sum_w_att = sum(w_l :* att_l)
        att_pool_l = sum_w_att / sum_w
        
        // Q statistic: sum(w_g * (ATT_g - ATT_pool)^2)
        dev_l = att_l :- att_pool_l
        Q_l = sum(w_l :* (dev_l :^ 2))
        
        // Degrees of freedom
        df = length(valid_g) - 1
        
        // p-value: P(chi2(df) > Q)
        p_l = chi2tail(df, Q_l)
        
        // I-squared: max(0, (Q - df) / Q) * 100
        if (Q_l <= 0) {
            I2_l = 0
        }
        else if (Q_l <= df) {
            I2_l = 0
        }
        else {
            I2_l = ((Q_l - df) / Q_l) * 100
        }
        
        Q_vec[1, l]  = Q_l
        p_vec[1, l]  = p_l
        I2_vec[1, l] = I2_l
        df_vec[1, l] = df
    }
    
    // ============================================================
    // Scalar summary only when valid cohort counts are constant
    // ============================================================
    
    df_scalar = .
    G_scalar = .
    if (!missing(df_vec[1, 1])) {
        df_scalar = df_vec[1, 1]
        G_scalar = G_vec[1, 1]
        for (l = 2; l <= L_plus_1; l++) {
            if (missing(df_vec[1, l]) | df_vec[1, l] != df_scalar | G_vec[1, l] != G_scalar) {
                df_scalar = .
                G_scalar = .
                break
            }
        }
    }
    
    // ============================================================
    // Optional: Pooled Q across all periods
    // Q_pooled = sum(Q_l), df_pooled = (L+1) * (G-1)
    // ============================================================
    
    Q_pooled = .
    df_pooled = .
    p_pooled = .
    
    if (do_pool == 1) {
        Q_pooled = 0
        df_pooled = 0
        n_pool_valid = 0
        for (l = 1; l <= L_plus_1; l++) {
            if (!missing(Q_vec[1, l])) {
                n_pool_valid = n_pool_valid + 1
                Q_pooled = Q_pooled + Q_vec[1, l]
                valid_g = selectindex(!rowmissing(W[., l]))
                df_pooled = df_pooled + (length(valid_g) - 1)
            }
        }
        if (n_pool_valid == 0) {
            Q_pooled = .
            df_pooled = .
            p_pooled = .
        }
        else if (df_pooled > 0) {
            p_pooled = chi2tail(df_pooled, Q_pooled)
        }
    }
    
    // ============================================================
    // Store results to Stata
    // ============================================================
    
    st_matrix(st_local("Q_mat"), Q_vec)
    st_matrix(st_local("p_mat"), p_vec)
    st_matrix(st_local("I2_mat"), I2_vec)
    st_matrix(st_local("df_mat"), df_vec)
    st_matrix(st_local("G_mat"), G_vec)
    st_numscalar(st_local("df_val"), df_scalar)
    st_numscalar(st_local("G_val"), G_scalar)
    st_numscalar(st_local("Q_pool_val"), Q_pooled)
    st_numscalar(st_local("p_pool_val"), p_pooled)
    st_numscalar(st_local("df_pool_val"), df_pooled)
    
    // Set column names
    _pte_qtest_set_colnames(L_plus_1)
}

// ================================================================
// Helper: Set column names for output matrices
// ================================================================

void _pte_qtest_set_colnames(real scalar L_plus_1)
{
    string matrix colstripe
    real scalar l
    
    colstripe = J(L_plus_1, 2, "")
    for (l = 1; l <= L_plus_1; l++) {
        colstripe[l, 1] = ""
        colstripe[l, 2] = "ATT" + strofreal(l - 1)
    }
    
    st_matrixcolstripe(st_local("Q_mat"), colstripe)
    st_matrixcolstripe(st_local("p_mat"), colstripe)
    st_matrixcolstripe(st_local("I2_mat"), colstripe)
    st_matrixcolstripe(st_local("df_mat"), colstripe)
    st_matrixcolstripe(st_local("G_mat"), colstripe)
}

end
