*! _pte_treatdep_omega.ado
*! Recovers productivity omega from estimated treatment-dependent production
*! function coefficients. Supports both Translog (15 coefficients) and
*! Cobb-Douglas (5 coefficients) specifications.
*! Formula (Translog):
*! omega = lny - β_l*lnl - β_lt*lnl_tp - β_k*lnk - β_kt*lnk_tp - β_t*t
*! - β_11*lnl^2 - β_12*lnl*lnl_tp - β_13*lnl*lnk - β_14*lnl*lnk_tp
*! - β_22*lnl_tp^2 - β_23*lnl_tp*lnk - β_24*lnl_tp*lnk_tp
*! - β_33*lnk^2 - β_34*lnk*lnk_tp - β_44*lnk_tp^2

version 14.0
capture program drop _pte_treatdep_omega
program define _pte_treatdep_omega, rclass
    version 14.0
    local _pte_clear_outputs "capture drop omega"
    
    // ═══════════════════════════════════════════════════════════════════════
    // Syntax parsing
    // ═══════════════════════════════════════════════════════════════════════
    capture noisily syntax [, NODIAGNOSE]
    if _rc != 0 {
        local _pte_syntax_rc = _rc
        `_pte_clear_outputs'
        exit `_pte_syntax_rc'
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Task 1: Input validation
    // ═══════════════════════════════════════════════════════════════════════
    
    // Infer the live variable names from the upstream treatdependent
    // production-function context instead of hard-coding canonical names.
    local depvar `"`e(depvar)'"'
    if `"`depvar'"' == "" {
        local depvar "lny"
    }

    local freevar `"`e(free)'"'
    if `"`freevar'"' == "" {
        local freevar "lnl"
    }

    local statevar `"`e(state)'"'
    if `"`statevar'"' == "" {
        local statevar "lnk"
    }

    local free_interact ""
    local state_interact ""
    local freevars_ext `"`e(free_vars)'"'
    local statevars_ext `"`e(state_vars)'"'
    foreach var of local freevars_ext {
        if `"`var'"' != `"`freevar'"' {
            local free_interact `"`var'"'
        }
    }
    foreach var of local statevars_ext {
        if `"`var'"' != `"`statevar'"' {
            local state_interact `"`var'"'
        }
    }
    if `"`free_interact'"' == "" {
        local free_interact "`freevar'_tp"
    }
    if `"`state_interact'"' == "" {
        local state_interact "`statevar'_tp"
    }

    // 1.1 Validate e(b) matrix exists
    capture confirm matrix e(b)
    if _rc {
        di as error "Error: Matrix e(b) not found"
        di as error "  Run _pte_treatdep_call_endopoly first"
        `_pte_clear_outputs'
        exit 198
    }

    // Resolve the live trend regressor before validating the input state.
    // The DO formula uses an exact time-trend term; abbreviation fallback
    // would silently substitute a different state variable and corrupt omega.
    local trendvar ""
    tempname _pte_td_b
    matrix `_pte_td_b' = e(b)
    if colnumb(`_pte_td_b', "_pte_t") < . {
        local trendvar "_pte_t"
    }
    else if colnumb(`_pte_td_b', "t") < . {
        local trendvar "t"
    }
    else {
        local trendvar "_pte_t"
    }

    // 1.2 Validate interaction variables exist exactly
    foreach var in `free_interact' `state_interact' {
        capture confirm variable `var', exact
        if _rc {
            di as error "Error: Variable `var' not found"
            di as error "  Run _pte_treatdep_interact first"
            `_pte_clear_outputs'
            exit 111
        }
    }
    
    // 1.3 Validate base variables exist exactly
    foreach var in `depvar' `freevar' `statevar' `trendvar' {
        capture confirm variable `var', exact
        if _rc {
            di as error "Error: Variable `var' not found"
            `_pte_clear_outputs'
            exit 111
        }
    }

    // 1.4 Determine production function type
    local pfunc "`e(pfunc)'"
    if "`pfunc'" == "" {
        // Infer from e(b) dimension
        tempname _pte_b_fallback
        matrix `_pte_b_fallback' = e(b)
        local ncols = colsof(`_pte_b_fallback')
        if `ncols' == 15 {
            local pfunc "translog"
        }
        else if `ncols' == 5 {
            local pfunc "cd"
        }
        else {
            di as error "Error: e(pfunc) not set and cannot infer from e(b) dimension"
            di as error "  e(b) has `ncols' columns (expected 15 for translog or 5 for cd)"
            `_pte_clear_outputs'
            exit 198
        }
    }

    tempname _pte_td_cols
    matrix `_pte_td_cols' = e(b)
    local actual_cols = colsof(`_pte_td_cols')
    local expected_cols = cond("`pfunc'" == "translog", 15, 5)
    if `actual_cols' != `expected_cols' {
        di as error "Error: unsupported treatdependent coefficient bundle"
        di as error "  e(pfunc): `pfunc'"
        di as error "  Expected: `expected_cols' coefficient(s)"
        di as error "  Actual:   `actual_cols' coefficient(s)"
        di as error "  The official DO contract supports one time-trend control only"
        `_pte_clear_outputs'
        exit 198
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Task 2: Coefficient verification
    // ═══════════════════════════════════════════════════════════════════════
    
    // Define required coefficient names
    if "`pfunc'" == "cd" {
        local required_coefs "`freevar' `free_interact' `statevar' `state_interact' `trendvar'"
        local n_expected = 5
        local formula_type "Cobb-Douglas"
    }
    else {
        local required_coefs "`freevar' `free_interact' `statevar' `state_interact' `trendvar'"
        local required_coefs "`required_coefs' var_1_1 var_1_2 var_1_3 var_1_4"
        local required_coefs "`required_coefs' var_2_2 var_2_3 var_2_4"
        local required_coefs "`required_coefs' var_3_3 var_3_4 var_4_4"
        local n_expected = 15
        local formula_type "Translog"
    }
    
    // Verify each coefficient exists in e(b) column names
    local coefnames : colnames e(b)
    local n_validated = 0
    foreach coef of local required_coefs {
        local found : list posof "`coef'" in coefnames
        if `found' == 0 {
            di as error "Error: Coefficient '`coef'' not found in e(b)"
            di as error "  This is coefficient `=`n_validated'+1' of `n_expected'"
            di as error "  Available coefficients: `coefnames'"
            `_pte_clear_outputs'
            exit 198
        }
        local ++n_validated
    }
    
    if "`nodiagnose'" == "" {
        di as text "  {c 252} All `n_expected' coefficients validated (`formula_type')"
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Task 3 & 4: Omega recovery formula
    // ═══════════════════════════════════════════════════════════════════════
    
    // Drop existing omega if present (for bootstrap loop compatibility)
    capture drop omega
    
    if "`pfunc'" == "translog" {
        // Translog: 15 coefficients (5 first-order + 10 second-order)
        // omega = lny - first_order_terms - second_order_terms
        //
        // First-order (5): lnl, lnl_tp, lnk, lnk_tp, t
        // Second-order (10): var_1_1 through var_4_4
        //   var_i_j corresponds to the cross-product of the i-th and j-th
        //   variables in the ordering: (lnl, lnl_tp, lnk, lnk_tp)
        
        quietly gen double omega = `depvar' ///
            - _b[`freevar'] * `freevar' - _b[`free_interact'] * `free_interact' ///
            - _b[`statevar'] * `statevar' - _b[`state_interact'] * `state_interact' ///
            - _b[`trendvar'] * `trendvar' ///
            - _b[var_1_1] * `freevar'^2 ///
            - _b[var_1_2] * `freevar' * `free_interact' ///
            - _b[var_1_3] * `freevar' * `statevar' ///
            - _b[var_1_4] * `freevar' * `state_interact' ///
            - _b[var_2_2] * `free_interact'^2 ///
            - _b[var_2_3] * `free_interact' * `statevar' ///
            - _b[var_2_4] * `free_interact' * `state_interact' ///
            - _b[var_3_3] * `statevar'^2 ///
            - _b[var_3_4] * `statevar' * `state_interact' ///
            - _b[var_4_4] * `state_interact'^2
    }
    else {
        // Cobb-Douglas: 5 coefficients
        // omega = lny - β_l*lnl - β_lt*lnl_tp - β_k*lnk - β_kt*lnk_tp - β_t*t
        
        quietly gen double omega = `depvar' ///
            - _b[`freevar'] * `freevar' - _b[`free_interact'] * `free_interact' ///
            - _b[`statevar'] * `statevar' - _b[`state_interact'] * `state_interact' ///
            - _b[`trendvar'] * `trendvar'
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Task 5: Data quality checks
    // ═══════════════════════════════════════════════════════════════════════
    
    // 5.1 Missing value check
    quietly count if missing(omega) & !missing(`depvar')
    local n_unexpected_missing = r(N)
    
    quietly count if missing(omega)
    local n_missing = r(N)
    
    quietly count if !missing(omega)
    local n_omega = r(N)
    
    if `n_unexpected_missing' > 0 & "`nodiagnose'" == "" {
        di as text "  Warning: `n_unexpected_missing' obs have missing omega but non-missing lny"
    }
    
    // 5.2 Summary statistics
    quietly summarize omega
    local omega_mean = r(mean)
    local omega_sd   = r(sd)
    local omega_min  = r(min)
    local omega_max  = r(max)
    
    // 5.3 Reasonableness checks
    local warn_count = 0
    
    if abs(`omega_mean') >= 10 & "`nodiagnose'" == "" {
        di as text "  Warning: |omega mean| = " %8.4f `omega_mean' " >= 10"
        local ++warn_count
    }
    
    if (`omega_sd' <= 0 | `omega_sd' >= 5) & "`nodiagnose'" == "" {
        di as text "  Warning: omega sd = " %8.4f `omega_sd' " outside (0, 5)"
        local ++warn_count
    }
    
    // 5.4 Extreme value detection
    quietly count if abs(omega) >= 20 & !missing(omega)
    local n_extreme = r(N)
    if `n_extreme' > 0 & "`nodiagnose'" == "" {
        di as text "  Note: `n_extreme' obs have |omega| >= 20"
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Task 6: Variable labeling
    // ═══════════════════════════════════════════════════════════════════════
    
    label variable omega "Recovered productivity (treatment-dependent `formula_type')"
    
    notes omega: Recovered using treatment-dependent production function
    notes omega: Formula: omega = lny - sum(beta * inputs)
    if "`pfunc'" == "translog" {
        notes omega: Translog: 15 coefficients (5 first-order + 10 second-order)
    }
    else {
        notes omega: Cobb-Douglas: 5 coefficients
    }
    notes omega: treatment-dependent omega recovery
    
    // ═══════════════════════════════════════════════════════════════════════
    // Diagnostic output
    // ═══════════════════════════════════════════════════════════════════════
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "Omega Recovery (Treatment-Dependent)"
        di as text "{hline 60}"
        di as text "  Production function:      " as result "`formula_type'"
        di as text "  Coefficients used:        " as result %10.0f `n_expected'
        di as text "  Valid observations:       " as result %10.0f `n_omega'
        di as text "  Missing values:           " as result %10.0f `n_missing'
        di as text "  Omega mean:               " as result %10.4f `omega_mean'
        di as text "  Omega std dev:            " as result %10.4f `omega_sd'
        di as text "  Omega range:              [" as result %8.4f `omega_min' ///
            as text ", " as result %8.4f `omega_max' as text "]"
        if `warn_count' > 0 {
            di as text "  Warnings:                 " as result %10.0f `warn_count'
        }
        di as text "{hline 60}"
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Task 7: Return values
    // ═══════════════════════════════════════════════════════════════════════
    
    return scalar omega_mean = `omega_mean'
    return scalar omega_sd   = `omega_sd'
    return scalar omega_min  = `omega_min'
    return scalar omega_max  = `omega_max'
    return scalar n_missing  = `n_missing'
    return scalar n_omega    = `n_omega'
    return scalar n_coefficients = `n_expected'
    return scalar n_extreme  = `n_extreme'
    return local  pfunc "`pfunc'"
    return local  formula_type "`formula_type'"
    return local  depvar "`depvar'"
    return local  free "`freevar'"
    return local  state "`statevar'"
    return local  free_interact "`free_interact'"
    return local  state_interact "`state_interact'"
    return local  trendvar "`trendvar'"
    
end
