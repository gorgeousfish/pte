*! _pte_treatdep_test.ado
*! Tests H0: all Delta_beta = 0 via individual t-tests and joint F-test

version 14.0
capture program drop _pte_treatdep_test
program define _pte_treatdep_test, eclass
    version 14.0
    syntax [, PFUNC(string) NOLOG]
    
    // ================================================================
    // Step 1: Validate estimation context (T-011: Error handling)
    // ================================================================
    
    // Check that an estimation has been run
    capture confirm matrix e(b)
    if _rc != 0 {
        di as error "Error: No estimation results found."
        di as error "  Run endopolyprodest or pte with treatdependent option first."
        exit 301
    }
    
    capture confirm matrix e(V)
    if _rc != 0 {
        di as error "Error: Variance-covariance matrix e(V) not found."
        exit 301
    }
    
    // ================================================================
    // Step 2: Determine production function type (T-002)
    // ================================================================
    
    // If pfunc not specified, try to get from e(pfunc)
    if "`pfunc'" == "" {
        local pfunc = e(pfunc)
        if "`pfunc'" == "" {
            // Try to infer from e(b) column names
            local colnames : colnames e(b)
            if strpos("`colnames'", "var_1_2") > 0 {
                local pfunc "translog"
            }
            else {
                local pfunc "cd"
            }
        }
    }
    
    // Validate pfunc
    if !inlist("`pfunc'", "cd", "translog", "tl") {
        di as error "Error: pfunc must be cd, translog, or tl"
        exit 198
    }
    
    // Normalize tl -> translog
    if "`pfunc'" == "tl" local pfunc "translog"
    
    // ================================================================
    // Step 3: Build treatment variable list (T-002, T-005)
    // ================================================================
    
    local colnames : colnames e(b)
    
    if "`pfunc'" == "cd" {
        local all_treatvars "lnl_tp lnk_tp"
    }
    else {
        // Translog: 9 treatment interaction parameters
        local all_treatvars "lnl_tp lnk_tp var_1_2 var_1_4 var_2_2 var_2_3 var_2_4 var_3_4 var_4_4"
    }
    
    // Filter to variables actually present in e(b) (T-005)
    local treatvars ""
    local n_vars = 0
    local n_missing = 0
    foreach var of local all_treatvars {
        local found = 0
        foreach cn of local colnames {
            if "`cn'" == "`var'" {
                local found = 1
            }
        }
        if `found' {
            local treatvars "`treatvars' `var'"
            local n_vars = `n_vars' + 1
        }
        else {
            local n_missing = `n_missing' + 1
            if "`nolog'" == "" {
                di as text "  Note: `var' not found in e(b); skipping"
            }
        }
    }
    local treatvars = strtrim("`treatvars'")
    
    // No treatment variables found at all
    if `n_vars' == 0 {
        di as error "Error: No treatment interaction variables found in e(b)."
        di as error "  Expected: `all_treatvars'"
        exit 111
    }
    
    // ================================================================
    // Step 4: Individual t-tests (T-003)
    // ================================================================
    
    // Get residual degrees of freedom
    local df_r = e(df_r)
    if missing(`df_r') {
        // Fallback: use N - k
        local _pte_b_names : colfullnames e(b)
        local _pte_k : word count `_pte_b_names'
        local df_r = e(N) - `_pte_k'
    }
    
    // Create results matrix: n_vars x 4 (coef, se, t_stat, p_value)
    tempname delta_beta_t
    matrix `delta_beta_t' = J(`n_vars', 4, .)
    matrix colnames `delta_beta_t' = coef se t_stat p_value
    matrix rownames `delta_beta_t' = `treatvars'
    
    local i = 1
    foreach var of local treatvars {
        local coef = _b[`var']
        local se = _se[`var']
        
        // Handle SE = 0 or missing (T-011)
        if missing(`se') | `se' == 0 {
            matrix `delta_beta_t'[`i', 1] = `coef'
            matrix `delta_beta_t'[`i', 2] = `se'
            matrix `delta_beta_t'[`i', 3] = .
            matrix `delta_beta_t'[`i', 4] = .
            if "`nolog'" == "" {
                di as text "  Warning: SE = 0 for `var'; t and p set to missing"
            }
        }
        else {
            local t_stat = `coef' / `se'
            local p_value = 2 * ttail(`df_r', abs(`t_stat'))
            
            matrix `delta_beta_t'[`i', 1] = `coef'
            matrix `delta_beta_t'[`i', 2] = `se'
            matrix `delta_beta_t'[`i', 3] = `t_stat'
            matrix `delta_beta_t'[`i', 4] = `p_value'
        }
        
        local i = `i' + 1
    }
    
    // ================================================================
    // Step 5: Joint F-test (T-004)
    // ================================================================
    
    local joint_F = .
    local joint_F_p = .
    local joint_F_df1 = .
    local joint_F_df2 = .
    
    capture quietly test `treatvars'
    if _rc == 0 {
        local joint_F = r(F)
        local joint_F_df1 = r(df)
        local joint_F_df2 = r(df_r)
        local joint_F_p = r(p)
    }
    else {
        // Graceful degradation: F-test failed, but t-tests still valid
        if "`nolog'" == "" {
            di as text "  Warning: Joint F-test failed (rc=" _rc "). F results set to missing."
        }
    }
    
    // ================================================================
    // Step 6: Model selection suggestion (T-007)
    // ================================================================
    
    local suggestion_code = -1
    local suggestion ""
    
    if missing(`joint_F_p') {
        local suggestion_code = -1
        local suggestion "Joint F-test could not be performed. Model selection inconclusive."
    }
    else if `joint_F_p' > 0.10 {
        local suggestion_code = 0
        local suggestion "Treatment-dependent parameters not significant at 10% level. Consider using standard model."
    }
    else if `joint_F_p' > 0.05 {
        local suggestion_code = 1
        local suggestion "Treatment-dependent parameters marginally significant (10% level). Treatment-dependent model may be appropriate."
    }
    else if `joint_F_p' > 0.01 {
        local suggestion_code = 2
        local suggestion "Treatment-dependent parameters significant at 5% level. Using treatment-dependent model is recommended."
    }
    else {
        local suggestion_code = 3
        local suggestion "Treatment-dependent parameters highly significant (1% level). Using treatment-dependent model is strongly recommended."
    }
    
    // ================================================================
    // Step 7: Display results (T-006)
    // ================================================================
    
    if "`nolog'" == "" {
        di as text ""
        di as text _dup(79) "-"
        di as text "Treatment-Dependent Parameter Significance Test"
        di as text _dup(79) "-"
        di as text ""
        di as text "Production function type: " as result "`pfunc'"
        di as text "Number of Delta_beta parameters: " as result `n_vars'
        if `n_missing' > 0 {
            di as text "  (`n_missing' expected variables not found in e(b))"
        }
        di as text ""
        di as text "Individual t-tests for Delta_beta parameters:"
        di as text _dup(79) "-"
        di as text %14s "Variable" "     Coef.    Std.Err.          t      P>|t|"
        di as text _dup(79) "-"
        
        local i = 1
        foreach var of local treatvars {
            local coef = `delta_beta_t'[`i', 1]
            local se = `delta_beta_t'[`i', 2]
            local t_stat = `delta_beta_t'[`i', 3]
            local p_val = `delta_beta_t'[`i', 4]
            
            // Significance stars
            local stars ""
            if !missing(`p_val') {
                if `p_val' <= 0.01 local stars "***"
                else if `p_val' <= 0.05 local stars "**"
                else if `p_val' <= 0.10 local stars "*"
            }
            
            if missing(`t_stat') {
                di as text %14s "`var'" as result %11.6f `coef' %11.6f `se' "          .          ."
            }
            else {
                di as text %14s "`var'" as result %11.6f `coef' %11.6f `se' %11.3f `t_stat' %11.4f `p_val' " `stars'"
            }
            
            local i = `i' + 1
        }
        
        di as text _dup(79) "-"
        di as text "Significance: *** p<0.01, ** p<0.05, * p<0.10"
        di as text ""
        
        // Joint F-test
        di as text "Joint F-test: H0: All Delta_beta = 0"
        di as text ""
        if !missing(`joint_F') {
            di as text "  F(" as result `joint_F_df1' as text ", " as result `joint_F_df2' as text ") = " as result %12.4f `joint_F'
            di as text "  Prob > F   = " as result %12.4f `joint_F_p'
        }
        else {
            di as text "  F-test could not be computed."
        }
        
        di as text ""
        di as text _dup(79) "-"
        di as text "Recommendation:"
        di as text "  `suggestion'"
        di as text _dup(79) "-"
    }
    
    // ================================================================
    // Step 8: Store return values (T-008)
    // ================================================================
    
    // Scalar returns
    ereturn scalar delta_beta_pvalue = `joint_F_p'
    ereturn scalar joint_F = `joint_F'
    ereturn scalar joint_F_pvalue = `joint_F_p'
    ereturn scalar joint_F_df1 = `joint_F_df1'
    ereturn scalar joint_F_df2 = `joint_F_df2'
    ereturn scalar treatdep_suggestion_code = `suggestion_code'
    ereturn scalar n_treatvars = `n_vars'
    
    // Matrix return
    ereturn matrix delta_beta_t = `delta_beta_t'
    
    // Macro returns
    ereturn local delta_beta_vars "`treatvars'"
    ereturn local treatdep_suggestion "`suggestion'"
    ereturn local treatdep_pfunc "`pfunc'"
    
end
