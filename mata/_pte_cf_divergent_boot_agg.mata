*! _pte_cf_divergent_boot_agg.mata
*! Bootstrap aggregation for divergent counterfactual ATE
*! Computes SE and percentile CI from bootstrap ATE matrix
*! Version 1.0.0 - 2026-02-21

version 14.0

mata:
mata set matastrict on

void _pte_cf_divergent_boot_agg(
    string scalar ate_boot_name,
    string scalar ate_se_name,
    string scalar ate_ci_lo_name,
    string scalar ate_ci_hi_name)
{
    real matrix ATE_boot
    real rowvector SE, CI_lo, CI_hi
    real scalar B, n_periods, n_valid, j, alpha_half
    real colvector col_j, valid_idx
    string scalar boot_alpha_str

    // Read bootstrap ATE matrix from Stata
    ATE_boot = st_matrix(ate_boot_name)
    B = rows(ATE_boot)
    n_periods = cols(ATE_boot)

    // Read alpha from Stata local
    boot_alpha_str = st_local("boot_alpha")
    if (boot_alpha_str == "") {
        alpha_half = 0.025  // default 95% CI
    }
    else {
        alpha_half = strtoreal(boot_alpha_str) / 2
    }

    // Initialize output vectors
    SE = J(1, n_periods, .)
    CI_lo = J(1, n_periods, .)
    CI_hi = J(1, n_periods, .)

    // Track minimum valid count across periods
    n_valid = 0

    // Compute SE and CI for each period
    for (j = 1; j <= n_periods; j++) {
        col_j = ATE_boot[., j]

        // Find non-missing rows
        valid_idx = selectindex(col_j :< .)
        if (length(valid_idx) < 2) {
            SE[1, j] = .
            CI_lo[1, j] = .
            CI_hi[1, j] = .
            continue
        }

        col_j = col_j[valid_idx]

        // Track valid count (use first period as reference)
        if (j == 1) {
            n_valid = length(valid_idx)
        }
        else {
            if (length(valid_idx) < n_valid) {
                n_valid = length(valid_idx)
            }
        }

        // Bootstrap SE = standard deviation of bootstrap estimates
        SE[1, j] = sqrt(variance(col_j))

        // Percentile CI: sort and pick quantiles
        _sort(col_j, 1)
        real scalar lo_idx, hi_idx, n_v
        n_v = length(col_j)
        lo_idx = max((1, ceil(alpha_half * n_v)))
        hi_idx = min((n_v, floor((1 - alpha_half) * n_v) + 1))

        CI_lo[1, j] = col_j[lo_idx]
        CI_hi[1, j] = col_j[hi_idx]
    }

    // Store results back to Stata
    st_matrix(ate_se_name, SE)
    st_matrix(ate_ci_lo_name, CI_lo)
    st_matrix(ate_ci_hi_name, CI_hi)

    // Set n_boot_valid as Stata local
    st_local("n_boot_valid", strofreal(n_valid))
}

end
