*! version 1.0.0  2026-02-18
*! Mata helper functions for _pte_mc_engine
*! These functions are extracted from mata: { } blocks that cannot
*! run inside Stata's program define due to r(3000) parsing issues.

// =========================================================================
// 1. Compute average of ATT_true (last column = mean of first L columns)
// =========================================================================
capture mata: mata drop _pte_mc_att_true_avg()
mata:
void _pte_mc_att_true_avg(string scalar matname)
{
    real matrix att
    real scalar L, avg

    att = st_matrix(matname)
    L = cols(att) - 1
    avg = mean(att[1, 1..L]')
    att[1, L + 1] = avg
    st_matrix(matname, att)
}
end

// =========================================================================
// 2. Compute bootstrap SE and percentile CI
// =========================================================================
capture mata: mata drop _pte_mc_boot_se_ci()
mata:
void _pte_mc_boot_se_ci(string scalar boot_name,
                         string scalar se_name,
                         string scalar lb_name,
                         string scalar ub_name)
{
    real matrix boot, se_out, lb_out, ub_out
    real scalar nc, j, n, p025, p975
    real colvector col, valid

    boot = st_matrix(boot_name)
    nc = cols(boot)
    se_out = J(1, nc, .)
    lb_out = J(1, nc, .)
    ub_out = J(1, nc, .)

    for (j = 1; j <= nc; j++) {
        col = boot[., j]
        valid = select(col, col :!= .)

        if (rows(valid) > 1) {
            // Bootstrap SE
            se_out[1, j] = sqrt(variance(valid))

            // Percentile CI (2.5th and 97.5th)
            _sort(valid, 1)
            n = rows(valid)
            p025 = ceil(0.025 * n)
            p975 = floor(0.975 * n)
            if (p025 < 1) p025 = 1
            if (p975 > n) p975 = n
            if (p975 < 1) p975 = 1
            lb_out[1, j] = valid[p025]
            ub_out[1, j] = valid[p975]
        }
    }

    st_matrix(se_name, se_out)
    st_matrix(lb_name, lb_out)
    st_matrix(ub_name, ub_out)
}
end


// =========================================================================
// 3. Compute bias: mean(est) - true for each column
// =========================================================================
capture mata: mata drop _pte_mc_compute_bias()
mata:
void _pte_mc_compute_bias(string scalar est_name,
                           string scalar true_name,
                           string scalar bias_name)
{
    real matrix est, trueval, bias
    real scalar nc, j
    real colvector col, valid

    est = st_matrix(est_name)
    trueval = st_matrix(true_name)
    nc = cols(est)
    bias = J(1, nc, .)

    for (j = 1; j <= nc; j++) {
        col = est[., j]
        valid = select(col, col :!= .)
        if (rows(valid) > 0) {
            bias[1, j] = mean(valid) - trueval[1, j]
        }
    }

    st_matrix(bias_name, bias)
}
end

// =========================================================================
// 4. Compute RMSE: sqrt(mean((est - true)^2)) for each column
// =========================================================================
capture mata: mata drop _pte_mc_compute_rmse()
mata:
void _pte_mc_compute_rmse(string scalar est_name,
                           string scalar true_name,
                           string scalar rmse_name)
{
    real matrix est, trueval, rmse
    real scalar nc, j
    real colvector col, valid, sq_err

    est = st_matrix(est_name)
    trueval = st_matrix(true_name)
    nc = cols(est)
    rmse = J(1, nc, .)

    for (j = 1; j <= nc; j++) {
        col = est[., j]
        valid = select(col, col :!= .)
        if (rows(valid) > 0) {
            sq_err = (valid :- trueval[1, j]):^2
            rmse[1, j] = sqrt(mean(sq_err))
        }
    }

    st_matrix(rmse_name, rmse)
}
end

// =========================================================================
// 5. Compute coverage: fraction of CIs containing true value
// =========================================================================
capture mata: mata drop _pte_mc_compute_coverage()
mata:
void _pte_mc_compute_coverage(string scalar true_name,
                               string scalar lb_name,
                               string scalar ub_name,
                               string scalar cov_name)
{
    real matrix trueval, lb, ub, cov
    real scalar nc, j
    real colvector lb_j, ub_j, vld, lb_v, ub_v, cvrd

    trueval = st_matrix(true_name)
    lb = st_matrix(lb_name)
    ub = st_matrix(ub_name)
    nc = cols(trueval)
    cov = J(1, nc, .)

    for (j = 1; j <= nc; j++) {
        lb_j = lb[., j]
        ub_j = ub[., j]
        vld = (lb_j :!= .) :& (ub_j :!= .)
        if (sum(vld) > 0) {
            lb_v = select(lb_j, vld)
            ub_v = select(ub_j, vld)
            cvrd = (lb_v :<= trueval[1, j]) :& (ub_v :>= trueval[1, j])
            cov[1, j] = mean(cvrd)
        }
    }

    st_matrix(cov_name, cov)
}
end


// =========================================================================
// 6. Compute SE ratio: mean(bootstrap SE) / MC standard deviation
// =========================================================================
capture mata: mata drop _pte_mc_compute_se_ratio()
mata:
void _pte_mc_compute_se_ratio(string scalar est_name,
                               string scalar se_name,
                               string scalar ser_name)
{
    real matrix est, se, ser
    real scalar nc, j, mcse, bse
    real colvector est_j, se_j

    est = st_matrix(est_name)
    se = st_matrix(se_name)
    nc = cols(est)
    ser = J(1, nc, .)

    for (j = 1; j <= nc; j++) {
        est_j = select(est[., j], est[., j] :!= .)
        se_j = select(se[., j], se[., j] :!= .)
        if (rows(est_j) > 1 & rows(se_j) > 0) {
            mcse = sqrt(variance(est_j))
            bse = mean(se_j)
            if (mcse > 0) {
                ser[1, j] = bse / mcse
            }
        }
    }

    st_matrix(ser_name, ser)
}
end

// =========================================================================
// 7. Display ATT comparison table
// =========================================================================
capture mata: mata drop _pte_mc_display_att_table()
mata:
void _pte_mc_display_att_table(string scalar true_name,
                                string scalar est_name,
                                string scalar bias_name,
                                string scalar rmse_name)
{
    real matrix att_t, att_e, bias_d, rmse_d
    real scalar nc, j, me
    real colvector ej

    att_t = st_matrix(true_name)
    att_e = st_matrix(est_name)
    bias_d = st_matrix(bias_name)
    rmse_d = st_matrix(rmse_name)
    nc = cols(att_t)

    for (j = 1; j <= nc; j++) {
        ej = select(att_e[., j], att_e[., j] :!= .)
        me = (rows(ej) > 0 ? mean(ej) : .)
        if (j < nc) {
            printf("  nt=%-4.0f   %9.4f   %9.4f   %9.4f   %9.4f\n",
                j - 1, att_t[1, j], me, bias_d[1, j], rmse_d[1, j])
        }
        else {
            printf("  avg       %9.4f   %9.4f   %9.4f   %9.4f\n",
                att_t[1, j], me, bias_d[1, j], rmse_d[1, j])
        }
    }
}
end

// =========================================================================
// 8. Display bootstrap inference table
// =========================================================================
capture mata: mata drop _pte_mc_display_boot_table()
mata:
void _pte_mc_display_boot_table(string scalar cov_name,
                                 string scalar ser_name)
{
    real matrix cov_d, ser_d
    real scalar nc, j

    cov_d = st_matrix(cov_name)
    ser_d = st_matrix(ser_name)
    nc = cols(cov_d)

    for (j = 1; j <= nc; j++) {
        if (j < nc) {
            printf("  nt=%-4.0f   %9.4f   %9.4f\n",
                j - 1, cov_d[1, j], ser_d[1, j])
        }
        else {
            printf("  avg       %9.4f   %9.4f\n",
                cov_d[1, j], ser_d[1, j])
        }
    }
}
end
