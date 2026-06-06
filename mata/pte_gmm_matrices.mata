*! version 1.1.0  13Feb2026
*! Matrix payload builder for the CLK GMM criterion.
*!
*! The ado layer must call this only after it has generated the required lagged
*! variables and removed observations that are outside the Theorem 3.1 sample,
*! namely first-panel observations and transition periods with D_t != D_{t-1}.
*! This Mata file then freezes the matrices shared by the optimizer and keeps
*! their column layout aligned with the paper and the reference DO files.

version 14.0

mata:

string scalar _pte_gmm_matrices_signature()
{
    return("pte_gmm_matrices_v2_11args")
}

// Build the fixed matrix payload consumed by GMM_CLK().
// `prodfunc' switches between the Cobb-Douglas and Translog column layouts.
// `omegapoly' is stored so the evaluator can rebuild the same evolution basis.
// The variable-name arguments identify the live Stata columns that hold the
// first-stage control function phi_t and the production-function regressors.
//
// Lagged helper columns such as phi_lag, lnl_lag, lnk_lag, treat_post_lag,
// const, and the Translog-specific mixed-lag terms must already exist in the
// current dataset. This routine trusts that preprocessing contract and fails
// only on dimension inconsistencies after the matrices are assembled.

void _pte_construct_gmm_matrices(string scalar prodfunc,
                                  real scalar omegapoly,
                                  string scalar phi_var,
                                  string scalar lnl_var,
                                  string scalar lnk_var,
                                  string scalar t_var,
                                  string scalar tp_var,
                                  string scalar l2_var,
                                  string scalar k2_var,
                                  string scalar l1k1_var,
                                  real scalar do_pooled_z)
{
    // Publish matrices through Mata externals so the optimizer can reuse them
    // across repeated criterion evaluations without rereading Stata memory.
    external real matrix    _pte_mat_X
    external real matrix    _pte_mat_X_lag
    external real matrix    _pte_mat_Z
    external real matrix    _pte_mat_W
    external real matrix    _pte_mat_PHI
    external real matrix    _pte_mat_PHI_lag
    external real matrix    _pte_mat_C
    external real matrix    _pte_mat_TP_lag
    external real scalar    _pte_mat_N
    external real scalar    _pte_mat_omegapoly

    real matrix ZtZ, Z_base, D0, D1
    real scalar N, cond_ZZ, rank_ZZ, cols_OLP

    // PHI and PHI_lag carry the control-function object before netting out
    // the candidate production-function coefficients inside the evaluator.
    _pte_mat_PHI     = st_data(., phi_var)
    _pte_mat_PHI_lag = st_data(., "phi_lag")

    // C and TP_lag are reused in every OMEGA_LAG_POL rebuild, so cache them
    // once here instead of reconstructing them inside the optimizer.
    _pte_mat_C      = st_data(., "const")
    _pte_mat_TP_lag = st_data(., "treat_post_lag")

    // X uses current inputs; X_lag uses their lagged counterparts exactly as
    // they enter the reference moment conditions. Z_base mirrors the base
    // instrument set, including the state-variable timing of capital.
    if (prodfunc == "cd") {
        _pte_mat_X     = st_data(., (lnl_var, lnk_var))
        _pte_mat_X_lag = st_data(., ("lnl_lag", "lnk_lag"))

        // Current-period capital belongs in Z because K_t is predetermined at
        // t-1, so lnk_t is valid when paired with lagged labor.
        Z_base = st_data(., ("const", "lnl_lag", lnk_var, t_var))
    }
    else {
        _pte_mat_X     = st_data(., (lnl_var, lnk_var, l2_var, k2_var, l1k1_var))
        _pte_mat_X_lag = st_data(., ("lnl_lag", "lnk_lag", "l2_lag", "k2_lag", "l1k1_lag"))

        // The mixed term l1k_lag must be L.lnl * lnk_t rather than the fully
        // lagged interaction in X_lag; otherwise the Translog Z matrix would
        // collapse the mixed-lag instrument required by the reference code.
        Z_base = st_data(., ("const", "lnl_lag", lnk_var, "l2_lag", k2_var, "l1k_lag", t_var))
    }

    // The default package path enforces the two stable-state moment blocks
    // implied by Theorem 3.1. Benchmark replicate() modes intentionally keep
    // the original paper DO files' weaker pooled-Z implementation, because
    // those modes promise numerical reproduction of the DO output.
    if (do_pooled_z) {
        _pte_mat_Z = Z_base
    }
    else {
        D0 = 1 :- _pte_mat_TP_lag
        D1 = _pte_mat_TP_lag
        _pte_mat_Z = (Z_base :* (D0 * J(1, cols(Z_base), 1)),
                      Z_base :* (D1 * J(1, cols(Z_base), 1)))
    }

    // The paper-strict one-step implementation uses W = invsym(Z'Z) / N on
    // the stacked state-specific instrument matrix. Keeping the 1/N scaling
    // preserves the criterion normalization seen by the optimizer and by the
    // ado-level diagnostics that consume fval.
    N = rows(_pte_mat_X)
    ZtZ = cross(_pte_mat_Z, _pte_mat_Z)
    cond_ZZ = cond(ZtZ)
    rank_ZZ = rank(ZtZ)
    if (rank_ZZ < cols(ZtZ) | cond_ZZ == . | cond_ZZ > 1e12) {
        if (do_pooled_z) printf("Warning: pooled DO Z'Z matrix is ill-conditioned\n")
        else printf("Warning: state-interacted Z'Z matrix is ill-conditioned\n")
        printf("  rank(Z'Z) = %g of %g\n", rank_ZZ, cols(ZtZ))
        printf("  cond(Z'Z) = %g\n", cond_ZZ)
        printf("  Continuing with invsym() to match the paper/DO benchmark path.\n")
    }
    _pte_mat_W = invsym(ZtZ) / N

    // Cache scalar metadata that the evaluator and the ado diagnostics both
    // need, without forcing them to infer dimensions from the matrices.
    _pte_mat_N = N
    _pte_mat_omegapoly = omegapoly

    // Return lightweight diagnostics to Stata so the caller can surface the
    // matrix layout and the Z'Z condition number in its own reporting layer.
    // OMEGA_LAG_POL alternates untreated and treated polynomial terms and
    // ends with D_{t-1}, so the width is fixed at 2 + 2 * omegapoly.
    cols_OLP = 2 + 2 * omegapoly

    st_local("cols_X", strofreal(cols(_pte_mat_X)))
    st_local("cols_Z", strofreal(cols(_pte_mat_Z)))
    st_local("cols_OLP", strofreal(cols_OLP))
    st_local("cond_ZZ", strofreal(cond_ZZ))

    printf("  Matrices constructed: N=%g, X=%gx%g, Z=%gx%g\n",
           N, rows(_pte_mat_X), cols(_pte_mat_X),
           rows(_pte_mat_Z), cols(_pte_mat_Z))

    // Fail closed if preprocessing left no usable Theorem 3.1 sample or if
    // any cached object drifted out of row alignment before optimization.
    if (N == 0) {
        errprintf("Error: GMM sample is empty after matrix construction\n")
        exit(498)
    }
    
    if (rows(_pte_mat_PHI) != N | rows(_pte_mat_PHI_lag) != N | 
        rows(_pte_mat_Z) != N | rows(_pte_mat_X_lag) != N |
        rows(_pte_mat_C) != N | rows(_pte_mat_TP_lag) != N) {
        errprintf("Error: Matrix dimension mismatch in GMM construction\n")
        errprintf("  PHI=%g, PHI_lag=%g, X=%g, X_lag=%g, Z=%g, C=%g, TP_lag=%g\n",
                  rows(_pte_mat_PHI), rows(_pte_mat_PHI_lag),
                  rows(_pte_mat_X), rows(_pte_mat_X_lag),
                  rows(_pte_mat_Z), rows(_pte_mat_C), rows(_pte_mat_TP_lag))
        exit(498)
    }
}


// Accessors keep the optimizer interface explicit while still using cached
// externals under the hood.

real matrix _pte_get_X()
{
    external real matrix _pte_mat_X
    return(_pte_mat_X)
}

real matrix _pte_get_X_lag()
{
    external real matrix _pte_mat_X_lag
    return(_pte_mat_X_lag)
}

real matrix _pte_get_Z()
{
    external real matrix _pte_mat_Z
    return(_pte_mat_Z)
}

real matrix _pte_get_W()
{
    external real matrix _pte_mat_W
    return(_pte_mat_W)
}

real matrix _pte_get_PHI()
{
    external real matrix _pte_mat_PHI
    return(_pte_mat_PHI)
}

real matrix _pte_get_PHI_lag()
{
    external real matrix _pte_mat_PHI_lag
    return(_pte_mat_PHI_lag)
}

real matrix _pte_get_C()
{
    external real matrix _pte_mat_C
    return(_pte_mat_C)
}

real matrix _pte_get_TP_lag()
{
    external real matrix _pte_mat_TP_lag
    return(_pte_mat_TP_lag)
}

real scalar _pte_get_N()
{
    external real scalar _pte_mat_N
    return(_pte_mat_N)
}

real scalar _pte_get_omegapoly()
{
    external real scalar _pte_mat_omegapoly
    return(_pte_mat_omegapoly)
}


// Utility builder for the lagged evolution basis. The live optimizer expands
// this inline for speed, but this helper documents and reproduces the exact
// alternating layout (1, omega, omega*D, omega^2, omega^2*D, ..., D).

real matrix _pte_construct_omega_lag_pol(real colvector omega_lag,
                                         real colvector tp_lag,
                                         real colvector C,
                                         real scalar omegapoly)
{
    real matrix result
    real colvector omega_tp, omega2, omega2_tp, omega3, omega3_tp
    real colvector omega4, omega4_tp

    omega_tp = omega_lag :* tp_lag

    if (omegapoly == 1) {
        result = (C, omega_lag, omega_tp, tp_lag)
    }
    else if (omegapoly == 2) {
        omega2 = omega_lag :* omega_lag
        omega2_tp = omega2 :* tp_lag
        result = (C, omega_lag, omega_tp, omega2, omega2_tp, tp_lag)
    }
    else if (omegapoly == 3) {
        omega2 = omega_lag :* omega_lag
        omega2_tp = omega2 :* tp_lag
        omega3 = omega2 :* omega_lag
        omega3_tp = omega3 :* tp_lag
        result = (C, omega_lag, omega_tp, omega2, omega2_tp,
                  omega3, omega3_tp, tp_lag)
    }
    else if (omegapoly == 4) {
        omega2 = omega_lag :* omega_lag
        omega2_tp = omega2 :* tp_lag
        omega3 = omega2 :* omega_lag
        omega3_tp = omega3 :* tp_lag
        omega4 = omega3 :* omega_lag
        omega4_tp = omega4 :* tp_lag
        result = (C, omega_lag, omega_tp, omega2, omega2_tp,
                  omega3, omega3_tp, omega4, omega4_tp, tp_lag)
    }
    else {
        errprintf("Error: Invalid omegapoly %g\n", omegapoly)
        result = J(0, 0, .)
    }

    return(result)
}


// Sanity check for the mixed-lag Translog instrument. If l1k_lag and the
// fully lagged interaction become numerically identical, either capital is
// effectively time-invariant or the preprocessing step built the wrong term.

real scalar _pte_verify_l1k_lag()
{
    real colvector l1k, l1k1, diff, scale, ok
    real scalar mean_diff, max_diff, mean_scale, rel_mean_diff, denom

    l1k  = st_data(., "l1k_lag")
    l1k1 = st_data(., "l1k1_lag")

    ok = (l1k :< .) :& (l1k1 :< .)
    diff = select(abs(l1k - l1k1), ok)
    scale = select(abs(l1k1), ok)

    if (rows(diff) == 0) {
        printf("  Warning: cannot validate Translog mixed-lag instrument; no rows have both comparison terms nonmissing\n")
        return(0)
    }

    mean_diff = mean(diff)
    max_diff = max(diff)
    mean_scale = mean(scale)
    denom = mean_scale
    if (denom == . | denom < 1e-12) denom = 1e-12
    rel_mean_diff = mean_diff / denom

    if (max_diff <= 1e-12 | rel_mean_diff < 1e-8) {
        printf("  Warning: Translog mixed-lag instrument is numerically close to the fully lagged interaction\n")
        printf("  mean|diff| = %g, max|diff| = %g, relative mean diff = %g\n",
                  mean_diff, max_diff, rel_mean_diff)
        printf("  Continuing because near equality can be a valid weak-variation feature of the sample.\n")
        return(0)
    }

    printf("  l1k_lag validation: mean|diff| = %g, relative mean diff = %g (OK)\n",
           mean_diff, rel_mean_diff)
    return(1)
}


end
