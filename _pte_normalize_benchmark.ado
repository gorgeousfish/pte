*! _pte_normalize_benchmark.ado
*! Benchmark Normalization
*! For D=0: omega_benchmark = lny - f(l,k; beta^0)
*! For D=1: omega_benchmark = lny - f(l,k; beta^1) + c
*! where c = f(l_bar,k_bar; beta^0) - f(l_bar,k_bar; beta^1)
*! = Delta_beta_l * l_bar + Delta_beta_k * k_bar + ...

version 14.0
capture program drop _pte_normalize_benchmark
program define _pte_normalize_benchmark
    version 14.0
    
    // Not eclass — returns results via scalar/matrix to caller
    syntax , [benchmarkinputs(varlist) ATTnorm Quietly]
    
    // ================================================================
    // Step 1: Validate treatdependent mode
    // ================================================================
    
    if "`e(treatdependent)'" != "1" {
        di as error "normalize(benchmark) requires treatdependent option"
        di as error "Run pte with: treatdependent normalize(benchmark)"
        exit 198
    }
    
    // ================================================================
    // Step 2: Validate required matrices
    // ================================================================
    
    tempname b0 b1
    
    capture matrix `b0' = e(b_untreated)
    if _rc {
        di as error "e(b_untreated) matrix not found"
        exit 198
    }
    
    capture matrix `b1' = e(b_treated)
    if _rc {
        di as error "e(b_treated) matrix not found"
        di as error "Benchmark normalization requires both b_untreated and b_treated"
        exit 198
    }
    
    // ================================================================
    // Step 3: Get production function type
    // ================================================================
    
    local prodfunc "`e(prodfunc)'"
    if "`prodfunc'" == "" local prodfunc "`e(pfunc)'"
    if "`prodfunc'" == "tl" local prodfunc "translog"
    
    if !inlist("`prodfunc'", "cd", "translog") {
        di as error "unsupported production function type: `prodfunc'"
        exit 198
    }
    
    // ================================================================
    // Step 4: Get variable names from e()
    // ================================================================
    
    local depvar "`e(depvar)'"
    local freevar "`e(free)'"
    if "`freevar'" == "" local freevar "`e(freevar)'"
    local statevar "`e(state)'"
    if "`statevar'" == "" local statevar "`e(statevar)'"
    local proxyvar "`e(proxy)'"
    if "`proxyvar'" == "" local proxyvar "`e(proxyvar)'"

    if "`freevar'" == "" {
        di as error "e(free) is empty; cannot identify free variable"
        di as error "Ensure the active estimation results expose free()"
        exit 198
    }
    if "`statevar'" == "" {
        di as error "e(state) is empty; cannot identify state variable"
        di as error "Ensure the active estimation results expose state()"
        exit 198
    }
    
    foreach var in `depvar' `freevar' `statevar' {
        capture confirm variable `var'
        if _rc {
            di as error "required variable `var' not found"
            exit 111
        }
    }
    
    local treatvar "`e(treatment)'"
    if "`treatvar'" == "" local treatvar "`e(treatvar)'"
    if "`treatvar'" == "" local treatvar "D"
    capture confirm variable `treatvar'
    if _rc {
        capture confirm variable treat_post
        if !_rc {
            local treatvar "treat_post"
        }
        else {
            di as error "treatment variable `treatvar' not found"
            exit 111
        }
    }

    // ================================================================
    // Step 5: Extract beta^0 and beta^1 parameters (Task 11)
    // ================================================================
    
    // Initialize parameters
    local beta_l_0 = .
    local beta_k_0 = .
    local beta_l_1 = .
    local beta_k_1 = .
    local beta_ll_0 = 0
    local beta_kk_0 = 0
    local beta_lk_0 = 0
    local beta_ll_1 = 0
    local beta_kk_1 = 0
    local beta_lk_1 = 0
    local beta_t = 0
    local has_time_trend = 0
    local n_params = 0
    
    // Extract beta^0 from b_untreated
    local colnames0 : colnames `b0'
    
    // Find freevar (labor) column in b_untreated
    local l_col0 = colnumb(`b0', "`freevar'")
    if `l_col0' != . {
        local beta_l_0 = `b0'[1, `l_col0']
    }
    else {
        capture local l_col0 = colnumb(`b0', "lnl")
        if `l_col0' != . local beta_l_0 = `b0'[1, `l_col0']
    }
    
    // Find statevar (capital) column in b_untreated
    local k_col0 = colnumb(`b0', "`statevar'")
    if `k_col0' != . {
        local beta_k_0 = `b0'[1, `k_col0']
    }
    else {
        capture local k_col0 = colnumb(`b0', "lnk")
        if `k_col0' != . local beta_k_0 = `b0'[1, `k_col0']
    }
    
    // Extract beta^1 from b_treated
    local colnames1 : colnames `b1'
    
    // Find freevar (labor) column in b_treated
    local l_col1 = colnumb(`b1', "`freevar'")
    if `l_col1' != . {
        local beta_l_1 = `b1'[1, `l_col1']
    }
    else {
        capture local l_col1 = colnumb(`b1', "lnl")
        if `l_col1' != . local beta_l_1 = `b1'[1, `l_col1']
    }
    
    // Find statevar (capital) column in b_treated
    local k_col1 = colnumb(`b1', "`statevar'")
    if `k_col1' != . {
        local beta_k_1 = `b1'[1, `k_col1']
    }
    else {
        capture local k_col1 = colnumb(`b1', "lnk")
        if `k_col1' != . local beta_k_1 = `b1'[1, `k_col1']
    }
    
    // Validate first-order params
    if missing(`beta_l_0') | missing(`beta_k_0') {
        di as error "cannot extract first-order parameters from e(b_untreated)"
        di as error "  beta_l_0 = `beta_l_0', beta_k_0 = `beta_k_0'"
        exit 198
    }
    if missing(`beta_l_1') | missing(`beta_k_1') {
        di as error "cannot extract first-order parameters from e(b_treated)"
        di as error "  beta_l_1 = `beta_l_1', beta_k_1 = `beta_k_1'"
        exit 198
    }
    local n_params = 2
    
    // Extract Translog second-order parameters
    if "`prodfunc'" == "translog" {
        // beta^0 second-order terms
        capture local beta_ll_0 = `b0'[1, colnumb(`b0', "var_1_1")]
        if _rc | missing(`beta_ll_0') local beta_ll_0 = 0
        
        capture local beta_kk_0 = `b0'[1, colnumb(`b0', "var_3_3")]
        if _rc | missing(`beta_kk_0') local beta_kk_0 = 0
        
        capture local beta_lk_0 = `b0'[1, colnumb(`b0', "var_1_3")]
        if _rc | missing(`beta_lk_0') local beta_lk_0 = 0
        
        // beta^1 second-order terms
        capture local beta_ll_1 = `b1'[1, colnumb(`b1', "var_1_1")]
        if _rc | missing(`beta_ll_1') local beta_ll_1 = 0
        
        capture local beta_kk_1 = `b1'[1, colnumb(`b1', "var_3_3")]
        if _rc | missing(`beta_kk_1') local beta_kk_1 = 0
        
        capture local beta_lk_1 = `b1'[1, colnumb(`b1', "var_1_3")]
        if _rc | missing(`beta_lk_1') local beta_lk_1 = 0
        
        local n_params = 5
    }
    
    // Time trend
    capture local beta_t = `b0'[1, colnumb(`b0', "t")]
    if _rc | missing(`beta_t') {
        local beta_t = 0
        local has_time_trend = 0
    }
    else {
        local has_time_trend = 1
        local ++n_params
    }

    // ================================================================
    // Step 6: Compute benchmark inputs (l_bar, k_bar) (Task 8-10)
    // ================================================================
    
    local lnl_bar = .
    local lnk_bar = .
    local bench_source = "sample_mean"
    
    if "`benchmarkinputs'" != "" {
        // User-specified benchmark inputs
        local bench_vars : word count `benchmarkinputs'
        if `bench_vars' != 2 {
            di as error "benchmarkinputs() requires exactly 2 variables"
            di as error "Usage: benchmarkinputs(lnl_var lnk_var)"
            exit 198
        }
        
        local bench_lnl : word 1 of `benchmarkinputs'
        local bench_lnk : word 2 of `benchmarkinputs'
        
        capture confirm variable `bench_lnl'
        if _rc {
            di as error "benchmark variable `bench_lnl' not found"
            exit 111
        }
        capture confirm variable `bench_lnk'
        if _rc {
            di as error "benchmark variable `bench_lnk' not found"
            exit 111
        }
        
        // Compute means from user-specified variables
        qui summ `bench_lnl'
        if r(N) == 0 {
            di as error "no valid observations for benchmark variable `bench_lnl'"
            exit 2000
        }
        local lnl_bar = r(mean)
        
        qui summ `bench_lnk'
        if r(N) == 0 {
            di as error "no valid observations for benchmark variable `bench_lnk'"
            exit 2000
        }
        local lnk_bar = r(mean)
        
        local bench_source "user_specified"
    }
    else {
        // Default: use sample means of freevar and statevar
        qui summ `freevar'
        if r(N) == 0 {
            di as error "no valid observations for `freevar'"
            exit 2000
        }
        local lnl_bar = r(mean)
        
        qui summ `statevar'
        if r(N) == 0 {
            di as error "no valid observations for `statevar'"
            exit 2000
        }
        local lnk_bar = r(mean)
    }

    // ================================================================
    // Step 7: Compute Delta_beta and adjustment factor c (Task 12-14)
    // ================================================================
    
    // Compute Delta_beta = beta^1 - beta^0
    local delta_l = `beta_l_1' - `beta_l_0'
    local delta_k = `beta_k_1' - `beta_k_0'
    local delta_ll = 0
    local delta_kk = 0
    local delta_lk = 0
    
    if "`prodfunc'" == "translog" {
        local delta_ll = `beta_ll_1' - `beta_ll_0'
        local delta_kk = `beta_kk_1' - `beta_kk_0'
        local delta_lk = `beta_lk_1' - `beta_lk_0'
    }
    
    // Compute adjustment factor c
    // Paper Appendix C.1: c = f(l_bar, k_bar; beta^0) - f(l_bar, k_bar; beta^1)
    //                       = Delta_beta_l * l_bar + Delta_beta_k * k_bar + ...
    // Note: c = f(beta^0) - f(beta^1) = -[f(beta^1) - f(beta^0)]
    //       = -(delta_l * l_bar + delta_k * k_bar + ...)
    // But the formula in spec uses c = delta_l * l_bar + delta_k * k_bar
    // which is f(beta^1) - f(beta^0), so D=1 uses: omega = lny - f(beta^1) + c
    // This is equivalent to: omega = lny - f(beta^1) + [f(beta^1) - f(beta^0)]
    //                              = lny - f(beta^0) at benchmark inputs
    
    local c = 0
    
    if "`prodfunc'" == "cd" {
        // Cobb-Douglas: c = delta_l * l_bar + delta_k * k_bar
        local c = `delta_l' * `lnl_bar' + `delta_k' * `lnk_bar'
    }
    else if "`prodfunc'" == "translog" {
        // Translog: c = delta_l * l_bar + delta_k * k_bar
        //             + delta_ll * l_bar^2 + delta_kk * k_bar^2 + delta_lk * l_bar * k_bar
        local c = `delta_l' * `lnl_bar' ///
                + `delta_k' * `lnk_bar' ///
                + `delta_ll' * `lnl_bar'^2 ///
                + `delta_kk' * `lnk_bar'^2 ///
                + `delta_lk' * `lnl_bar' * `lnk_bar'
    }
    
    // Warning for large adjustment factor
    if abs(`c') > 1 {
        di as text "Warning: Large adjustment factor |c| = " %9.4f abs(`c') " > 1"
        di as text "This may indicate substantial technology differences between D=0 and D=1"
    }

    // ================================================================
    // Step 8: Compute omega_benchmark (Task 15-16)
    // ================================================================
    
    // Handle variable conflict
    capture drop _pte_omega_benchmark
    
    // For D=0: omega_benchmark = lny - f(l,k; beta^0)
    // For D=1: omega_benchmark = lny - f(l,k; beta^1) + c
    
    if "`prodfunc'" == "cd" {
        // Cobb-Douglas
        // D=0: omega = lny - beta_l^0 * lnl - beta_k^0 * lnk
        qui gen double _pte_omega_benchmark = `depvar' ///
            - `beta_l_0' * `freevar' ///
            - `beta_k_0' * `statevar' ///
            if `treatvar' == 0
        
        // D=1: omega = lny - beta_l^1 * lnl - beta_k^1 * lnk + c
        qui replace _pte_omega_benchmark = `depvar' ///
            - `beta_l_1' * `freevar' ///
            - `beta_k_1' * `statevar' ///
            + `c' ///
            if `treatvar' == 1
        
        // Subtract time trend if present
        if `has_time_trend' {
            capture confirm variable t
            if !_rc {
                qui replace _pte_omega_benchmark = _pte_omega_benchmark - `beta_t' * t
            }
        }
    }
    else if "`prodfunc'" == "translog" {
        // Translog
        // D=0: omega = lny - beta_l^0*lnl - beta_k^0*lnk
        //            - beta_ll^0*lnl^2 - beta_kk^0*lnk^2 - beta_lk^0*lnl*lnk
        qui gen double _pte_omega_benchmark = `depvar' ///
            - `beta_l_0' * `freevar' ///
            - `beta_k_0' * `statevar' ///
            - `beta_ll_0' * `freevar'^2 ///
            - `beta_kk_0' * `statevar'^2 ///
            - `beta_lk_0' * `freevar' * `statevar' ///
            if `treatvar' == 0
        
        // D=1: omega = lny - beta_l^1*lnl - beta_k^1*lnk
        //            - beta_ll^1*lnl^2 - beta_kk^1*lnk^2 - beta_lk^1*lnl*lnk + c
        qui replace _pte_omega_benchmark = `depvar' ///
            - `beta_l_1' * `freevar' ///
            - `beta_k_1' * `statevar' ///
            - `beta_ll_1' * `freevar'^2 ///
            - `beta_kk_1' * `statevar'^2 ///
            - `beta_lk_1' * `freevar' * `statevar' ///
            + `c' ///
            if `treatvar' == 1
        
        // Subtract time trend if present
        if `has_time_trend' {
            capture confirm variable t
            if !_rc {
                qui replace _pte_omega_benchmark = _pte_omega_benchmark - `beta_t' * t
            }
        }
    }
    
    // Missing value check
    qui count if missing(_pte_omega_benchmark) & !missing(`depvar') & !missing(`freevar') & !missing(`statevar')
    if r(N) > 0 {
        di as error "WARNING: `r(N)' unexpected missing values in _pte_omega_benchmark"
    }
    
    // Variable label
    label variable _pte_omega_benchmark "Normalized productivity (Benchmark method)"
    
    // Basic statistics
    qui summ _pte_omega_benchmark
    local omega_n = r(N)
    local omega_mean = r(mean)
    local omega_sd = r(sd)

    // ================================================================
    // Step 9: Verification, display, and return values (Task 17-18)
    // ================================================================
    
    // D=0 consistency: omega_benchmark should equal original omega for D=0
    local max_diff0 = .
    local d0_n = 0
    local d0_pass = 1
    local d0_status = "N/A"
    
    capture confirm variable _pte_omega
    if !_rc {
        tempvar diff0
        qui gen double `diff0' = abs(_pte_omega_benchmark - _pte_omega) if `treatvar' == 0
        qui summ `diff0'
        local max_diff0 = r(max)
        local d0_n = r(N)
        
        if missing(`max_diff0') {
            local d0_pass = 1
            local d0_status = "N/A (no D=0 observations)"
        }
        else if `max_diff0' < 1e-6 {
            local d0_pass = 1
            local d0_status = "PASS"
        }
        else {
            local d0_pass = 0
            local d0_status = "FAIL (max diff = `max_diff0')"
            di as error "WARNING: D=0 consistency check failed, max diff = " %12.2e `max_diff0'
        }
    }
    
    // D=1 difference check: should differ from original omega (due to c adjustment)
    local mean_diff1 = .
    local d1_n = 0
    local d1_pass = 1
    local d1_status = "N/A"
    
    capture confirm variable _pte_omega
    if !_rc {
        tempvar diff1
        qui gen double `diff1' = abs(_pte_omega_benchmark - _pte_omega) if `treatvar' == 1
        qui summ `diff1'
        local mean_diff1 = r(mean)
        local d1_n = r(N)
        
        if missing(`mean_diff1') {
            local d1_pass = 1
            local d1_status = "N/A (no D=1 observations)"
        }
        else if abs(`c') > 1e-10 {
            // If c != 0, D=1 should differ
            if `mean_diff1' > 1e-6 {
                local d1_pass = 1
                local d1_status = "PASS (expected difference)"
            }
            else {
                local d1_pass = 0
                local d1_status = "UNEXPECTED (no difference despite c != 0)"
            }
        }
        else {
            // If c == 0, D=1 should be same as original
            local d1_pass = 1
            local d1_status = "PASS (c=0, no adjustment needed)"
        }
    }
    
    // D=0 correlation check
    local corr_d0 = .
    capture confirm variable _pte_omega
    if !_rc {
        capture qui corr _pte_omega_benchmark _pte_omega if `treatvar' == 0
        if !_rc local corr_d0 = r(rho)
    }
    
    local verify_pass = `d0_pass' & `d1_pass'
    
    // Display output
    if "`quietly'" == "" {
        di as text ""
        di as text "{hline 64}"
        di as text "Productivity Normalization: Benchmark Method"
        di as text "{hline 64}"
        di as text "Method:              Benchmark Normalization"
        di as text "Reference:           Paper Appendix C.1"
        di as text ""
        di as text "Production function: " as result "`prodfunc'"
        di as text "Parameters count:    " as result "`n_params'"
        di as text ""
        di as text "Benchmark inputs (`bench_source'):"
        di as text "  lnl_bar = " as result %9.6f `lnl_bar'
        di as text "  lnk_bar = " as result %9.6f `lnk_bar'
        di as text ""
        di as text "Beta^0 (untreated):"
        di as text "  beta_l_0 = " as result %9.6f `beta_l_0'
        di as text "  beta_k_0 = " as result %9.6f `beta_k_0'
        if "`prodfunc'" == "translog" {
            di as text "  beta_ll_0 = " as result %9.6f `beta_ll_0'
            di as text "  beta_kk_0 = " as result %9.6f `beta_kk_0'
            di as text "  beta_lk_0 = " as result %9.6f `beta_lk_0'
        }
        di as text ""
        di as text "Beta^1 (treated):"
        di as text "  beta_l_1 = " as result %9.6f `beta_l_1'
        di as text "  beta_k_1 = " as result %9.6f `beta_k_1'
        if "`prodfunc'" == "translog" {
            di as text "  beta_ll_1 = " as result %9.6f `beta_ll_1'
            di as text "  beta_kk_1 = " as result %9.6f `beta_kk_1'
            di as text "  beta_lk_1 = " as result %9.6f `beta_lk_1'
        }
        di as text ""
        di as text "Delta_beta (beta^1 - beta^0):"
        di as text "  delta_l = " as result %9.6f `delta_l'
        di as text "  delta_k = " as result %9.6f `delta_k'
        if "`prodfunc'" == "translog" {
            di as text "  delta_ll = " as result %9.6f `delta_ll'
            di as text "  delta_kk = " as result %9.6f `delta_kk'
            di as text "  delta_lk = " as result %9.6f `delta_lk'
        }
        di as text ""
        di as text "Adjustment factor:"
        di as text "  c = " as result %9.6f `c'
        di as text ""
        di as text "Normalized variable: " as result "_pte_omega_benchmark"
        di as text "  Observations:      " as result `omega_n'
        di as text "  Mean:              " as result %9.4f `omega_mean'
        di as text "  Std. Dev.:         " as result %9.4f `omega_sd'
        di as text ""
        di as text "Verification:"
        di as text "  D=0 obs:          " as result `d0_n'
        di as text "  D=0 max diff:     " as result "`d0_status'"
        di as text "  D=1 obs:          " as result `d1_n'
        di as text "  D=1 mean diff:    " as result "`d1_status'"
        if !missing(`corr_d0') {
            di as text "  D=0 correlation:  " as result %9.6f `corr_d0'
        }
        di as text ""
        di as text "Interpretation:"
        di as text "  omega_benchmark answers: 'What productivity would produce"
        di as text "  the same output at benchmark input levels?'"
        di as text "{hline 64}"
    }
    
    // Return results via scalar/matrix (not ereturn)
    // This module is NOT eclass — caller handles ereturn
    scalar _pte_norm_c = `c'
    scalar _pte_norm_lnl_bar = `lnl_bar'
    scalar _pte_norm_lnk_bar = `lnk_bar'
    scalar _pte_norm_delta_l = `delta_l'
    scalar _pte_norm_delta_k = `delta_k'
    scalar _pte_norm_d0_corr = `corr_d0'
    scalar _pte_norm_d0_maxdiff = `max_diff0'
    scalar _pte_norm_d1_meandiff = `mean_diff1'
    scalar _pte_norm_verify_pass = `verify_pass'
    scalar _pte_norm_n_params = `n_params'
    scalar _pte_norm_omega_n = `omega_n'
    scalar _pte_norm_omega_mean = `omega_mean'
    scalar _pte_norm_omega_sd = `omega_sd'
    
    // Copy matrices for caller
    matrix _pte_norm_b0_used = `b0'
    matrix _pte_norm_b1_used = `b1'
    
    // Benchmark inputs matrix
    tempname bench_mat
    matrix `bench_mat' = (`lnl_bar', `lnk_bar')
    matrix colnames `bench_mat' = lnl_bar lnk_bar
    matrix _pte_norm_benchmark_inputs = `bench_mat'
    
end
