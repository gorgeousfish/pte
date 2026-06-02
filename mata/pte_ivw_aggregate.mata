*! version 1.0.0  20Feb2026
*! pte_ivw_aggregate.mata - US-E11-006
*! Inverse Variance Weighted ATT Aggregation - Mata engine
*! Reference: Chen, Liao & Schurter (2026)

version 14.0

mata:
mata set matastrict on

// ================================================================
// _pte_ivw_aggregate_compute()
// Main computation function for IVW aggregation
// 
// Input (from e() returns):
//   e(att_cohort)    : G x (L+1) matrix of cohort ATTs
//   e(att_cohort_se) : G x (L+1) matrix of cohort SEs
//
// Output (stored to Stata tempnames):
//   att_pool    : 1 x (L+1) pooled ATT
//   se_pool     : 1 x (L+1) pooled SE
//   ci_lo       : 1 x (L+1) CI lower bound
//   ci_hi       : 1 x (L+1) CI upper bound
//   ivw_w       : G x (L+1) raw weights (1/SE^2)
//   n_valid     : 1 x (L+1) number of valid cohorts per period
// ================================================================

void _pte_ivw_aggregate_compute(real scalar level)
{
    real matrix ATT, SE, W
    real rowvector ATT_pool, SE_pool, CI_lo, CI_hi, N_valid
    real scalar G, L_plus_1, alpha, z_crit
    real scalar g, l, n_v, sum_w, sum_w_att
    real colvector valid_idx, w_l, att_l
    
    // ============================================================
    // T4: Read input matrices
    // ============================================================
    
    ATT = st_matrix("e(att_cohort)")
    SE  = st_matrix("e(att_cohort_se)")
    
    G = rows(ATT)
    L_plus_1 = cols(ATT)
    
    // ============================================================
    // T5: Dimension validation
    // ============================================================
    
    if (rows(SE) != G | cols(SE) != L_plus_1) {
        errprintf("\n{bf:pte error E-3016}: Dimension mismatch\n")
        errprintf("  e(att_cohort):    %g x %g\n", G, L_plus_1)
        errprintf("  e(att_cohort_se): %g x %g\n", rows(SE), cols(SE))
        exit(3016)
    }
    
    // ============================================================
    // T6 + T7: Boundary detection and weight calculation
    // w_g = 1 / SE_g^2 (missing if SE is missing or zero)
    // ============================================================
    
    W = J(G, L_plus_1, .)
    
    for (g = 1; g <= G; g++) {
        for (l = 1; l <= L_plus_1; l++) {
            if (!missing(SE[g, l]) & SE[g, l] > 0) {
                W[g, l] = 1 / (SE[g, l]^2)
            }
            else {
                W[g, l] = .
                if (missing(SE[g, l])) {
                    printf("{txt}Warning W-3015: Cohort %g period %g: SE missing, skipped\n", g, l-1)
                }
                else {
                    printf("{txt}Warning W-3015: Cohort %g period %g: SE=0, skipped\n", g, l-1)
                }
            }
        }
    }
    
    // ============================================================
    // T8 + T9: Weighted mean ATT and pooled SE per period
    // ATT_pool_l = sum(w_g * ATT_g) / sum(w_g)
    // SE_pool_l  = sqrt(1 / sum(w_g))
    // ============================================================
    
    ATT_pool = J(1, L_plus_1, .)
    SE_pool  = J(1, L_plus_1, .)
    N_valid  = J(1, L_plus_1, 0)
    
    for (l = 1; l <= L_plus_1; l++) {
        // Find valid cohorts for this period
        valid_idx = selectindex(!rowmissing(W[., l]))
        n_v = length(valid_idx)
        N_valid[1, l] = n_v
        
        if (n_v == 0) {
            errprintf("\n{bf:pte error E-3015}: No valid cohorts for period %g\n", l-1)
            errprintf("  All cohort SEs are missing or zero\n")
            exit(3015)
        }
        else if (n_v == 1) {
            // Single valid cohort: return its values directly
            ATT_pool[1, l] = ATT[valid_idx[1], l]
            SE_pool[1, l]  = SE[valid_idx[1], l]
            if (G > 1) {
                printf("{txt}Info I-3015: Period %g: only 1 valid cohort\n", l-1)
            }
        }
        else {
            // Multiple valid cohorts: IVW aggregation
            w_l   = W[valid_idx, l]
            att_l = ATT[valid_idx, l]
            sum_w     = sum(w_l)
            sum_w_att = sum(w_l :* att_l)
            
            ATT_pool[1, l] = sum_w_att / sum_w
            SE_pool[1, l]  = sqrt(1 / sum_w)
        }
    }
    
    // ============================================================
    // T10: Confidence interval calculation
    // CI = ATT_pool +/- z_crit * SE_pool
    // ============================================================
    
    alpha  = (100 - level) / 100
    z_crit = invnormal(1 - alpha / 2)
    
    CI_lo = ATT_pool :- z_crit :* SE_pool
    CI_hi = ATT_pool :+ z_crit :* SE_pool
    
    // ============================================================
    // T11 + T12: Store results to Stata matrices with column names
    // ============================================================
    
    st_matrix(st_local("att_pool"), ATT_pool)
    st_matrix(st_local("se_pool"),  SE_pool)
    st_matrix(st_local("ci_lo"),    CI_lo)
    st_matrix(st_local("ci_hi"),    CI_hi)
    st_matrix(st_local("ivw_w"),    W)
    st_matrix(st_local("n_valid"),  N_valid)
    
    // Set column names: ATT0, ATT1, ..., ATT{L}
    _pte_ivw_set_colnames(L_plus_1)
}

// ================================================================
// Helper: Set column names for output matrices
// ================================================================

void _pte_ivw_set_colnames(real scalar L_plus_1)
{
    string matrix colstripe
    real scalar l
    
    colstripe = J(L_plus_1, 2, "")
    for (l = 1; l <= L_plus_1; l++) {
        colstripe[l, 1] = ""
        colstripe[l, 2] = "ATT" + strofreal(l - 1)
    }
    
    st_matrixcolstripe(st_local("att_pool"), colstripe)
    st_matrixcolstripe(st_local("se_pool"),  colstripe)
    st_matrixcolstripe(st_local("ci_lo"),    colstripe)
    st_matrixcolstripe(st_local("ci_hi"),    colstripe)
    st_matrixcolstripe(st_local("n_valid"),  colstripe)
}

end
