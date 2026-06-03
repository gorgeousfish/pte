*! _pte_check_assumption33.ado
*! Assumption 3.3 data requirement validation
*! Validates consecutive untreated/treated observations exist

version 14.0
capture program drop _pte_check_assumption33
program define _pte_check_assumption33, rclass
    version 14.0

    // =========================================================================
    // Task 2: Parse syntax - treatment variable + options
    // =========================================================================
    syntax name(name=treatment) [, Verbose MINthreshold(integer 30) NONFatal QUIETly]
    local minthreshold = `minthreshold'
    local assumption33_passed = 1

    // =========================================================================
    // Task 1: Panel setup verification
    // =========================================================================
    local pte_had_xtset 0
    local pte_setup_xtset_sw 0

    // Check xtset is configured, or use the dataset-scoped setup contract
    // published by pte_setup for the same treatment law / canonical helper.
    capture qui xtset
    if _rc != 0 {
        local setup_panel : char _dta[_pte_setup_panelvar]
        local setup_time : char _dta[_pte_setup_timevar]
        local setup_treatment : char _dta[_pte_setup_treatment]
        local setup_xtdelta : char _dta[_pte_setup_xtdelta]
        if "`setup_panel'" != "" & "`setup_time'" != "" & ///
            "`setup_treatment'" != "" & ///
            ("`treatment'" == "`setup_treatment'" | "`treatment'" == "_pte_D") {
            local setup_delta_opt ""
            if "`setup_xtdelta'" != "" {
                local setup_delta_opt "delta(`setup_xtdelta')"
            }
            capture quietly xtset `setup_panel' `setup_time', `setup_delta_opt'
            if _rc == 0 {
                local pte_setup_xtset_sw 1
            }
        }
        if !`pte_setup_xtset_sw' {
            display as error "panel data not set; use {bf:xtset panelvar timevar}"
            exit 459
        }
    }
    else {
        local pte_had_xtset 1
    }
    
    // Re-run to capture r() values (capture clears them)
    qui xtset

    local panelvar "`r(panelvar)'"
    local timevar  "`r(timevar)'"

    if "`panelvar'" == "" | "`timevar'" == "" {
        display as error "panel data not fully set; use {bf:xtset panelvar timevar}"
        exit 459
    }

    // Check at least 2 time periods
    qui summarize `timevar'
    local t_min = r(min)
    local t_max = r(max)
    if (`t_max' - `t_min') < 1 {
        display as error "at least 2 time periods required for Assumption 3.3"
        exit 459
    }

    // =========================================================================
    // Task 2 (cont): Treatment variable existence verification
    // =========================================================================
    capture confirm variable `treatment', exact
    if _rc != 0 {
        display as error "treatment variable {bf:`treatment'} not found"
        exit 111
    }

    capture confirm numeric variable `treatment'
    if _rc != 0 {
        display as error "treatment variable {bf:`treatment'} not found or not numeric"
        exit 111
    }

    // =========================================================================
    // Task 3: Binary defensive assertion
    // =========================================================================
    qui count if !mi(`treatment') & !inlist(`treatment', 0, 1)
    if r(N) > 0 {
        display as error "treatment variable {bf:`treatment'} must be binary (0/1)"
        display as error "found `=r(N)' non-binary observations"
        exit 450
    }

    // =========================================================================
    // Task 4: Count consecutive untreated (D_t = D_{t-1} = 0)
    // =========================================================================
    qui count if `treatment' == 0 & L.`treatment' == 0
    local n_stable_0 = r(N)

    // =========================================================================
    // Task 5: Count consecutive treated (D_t = D_{t-1} = 1)
    // =========================================================================
    qui count if `treatment' == 1 & L.`treatment' == 1
    local n_stable_1 = r(N)

    // =========================================================================
    // Task 6: Transition and first-period statistics
    // =========================================================================
    // Transition in (0 -> 1)
    qui count if `treatment' == 1 & L.`treatment' == 0
    local n_trans_in = r(N)

    // Transition out (1 -> 0) - non-absorbing case
    qui count if `treatment' == 0 & L.`treatment' == 1
    local n_trans_out = r(N)

    local n_transition = `n_trans_in' + `n_trans_out'

    // First period observations (no lag available)
    qui count if missing(L.`treatment')
    local n_first = r(N)

    // Valid observations (excluding first period)
    local n_valid = `n_stable_0' + `n_stable_1' + `n_transition'

    if `n_valid' > 0 {
        local pct_transition = 100 * `n_transition' / `n_valid'
    }
    else {
        local pct_transition = .
    }

    // =========================================================================
    // Task 7a: Condition (i) - consecutive untreated must exist
    // =========================================================================
    if `n_stable_0' == 0 {
        local assumption33_passed = 0
        if "`quietly'" == "" {
            display as error "{hline 50}"
            display as error "Assumption 3.3 violated - no consecutive untreated observations"
            display as error "{hline 50}"
            display as error ""
            display as error "Identification requires Pr(D_t = D_{t-1} = 0) > 0"
            display as error "needed to identify evolution function h_bar_0"
            display as error "(Theorem 3.1, moment condition (8))"
            display as error ""
            display as error "Possible causes:"
            display as error "  - All units are treated in all periods"
            display as error "  - Treatment variable is constant within panels"
            display as error "  - Insufficient time periods"
            display as error ""
            display as error "Suggestions:"
            display as error "  - Verify treatment variable coding (must be 0/1)"
            display as error "  - Check panel structure with {bf:xtdescribe}"
            display as error "  - Ensure data contains untreated spells of length >= 2"
        }
        if "`nonfatal'" == "" {
            if `pte_setup_xtset_sw' & !`pte_had_xtset' {
                capture quietly xtset, clear
            }
            exit 2001
        }
    }

    // =========================================================================
    // Task 7b: Condition (ii) - consecutive treated must exist
    // =========================================================================
    if `n_stable_1' == 0 {
        local assumption33_passed = 0
        if "`quietly'" == "" {
            display as error "{hline 50}"
            display as error "Assumption 3.3 violated - no consecutive treated observations"
            display as error "{hline 50}"
            display as error ""
            display as error "Identification requires Pr(D_t = D_{t-1} = 1) > 0"
            display as error "needed to identify evolution function h_bar_1"
            display as error "(Theorem 3.1, moment condition (9))"
            display as error ""
            display as error "Possible causes:"
            display as error "  - No units remain treated for consecutive periods"
            display as error "  - Treatment is transitory (single-period)"
            display as error "  - Insufficient post-treatment observations"
            display as error ""
            display as error "Suggestions:"
            display as error "  - Verify treatment timing and duration"
            display as error "  - Check panel structure with {bf:xtdescribe}"
            display as error "  - Ensure data contains treated spells of length >= 2"
        }
        if "`nonfatal'" == "" {
            if `pte_setup_xtset_sw' & !`pte_had_xtset' {
                capture quietly xtset, clear
            }
            exit 2002
        }
    }

    // =========================================================================
    // Task 8: Sample size warnings (strict <, not <=)
    // =========================================================================
    if "`quietly'" == "" & `n_stable_0' > 0 & `n_stable_0' < `minthreshold' {
        display as text ""
        display as text "Warning: few consecutive untreated observations (`n_stable_0')"
        display as text "  h_bar_0 estimation precision may be affected"
        display as text "  Consider pooling across industries if possible"
        display as text ""
    }

    if "`quietly'" == "" & `n_stable_1' > 0 & `n_stable_1' < `minthreshold' {
        display as text ""
        display as text "Warning: few consecutive treated observations (`n_stable_1')"
        display as text "  h_bar_1 estimation precision may be affected"
        display as text "  Consider using longer post-treatment observation window"
        display as text ""
    }

    // =========================================================================
    // Task 10: Verbose output
    // =========================================================================
    if "`verbose'" != "" & "`quietly'" == "" {
        display ""
        display as text "{hline 50}"
        if `assumption33_passed' {
            display as result "  Assumption 3.3 Verification: PASSED"
        }
        else {
            display as error "  Assumption 3.3 Verification: FAILED"
        }
        display as text "{hline 50}"
        display ""
        display as text "  {bf:Sample Classification}"
        display as text "  {hline 46}"
        display as text "    Consecutive untreated (D=D_lag=0):" ///
            as result %8.0fc `n_stable_0' as text "  {c +}"
        display as text "    Consecutive treated   (D=D_lag=1):" ///
            as result %8.0fc `n_stable_1' as text "  {c +}"
        display ""
        display as text "  {bf:Transition Periods}"
        display as text "  {hline 46}"
        display as text "    Transitions in  (0 -> 1):         " ///
            as result %8.0fc `n_trans_in'
        display as text "    Transitions out (1 -> 0):         " ///
            as result %8.0fc `n_trans_out'
        display as text "    Total transitions:                " ///
            as result %8.0fc `n_transition'
        display as text "    Transition share:                 " ///
            as result %7.2f `pct_transition' as text "%"
        display ""
        display as text "  {bf:Other}"
        display as text "  {hline 46}"
        display as text "    First-period obs (no lag):        " ///
            as result %8.0fc `n_first'
        display as text "    Valid obs (excl. first period):   " ///
            as result %8.0fc `n_valid'
        display as text "{hline 50}"
        display ""
    }

    // =========================================================================
    // Task 9: Return r() values
    // =========================================================================
    return scalar n_stable_0       = `n_stable_0'
    return scalar n_stable_1       = `n_stable_1'
    return scalar n_transition     = `n_transition'
    return scalar n_trans_in       = `n_trans_in'
    return scalar n_trans_out      = `n_trans_out'
    return scalar n_first_period   = `n_first'
    return scalar n_valid          = `n_valid'
    return scalar pct_transition   = `pct_transition'
    return scalar assumption33_passed = `assumption33_passed'
    return scalar minthreshold     = `minthreshold'
    return local  treatment          "`treatment'"
    return local  panelvar           "`panelvar'"
    return local  timevar            "`timevar'"

    if `pte_setup_xtset_sw' & !`pte_had_xtset' {
        capture quietly xtset, clear
    }

end
