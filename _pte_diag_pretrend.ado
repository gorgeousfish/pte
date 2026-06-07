*! _pte_diag_pretrend.ado
*! Pre-treatment Trend Test (Event Study Regression)
*!
*! Tests whether treated firms exhibit parallel trends in omega
*! before treatment by running an event study regression on the
*! treated group only. Validates the parallel trends assumption.

version 14.0
program define _pte_diag_pretrend, rclass
    version 14.0
    syntax , [omega(varname) PREperiods(integer 4) Level(cilevel)]
    
    // =========================================================
    // 1. Validate prerequisites
    // =========================================================
    
    // Confirm the canonical treatment helper exists exactly. Shadow-only
    // leftovers from failed ATT reruns must not be accepted through Stata's
    // unique-abbreviation fallback.
    capture confirm variable _pte_treat, exact
    if _rc != 0 {
        di as error "Error: _pte_treat not found. Run pte_setup first."
        exit 111
    }
    _pte_validate_internal_state _pte_treat binary ///
        "Pre-trend diagnostics require the exact certified ever-treated indicator _pte_treat."
    
    // Determine omega variable
    if "`omega'" == "" {
        capture confirm variable _pte_omega, exact
        if _rc == 0 {
            local omega "_pte_omega"
        }
        else {
            di as error "Error: Specify omega() or ensure _pte_omega exists"
            exit 111
        }
        _pte_validate_internal_state _pte_omega numeric ///
            "Pre-trend diagnostics require the exact certified productivity series _pte_omega."
    }
    
    // Verify omega is numeric
    capture confirm numeric var `omega'
    if _rc != 0 {
        di as error "Error: `omega' must be numeric"
        exit 198
    }
    
    // Pre-trend uses the estimation panel contract, not the caller's current
    // xtset side state.
    _pte_diag_panel_contract, context("pretrend diagnostics") allowsetupmissingxtdelta
    local idvar = r(idvar)
    local timevar = r(timevar)

    if `preperiods' < 2 {
        di as error "Error: preperiods() must be at least 2"
        exit 198
    }
    
    // Confirm the exact event-time helper. Shadow variables such as
    // _pte_nt_shadow must never satisfy the ATT/pretrend contract.
    capture confirm variable _pte_nt, exact
    if _rc != 0 {
        di as error "Error: _pte_nt not found. Run pte_setup first."
        exit 111
    }
    _pte_validate_internal_state _pte_nt integer ///
        "Pre-trend diagnostics require the exact certified event-time index _pte_nt."
    
    // Count treated observations
    qui count if _pte_treat == 1
    if r(N) == 0 {
        di as error "Error: No treated observations found (_pte_treat == 1)"
        exit 2000
    }
    
    // Count pre-treatment observations for treated group
    qui count if _pte_treat == 1 & _pte_nt < 0
    if r(N) == 0 {
        di as error "Error: No pre-treatment observations for treated group"
        exit 2000
    }
    
    // =========================================================
    // 2. Filter sample
    // =========================================================
    
    preserve
    
    // Keep treated group, pre-treatment periods within window
    qui keep if _pte_treat == 1 & _pte_nt < 0 & _pte_nt >= -`preperiods'
    
    // Drop missing omega
    qui drop if missing(`omega')
    
    qui count
    local N_sample = r(N)
    
    if `N_sample' == 0 {
        di as error "Error: No observations after filtering"
        restore
        exit 2000
    }
    
    if `N_sample' < 10 {
        di as text "Warning: Only `N_sample' observations in pre-trend sample"
    }

    // A joint pretrend test needs the omitted base period (nt=-1) plus at
    // least one earlier treated event time inside the requested window.
    qui count if _pte_nt == -1
    local has_base_period = (r(N) > 0)
    qui count if _pte_nt <= -2
    local has_nonbase_period = (r(N) > 0)

    if !`has_base_period' | !`has_nonbase_period' {
        di as text _n "Pre-trend Test (Treated group only)"
        di as text "{hline 50}"
        di as text "H0: No differential pre-treatment trend in omega"
        di as text "Base period:    nt = -1"
        di as text "Periods tested: nt = -`preperiods' to -2"
        di as text "Observations:   `N_sample'"
        di as text ""
        di as text "Result: SKIPPED - insufficient treated pre-treatment event-time support"
        if !`has_base_period' {
            di as text "        Missing treated base period nt = -1 within preperiods(`preperiods')"
        }
        if !`has_nonbase_period' {
            di as text "        No treated periods nt <= -2 within preperiods(`preperiods')"
        }
        di as text "{hline 50}"

        return scalar pretrend_skipped = 1
        return scalar pretrend_pass = .
        return scalar F_pretrend = .
        return scalar p_pretrend = .
        return scalar df_pretrend = .
        return scalar df_r_pretrend = .
        return scalar N_pretrend = `N_sample'
        return scalar preperiods = `preperiods'
        restore
        exit
    }

    // The treated-only event-study test needs a base period (nt = -1) plus at
    // least one earlier treated pre-period inside the requested window.
    qui count if _pte_nt == -1
    local has_base_period = (r(N) > 0)
    qui count if _pte_nt <= -2
    local has_nonbase_period = (r(N) > 0)

    if !`has_base_period' | !`has_nonbase_period' {
        di as text _n "Pre-trend Test (Treated group only)"
        di as text "{hline 50}"
        di as text "Result: SKIPPED - insufficient treated pre-treatment support"
        if !`has_base_period' {
            di as text "  Missing base period nt = -1 within preperiods(`preperiods')"
        }
        if !`has_nonbase_period' {
            di as text "  No treated pre-period earlier than nt = -1 within preperiods(`preperiods')"
        }
        di as text "{hline 50}"

        return scalar F_pretrend = .
        return scalar p_pretrend = .
        return scalar df_pretrend = .
        return scalar df_r_pretrend = .
        return scalar pretrend_pass = .
        return scalar pretrend_skipped = 1
        return scalar N_pretrend = `N_sample'
        return scalar preperiods = `preperiods'

        restore
        exit
    }
    
    // =========================================================
    // 3. Event study regression (Pooled OLS, NO firm FE)
    // =========================================================
    
    // Stata factor variables require non-negative integers.
    // Recode _pte_nt (negative) to non-negative: nt_pos = _pte_nt + preperiods
    // e.g., preperiods=4: nt=-4 -> 0, nt=-3 -> 1, nt=-2 -> 2, nt=-1 -> 3
    // Base category: nt=-1 corresponds to nt_pos = preperiods - 1
    tempvar nt_pos
    qui gen int `nt_pos' = _pte_nt + `preperiods'
    local base_pos = `preperiods' - 1
    
    qui reg `omega' ib`base_pos'.`nt_pos', cluster(`idvar')
    
    local N_reg    = e(N)
    local r2_reg   = e(r2)
    local rmse_reg = e(rmse)
    local df_r_reg = e(df_r)
    
    // =========================================================
    // 4. Joint F-test on all non-base period coefficients
    // =========================================================
    
    qui testparm i.`nt_pos'
    
    local F_val  = r(F)
    local p_val  = r(p)
    local df_val = r(df)
    local df_r_val = r(df_r)
    
    // =========================================================
    // 5. Extract per-period coefficients
    // =========================================================
    
    // Count number of non-base coefficients (from -preperiods to -2)
    // In recoded terms: positions 0 to (preperiods-2), base = preperiods-1
    local ncoefs = `preperiods' - 1
    
    // Create coefficient matrix: ncoefs x 4 (coef, se, t, p)
    tempname pretrend_coefs
    matrix `pretrend_coefs' = J(`ncoefs', 4, .)
    
    local row = 1
    forvalues j = -`preperiods'(1)-2 {
        // Map original nt value to recoded position
        local j_pos = `j' + `preperiods'
        
        local coef = _b[`j_pos'.`nt_pos']
        local se   = _se[`j_pos'.`nt_pos']
        local t_stat = `coef' / `se'
        local p_coef = 2 * ttail(`df_r_reg', abs(`t_stat'))
        
        matrix `pretrend_coefs'[`row', 1] = `coef'
        matrix `pretrend_coefs'[`row', 2] = `se'
        matrix `pretrend_coefs'[`row', 3] = `t_stat'
        matrix `pretrend_coefs'[`row', 4] = `p_coef'
        
        local row = `row' + 1
    }
    
    // Label rows and columns
    local rownames ""
    forvalues j = -`preperiods'(1)-2 {
        local absj = abs(`j')
        local rownames "`rownames' nt_m`absj'"
    }
    matrix rownames `pretrend_coefs' = `rownames'
    matrix colnames `pretrend_coefs' = coef se t p
    
    // =========================================================
    // 6. PASS/FAIL judgment
    // =========================================================
    
    local alpha = 1 - `level' / 100
    
    local pretrend_pass = 0
    if `p_val' >= `alpha' {
        local pretrend_pass = 1
    }
    
    // =========================================================
    // 7. Display output
    // =========================================================
    
    di as text _n "Pre-trend Test (Treated group only)"
    di as text "{hline 50}"
    di as text "H0: No differential pre-treatment trend in omega"
    di as text "Base period:    nt = -1"
    di as text "Periods tested: nt = -`preperiods' to -2"
    di as text "Observations:   `N_reg'"
    di as text "Clusters:       " `df_r_reg' + 1
    di as text "{hline 50}"
    
    // Display per-period coefficients
    di as text ""
    di as text "  Period     Coef.      Std.Err.     t       p"
    di as text "  {hline 46}"
    
    local row = 1
    forvalues j = -`preperiods'(1)-2 {
        local c  = `pretrend_coefs'[`row', 1]
        local s  = `pretrend_coefs'[`row', 2]
        local tv = `pretrend_coefs'[`row', 3]
        local pv = `pretrend_coefs'[`row', 4]
        di as text "  nt=`j'" _col(14) %9.4f `c' _col(26) %9.4f `s' _col(38) %7.3f `tv' _col(48) %6.4f `pv'
        local row = `row' + 1
    }
    
    di as text "  {hline 46}"
    di as text "  Base: nt = -1 (omitted)"
    
    // Display joint F-test
    di as text ""
    di as text "Joint F-test:"
    di as text "  F(" %3.0f `df_val' ", " %6.0f `df_r_val' ") = " %8.4f `F_val'
    di as text "  Prob > F         = " %8.4f `p_val'
    
    // Display PASS/FAIL
    di as text ""
    if `pretrend_pass' == 1 {
        di as result "Result: PASS - No significant pre-treatment trend (p = " %6.4f `p_val' ")"
    }
    else {
        di as error "Result: FAIL - Significant pre-treatment trend detected (p = " %6.4f `p_val' ")"
        di as error "        Parallel trends assumption may be violated"
    }
    di as text "{hline 50}"
    
    // =========================================================
    // 8. Store return values
    // =========================================================
    
    return scalar F_pretrend    = `F_val'
    return scalar p_pretrend    = `p_val'
    return scalar df_pretrend   = `df_val'
    return scalar df_r_pretrend = `df_r_val'
    return scalar pretrend_skipped = 0
    return scalar pretrend_pass = `pretrend_pass'
    return scalar pretrend_skipped = 0
    return scalar N_pretrend    = `N_reg'
    return scalar preperiods    = `preperiods'
    return matrix pretrend_coefs = `pretrend_coefs'
    
    // =========================================================
    // 9. Restore
    // =========================================================
    
    restore
    
end
