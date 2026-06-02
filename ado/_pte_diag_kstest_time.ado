*! _pte_diag_kstest_time.ado
*! K-S Time Stability Test for eps0
*!
*! Tests whether the distribution of eps0 (productivity shocks)
*! is stable over time by splitting at a reference year and
*! running a two-sample K-S test. Validates Assumption 4.3 (iid).

version 14.0
program define _pte_diag_kstest_time, rclass
    version 14.0
    syntax , [eps0(varname) REPlicate(integer 0) STRICTcontrol]
    
    // =========================================================
    // 1. Variable validation
    // =========================================================
    
    // Determine eps0 variable
    if "`eps0'" == "" {
        capture confirm variable _pte_eps0, exact
        if _rc == 0 {
            local eps0 "_pte_eps0"
        }
        else {
            di as error "Error: Specify eps0() or ensure _pte_eps0 exists"
            exit 111
        }
    }
    
    // Verify eps0 is numeric
    capture confirm numeric var `eps0'
    if _rc != 0 {
        di as error "Error: `eps0' must be numeric"
        exit 198
    }

    quietly _pte_diag_eps0_support_if, epsvar(`eps0') ///
        context("time stability K-S diagnostics")
    local eps0_sample_if `"`r(sample_if)'"'
    
    // Verify _pte_treat exists
    capture confirm variable _pte_treat, exact
    if _rc != 0 {
        di as error "Error: _pte_treat not found. Run pte_setup first."
        exit 111
    }
    _pte_validate_internal_state _pte_treat binary ///
        "Time stability K-S diagnostics require _pte_treat to remain the certified binary ever-treated indicator."
    
    // Match the shared diagnostics contract: use stored estimation-time
    // panel/time metadata when available, and only fall back to the current
    // xtset when no stored contract exists.
    _pte_diag_panel_contract, context("time stability K-S diagnostics") allowsetupmissingxtdelta
    local idvar = r(idvar)
    local timevar = r(timevar)
    
    // =========================================================
    // 2. Initialize return values and output title
    // =========================================================
    
    local time_stability_skipped = 0
    local time_stability_fallback = 0
    local sample_type "never_treated"
    local ks_D_time = .
    local ks_p_time = .
    local mid_year = .
    local n_early = 0
    local n_late = 0
    
    di as text _n "K-S Test 2: Temporal Stability of eps0"
    di as text "{hline 50}"
    di as text "H0: Same shock distribution before and after mid_year"
    
    // =========================================================
    // 3. Sample selection
    // =========================================================
    
    tempvar sample
    gen byte `sample' = 0
    
    // Count never-treated observations
    qui count if _pte_treat == 0 & `eps0_sample_if'
    local n_never_treated = r(N)
    
    if `n_never_treated' >= 30 {
        // Normal path: use never-treated only
        qui replace `sample' = (_pte_treat == 0) & `eps0_sample_if'
        local sample_type "never_treated"
        di as text "(Tested in never-treated group only, N = `n_never_treated')"
    }
    else if "`strictcontrol'" == "" {
        // Fallback: use all D=0 observations
        di as text "Note: Never-treated sample (`n_never_treated') < 30"
        di as text "      Falling back to all D=0 observations"
        
        capture confirm variable _pte_D, exact
        if _rc != 0 {
            di as error "Error: _pte_D not found for fallback"
            local time_stability_skipped = 1
        }
        else {
            _pte_validate_internal_state _pte_D binary ///
                "Time stability K-S fallback requires _pte_D to remain the certified binary current-treatment indicator."
            qui replace `sample' = (_pte_D == 0) & `eps0_sample_if'
            local time_stability_fallback = 1
            local sample_type "all_d0"
            
            qui count if `sample'
            local n_fallback = r(N)
            di as text "      Using `n_fallback' D=0 observations"
            
            if `n_fallback' < 30 {
                di as text "      Still insufficient (<30). Skipping."
                local time_stability_skipped = 1
            }
        }
    }
    else {
        // strictcontrol: skip
        di as text "Note: Never-treated sample (`n_never_treated') < 30"
        di as text "      Skipping time stability test (strictcontrol enabled)"
        local time_stability_skipped = 1
    }
    
    // =========================================================
    // 4. Time splitting
    // =========================================================
    
    if `time_stability_skipped' == 0 {
        if `replicate' != 0 {
            local mid_year = `replicate'
            di as text "Reference year: `mid_year' (replicate mode, split at year >= " ///
                %4.0f (`mid_year' + 1) ")"
        }
        else {
            qui summ `timevar' if `sample'
            local min_year = r(min)
            local max_year = r(max)
            local mid_year = floor((`min_year' + `max_year') / 2)
            di as text "Reference year: `mid_year' (mid_year, split at year >= " ///
                %4.0f (`mid_year' + 1) ")"
        }
        
        // Check time span
        qui summ `timevar' if `sample'
        local time_span = r(max) - r(min)
        if `time_span' < 2 {
            di as text "Warning: Time span (`time_span' years) < 2"
            di as text "         Cannot perform time stability test"
            local time_stability_skipped = 1
        }
    }
    
    // =========================================================
    // 5. K-S test execution
    // =========================================================
    
    if `time_stability_skipped' == 0 {
        // Create time group variable
        tempvar time_group
        gen byte `time_group' = (`timevar' >= `mid_year' + 1) if `sample'
        
        // Count group sizes
        qui count if `sample' & `time_group' == 0
        local n_early = r(N)
        qui count if `sample' & `time_group' == 1
        local n_late = r(N)
        
        di as text "N_early (year <= `mid_year') = `n_early'"
        di as text "N_late  (year >= " %4.0f (`mid_year' + 1) ") = `n_late'"
        
        if `n_early' < 15 | `n_late' < 15 {
            di as text "Insufficient observations (need >= 15 each)"
            local time_stability_skipped = 1
        }
    }
    
    if `time_stability_skipped' == 0 {
        // Execute K-S test
        qui ksmirnov `eps0' if `sample', by(`time_group')
        local ks_D_time = r(D)
        local ks_p_time = r(p)
        
        di as text "D = " %8.4f `ks_D_time'
        di as text "Prob > D = " %8.4f `ks_p_time'
        
        // PASS/FAIL judgment
        if `ks_p_time' < 0.05 {
            di as error "Result: FAIL - Distribution unstable over time"
            di as error "        Assumption 4.3 (iid) may be violated"
        }
        else {
            di as text "Result: PASS - No significant temporal variation"
        }
    }
    else {
        di as text "Result: SKIPPED (insufficient data)"
    }
    
    di as text "{hline 50}"
    
    // =========================================================
    // 6. Return values
    // =========================================================
    
    return scalar ks_D_time = `ks_D_time'
    return scalar ks_p_time = `ks_p_time'
    return scalar mid_year = `mid_year'
    if `replicate' != 0 {
        return scalar replicate_year = `replicate'
    }
    return scalar n_early = `n_early'
    return scalar n_late = `n_late'
    return scalar time_stability_skipped = `time_stability_skipped'
    return scalar time_stability_fallback = `time_stability_fallback'
    return local sample_type "`sample_type'"
    
end
