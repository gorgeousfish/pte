*! _pte_setup_summary.ado
*! Summarize the panel and treatment-support objects created by pte_setup.

version 14.0
capture program drop _pte_setup_summary
program define _pte_setup_summary, rclass
    version 14.0

    syntax , treatment(varname) [REPort MINTHreshold(integer 100)]

    if `minthreshold' < 0 {
        di as error "minthreshold() must be nonnegative"
        exit 198
    }

    // Verify panel setup
    capture qui xtset
    if _rc != 0 {
        di as error "panel data not set; use {bf:xtset panelvar timevar}"
        exit 459
    }

    // Re-run to capture r() values (capture clears them)
    qui xtset
    local idvar "`r(panelvar)'"
    local timevar "`r(timevar)'"

    if "`idvar'" == "" | "`timevar'" == "" {
        di as error "panel data not fully set; use {bf:xtset panelvar timevar}"
        exit 459
    }

    // These generated variables are the public setup contract consumed by
    // later estimators and diagnostics. Fail here if the caller bypassed the
    // setup stage or partially cleaned the dataset.
    foreach var in _pte_treat _pte_nt _pte_mid _pte_cohort _pte_treat_year {
        capture confirm variable `var'
        if _rc != 0 {
            di as error "variable `var' not found; run pte_setup variable generation first"
            exit 111
        }
    }

    // The report falls back to ASCII markers when the Stata session cannot
    // display Unicode glyphs cleanly.
    capture di as text "✓"
    if _rc != 0 {
        local check_mark "OK"
        local cross_mark "FAIL"
        local times_sign "x"
    }
    else {
        local check_mark "✓"
        local cross_mark "✗"
        local times_sign "×"
    }

    // Total observations
    qui count
    local N = r(N)

    // Total firms
    tempvar tag_firm
    bys `idvar': gen byte `tag_firm' = (_n == 1)
    qui count if `tag_firm' == 1
    local N_g = r(N)

    // Time span
    qui summ `timevar'
    local t_min = r(min)
    local t_max = r(max)

    // Treated / control firm counts
    tempvar tag_treated tag_ctrl
    bys `idvar': gen byte `tag_treated' = (_n == 1) & (_pte_treat == 1)
    bys `idvar': gen byte `tag_ctrl' = (_n == 1) & (_pte_treat == 0)

    qui count if `tag_treated' == 1
    local N_treated = r(N)
    qui count if `tag_ctrl' == 1
    local N_ctrl = r(N)

    // Percentages (handle divide-by-zero)
    if `N_g' > 0 {
        local pct_treated = `N_treated' / `N_g' * 100
        local pct_ctrl = `N_ctrl' / `N_g' * 100
    }
    else {
        local pct_treated = 0
        local pct_ctrl = 0
    }

    // Transition observations are the rows with D_t != D_{t-1}. They remain
    // useful for setup diagnostics even though Theorem 3.1 later excludes
    // them from the production-function moments.
    qui count if _pte_mid == 1
    local N_trans = r(N)

    // Reversals distinguish absorbing from non-absorbing treatment paths at
    // the raw panel level. The summary keeps that distinction visible before
    // downstream modules choose the appropriate estimator branch.
    qui count if `treatment' < L.`treatment' & L.`treatment' != .
    local N_reversal = r(N)
    if `N_reversal' == 0 {
        local trt_type "absorbing"
    }
    else {
        local trt_type "non-absorbing"
    }

    // Observation-level counts (D=1 obs vs D=0 obs)
    qui count if `treatment' == 1
    local N_treated_obs = r(N)
    qui count if `treatment' == 0
    local N_ctrl_obs = r(N)

    tempname cohort_years cohort_counts

    quietly count if _pte_treat == 1 & !missing(_pte_cohort)
    local N_timing_treated = r(N)

    if `N_timing_treated' > 0 {
        preserve

        // _pte_cohort is defined only for observed treatment onsets, so the
        // cohort table intentionally excludes always-treated and censored
        // treated firms without an observed entry date.
        qui keep if _pte_treat == 1 & !missing(_pte_cohort)

        // Keep first observation per firm
        bys `idvar': keep if _n == 1

        // Tabulate cohorts
        qui tab _pte_cohort, matrow(`cohort_years') matcell(`cohort_counts')
        local n_cohorts = r(r)

        restore
    }
    else {
        local n_cohorts = 0
        matrix `cohort_years' = J(1, 1, .)
        matrix `cohort_counts' = J(1, 1, 0)
    }

    if `N_timing_treated' > 0 {
        // Relative time statistics are meaningful only for firms with an
        // observed treatment entry, because _pte_nt is anchored at the first
        // observed switch into treatment.
        tempvar firm_pre firm_post first_treated

        bys `idvar': egen double `firm_pre' = total(_pte_nt < 0) if _pte_treat == 1 & !missing(_pte_nt)
        bys `idvar': egen double `firm_post' = total(_pte_nt >= 0) if _pte_treat == 1 & !missing(_pte_nt)
        bys `idvar': gen byte `first_treated' = (_n == 1)

        // Summarize across treated firms
        qui summ `firm_pre' if _pte_treat == 1 & !missing(_pte_nt) & `first_treated' == 1
        local avg_pre = r(mean)
        local min_pre = r(min)
        local max_pre = r(max)

        qui summ `firm_post' if _pte_treat == 1 & !missing(_pte_nt) & `first_treated' == 1
        local avg_post = r(mean)
        local min_post = r(min)
        local max_post = r(max)
    }
    else {
        local avg_pre = .
        local min_pre = .
        local max_pre = .
        local avg_post = .
        local min_post = .
        local max_post = .
    }

    // Assumption 3.3 requires support in both stable states. The summary uses
    // consecutive untreated and consecutive treated rows as an immediate check
    // on whether the sample can identify both non-transition laws.
    qui count if `treatment' == L.`treatment' & `treatment' == 0
    local N_stable_0 = r(N)

    qui count if `treatment' == L.`treatment' & `treatment' == 1
    local N_stable_1 = r(N)

    local assumption_pass = (`N_stable_0' >= `minthreshold') & (`N_stable_1' >= `minthreshold')

    if "`report'" != "" {
        di as text _n "{hline 70}"
        di as text "PTE Data Setup Summary"
        di as text "{hline 70}"

        di as text _n "Panel structure:" _col(30) as result "`idvar' `times_sign' `timevar'"
        di as text "Total observations:" _col(30) as result %12.0fc `N'
        di as text "Total firms:" _col(30) as result %12.0fc `N_g'
        di as text "Time span:" _col(30) as result "`t_min' - `t_max'"

        di as text _n "Treatment Summary:"
        di as text "  Treated firms:" _col(30) as result %12.0fc `N_treated' ///
           as text " (" as result %4.1f `pct_treated' as text "%)"
        di as text "  Control firms:" _col(30) as result %12.0fc `N_ctrl' ///
           as text " (" as result %4.1f `pct_ctrl' as text "%)"
        di as text "  Treatment type:" _col(30) as result "`trt_type'"
        di as text "  Transition obs:" _col(30) as result %12.0fc `N_trans' ///
           as text " (will be excluded)"

        if `n_cohorts' > 0 {
            di as text _n "Observed-Entry Treatment Cohorts:"
            forvalues i = 1/`n_cohorts' {
                local cohort_year = `cohort_years'[`i', 1]
                local cohort_n = `cohort_counts'[`i', 1]
                di as text "  Cohort `cohort_year':" _col(30) as result %12.0fc `cohort_n' ///
                   as text " firms"
            }
            di as text "  Total observed-entry cohorts:" _col(30) as result %12.0fc `n_cohorts'
        }

        if `N_timing_treated' > 0 {
            di as text _n "Treatment Timing (Observed-Entry Treated Group):"
            di as text "  Avg pre-treatment periods:" _col(30) as result %8.1f `avg_pre' ///
               as text " [" as result `min_pre' as text "-" as result `max_pre' as text "]"
            di as text "  Avg post-treatment periods:" _col(30) as result %8.1f `avg_post' ///
               as text " [" as result `min_post' as text "-" as result `max_post' as text "]"
        }

        di as text _n "Identification Check (Assumption 3.3):"

        di as text "  Stable untreated (D=L.D=0):" _col(30) as result %12.0fc `N_stable_0' _c
        if `N_stable_0' >= `minthreshold' {
            di as text " `check_mark'"
        }
        else {
            di as error " `cross_mark' (< `minthreshold')"
        }

        di as text "  Stable treated (D=L.D=1):" _col(30) as result %12.0fc `N_stable_1' _c
        if `N_stable_1' >= `minthreshold' {
            di as text " `check_mark'"
        }
        else {
            di as error " `cross_mark' (< `minthreshold')"
        }

        // Keep the setup-generated variables visible because later user-facing
        // commands refer to them indirectly rather than asking the user to
        // recreate them by hand.
        di as text _n "Variables created:"
        di as text "  _pte_treat_year" _col(20) "Observed treatment entry year"
        di as text "  _pte_nt" _col(20) "Relative time to observed entry"
        di as text "  _pte_mid" _col(20) "Transition period indicator"
        di as text "  _pte_treat" _col(20) "Ever-treated indicator"
        di as text "  _pte_cohort" _col(20) "Observed-entry cohort"

        di as text "{hline 70}"
    }

    return scalar N = `N'
    return scalar n_firms = `N_g'
    return scalar t_min = `t_min'
    return scalar t_max = `t_max'

    return scalar n_treated = `N_treated'
    return scalar n_control = `N_ctrl'
    return scalar pct_treated = `pct_treated'
    return scalar pct_control = `pct_ctrl'
    return scalar N_trans = `N_trans'
    return scalar N_treated_obs = `N_treated_obs'
    return scalar N_ctrl_obs = `N_ctrl_obs'

    return scalar n_cohorts = `n_cohorts'

    return scalar pre_periods = `avg_pre'
    return scalar post_periods = `avg_post'
    return scalar min_pre_periods = `min_pre'
    return scalar max_pre_periods = `max_pre'
    return scalar min_post_periods = `min_post'
    return scalar max_post_periods = `max_post'

    return scalar N_stable_0 = `N_stable_0'
    return scalar N_stable_1 = `N_stable_1'
    return scalar assumption_33_pass = `assumption_pass'
    return scalar assumption_33_threshold = `minthreshold'

    return local trt_type "`trt_type'"

    // Return matrices appear only when observed-entry cohorts exist, so
    // callers can distinguish "no cohort support" from a non-empty matrix of
    // zeros.
    if `n_cohorts' > 0 {
        return matrix cohort_years = `cohort_years'
        return matrix cohort_counts = `cohort_counts'
    }

end
