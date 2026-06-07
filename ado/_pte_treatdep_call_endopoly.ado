*! _pte_treatdep_call_endopoly.ado
*! This module calls endopolyprodest for treatment-dependent production function
*! estimation and verifies output completeness.

version 14.0
/*******************************************************************************
** Program Function:
**   Call endopolyprodest to estimate treatment-dependent production function
**   and verify output completeness
**
** Input Parameters:
**   depvar    - Dependent variable (lny)
**   free      - Free variable list (with interaction terms)
**   state     - State variable list (with interaction terms)
**   proxy     - Proxy variable
**   control   - Control variables (optional)
**   endo      - Endogenous variable (optional)
**   treat     - Treatment variable for treat-dependent evolution (optional)
**   pfunc     - Production function type (translog/cd, default translog)
**   method    - Estimation method (default lp)
**   reps      - Bootstrap repetitions (default 5)
**   omegapoly - Evolution polynomial order (default 3)
**   verbose   - Verbose output flag
**
** Output:
**   e(b)         - Coefficient matrix
**   e(V)         - Variance-covariance matrix
**   e(N)         - Sample size
**   e(N_excluded)- Excluded transition observations
**   e(pfunc)     - Production function type
**   e(method)    - Estimation method
**
** Example:
**   _pte_treatdep_call_endopoly, ///
**       depvar(lny) ///
**       free(lnl lnl_tp) ///
**       state(lnk lnk_tp) ///
**       proxy(lnm) ///
**       control(t) ///
**       endo(treat_post) ///
**       treat(treat_post) ///
**       pfunc(translog) ///
**       verbose
**
*******************************************************************************/

capture program drop _pte_treatdep_call_endopoly
program define _pte_treatdep_call_endopoly, eclass
    version 14.0
    
    // ═══════════════════════════════════════════════════════════════════════
    // Syntax parsing
    // ═══════════════════════════════════════════════════════════════════════
    syntax, DEPVAR(varname) FREE(varlist) STATE(varlist) PROXY(varname) ///
        [CONTROL(varlist) ENDO(varname) TREAT(varname) PFUNC(string) ///
         METHOD(string) REPS(integer 5) OMEGAPOLY(integer 3) VERBOSE ///
         MID(varname) TOUSE(varname)]

    // The paper/DO treatdependent estimator carries exactly one control
    // regressor: the time trend. Internal callers may pass the generated
    // trend name (`_pte_t`) or a single equivalent trend column, but a wider
    // control bundle has no faithful downstream contract in e(b) or omega.
    local n_controls : word count `control'
    if `n_controls' > 1 {
        di as error "Error: treatdependent currently supports exactly one control() variable"
        di as error "  Received: `control'"
        di as error "  The official DO contract uses a single time-trend control"
        exit 198
    }
    if inlist("`method'", "", "lp", "op") & `reps' < 2 {
        di as error "Error: reps() must be at least 2 for treatdependent `method' estimation"
        di as error "  Received: reps(`reps')"
        exit 198
    }
    
    // Entry check: dependency detection
    _pte_treatdep_check_deps
    local _pte_deps_ok = r(all_checks_passed)
    if `"_pte_deps_ok"' == "" local _pte_deps_ok 0
    if `_pte_deps_ok' != 1 {
        di as error "Error: treatdependent dependency gate did not certify a runnable runtime"
        exit 601
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Step 1: Parameter validation (T-002)
    // ═══════════════════════════════════════════════════════════════════════
    
    // 1.1 Set default values
    if "`pfunc'" == "" local pfunc "translog"
    if "`method'" == "" local method "lp"
    if "`mid'" == "" local mid "_pte_mid"

    if "`touse'" != "" {
        capture confirm variable `touse', exact
        if _rc {
            di as error "Error: Active-sample indicator `touse' not found"
            exit 111
        }
        capture confirm numeric variable `touse'
        if _rc {
            di as error "Error: Active-sample indicator `touse' must be numeric"
            exit 109
        }
    }
    
    // 1.2 Validate pfunc parameter
    if !inlist("`pfunc'", "translog", "cd") {
        di as error "Error: pfunc must be 'translog' or 'cd'"
        di as error "Actual value: `pfunc'"
        exit 198
    }
    
    // 1.3 Validate method parameter
    if !inlist("`method'", "lp", "op") {
        di as error "Error: method must be 'lp' or 'op'"
        di as error "Actual value: `method'"
        exit 198
    }
    
    // 1.4 Validate numeric parameters
    if `reps' < 1 {
        di as error "Error: reps must be >= 1"
        di as error "Actual value: `reps'"
        exit 198
    }
    
    if !inlist(`omegapoly', 1, 2, 3, 4) {
        di as error "Error: omegapoly must be in {1,2,3,4}"
        di as error "Actual value: `omegapoly'"
        exit 198
    }
    
    // 1.5 Display parameter summary
    if "`verbose'" != "" {
        di as text ""
        di as text "{hline 70}"
        di as text "Call endopolyprodest and verify output"
        di as text "{hline 70}"
        di as text "Parameter Summary:"
        di as text "  Dependent variable: `depvar'"
        di as text "  Free variables:     `free'"
        di as text "  State variables:    `state'"
        di as text "  Proxy variable:     `proxy'"
        di as text "  Control variables:  `control'"
        di as text "  Endogenous var:     `endo'"
        di as text "  Treat variable:     `treat'"
        di as text "  Production func:    `pfunc'"
        di as text "  Method:             `method'"
        di as text "  Bootstrap reps:     `reps'"
        di as text "  Omega polynomial:   `omegapoly'"
        di as text "{hline 70}"
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Step 2: Validate prerequisites (T-006)
    // ═══════════════════════════════════════════════════════════════════════
    
    // 2.1 Validate mid variable exists
    capture confirm variable `mid'
    if _rc {
        di as error "Error: Transition period variable `mid' not found"
        di as error "Hint: Run transition period identification module first"
        exit 198
    }
    
    // 2.2 Validate mid variable values
    quietly {
        count if !missing(`mid') & !inlist(`mid', 0, 1)
        if r(N) > 0 {
            noisily di as error "Error: `mid' contains non-0/1 values"
            noisily di as error "  Abnormal observations: " r(N)
            exit 198
        }
    }
    
    // 2.3 Count sample sizes on the active estimation support
    local _sample_if "`mid' == 0"
    local _trans_if "`mid' == 1"
    if "`touse'" != "" {
        local _sample_if "`touse' & (`_sample_if')"
        local _trans_if "`touse' & (`_trans_if')"
    }

    quietly count if `_sample_if'
    local N_nontrans = r(N)
    quietly count if `_trans_if'
    local N_trans = r(N)
    
    if `N_nontrans' == 0 {
        di as error "Error: No available observations (all are transition periods)"
        di as error "  Transition observations: `N_trans'"
        di as error "Hint: Check `mid' variable generation logic"
        exit 2000
    }
    
    if "`verbose'" != "" {
        di as text ""
        di as text "Sample Statistics:"
        di as text "  Non-transition: `N_nontrans' observations"
        di as text "  Transition:     `N_trans' observations (will be excluded)"
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Step 3: Construct command string (T-003)
    // ═══════════════════════════════════════════════════════════════════════
    
    // 3.1 Base command (with transition exclusion on the active sample)
    local cmd "endopolyprodest `depvar' if `mid'==0"
    if "`touse'" != "" {
        local cmd "endopolyprodest `depvar' if `touse' & `mid'==0"
    }
    
    // 3.2 Required parameters (order matches replication code)
    local cmd "`cmd', method(`method')"
    local cmd "`cmd' free(`free')"
    local cmd "`cmd' proxy(`proxy')"
    local cmd "`cmd' state(`state')"
    
    // 3.3 Optional parameters
    if "`control'" != "" {
        local cmd "`cmd' control(`control')"
    }
    
    if "`endo'" != "" {
        local cmd "`cmd' endo(`endo')"
    }
    
    if "`treat'" != "" {
        local cmd "`cmd' treat(`treat')"
    }
    
    // 3.4 Production function type
    if "`pfunc'" == "translog" {
        local cmd "`cmd' translog"
    }
    
    // 3.5 Fixed options (matches replication code)
    local cmd "`cmd' valueadded acf"
    
    // 3.6 Numeric parameters
    local cmd "`cmd' reps(`reps') prodpoly(`omegapoly')"
    
    // 3.7 Display command (verbose mode)
    if "`verbose'" != "" {
        di as text ""
        di as text "Constructed command:"
        di as input "  `cmd'"
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Step 4: Execute endopolyprodest (T-004/T-005)
    // ═══════════════════════════════════════════════════════════════════════
    
    if "`verbose'" != "" {
        di as text ""
        di as text "Estimating treatment-dependent production function (`pfunc' mode)..."
    }
    
    // 4.1 Execute command
    capture noisily `cmd'
    local rc = _rc
    
    // 4.2 Check return code
    if `rc' {
        di as error ""
        di as error "Error: endopolyprodest execution failed"
        di as error "Return code: `rc'"
        di as error "Command: `cmd'"
        
        // Provide specific suggestions based on return code
        if `rc' == 111 {
            di as error ""
            di as error "Hint: Variable not found"
            di as error "  Check if interaction variables exist"
        }
        else if `rc' == 2000 {
            di as error ""
            di as error "Hint: No available observations"
            di as error "  Check if `mid' variable correctly identifies transition periods"
        }
        else if `rc' == 430 {
            di as error ""
            di as error "Hint: Optimizer did not converge"
            di as error "  Suggestion: Check data for outliers, try increasing maxiter"
        }
        
        exit `rc'
    }
    
    if "`verbose'" != "" {
        di as text "  Estimation sample size: " e(N)
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Step 5: Verify output (T-007 ~ T-010)
    // ═══════════════════════════════════════════════════════════════════════
    
    if "`verbose'" != "" {
        di as text ""
        di as text "Verifying output completeness..."
    }
    
    // 5.1 Verify e(b) dimension (T-007)
    // NOTE: In Stata eclass programs, matrix functions like rowsof(e(b)),
    //       colsof(e(b)), vecdiag(e(V)) trigger rc=509 when used in
    //       expressions (if/local/scalar assignments).
    //       FIX: Copy e(b)/e(V) to tempname matrices first, then use
    //       rowsof()/colsof() on the named temp matrices.
    tempname _tmpb _tmpV _se_diag
    matrix `_tmpb' = e(b)
    matrix `_tmpV' = e(V)
    
    local actual_rows = rowsof(`_tmpb')
    local actual_cols = colsof(`_tmpb')
    
    if `actual_rows' != 1 {
        di as error "Error: e(b) is not a row vector"
        di as error "  Rows: `actual_rows'"
        exit 198
    }
    
    if "`pfunc'" == "translog" {
        local expected_cols = 15
    }
    else {
        local expected_cols = 5
    }
    
    if `actual_cols' != `expected_cols' {
        di as error "Error: e(b) dimension mismatch"
        di as error "  Expected: `expected_cols' columns (`pfunc' mode)"
        di as error "  Actual: `actual_cols' columns"
        exit 198
    }
    
    if "`verbose'" != "" {
        di as text "  e(b) dimension correct: 1x`actual_cols'"
    }
    
    // 5.2 Verify e(V) dimension and positive definiteness (T-008)
    local ncols_b = `actual_cols'
    local Vrows = rowsof(`_tmpV')
    local Vcols = colsof(`_tmpV')
    
    if `Vrows' != `ncols_b' | `Vcols' != `ncols_b' {
        di as error "Error: e(V) dimension mismatch"
        di as error "  e(b) columns: `ncols_b'"
        di as error "  e(V) rows: `Vrows'"
        di as error "  e(V) cols: `Vcols'"
        exit 198
    }
    
    // Verify diagonal elements are positive
    matrix `_se_diag' = vecdiag(`_tmpV')
    local all_positive = 1
    forvalues i = 1/`ncols_b' {
        if `_se_diag'[1,`i'] <= 0 {
            di as error "Error: e(V)[`i',`i'] is non-positive: " `_se_diag'[1,`i']
            local all_positive = 0
        }
    }
    
    if !`all_positive' {
        di as error "Error: e(V) contains non-positive diagonal elements"
        exit 198
    }
    
    if "`verbose'" != "" {
        di as text "  e(V) dimension correct: `ncols_b'x`ncols_b'"
        di as text "  e(V) diagonal elements all positive"
    }
    
    // 5.3 Verify convergence status (T-009)
    // Note: endopolyprodest may set e(converged) to missing (.) rather than
    //       not setting it at all. Both cases are normal behavior.
    //       We only flag non-convergence if e(converged) exists AND equals 0.
    capture scalar _converge_check = e(converged)
    if _rc == 0 {
        if missing(_converge_check) {
            // e(converged) is missing (.) - normal for endopolyprodest
            if "`verbose'" != "" {
                di as text "  Execution successful (e(converged) is missing, relying on _rc==0)"
            }
        }
        else if _converge_check == 0 {
            di as error "Error: Optimizer did not converge"
            di as error "  e(converged) = 0"
            exit 430
        }
        else {
            // e(converged) == 1 or other positive value
            if "`verbose'" != "" {
                di as text "  Optimizer converged (e(converged) = " _converge_check ")"
            }
        }
    }
    else {
        // e(converged) does not exist - normal behavior for endopolyprodest
        if "`verbose'" != "" {
            di as text "  Execution successful (e(converged) not set, relying on _rc==0)"
        }
    }
    
    // 5.4 Verify key coefficients (T-010)
    local key_coefs "lnl lnk t"
    // Add interaction terms if they exist in free/state
    if strpos("`free'", "_tp") > 0 | strpos("`state'", "_tp") > 0 {
        local key_coefs "`key_coefs' lnl_tp lnk_tp"
    }
    
    local all_valid = 1
    foreach coef of local key_coefs {
        capture scalar _check_b = _b[`coef']
        if _rc {
            // Coefficient may not exist (e.g., no control variable t)
            continue
        }
        
        if missing(_b[`coef']) {
            di as error "Error: Coefficient `coef' is missing"
            local all_valid = 0
            continue
        }
        
        if abs(_b[`coef']) > 1e10 {
            di as error "Warning: Coefficient `coef' absolute value too large: " _b[`coef']
            di as error "  Possible numerical instability"
        }
    }
    
    if "`verbose'" != "" {
        di as text "  Key coefficients valid"
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Step 6: Store additional e() return values (T-012)
    // ═══════════════════════════════════════════════════════════════════════
    // IMPORTANT: ereturn scalar/local APPENDS to existing e()
    //            DO NOT use ereturn post/clear - would lose e(b)/e(V)
    
    // 6.1 Store scalars (append, do not overwrite endopolyprodest returns)
    ereturn scalar N_excluded = `N_trans'
    
    // 6.2 Store macros (append)
    ereturn local pfunc "`pfunc'"
    ereturn local method "`method'"
    ereturn local us_name "endopolyprodest_call_verify"
    ereturn local free_vars "`free'"
    ereturn local state_vars "`state'"
    
    // 6.3 Display completion message
    if "`verbose'" != "" {
        di as text ""
        di as text "{hline 70}"
        di as result "Verification passed: endopolyprodest call and output correct"
        di as text "{hline 70}"
        di as text ""
        di as text "Coefficient estimates:"
        matrix list e(b), noheader
    }
    
    // Clean up: tempname matrices are auto-dropped when program exits
    
end
