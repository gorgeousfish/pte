*! _pte_multiswitch.ado
*! Diagnose repeated treatment switching and optionally trim the sample.
*! This helper assumes upstream code has already generated the switch indicator
*! G in {-1,0,1} and the episode anchors _last_entry_yr / _last_exit_yr. It
*! never estimates effects itself; it only checks whether the realized panel
*! provides a credible persistent-switch design for Appendix C style ATT+/ATT-.
*! Returns (rclass):
*! r(max_switch_observed)  maximum switches per firm in the live sample
*! r(N_never_switch)       firms with 0 switches
*! r(N_once_switch)        firms with exactly 1 switch
*! r(N_few_switch)         firms with 2-3 switches
*! r(N_frequent_switch)    firms with more than 3 switches
*! r(pct_frequent)         share of frequent switchers before filtering
*! r(n_dropped)            rows dropped by firstswitchonly
*! r(n_excluded_firms)     firms excluded by maxswitch()
*! r(warning_triggered)    1 when the warning path was activated

version 14.0
capture program drop _pte_multiswitch
program define _pte_multiswitch, rclass
    version 14.0

    syntax, FIRMvar(varname) TIMEvar(varname) ///
        [ATTperiods(integer 3) PERSISTperiods(integer 0) ///
         FIRSTswitchonly MAXswitch(integer -1) ///
         NOCheck Verbose]

    // The non-absorbing helpers downstream treat G as the canonical switch
    // map, so fail fast if the required state variables are missing.
    confirm variable G
    qui assert inlist(G, -1, 0, 1) | missing(G)
    confirm variable _last_entry_yr
    confirm variable _last_exit_yr

    if "`verbose'" != "" {
        di as text "[debug] _pte_multiswitch: preconditions verified"
    }

    // Sorting is a side effect: later cumulative counts depend on the current
    // row order being a unique firm-time panel.
    sort `firmvar' `timevar'
    qui by `firmvar' `timevar': assert _N == 1

    // n_switch is cumulative within firm. Recompute it even if the variable
    // already exists so repeated calls stay aligned with the current sample.
    capture confirm numeric variable n_switch
    if _rc == 0 {
        bys `firmvar' (`timevar'): replace n_switch = sum(G != 0)
    }
    else {
        bys `firmvar' (`timevar'): gen int n_switch = sum(G != 0)
    }

    // The first row has no prior history, so its cumulative switch count must
    // be zero regardless of the current treatment state.
    bys `firmvar' (`timevar'): assert n_switch == 0 if _n == 1

    if "`verbose'" != "" {
        di as text "[debug] n_switch computed, range: " ///
            _col(50) "see summary below"
    }

    // max_switch is the firm-level volatility summary used by all later
    // warnings and trimming rules.
    capture drop max_switch
    bys `firmvar': egen max_switch = max(n_switch)

    // egen max() should be constant within firm; if not, the panel ordering or
    // cumulative counter was corrupted upstream.
    bys `firmvar': assert max_switch == max_switch[1]

    // Report the unfiltered distribution first because the warning threshold is
    // meant to describe the raw switching environment faced by the estimator.
    di as text _n "Computing switching statistics..."
    qui summ max_switch, detail
    local max_obs = r(max)
    local p50 = r(p50)
    local p75 = r(p75)
    di as text "  Maximum switches per firm: " as result `max_obs'
    di as text "  Median: " as result `p50'
    di as text "  75th percentile: " as result `p75'

    // The categories are coarse diagnostics, not separate estimands.
    capture drop switch_category
    gen switch_category = 1 if max_switch == 0
    replace switch_category = 2 if max_switch == 1
    replace switch_category = 3 if max_switch >= 2 & max_switch <= 3
    replace switch_category = 4 if max_switch > 3

    // Every retained row inherits its firm's category.
    assert !missing(switch_category)
    assert inlist(switch_category, 1, 2, 3, 4)

    capture label drop switch_cat_lbl
    label define switch_cat_lbl ///
        1 "Never switch" ///
        2 "Single switch" ///
        3 "2-3 switches" ///
        4 "Frequent (>3)"
    label values switch_category switch_cat_lbl

    // Frequent switching makes it harder to find firms that keep the new
    // status for the l periods required by the persistent ATT definition.
    local pct_frequent = 0
    local n_frequent = 0
    local n_total_firms = 0

    if `max_obs' > 3 {
        // Count each firm once when computing the headline frequency.
        tempvar _one_obs_warn
        bys `firmvar': gen `_one_obs_warn' = (_n == 1)
        qui count if `_one_obs_warn' == 1 & max_switch > 3
        local n_frequent = r(N)
        qui count if `_one_obs_warn' == 1
        local n_total_firms = r(N)
        local pct_frequent = round(100 * `n_frequent' / `n_total_firms', 0.1)

        // The warning explains why repeated switching threatens the support
        // conditions behind persistent-switch comparisons.
        di as text _n "{hline 70}"
        di as error "{bf:Warning: Frequent treatment switching detected}"
        di as text "{hline 70}"
        di as text "  Maximum switches per firm: " as result `max_obs'
        di as text "  75th percentile: " as result `p75'
        di as text _n "  Firms with >3 switches: " as result `n_frequent' ///
                   as text " (" as result "`pct_frequent'%" as text " of sample)"

        di as text _n "  {bf:Theoretical concern}:"
        di as text "    Frequent switching violates Assumption C.2"
        di as text "    (control group availability)"
        di as text "    See Chen, Liao & Schurter (2026) Appendix C.3"

        di as text _n "  {bf:Recommendations}:"
        di as text "    1. Use first_switch_only option"
        di as text "    2. Increase persistperiods() to require longer stability"
        if `persistperiods' < `attperiods' {
            di as text "       [Current: persistperiods(`persistperiods')," ///
                       " recommend: persistperiods(`attperiods')]"
        }
        di as text "    3. Use maxswitch(#) to exclude frequent switchers"
        di as text "    4. Report switching patterns in your analysis"

        // Severity escalates at inclusive thresholds so the warning is stable
        // at the exact boundary values.
        if `pct_frequent' >= 30 {
            di as error _n "  STRONG WARNING: `pct_frequent'% firms are frequent switchers"
            di as error "     Estimation results may not be theoretically valid"
            di as error "     Strongly recommend using first_switch_only or maxswitch()"
        }
        else if `pct_frequent' >= 10 {
            di as text _n "  Note: `pct_frequent'% firms are frequent switchers"
            di as text "        Consider robustness checks with first_switch_only"
        }

        di as text "{hline 70}" _n

        // more pauses only in interactive mode; batch runs must use nocheck.
        if "`nocheck'" == "" {
            di as text "Press any key to continue, or Ctrl+C to abort"
            more
        }
        else {
            di as text "Option nocheck: Proceeding without user confirmation"
        }
    }
    else {
        di as text "  No frequent switching detected (max_switch <= 3)"
        // Still count firms for r() returns even when the warning path is off.
        tempvar _one_obs_nw
        bys `firmvar': gen `_one_obs_nw' = (_n == 1)
        qui count if `_one_obs_nw' == 1
        local n_total_firms = r(N)
    }

    // firstswitchonly keeps a single switch episode per firm so later ATT+/ATT-
    // logic is not contaminated by subsequent reversals.
    local n_dropped_fso = 0

    if "`firstswitchonly'" != "" {
        di as text _n "Option first_switch_only: Restricting to first switch per firm"

        // Keep the lag row before the first switch, the first switch itself,
        // and the stable continuation before any second switch. Later switches
        // belong to different treatment episodes and are discarded here.
        tempvar _pte_switch_seq _pte_first_switch_yr _pte_first_switch _pte_second_switch_yr _pte_second_switch
        tempvar _first_entry_yr _first_exit_yr _first_entry _first_exit _keep

        bys `firmvar' (`timevar'): gen int `_pte_switch_seq' = sum(G != 0)
        bys `firmvar' (`timevar'): gen double `_pte_first_switch_yr' = `timevar' ///
            if G != 0 & `_pte_switch_seq' == 1
        bys `firmvar': egen double `_pte_first_switch' = min(`_pte_first_switch_yr')
        bys `firmvar': egen double `_pte_second_switch_yr' = min(cond(G != 0 & `_pte_switch_seq' == 2, `timevar', .))
        bys `firmvar': egen double `_pte_second_switch' = min(`_pte_second_switch_yr')

        // Track the sign of the first switch so relative time is re-anchored to
        // the correct first episode only.
        bys `firmvar' (`timevar'): gen double `_first_entry_yr' = `timevar' ///
            if G == 1 & `_pte_switch_seq' == 1
        bys `firmvar': egen double `_first_entry' = min(`_first_entry_yr')

        bys `firmvar' (`timevar'): gen double `_first_exit_yr' = `timevar' ///
            if G == -1 & `_pte_switch_seq' == 1
        bys `firmvar': egen double `_first_exit' = min(`_first_exit_yr')

        // Proposition C.3 uses omega_{g-1} as the anchor, so first-switch
        // filtering must preserve the lag row (nt = -1) while excluding the
        // second switch and anything after it.
        gen byte `_keep' = 0
        replace `_keep' = 1 if `timevar' >= (`_pte_first_switch' - 1) ///
            & !missing(`_pte_first_switch') ///
            & (missing(`_pte_second_switch') | `timevar' < `_pte_second_switch')
        // Keep all obs for firms that never switched
        replace `_keep' = 1 if missing(`_pte_first_switch')

        // Filtering is destructive by design because downstream estimators work
        // on the live dataset after this diagnostic pass.
        qui count if `_keep' == 0
        local n_dropped_fso = r(N)
        di as text "  Dropped " as result `n_dropped_fso' ///
                   as text " observations from subsequent switches"

        qui keep if `_keep' == 1
        di as text "  Remaining observations: " as result _N

        // Re-anchor relative event time to the retained first episode so ATT+
        // and ATT- helpers read the same event clock after trimming.
        capture confirm variable nt_plus
        if _rc == 0 {
            di as text "  Redefining nt_plus and nt_minus based on first switch"
            drop nt_plus nt_minus

            // The retained episode includes the lag row g-1, so define event
            // time directly from the first-entry / first-exit anchor.
            gen nt_plus = `timevar' - `_first_entry' if !missing(`_first_entry')
            gen nt_minus = `timevar' - `_first_exit' if !missing(`_first_exit')

            // nt = -1 is the simulation starting point for persistent effects.
            qui count if nt_plus == -1
            local n_nt_m1_plus = r(N)
            qui count if nt_minus == -1
            local n_nt_m1_minus = r(N)

            if `n_nt_m1_plus' == 0 & `n_nt_m1_minus' == 0 {
                di as error "  Warning: No nt=-1 observations after redefinition"
                di as error "           Simulation may lack proper starting points"
            }
            else {
                di as text "  nt=-1 preserved: ATT+ n=" ///
                    as result `n_nt_m1_plus' ///
                    as text ", ATT- n=" as result `n_nt_m1_minus'
            }
        }
        else {
            di as text "  Note: nt_plus/nt_minus not found, skipping redefinition"
        }
    }

    // maxswitch() trims firms whose treatment path is too volatile for the
    // intended persistent-switch design.
    local n_excluded_firms = 0
    local n_dropped_ms = 0

    if `maxswitch' >= 0 {
        if `maxswitch' == 0 {
            di as text _n "Warning: maxswitch(0) keeps only firms that never switch"
            di as text "         This disables the switching feature"
        }

        di as text _n "Option maxswitch(`maxswitch'): " ///
            "Excluding firms with >`maxswitch' switches"

        // Count firms and rows separately because the user-facing report needs
        // both the economic unit and the observation loss.
        tempvar _one_obs_ms
        bys `firmvar': gen `_one_obs_ms' = (_n == 1)
        qui count if `_one_obs_ms' == 1 & max_switch > `maxswitch'
        local n_excluded_firms = r(N)
        qui count if max_switch > `maxswitch'
        local n_dropped_ms = r(N)

        qui keep if max_switch <= `maxswitch'

        di as text "  Excluded " as result `n_excluded_firms' ///
            as text " firms with >`maxswitch' switches"
        di as text "  Dropped " as result `n_dropped_ms' as text " observations"
        di as text "  Remaining observations: " as result _N

        // A tiny post-filter sample invalidates the downstream estimator even
        // if the switching pattern looks cleaner.
        qui count
        if r(N) < 50 {
            di as error "Error: Sample too small after maxswitch exclusion" ///
                " (N=" r(N) ")"
            di as error "       Cannot proceed with estimation"
            exit 2001
        }
    }

    // Refresh the live-sample maximum after any filtering so r(max_switch_observed)
    // describes the dataset that remains in memory.
    qui summ max_switch, meanonly
    local max_obs_live = r(max)

    // Publish a firm-level summary that later helpers can consume without
    // reconstructing the switching diagnostics.
    tempvar _one_obs_ret
    bys `firmvar': gen `_one_obs_ret' = (_n == 1)

    qui count if `_one_obs_ret' == 1 & switch_category == 1
    return scalar N_never_switch = r(N)
    qui count if `_one_obs_ret' == 1 & switch_category == 2
    return scalar N_once_switch = r(N)
    qui count if `_one_obs_ret' == 1 & switch_category == 3
    return scalar N_few_switch = r(N)
    qui count if `_one_obs_ret' == 1 & switch_category == 4
    return scalar N_frequent_switch = r(N)

    return scalar max_switch_observed = `max_obs_live'
    return scalar pct_frequent = `pct_frequent'
    return scalar warning_triggered = (`max_obs' > 3)

    if "`firstswitchonly'" != "" {
        return scalar n_dropped = `n_dropped_fso'
        return local first_switch_only "yes"
    }
    else {
        return scalar n_dropped = 0
        return local first_switch_only "no"
    }

    if `maxswitch' >= 0 {
        return scalar n_excluded_firms = `n_excluded_firms'
        return scalar n_dropped_maxswitch = `n_dropped_ms'
    }

    if "`verbose'" != "" {
        di as text "[debug] _pte_multiswitch: completed successfully"
    }

end
