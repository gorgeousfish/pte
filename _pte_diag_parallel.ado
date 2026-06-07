*! _pte_diag_parallel.ado
*! Parallel Trends Test (DID-style Treatment x Time Interaction)
*!
*! Tests whether treated and control groups exhibit parallel trends
*! in omega before treatment using a DID-style interaction regression.
*! Unlike _pte_diag_pretrend (treated-only), this tests BOTH groups
*! via treatment x relative-time interaction terms.

version 14.0
program define _pte_diag_parallel, rclass
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
        "Parallel diagnostics require the exact certified ever-treated indicator _pte_treat."
    
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
            "Parallel diagnostics require the exact certified productivity series _pte_omega."
    }
    
    // Verify omega is numeric
    capture confirm numeric var `omega'
    if _rc != 0 {
        di as error "Error: `omega' must be numeric"
        exit 198
    }
    
    // Parallel diagnostics must consume the same panel/time contract that
    // generated the stored setup helpers, not the caller's current xtset.
    _pte_diag_panel_contract, context("parallel diagnostics") allowsetupmissingxtdelta
    local idvar = r(idvar)
    local timevar = r(timevar)
    
    // Confirm the exact event-time helper. Shadow variables such as
    // _pte_nt_shadow must never satisfy the ATT/pretrend contract.
    capture confirm variable _pte_nt, exact
    if _rc != 0 {
        di as error "Error: _pte_nt not found. Run pte_setup first."
        exit 111
    }
    _pte_validate_internal_state _pte_nt integer ///
        "Parallel diagnostics require the exact certified event-time index _pte_nt."
    
    // Count treated observations
    qui count if _pte_treat == 1
    if r(N) == 0 {
        di as error "Error: No treated observations found (_pte_treat == 1)"
        exit 2000
    }
    
    // Count control observations
    qui count if _pte_treat == 0
    if r(N) == 0 {
        di as error "Error: No control observations found (_pte_treat == 0)"
        exit 2000
    }
    
    // Count pre-treatment observations for treated group
    qui count if _pte_treat == 1 & _pte_nt < 0
    if r(N) == 0 {
        di as error "Error: No pre-treatment observations for treated group"
        exit 2000
    }
    
    // =========================================================
    // 2. Create pseudo relative time for control group
    // =========================================================
    
    preserve
    
    // Control firms (_pte_treat==0) have missing _pte_nt since they are
    // never treated. We assign pseudo relative time so that all control
    // observations fall in the pre-treatment region (negative nt).
    // Strategy: nt_pseudo = year - (max_year + 1), guaranteeing nt < 0.
    
    tempvar nt_combined max_yr nt_pseudo
    
    // Compute max year in the dataset
    qui summ `timevar', meanonly
    local max_year = r(max)
    
    // Pseudo relative time for control: year - (max_year + 1)
    qui gen double `nt_pseudo' = `timevar' - (`max_year' + 1)
    
    // Combined relative time: use actual _pte_nt for treated, pseudo for control
    qui gen int `nt_combined' = _pte_nt if _pte_treat == 1
    qui replace  `nt_combined' = int(`nt_pseudo') if _pte_treat == 0
    
    // =========================================================
    // 3. Filter sample: pre-treatment window
    // =========================================================
    
    // Keep only pre-treatment period within the specified window
    qui keep if `nt_combined' < 0 & `nt_combined' >= -`preperiods'
    
    // Drop missing omega
    qui drop if missing(`omega')
    
    qui count
    local N_sample = r(N)
    
    if `N_sample' == 0 {
        di as error "Error: No observations after filtering"
        restore
        exit 2000
    }
    
    // Verify both groups remain after filtering
    qui count if _pte_treat == 1
    local N_treated = r(N)
    qui count if _pte_treat == 0
    local N_control = r(N)
    
    if `N_treated' == 0 {
        di as error "Error: No treated observations in pre-treatment window"
        restore
        exit 2000
    }
    if `N_control' == 0 {
        di as error "Error: No control observations in pre-treatment window"
        restore
        exit 2000
    }
    
    if `N_sample' < 10 {
        di as text "Warning: Only `N_sample' observations in parallel trends sample"
    }
    
    // =========================================================
    // 4. Recode to non-negative integers for factor variables
    // =========================================================
    
    // Stata factor variables require non-negative integers.
    // Recode nt_combined (negative) to non-negative:
    //   nt_pos = nt_combined + preperiods
    // e.g., preperiods=4: nt=-4 -> 0, nt=-3 -> 1, nt=-2 -> 2, nt=-1 -> 3
    // Base category: nt=-1 corresponds to nt_pos = preperiods - 1
    
    tempvar nt_pos
    qui gen int `nt_pos' = `nt_combined' + `preperiods'
    local base_pos = `preperiods' - 1
    
    // =========================================================
    // 5. Interaction regression: omega = nt_pos + treat + nt_pos#treat
    // =========================================================
    
    // DID-style regression with interaction terms.
    // The interaction coefficients (nt_pos#1._pte_treat) capture
    // differential trends between treated and control groups.
    // Base period nt=-1 is omitted; significant interactions indicate
    // violation of parallel trends.
    
    qui reg `omega' ib`base_pos'.`nt_pos'##i._pte_treat, cluster(`idvar')
    
    local N_reg    = e(N)
    local r2_reg   = e(r2)
    local df_r_reg = e(df_r)
    
    // Number of clusters
    local N_clust = `df_r_reg' + 1
    
    // =========================================================
    // 6. Joint F-test on interaction terms
    // =========================================================
    
    // Test all interaction terms jointly: H0 = no differential pre-trends
    qui testparm i.`nt_pos'#1._pte_treat
    
    local F_val    = r(F)
    local p_val    = r(p)
    local df1_val  = r(df)
    local df2_val  = r(df_r)
    
    // =========================================================
    // 7. Extract per-period interaction coefficients
    // =========================================================
    
    // Interaction coefficients from -preperiods to -2
    // (base period nt=-1 is omitted)
    // In recoded terms: positions 0 to (preperiods-2)
    local ncoefs = `preperiods' - 1
    
    // Create coefficient matrix: ncoefs x 4 (coef, se, t, p)
    tempname parallel_coefs
    matrix `parallel_coefs' = J(`ncoefs', 4, .)
    
    local row = 1
    forvalues j = -`preperiods'(1)-2 {
        // Map original nt value to recoded position
        local j_pos = `j' + `preperiods'
        
        // Extract interaction coefficient: j_pos.nt_pos#1._pte_treat
        local coef = _b[`j_pos'.`nt_pos'#1._pte_treat]
        local se   = _se[`j_pos'.`nt_pos'#1._pte_treat]
        
        if `se' > 0 {
            local t_stat = `coef' / `se'
            local p_coef = 2 * ttail(`df_r_reg', abs(`t_stat'))
        }
        else {
            local t_stat = .
            local p_coef = .
        }
        
        matrix `parallel_coefs'[`row', 1] = `coef'
        matrix `parallel_coefs'[`row', 2] = `se'
        matrix `parallel_coefs'[`row', 3] = `t_stat'
        matrix `parallel_coefs'[`row', 4] = `p_coef'
        
        local row = `row' + 1
    }
    
    // Label rows and columns
    local rownames ""
    forvalues j = -`preperiods'(1)-2 {
        local absj = abs(`j')
        local rownames "`rownames' nt_m`absj'"
    }
    matrix rownames `parallel_coefs' = `rownames'
    matrix colnames `parallel_coefs' = coef se t p
    
    // =========================================================
    // 8. PASS/FAIL judgment
    // =========================================================
    
    local alpha = 1 - `level' / 100
    
    local parallel_pass = 0
    if `p_val' >= `alpha' {
        local parallel_pass = 1
    }
    
    // =========================================================
    // 9. Display formatted output
    // =========================================================
    
    di as text _n "Parallel Trends Test (Treatment x Time Interaction)"
    di as text "{hline 60}"
    di as text "H0: No differential pre-trends between treatment and control"
    di as text "Base period:    nt = -1"
    di as text "Periods tested: nt = -`preperiods' to -2"
    di as text "Observations:   `N_reg'"
    di as text "  Treated:      `N_treated'"
    di as text "  Control:      `N_control'"
    di as text "Clusters:       `N_clust'"
    di as text "{hline 60}"
    
    // Display per-period interaction coefficients
    di as text ""
    di as text "  Period     Coef.      Std.Err.     t       p"
    di as text "  {hline 46}"
    
    local row = 1
    forvalues j = -`preperiods'(1)-2 {
        local c  = `parallel_coefs'[`row', 1]
        local s  = `parallel_coefs'[`row', 2]
        local tv = `parallel_coefs'[`row', 3]
        local pv = `parallel_coefs'[`row', 4]
        di as text "  nt=`j'" _col(14) %9.4f `c' _col(26) %9.4f `s' _col(38) %7.3f `tv' _col(48) %6.4f `pv'
        local row = `row' + 1
    }
    
    di as text "  {hline 46}"
    di as text "  Base: nt = -1 (omitted)"
    
    // Display joint F-test
    di as text ""
    di as text "Joint F-test (interaction terms):"
    di as text "  F(" %3.0f `df1_val' ", " %6.0f `df2_val' ") = " %8.4f `F_val'
    di as text "  Prob > F    = " %8.4f `p_val'
    
    // Display PASS/FAIL
    di as text ""
    if `parallel_pass' == 1 {
        di as result "Result: PASS - No significant differential pre-trends (p = " %6.4f `p_val' ")"
    }
    else {
        di as error "Result: FAIL - Significant differential pre-trends detected (p = " %6.4f `p_val' ")"
        di as error "        Parallel trends assumption may be violated"
    }
    di as text "{hline 60}"
    
    // =========================================================
    // 10. Store return values
    // =========================================================
    
    return scalar F_parallel    = `F_val'
    return scalar p_parallel    = `p_val'
    return scalar df1_parallel  = `df1_val'
    return scalar df2_parallel  = `df2_val'
    return scalar parallel_pass = `parallel_pass'
    return scalar N_parallel    = `N_reg'
    return scalar preperiods    = `preperiods'
    return matrix parallel_coefs = `parallel_coefs'
    
    // =========================================================
    // 11. Restore
    // =========================================================
    
    restore
    
end
