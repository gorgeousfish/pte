*! _pte_cohort_bootstrap.ado
*! Bootstrap Inference for Cohort-Specific ATT
*! Implements block bootstrap for cohort ATT:
*! Outer loop: b = 1..B, set seed b
*! Cluster resampling: bsample, cluster(firm) strata(D)
*! Re-estimate: prodfunc -> omega -> cohort ATT -> IVW aggregate
*! Inner seed: fixed at 123456 for ATT simulation

version 14.0
// ================================================================
// Mata: percentile helpers. Cohort/pool CIs use _pte_boot_ci_bound, which
// reproduces Stata's default _pctile (egen pctile(), p(.)). The legacy
// _pte_boot_quantile (altdef interpolation) is retained for reference only
// and is not on the active CI path.
// ================================================================
mata:
mata set matastrict on

void _pte_ivw_assert_nonnegative_se(real matrix SE, string scalar context)
{
    if (sum(vec((SE :< 0) :& !missing(SE))) > 0) {
        errprintf("\n{bf:pte error E-3016}: Negative SE values detected in %s\n", context)
        errprintf("  Cohort ATT standard errors must be nonnegative or missing\n")
        exit(3016)
    }
}

real rowvector _pte_boot_quantile(real matrix X, real scalar p)
{
    real scalar K, k, n, j
    real scalar g_frac
    real colvector col_k, sorted_k
    real rowvector result

    K = cols(X)
    result = J(1, K, .)

    for (k = 1; k <= K; k++) {
        // Extract non-missing values for column k
        col_k = select(X[., k], X[., k] :< .)
        n = rows(col_k)

        if (n < 2) {
            result[1, k] = .
            continue
        }

        // Sort ascending
        sorted_k = sort(col_k, 1)

        // Linear interpolation: altdef method
        // h = p * (n + 1)
        // j = floor(h), g = h - j
        j = floor(p * (n + 1))
        g_frac = p * (n + 1) - j

        // Boundary handling
        if (j < 1) {
            result[1, k] = sorted_k[1]
        }
        else if (j >= n) {
            result[1, k] = sorted_k[n]
        }
        else {
            result[1, k] = (1 - g_frac) * sorted_k[j] + g_frac * sorted_k[j + 1]
        }
    }

    return(result)
}

real rowvector _pte_boot_ci_bound(real matrix X, real scalar p)
{
    real scalar K, k, n, pos, fl
    real colvector col_k, sorted_k
    real rowvector result

    K = cols(X)
    result = J(1, K, .)

    for (k = 1; k <= K; k++) {
        col_k = select(X[., k], X[., k] :< .)
        n = rows(col_k)

        if (n < 2) {
            result[1, k] = .
            continue
        }

        sorted_k = sort(col_k, 1)
        // Interpolated quantile matching Stata's default _pctile (the algorithm
        // behind the official replication DOs' egen pctile(), p(.)). Position
        // n*p landing on an integer i (1<=i<n) averages order statistics i and
        // i+1; otherwise the floor(n*p)+1 order statistic is used (clamped).
        pos = p * n
        if (pos == floor(pos) & pos >= 1 & pos < n) {
            result[1, k] = (sorted_k[pos] + sorted_k[pos + 1]) / 2
        }
        else {
            fl = floor(pos) + 1
            if (fl < 1) fl = 1
            if (fl > n) fl = n
            result[1, k] = sorted_k[fl]
        }
    }

    return(result)
}

// ================================================================
// Mata: IVW aggregation helper for bootstrap iterations
// Computes pooled ATT via inverse-variance weighting and stores
// into ATT_pool_boot[b, .]
// ================================================================
void _pte_boot_ivw(real scalar b, real scalar G, real scalar L_plus_1,
                   string scalar att_name, string scalar se_name)
{
    real matrix ATT, SE, W
    real rowvector pool_att
    real scalar l, g, sum_w, sum_wa
    real scalar n_valid

    ATT = st_matrix(att_name)
    SE  = st_matrix(se_name)
    pool_att = J(1, L_plus_1, .)
    _pte_ivw_assert_nonnegative_se(SE, "cohort bootstrap IVW")

    for (l = 1; l <= L_plus_1; l++) {
        sum_w = 0
        sum_wa = 0
        n_valid = 0
        for (g = 1; g <= G; g++) {
            if (!missing(SE[g, l]) & SE[g, l] > 0 & !missing(ATT[g, l])) {
                sum_w = sum_w + 1 / (SE[g, l]^2)
                sum_wa = sum_wa + ATT[g, l] / (SE[g, l]^2)
                n_valid++
            }
        }
        if (n_valid > 0 & sum_w > 0) {
            pool_att[1, l] = sum_wa / sum_w
        }
    }

    // Store into global Mata matrix
    external real matrix ATT_pool_boot
    ATT_pool_boot[b, .] = pool_att
}

void _pte_boot_rebuild_pool(real matrix keep_rows, real scalar L_plus_1)
{
    real scalar b, l, idx, g, sum_w, sum_wa, nboot, nkeep, flat_col
    real scalar att_gl, se_gl
    real rowvector pool_att
    external real matrix ATT_cohort_boot, ATT_pool_boot, SE_cohort_boot

    nboot = rows(ATT_cohort_boot)
    nkeep = cols(keep_rows)

    ATT_pool_boot = J(nboot, L_plus_1, .)
    if (nkeep == 0) {
        return
    }

    for (b = 1; b <= nboot; b++) {
        pool_att = J(1, L_plus_1, .)
        for (l = 1; l <= L_plus_1; l++) {
            sum_w = 0
            sum_wa = 0
            for (idx = 1; idx <= nkeep; idx++) {
                g = keep_rows[1, idx]
                flat_col = (g - 1) * L_plus_1 + l
                att_gl = ATT_cohort_boot[b, flat_col]
                se_gl = SE_cohort_boot[b, flat_col]
                if (!missing(att_gl) & !missing(se_gl) & se_gl > 0) {
                    sum_w = sum_w + 1 / (se_gl^2)
                    sum_wa = sum_wa + att_gl / (se_gl^2)
                }
            }
            if (sum_w > 0) {
                pool_att[1, l] = sum_wa / sum_w
            }
        }
        ATT_pool_boot[b, .] = pool_att
    }
}

void _pte_bootstrap_compute_se(string scalar cohort_se_name,
                               string scalar pool_se_name)
{
    real matrix valid_k
    real rowvector se_c, se_p
    real scalar K_c, K_p, kk
    external real matrix ATT_cohort_boot, ATT_pool_boot

    K_c = cols(ATT_cohort_boot)
    K_p = cols(ATT_pool_boot)

    se_c = J(1, K_c, .)
    for (kk = 1; kk <= K_c; kk++) {
        valid_k = select(ATT_cohort_boot[., kk], ATT_cohort_boot[., kk] :< .)
        if (rows(valid_k) > 1) {
            se_c[1, kk] = sqrt(variance(valid_k))
        }
    }

    se_p = J(1, K_p, .)
    for (kk = 1; kk <= K_p; kk++) {
        valid_k = select(ATT_pool_boot[., kk], ATT_pool_boot[., kk] :< .)
        if (rows(valid_k) > 1) {
            se_p[1, kk] = sqrt(variance(valid_k))
        }
    }

    st_matrix(cohort_se_name, se_c)
    st_matrix(pool_se_name, se_p)
}

void _pte_bootstrap_compute_ci(real scalar p_lo, real scalar p_hi,
                               string scalar cohort_lo_name,
                               string scalar cohort_hi_name,
                               string scalar pool_lo_name,
                               string scalar pool_hi_name)
{
    external real matrix ATT_cohort_boot, ATT_pool_boot

    // Match the main bootstrap CI contract used by the serial and grouped ATT
    // paths: percentile bounds computed via Stata's default _pctile algorithm
    // (egen pctile(), p(.)) with linear interpolation between order statistics.
    st_matrix(cohort_lo_name, _pte_boot_ci_bound(ATT_cohort_boot, p_lo))
    st_matrix(cohort_hi_name, _pte_boot_ci_bound(ATT_cohort_boot, p_hi))
    st_matrix(pool_lo_name, _pte_boot_ci_bound(ATT_pool_boot, p_lo))
    st_matrix(pool_hi_name, _pte_boot_ci_bound(ATT_pool_boot, p_hi))
}

void _pte_bootstrap_point_ivw(string scalar att_name,
                              string scalar se_name,
                              string scalar pool_name,
                              string scalar pool_se_name)
{
    real matrix ATT_o, SE_o
    real rowvector pool_o, pool_se_o
    real scalar ll, gg, sw, swa, nv

    ATT_o = st_matrix(att_name)
    SE_o  = st_matrix(se_name)
    _pte_ivw_assert_nonnegative_se(SE_o, "cohort point-estimate IVW")

    pool_o = J(1, cols(ATT_o), .)
    pool_se_o = J(1, cols(ATT_o), .)

    for (ll = 1; ll <= cols(ATT_o); ll++) {
        sw = 0
        swa = 0
        nv = 0
        for (gg = 1; gg <= rows(ATT_o); gg++) {
            if (!missing(SE_o[gg, ll]) & SE_o[gg, ll] > 0 &
                !missing(ATT_o[gg, ll])) {
                sw = sw + 1 / (SE_o[gg, ll]^2)
                swa = swa + ATT_o[gg, ll] / (SE_o[gg, ll]^2)
                nv++
            }
        }
        if (nv > 0 & sw > 0) {
            pool_o[1, ll] = swa / sw
            pool_se_o[1, ll] = sqrt(1 / sw)
        }
    }

    st_matrix(pool_name, pool_o)
    st_matrix(pool_se_name, pool_se_o)
}

end


// ================================================================
// Stata program: _pte_cohort_bootstrap (T-002 framework)
// ================================================================

capture program drop _pte_cohort_bootstrap
program define _pte_cohort_bootstrap, eclass
    version 14.0
    local _pte_cmdline `"`0'"'

    // ================================================================
    // Syntax parsing
    // ================================================================
    syntax , ///
        cohorts(string)          /// space-separated cohort years
        cohortvar(varname)       /// cohort definition variable
        treatment(varname)       /// treatment variable D
        depvar(varname)          /// dependent variable
        free(varname)            /// free input (labor)
        state(varname)           /// state variable (capital)
        proxy(varname)           /// proxy variable (materials)
        id(varname)              /// panel ID variable
        time(varname)            /// time variable
        nboot(integer)           /// number of bootstrap replications
        [omegapoly(integer 3)    /// evolution polynomial order
         attperiods(integer 4)   /// ATT periods
         nsim(integer -1)        /// simulation paths
         matchstrategy(string)   /// matching strategy
         matchexpr(string)       /// custom matching expression
         prodfunc(string)        /// production function type
         poly(integer -1)        /// polynomial order
         control(varlist)        /// control variables
         level(integer 95)       /// confidence level
         inner_seed(integer 123456) /// inner seed for ATT simulation
         NOTRIMeps               /// don't Winsorize eps0
         NOLOg                   /// silent mode
         SIMPlified              /// reserved simplified mode flag
         REPlicate]              /// replication mode

    // ================================================================
    // Input validation (T-002)
    // ================================================================
    if `nboot' < 2 {
        di as error "{bf:pte error}: nboot must be >= 2, got `nboot'"
        exit 198
    }
    if `level' < 10 | `level' > 99 {
        di as error "{bf:pte error}: level must be between 10 and 99"
        exit 198
    }
    if `nsim' == -1 {
        if `omegapoly' == 1 {
            local nsim = 1
        }
        else {
            local nsim = 100
        }
    }
    local _pte_has_poly = regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])poly[(]")
    local _pte_has_omegapoly = regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])omegapoly[(]")
    if `_pte_has_poly' {
        if `_pte_has_omegapoly' & `poly' != `omegapoly' {
            di as error "{bf:pte error}: cannot specify both poly(`poly') and omegapoly(`omegapoly')"
            exit 198
        }
        local omegapoly = `poly'
    }
    local poly = `omegapoly'
    if `nsim' < 1 {
        di as error "{bf:pte error}: nsim must be >= 1, got `nsim'"
        exit 198
    }
    if `inner_seed' < 1 {
        di as error "{bf:pte error}: inner_seed() must be a positive integer"
        exit 198
    }
    if `inner_seed' > 2147483647 {
        di as error "{bf:pte error}: inner_seed() exceeds maximum value (2147483647)"
        exit 198
    }
    if "`simplified'" != "" {
        di as error "{bf:pte error}: simplified is not implemented for _pte_cohort_bootstrap"
        di as error "Use the full cohort bootstrap path until a pooled-only ereturn contract is defined."
        exit 198
    }

    // Verify panel data
    capture _xt, trequired
    if _rc != 0 {
        di as error "{bf:pte error}: data must be xtset as panel"
        exit 459
    }

    // Verify required variables exist
    foreach v in `depvar' `free' `state' `proxy' `treatment' `cohortvar' {
        capture confirm variable `v', exact
        if _rc != 0 {
            di as error "{bf:pte error}: variable '`v'' not found"
            exit 111
        }
    }

    // Defaults
    if "`prodfunc'" == "" local prodfunc "cd"
    if "`matchstrategy'" == "" local matchstrategy "notyettreated"
    if "`matchstrategy'" == "custom" {
        if `"`matchexpr'"' == "" {
            di as error "{bf:pte error E-3017}: matchstrategy(custom) requires matchexpr()"
            exit 198
        }
        quietly _pte_validate_matchexpr, expr(`"`matchexpr'"')
    }

    // Count cohorts and periods
    local G : word count `cohorts'
    local L_plus_1 = `attperiods' + 1
    local K_cohort = `G' * `L_plus_1'

    if `G' < 1 {
        di as error "{bf:pte error}: at least 1 cohort required"
        exit 198
    }

    // Late failures happen after nested production/omega helpers have
    // overwritten e(). Preserve the caller's estimate so failure exits can
    // roll back instead of leaking worker state.
    tempname _pte_prev_est
    local _pte_has_prev_est = 0
    capture local _pte_prev_cmd `"`e(cmd)'"'
    if _rc == 0 {
        capture estimates store `_pte_prev_est', copy
        if _rc == 0 {
            local _pte_has_prev_est = 1
        }
    }

    // ================================================================
    // Display header
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "{hline 70}"
        di as text "{bf:Cohort Bootstrap Inference}"
        di as text "{hline 70}"
        di as text "  Cohorts:              " as result "`G' (`cohorts')"
        di as text "  ATT periods:          " as result "0 to `attperiods'"
        di as text "  Bootstrap reps:       " as result "`nboot'"
        di as text "  Inner seed:           " as result "`inner_seed'"
        di as text "  nsim:                 " as result "`nsim'"
        di as text "  Production function:  " as result "`prodfunc'"
        di as text "  Match strategy:       " as result "`matchstrategy'"
        di as text "  Confidence level:     " as result "`level'%"
        di as text "{hline 70}"
    }

    // ================================================================
    // Create firm-level treatment indicator for stratification
    //   bys firm: egen treat=max(treat_post1)
    // ================================================================
    tempvar treat_firm
    qui bysort `id': egen `treat_firm' = max(`treatment')

    // ================================================================
    // Save original data and RNG state
    // ================================================================
    tempfile orig_data
    qui save `orig_data', replace
    local orig_rngstate = c(rngstate)
    local pte_restore_rng "capture set rngstate `orig_rngstate'"

    // ================================================================
    // Initialize Mata storage matrices (T-002)
    // ATT_cohort_boot: nboot x (G * (L+1)) - cohort-specific ATT
    // SE_cohort_boot:  nboot x (G * (L+1)) - per-iteration analytical SE
    // ATT_pool_boot:   nboot x (L+1)       - pooled ATT
    // ================================================================
    mata: ATT_cohort_boot = J(`nboot', `K_cohort', .)
    mata: SE_cohort_boot = J(`nboot', `K_cohort', .)
    mata: ATT_pool_boot = J(`nboot', `L_plus_1', .)

    local boot_failed = 0

    // ================================================================
    // Bootstrap main loop (T-003)
    // Outer seed: set seed b
    // Cluster resampling: bsample, cluster(id) strata(treat_firm)
    // Re-estimate full pipeline per iteration
    // ================================================================

    if "`nolog'" == "" {
        di as text ""
        di as text "Bootstrap progress (B = `nboot'):"
        di as text "----+--- 1 ---+--- 2 ---+--- 3 ---+--- 4 ---+--- 5"
    }

    preserve
    forvalues b = 1/`nboot' {
        restore, preserve
        tempvar _pte_firm_bs

        // Outer seed
        set seed `b'

        // Cluster bootstrap must preserve duplicate-cluster multiplicity.
        // idcluster() assigns a unique bootstrap panel ID for each resampled draw.
        qui bsample, cluster(`id') strata(`treat_firm') idcluster(`_pte_firm_bs')
        qui xtset `_pte_firm_bs' `time'

        // ============================================================
        // T-004: Per-iteration estimation pipeline
        // Step 1: Production function estimation
        // Step 2: Omega recovery and evolution
        // Step 3: Cohort ATT estimation
        // Step 4: IVW aggregation
        // ============================================================

        capture noisily {

            // --- Step 1: Production function estimation ---
            local pf_opts "treatment(`treatment') id(`_pte_firm_bs') time(`time')"
            local pf_opts "`pf_opts' lny(`depvar') free(`free') state(`state') proxy(`proxy')"
            local pf_opts "`pf_opts' pfunc(`prodfunc') poly(`poly') omegapoly(`omegapoly')"
            if "`control'" != "" local pf_opts "`pf_opts' control(`control')"
            local pf_opts "`pf_opts' noreport nodiagnose"

            qui _pte_prodfunc, `pf_opts'

            // --- Step 2: Omega recovery ---
            local om_opts "treatment(`treatment') omegapoly(`omegapoly') nodiagnose"
            if "`notrimeps'" != "" local om_opts "`om_opts' notrimeps"
            if "`prodfunc'" == "translog" local om_opts "`om_opts' prodfunc(translog)"
            qui _pte_omega, `om_opts'
            
            // Retrieve evolution parameters.
            // Cohort dynamic ATT should follow the same trimmed-Gaussian
            // innovation convention as the main ATT path unless NOTRIMeps is
            // explicitly requested or trimmed sigma is unavailable.
            tempname rho_b
            matrix `rho_b' = e(rho_0)
            local sigmaeps_b = e(sigma_eps_trim)
            if "`notrimeps'" != "" | missing(`sigmaeps_b') | `sigmaeps_b' < 0 {
                local sigmaeps_b = e(sigma_eps)
            }

            // --- Step 3: Set inner seed for ATT simulation ---
            set seed `inner_seed'
            tempfile boot_iter_data
            qui save `boot_iter_data', replace

            // --- Step 4: Cohort ATT estimation (T-004) ---
            // For each cohort, estimate instantaneous and dynamic ATT
            local col_offset = 0
            local g_idx = 0

            // Temporary matrices for this iteration
            tempname att_c_b att_c_se_b
            matrix `att_c_b' = J(`G', `L_plus_1', .)
            matrix `att_c_se_b' = J(`G', `L_plus_1', .)

            foreach cohort_yr of local cohorts {
                local ++g_idx
                qui use `boot_iter_data', clear

                local match_opts "cohort(`cohort_yr') max_periods(`attperiods') matchstrategy(`matchstrategy')"
                if `"`matchexpr'"' != "" {
                    local match_opts "`match_opts' matchexpr(`"`matchexpr'"')"
                }
                local match_opts "`match_opts' treatvar(`treatment') treatyearvar(`cohortvar') nolog"
                qui _pte_cohort_match, `match_opts'

                if r(skip) {
                    continue
                }

                // Instantaneous ATT (nt=0)
                qui _pte_cohort_att_instant, cohort(`cohort_yr') ///
                    rho(`rho_b') omegapoly(`omegapoly') ///
                    panelvar(`_pte_firm_bs') timevar(`time') ///
                    cohortvar(`cohortvar') nolog

                matrix `att_c_b'[`g_idx', 1] = r(att_g_0)
                matrix `att_c_se_b'[`g_idx', 1] = r(att_g_0_se)

                // Dynamic ATT (nt=1..attperiods) if attperiods > 0
                if `attperiods' > 0 {
                    qui _pte_cohort_att_dynamic, cohort(`cohort_yr') ///
                        rho(`rho_b') omegapoly(`omegapoly') ///
                        maxperiods(`attperiods') sigmaeps(`sigmaeps_b') ///
                        nsim(`nsim') seed(`inner_seed') ///
                        panelvar(`_pte_firm_bs') timevar(`time') ///
                        cohortvar(`cohortvar') nolog

                    // Copy dynamic ATT values (nt=1..L)
                    tempname att_dyn_b
                    matrix `att_dyn_b' = r(att_dynamic)
                    forvalues l = 2/`L_plus_1' {
                        matrix `att_c_b'[`g_idx', `l'] = `att_dyn_b'[1, `l']
                    }
                    // Use dynamic SE for nt>=1
                    tempname se_dyn_b
                    matrix `se_dyn_b' = r(att_dynamic_se)
                    forvalues l = 2/`L_plus_1' {
                        matrix `att_c_se_b'[`g_idx', `l'] = `se_dyn_b'[1, `l']
                    }
                }
            }

            // --- Step 5: Store cohort ATT into Mata boot matrix ---
            // Flatten G x (L+1) into 1 x (G*(L+1)) row
            forvalues g = 1/`G' {
                forvalues l = 1/`L_plus_1' {
                    local flat_col = (`g' - 1) * `L_plus_1' + `l'
                    mata: ATT_cohort_boot[`b', `flat_col'] = st_matrix("`att_c_b'")[`g', `l']
                    mata: SE_cohort_boot[`b', `flat_col'] = st_matrix("`att_c_se_b'")[`g', `l']
                }
            }

            // --- Step 6: IVW aggregation for pooled ATT ---
            // Post cohort results temporarily for IVW
            tempname att_pool_iter se_pool_iter
            
            // Use Mata for IVW computation inline
            mata: _pte_boot_ivw(`b', `G', `L_plus_1', "`att_c_b'", "`att_c_se_b'")

        } // end capture

        if _rc != 0 {
            local ++boot_failed
            if "`nolog'" == "" {
                di as text "x" _continue
            }
        }
        else {
            if "`nolog'" == "" {
                di as text "." _continue
            }
        }

        // Progress display: newline every 50 iterations
        if mod(`b', 50) == 0 & "`nolog'" == "" {
            di as text "  `b'/`nboot'"
        }
    }
    restore


    // ================================================================
    // Failure rate check
    // ================================================================
    if `boot_failed' >= `nboot' {
        `pte_restore_rng'
        di as error "{bf:pte error E-3015}: All `nboot' bootstrap iterations failed"
        mata: mata drop ATT_cohort_boot SE_cohort_boot ATT_pool_boot
        if `_pte_has_prev_est' {
            capture estimates restore `_pte_prev_est'
            capture estimates drop `_pte_prev_est'
        }
        else {
            capture ereturn clear
        }
        exit 3015
    }
    local boot_success = `nboot' - `boot_failed'
    if `boot_failed' > `nboot' / 2 {
        `pte_restore_rng'
        di as error "{bf:pte error}: More than 50% of bootstrap iterations failed"
        di as error "  Failed: `boot_failed' / `nboot'"
        mata: mata drop ATT_cohort_boot SE_cohort_boot ATT_pool_boot
        if `_pte_has_prev_est' {
            capture estimates restore `_pte_prev_est'
            capture estimates drop `_pte_prev_est'
        }
        else {
            capture ereturn clear
        }
        exit 498
    }

    if "`nolog'" == "" {
        di as text ""
        di as text "Bootstrap complete: `boot_success'/`nboot' successful iterations"
        if `boot_failed' > 0 {
            di as text "  (`boot_failed' failed)"
        }
    }

    capture noisily {
        // ================================================================
        // T-005: SE computation (Mata)
        // SE = sample standard deviation of bootstrap estimates
        // ================================================================
        tempname att_cohort_se att_pool_se

        mata: _pte_bootstrap_compute_se("`att_cohort_se'", "`att_pool_se'")

        // ================================================================
        // T-006: Percentile CI computation (Mata)
        // Match the main bootstrap contract via discrete lower/upper
        // order-statistic bounds on the non-missing bootstrap draws.
        // ================================================================
        local alpha = (100 - `level') / 100
        local p_lo = `alpha' / 2
        local p_hi = 1 - `alpha' / 2

        tempname ci_cohort_l ci_cohort_u ci_pool_l ci_pool_u

        mata: _pte_bootstrap_compute_ci(`p_lo', `p_hi', ///
            "`ci_cohort_l'", "`ci_cohort_u'", "`ci_pool_l'", "`ci_pool_u'")

        // ================================================================
        // Reshape flat vectors into G x (L+1) matrices
        // att_cohort_se: 1 x (G*L1) -> G x L1
        // ci_cohort_l/u: 1 x (G*L1) -> G x L1
        // ================================================================
        tempname se_c_mat ci_cl_mat ci_cu_mat

        matrix `se_c_mat' = J(`G', `L_plus_1', .)
        matrix `ci_cl_mat' = J(`G', `L_plus_1', .)
        matrix `ci_cu_mat' = J(`G', `L_plus_1', .)

        forvalues g = 1/`G' {
            forvalues l = 1/`L_plus_1' {
                local flat_col = (`g' - 1) * `L_plus_1' + `l'
                matrix `se_c_mat'[`g', `l'] = `att_cohort_se'[1, `flat_col']
                matrix `ci_cl_mat'[`g', `l'] = `ci_cohort_l'[1, `flat_col']
                matrix `ci_cu_mat'[`g', `l'] = `ci_cohort_u'[1, `flat_col']
            }
        }

        // Pool SE and CI are already 1 x (L+1) - no reshape needed
        // But rename for clarity
        tempname se_p_mat ci_pl_mat ci_pu_mat
        matrix `se_p_mat' = `att_pool_se'
        matrix `ci_pl_mat' = `ci_pool_l'
        matrix `ci_pu_mat' = `ci_pool_u'

        // ================================================================
        // T-007/T-008: Compute point estimates from original data
        // We need the original (non-bootstrap) ATT estimates as point estimates
        // Re-load original data and run estimation once
        // ================================================================
        qui use `orig_data', clear
        qui xtset `id' `time'

        // Run production function on original data
        local pf_opts "treatment(`treatment') id(`id') time(`time')"
        local pf_opts "`pf_opts' lny(`depvar') free(`free') state(`state') proxy(`proxy')"
        local pf_opts "`pf_opts' pfunc(`prodfunc') poly(`poly') omegapoly(`omegapoly')"
        if "`control'" != "" local pf_opts "`pf_opts' control(`control')"
        local pf_opts "`pf_opts' noreport nodiagnose"

        qui _pte_prodfunc, `pf_opts'

        local om_opts "treatment(`treatment') omegapoly(`omegapoly') nodiagnose"
        if "`notrimeps'" != "" local om_opts "`om_opts' notrimeps"
        if "`prodfunc'" == "translog" local om_opts "`om_opts' prodfunc(translog)"
        qui _pte_omega, `om_opts'

        tempname rho_orig
        matrix `rho_orig' = e(rho_0)
        local sigmaeps_orig = e(sigma_eps_trim)
        if "`notrimeps'" != "" | missing(`sigmaeps_orig') | `sigmaeps_orig' < 0 {
            local sigmaeps_orig = e(sigma_eps)
        }
        tempfile point_est_data
        qui save `point_est_data', replace

        // Point estimates for each cohort
        tempname att_c_orig att_c_se_orig
        matrix `att_c_orig' = J(`G', `L_plus_1', .)
        matrix `att_c_se_orig' = J(`G', `L_plus_1', .)

        set seed `inner_seed'
        local g_idx = 0
        foreach cohort_yr of local cohorts {
            local ++g_idx
            qui use `point_est_data', clear

            local match_opts "cohort(`cohort_yr') max_periods(`attperiods') matchstrategy(`matchstrategy')"
            if `"`matchexpr'"' != "" {
                local match_opts "`match_opts' matchexpr(`"`matchexpr'"')"
            }
            local match_opts "`match_opts' treatvar(`treatment') treatyearvar(`cohortvar') nolog"
            qui _pte_cohort_match, `match_opts'

            if r(skip) {
                continue
            }

            // Instantaneous ATT
            qui _pte_cohort_att_instant, cohort(`cohort_yr') ///
                rho(`rho_orig') omegapoly(`omegapoly') ///
                panelvar(`id') timevar(`time') ///
                cohortvar(`cohortvar') nolog

            matrix `att_c_orig'[`g_idx', 1] = r(att_g_0)
            matrix `att_c_se_orig'[`g_idx', 1] = r(att_g_0_se)

            // Dynamic ATT
            if `attperiods' > 0 {
                qui _pte_cohort_att_dynamic, cohort(`cohort_yr') ///
                    rho(`rho_orig') omegapoly(`omegapoly') ///
                    maxperiods(`attperiods') sigmaeps(`sigmaeps_orig') ///
                    nsim(`nsim') seed(`inner_seed') ///
                    panelvar(`id') timevar(`time') ///
                    cohortvar(`cohortvar') nolog

                tempname att_dyn_orig se_dyn_orig
                matrix `att_dyn_orig' = r(att_dynamic)
                matrix `se_dyn_orig' = r(att_dynamic_se)
                forvalues l = 2/`L_plus_1' {
                    matrix `att_c_orig'[`g_idx', `l'] = `att_dyn_orig'[1, `l']
                    matrix `att_c_se_orig'[`g_idx', `l'] = `se_dyn_orig'[1, `l']
                }
            }
        }

        // Public cohort results should include only cohorts that produced at
        // least one ATT estimate on the point-estimate sample. Skip-path
        // cohorts are a valid internal state during matching, but they are
        // not part of the published K x (L+1) cohort contract.
        local valid_rows ""
        local G_pub = 0
        forvalues g = 1/`G' {
            local row_has_att = 0
            forvalues l = 1/`L_plus_1' {
                local att_gl = `att_c_orig'[`g', `l']
                if `att_gl' < . {
                    local row_has_att = 1
                }
            }
            if `row_has_att' {
                local ++G_pub
                local valid_rows "`valid_rows' `g'"
            }
        }

        if `G_pub' == 0 {
            error 3011
        }

        if `G_pub' < `G' {
            tempname valid_rows_mat
            matrix `valid_rows_mat' = J(1, `G_pub', .)
            local _pte_keep_idx = 0
            foreach g of local valid_rows {
                local ++_pte_keep_idx
                matrix `valid_rows_mat'[1, `_pte_keep_idx'] = `g'
            }
            mata: _pte_boot_rebuild_pool(st_matrix("`valid_rows_mat'"), `L_plus_1')
            mata: _pte_bootstrap_compute_se("`att_cohort_se'", "`att_pool_se'")
            mata: _pte_bootstrap_compute_ci(`p_lo', `p_hi', ///
                "`ci_cohort_l'", "`ci_cohort_u'", "`ci_pool_l'", "`ci_pool_u'")
            matrix `se_p_mat' = `att_pool_se'
            matrix `ci_pl_mat' = `ci_pool_l'
            matrix `ci_pu_mat' = `ci_pool_u'
        }

        // ================================================================
        // Compute pooled ATT from original point estimates via IVW
        // ================================================================
        tempname att_p_orig att_p_se_orig
        tempname att_c_pub att_c_se_pub
        matrix `att_c_pub' = J(`G_pub', `L_plus_1', .)
        matrix `att_c_se_pub' = J(`G_pub', `L_plus_1', .)

        local g_pub = 0
        foreach g of local valid_rows {
            local ++g_pub
            forvalues l = 1/`L_plus_1' {
                matrix `att_c_pub'[`g_pub', `l'] = `att_c_orig'[`g', `l']
                matrix `att_c_se_pub'[`g_pub', `l'] = `att_c_se_orig'[`g', `l']
            }
        }

        matrix `att_p_orig' = J(1, `L_plus_1', .)
        matrix `att_p_se_orig' = J(1, `L_plus_1', .)

        mata: _pte_bootstrap_point_ivw("`att_c_pub'", "`att_c_se_pub'", ///
            "`att_p_orig'", "`att_p_se_orig'")

        // ================================================================
        // Build cohort metadata matrices for ereturn
        // ================================================================
        tempname cohort_list_mat cohort_sizes_mat attperiods_mat

        // Cohort list: G x 1 matrix of cohort years
        matrix `cohort_list_mat' = J(`G_pub', 1, .)

        // Cohort metadata must come from the full point-estimate sample rather
        // than the last cohort-specific matched slice left in memory.
        qui use `point_est_data', clear

        // Cohort sizes: G x 1 matrix of firm counts per cohort
        matrix `cohort_sizes_mat' = J(`G_pub', 1, .)
        local g_pub = 0
        foreach g of local valid_rows {
            local ++g_pub
            local cohort_yr : word `g' of `cohorts'
            matrix `cohort_list_mat'[`g_pub', 1] = `cohort_yr'
            qui count if `cohortvar' == `cohort_yr'
            // Count unique firms in this cohort
            tempvar is_cohort_g
            qui gen byte `is_cohort_g' = (`cohortvar' == `cohort_yr')
            qui tab `id' if `is_cohort_g' == 1
            matrix `cohort_sizes_mat'[`g_pub', 1] = r(r)
            drop `is_cohort_g'
        }

        // Publish the same period-level heterogeneity payload that the
        // standalone cohort Q-test derives from e(att_cohort)/e(att_cohort_se).
        tempname q_mat p_mat i2_mat df_q_mat G_q_mat
        tempname se_c_pub ci_cl_pub ci_cu_pub
        matrix `se_c_pub' = J(`G_pub', `L_plus_1', .)
        matrix `ci_cl_pub' = J(`G_pub', `L_plus_1', .)
        matrix `ci_cu_pub' = J(`G_pub', `L_plus_1', .)

        local g_pub = 0
        foreach g of local valid_rows {
            local ++g_pub
            forvalues l = 1/`L_plus_1' {
                matrix `se_c_pub'[`g_pub', `l'] = `se_c_mat'[`g', `l']
                matrix `ci_cl_pub'[`g_pub', `l'] = `ci_cl_mat'[`g', `l']
                matrix `ci_cu_pub'[`g_pub', `l'] = `ci_cu_mat'[`g', `l']
            }
        }

        matrix `q_mat' = J(1, `L_plus_1', .)
        matrix `p_mat' = J(1, `L_plus_1', .)
        matrix `i2_mat' = J(1, `L_plus_1', .)
        matrix `df_q_mat' = J(1, `L_plus_1', .)
        matrix `G_q_mat' = J(1, `L_plus_1', .)
        if `G_pub' >= 2 {
            forvalues l = 1/`L_plus_1' {
                local n_valid = 0
                local sum_w = 0
                local sum_w_att = 0
                forvalues g = 1/`G_pub' {
                    local se_gl = `se_c_pub'[`g', `l']
                    local att_gl = `att_c_pub'[`g', `l']
                    if !missing(`se_gl') & `se_gl' > 0 & !missing(`att_gl') {
                        local w_gl = 1 / (`se_gl' * `se_gl')
                        local sum_w = `sum_w' + `w_gl'
                        local sum_w_att = `sum_w_att' + `w_gl' * `att_gl'
                        local ++n_valid
                    }
                }
                matrix `G_q_mat'[1, `l'] = `n_valid'
                if `n_valid' >= 2 & `sum_w' > 0 {
                    local att_pool_l = `sum_w_att' / `sum_w'
                    local q_l = 0
                    forvalues g = 1/`G_pub' {
                        local se_gl = `se_c_pub'[`g', `l']
                        local att_gl = `att_c_pub'[`g', `l']
                        if !missing(`se_gl') & `se_gl' > 0 & !missing(`att_gl') {
                            local w_gl = 1 / (`se_gl' * `se_gl')
                            local dev_gl = `att_gl' - `att_pool_l'
                            local q_l = `q_l' + `w_gl' * (`dev_gl' * `dev_gl')
                        }
                    }
                    matrix `q_mat'[1, `l'] = `q_l'
                    matrix `p_mat'[1, `l'] = chi2tail(`n_valid' - 1, `q_l')
                    matrix `df_q_mat'[1, `l'] = `n_valid' - 1
                    if `q_l' > `n_valid' - 1 {
                        matrix `i2_mat'[1, `l'] = ((`q_l' - (`n_valid' - 1)) / `q_l') * 100
                    }
                    else {
                        matrix `i2_mat'[1, `l'] = 0
                    }
                }
            }
        }

        // Public cohort/bootstrap results must use exact realized dynamic
        // support, just like the main ATT chain and cohort publishers. A
        // contiguous 0..L attperiods matrix would hand missing ATT columns to
        // _pte_cohort_ereturn, where e(b) cannot contain unsupported periods.
        local pte_cohort_support_periods ""
        forvalues l = 1/`L_plus_1' {
            if `att_p_orig'[1, `l'] < . {
                local pte_period = `l' - 1
                local pte_cohort_support_periods ///
                    "`pte_cohort_support_periods' `pte_period'"
            }
        }
        local pte_cohort_support_periods : list retokenize pte_cohort_support_periods
        local L_plus_1_pub : word count `pte_cohort_support_periods'

        if `L_plus_1_pub' == 0 {
            error 3011
        }

        if `L_plus_1_pub' < `L_plus_1' {
            tempname att_c_pub_sparse att_c_se_pub_sparse
            tempname att_p_orig_sparse se_p_mat_sparse
            tempname ci_cl_pub_sparse ci_cu_pub_sparse
            tempname ci_pl_mat_sparse ci_pu_mat_sparse
            tempname q_mat_sparse p_mat_sparse i2_mat_sparse
            tempname df_q_mat_sparse G_q_mat_sparse attperiods_mat_sparse

            matrix `att_c_pub_sparse' = J(`G_pub', `L_plus_1_pub', .)
            matrix `att_c_se_pub_sparse' = J(`G_pub', `L_plus_1_pub', .)
            matrix `att_p_orig_sparse' = J(1, `L_plus_1_pub', .)
            matrix `se_p_mat_sparse' = J(1, `L_plus_1_pub', .)
            matrix `ci_cl_pub_sparse' = J(`G_pub', `L_plus_1_pub', .)
            matrix `ci_cu_pub_sparse' = J(`G_pub', `L_plus_1_pub', .)
            matrix `ci_pl_mat_sparse' = J(1, `L_plus_1_pub', .)
            matrix `ci_pu_mat_sparse' = J(1, `L_plus_1_pub', .)
            matrix `q_mat_sparse' = J(1, `L_plus_1_pub', .)
            matrix `p_mat_sparse' = J(1, `L_plus_1_pub', .)
            matrix `i2_mat_sparse' = J(1, `L_plus_1_pub', .)
            matrix `df_q_mat_sparse' = J(1, `L_plus_1_pub', .)
            matrix `G_q_mat_sparse' = J(1, `L_plus_1_pub', .)
            matrix `attperiods_mat_sparse' = J(1, `L_plus_1_pub', .)

            local _pte_sparse_col = 0
            foreach pte_period of local pte_cohort_support_periods {
                local ++_pte_sparse_col
                local _pte_src_col = `pte_period' + 1

                forvalues g = 1/`G_pub' {
                    matrix `att_c_pub_sparse'[`g', `_pte_sparse_col'] = ///
                        `att_c_pub'[`g', `_pte_src_col']
                    matrix `att_c_se_pub_sparse'[`g', `_pte_sparse_col'] = ///
                        `se_c_pub'[`g', `_pte_src_col']
                    matrix `ci_cl_pub_sparse'[`g', `_pte_sparse_col'] = ///
                        `ci_cl_pub'[`g', `_pte_src_col']
                    matrix `ci_cu_pub_sparse'[`g', `_pte_sparse_col'] = ///
                        `ci_cu_pub'[`g', `_pte_src_col']
                }

                matrix `att_p_orig_sparse'[1, `_pte_sparse_col'] = ///
                    `att_p_orig'[1, `_pte_src_col']
                matrix `se_p_mat_sparse'[1, `_pte_sparse_col'] = ///
                    `se_p_mat'[1, `_pte_src_col']
                matrix `ci_pl_mat_sparse'[1, `_pte_sparse_col'] = ///
                    `ci_pl_mat'[1, `_pte_src_col']
                matrix `ci_pu_mat_sparse'[1, `_pte_sparse_col'] = ///
                    `ci_pu_mat'[1, `_pte_src_col']
                matrix `q_mat_sparse'[1, `_pte_sparse_col'] = ///
                    `q_mat'[1, `_pte_src_col']
                matrix `p_mat_sparse'[1, `_pte_sparse_col'] = ///
                    `p_mat'[1, `_pte_src_col']
                matrix `i2_mat_sparse'[1, `_pte_sparse_col'] = ///
                    `i2_mat'[1, `_pte_src_col']
                matrix `df_q_mat_sparse'[1, `_pte_sparse_col'] = ///
                    `df_q_mat'[1, `_pte_src_col']
                matrix `G_q_mat_sparse'[1, `_pte_sparse_col'] = ///
                    `G_q_mat'[1, `_pte_src_col']
                matrix `attperiods_mat_sparse'[1, `_pte_sparse_col'] = ///
                    `pte_period'
            }

            matrix `att_c_pub' = `att_c_pub_sparse'
            matrix `se_c_pub' = `att_c_se_pub_sparse'
            matrix `att_p_orig' = `att_p_orig_sparse'
            matrix `se_p_mat' = `se_p_mat_sparse'
            matrix `ci_cl_pub' = `ci_cl_pub_sparse'
            matrix `ci_cu_pub' = `ci_cu_pub_sparse'
            matrix `ci_pl_mat' = `ci_pl_mat_sparse'
            matrix `ci_pu_mat' = `ci_pu_mat_sparse'
            matrix `q_mat' = `q_mat_sparse'
            matrix `p_mat' = `p_mat_sparse'
            matrix `i2_mat' = `i2_mat_sparse'
            matrix `df_q_mat' = `df_q_mat_sparse'
            matrix `G_q_mat' = `G_q_mat_sparse'
            matrix `attperiods_mat' = `attperiods_mat_sparse'
        }
        else {
            matrix `attperiods_mat' = J(1, `L_plus_1_pub', .)
            local _pte_sparse_col = 0
            foreach pte_period of local pte_cohort_support_periods {
                local ++_pte_sparse_col
                matrix `attperiods_mat'[1, `_pte_sparse_col'] = `pte_period'
            }
        }

        // ================================================================
        // Use bootstrap SE instead of analytical SE for ereturn
        // The bootstrap SE replaces the analytical SE as the primary SE
        // ================================================================
        local ereturn_match_opts ""
        if `"`matchexpr'"' != "" {
            local ereturn_match_opts `"`ereturn_match_opts' matchexpr(`"`matchexpr'"')"' 
        }

        // ================================================================
        // Call _pte_cohort_ereturn to store all results (T-008)
        // ================================================================
        _pte_cohort_ereturn, ///
            att_cohort(`att_c_pub') ///
            att_cohort_se(`se_c_pub') ///
            att_pool(`att_p_orig') ///
            att_pool_se(`se_p_mat') ///
            cohort_list(`cohort_list_mat') ///
            cohort_sizes(`cohort_sizes_mat') ///
            attperiods(`attperiods_mat') ///
            het_Q(`q_mat') ///
            het_Q_p(`p_mat') ///
            het_I2(`i2_mat') ///
            het_Q_df(`df_q_mat') ///
            het_Q_G(`G_q_mat') ///
            matchstrategy(`matchstrategy') ///
            `ereturn_match_opts' ///
            ci_cohort_l(`ci_cl_pub') ///
            ci_cohort_u(`ci_cu_pub') ///
            ci_pool_l(`ci_pl_mat') ///
            ci_pool_u(`ci_pu_mat') ///
            nboot(`nboot') ///
            boot_failed(`boot_failed') ///
            boot_mode("cohort") ///
            nodisplay
    }
    local _pte_postloop_rc = _rc
    `pte_restore_rng'
    capture mata: mata drop ATT_cohort_boot SE_cohort_boot ATT_pool_boot
    if `_pte_postloop_rc' != 0 {
        if `_pte_has_prev_est' {
            capture estimates restore `_pte_prev_est'
            capture estimates drop `_pte_prev_est'
        }
        else {
            capture ereturn clear
        }
        exit `_pte_postloop_rc'
    }
    if `_pte_has_prev_est' {
        capture estimates drop `_pte_prev_est'
    }

    // ================================================================
    // Display summary if not silent
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "{hline 70}"
        di as text "{bf:Bootstrap Results Summary}"
        di as text "{hline 70}"
        di as text "  Successful iterations: " as result "`boot_success' / `nboot'"
        di as text "  Confidence level:      " as result "`level'%"
        di as text ""

        // Display pooled ATT with bootstrap SE and CI
        di as text "  Pooled ATT (Bootstrap SE, `level'% Percentile CI):"
        local _pte_disp_col = 0
        foreach nt_val of local pte_cohort_support_periods {
            local ++_pte_disp_col
            local att_val = `att_p_orig'[1, `_pte_disp_col']
            local se_val = `se_p_mat'[1, `_pte_disp_col']
            local ci_l_val = `ci_pl_mat'[1, `_pte_disp_col']
            local ci_u_val = `ci_pu_mat'[1, `_pte_disp_col']
            di as text "    nt=`nt_val': " ///
                as result %9.6f `att_val' ///
                as text " (SE=" as result %7.5f `se_val' ///
                as text ", CI=[" as result %7.4f `ci_l_val' ///
                as text "," as result %7.4f `ci_u_val' as text "])"
        }
        di as text "{hline 70}"
    }

    `pte_restore_rng'

end
