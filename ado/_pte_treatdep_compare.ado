*! _pte_treatdep_compare.ado
*! Compares production function parameters, evolution parameters, and ATT
*! between standard and treatment-dependent models

version 14.0
capture program drop _pte_treatdep_compare
program define _pte_treatdep_compare, eclass
    version 14.0
    
    syntax [, NOGRaph DETail FORmat(string) NOLOG]
    
    // Default format
    if "`format'" == "" local format "%9.4f"
    
    // ================================================================
    // Step 1: Detect standard model results (TASK-002)
    // ================================================================
    
    local std_available = 0
    
    // Method 1: Check saved estimates
    capture estimates restore _pte_standard
    if _rc == 0 {
        // The official DO treatment-dependent stack posts endoprodest as the
        // command name, while the package may also compare against pte or
        // prodest-style standard results. Accept all official/live labels.
        if inlist("`e(cmd)'", "pte", "prodest", "endopolyprodest", "endoprodest") {
            local std_available = 1
        }
    }
    
    // Method 2: Check for standard ATT scalar in current e()
    if `std_available' == 0 {
        capture confirm scalar e(att_standard_0)
        if _rc == 0 {
            local std_available = 1
        }
    }
    
    if `std_available' == 0 {
        di as error "Error: Standard model results not found."
        di as error "  Run pte without treatdependent option first,"
        di as error "  then: estimates store _pte_standard"
        exit 301
    }
    
    // ================================================================
    // Step 2: Extract standard model parameters (TASK-005)
    // ================================================================
    
    capture estimates restore _pte_standard
    
    tempname b_std V_std
    capture matrix `b_std' = e(b)
    capture matrix `V_std' = e(V)
    
    local K_std = colsof(`b_std')
    local param_names_std : colnames `b_std'
    
    // Extract standard model ATT (up to 10 periods)
    local max_nt = 9
    forvalues nt = 0/`max_nt' {
        capture local att_std_`nt' = e(att_`nt')
        if _rc != 0 local att_std_`nt' = .
    }
    capture local att_std_pooled = e(ATT_avg)
    if _rc != 0 local att_std_pooled = .
    
    // Extract standard rho
    tempname rho_std
    capture matrix `rho_std' = e(rho_0)
    local rho_std_ok = (_rc == 0)
    
    // ================================================================
    // Step 3: Detect treatment-dependent model results (TASK-003)
    // ================================================================
    
    local td_available = 0
    
    capture estimates restore _pte_treatdep
    if _rc == 0 {
        // Check for treatment-dependent markers
        capture confirm scalar e(joint_F)
        if _rc == 0 {
            local td_available = 1
        }
        else {
            // Also accept if treatdep_mode is set
            if "`e(treatdep_mode)'" == "1" {
                local td_available = 1
            }
        }
    }
    
    if `td_available' == 0 {
        di as error "Error: Treatment-dependent model results not found."
        di as error "  Run pte with treatdependent option first,"
        di as error "  then: estimates store _pte_treatdep"
        exit 301
    }
    
    // ================================================================
    // Step 4: Extract treatment-dependent model parameters (TASK-006)
    // ================================================================
    
    capture estimates restore _pte_treatdep
    
    tempname b_td V_td
    capture matrix `b_td' = e(b)
    capture matrix `V_td' = e(V)
    
    local K_td = colsof(`b_td')
    local param_names_td : colnames `b_td'
    
    // Extract treatment-dependent ATT
    forvalues nt = 0/`max_nt' {
        capture local att_td_`nt' = e(att_`nt')
        if _rc != 0 local att_td_`nt' = .
    }
    capture local att_td_pooled = e(ATT_avg)
    if _rc != 0 local att_td_pooled = .
    
    // Extract treatment-dependent rho
    tempname rho_td
    capture matrix `rho_td' = e(rho_0)
    local rho_td_ok = (_rc == 0)
    
    // Extract US-007 test results
    local joint_F = .
    local joint_F_p = .
    local joint_F_df1 = .
    local joint_F_df2 = .
    
    capture local joint_F = e(joint_F)
    capture local joint_F_p = e(joint_F_pvalue)
    capture local joint_F_df1 = e(joint_F_df1)
    capture local joint_F_df2 = e(joint_F_df2)
    
    // Extract delta_beta_t matrix if available
    tempname delta_beta_t
    capture matrix `delta_beta_t' = e(delta_beta_t)
    local has_delta_t = (_rc == 0)
    
    // ================================================================
    // Step 5: Build parameter comparison matrix (TASK-007)
    // ================================================================
    
    // Use the smaller K for comparison
    local K = min(`K_std', `K_td')
    
    tempname beta_compare
    matrix `beta_compare' = J(`K', 2, .)
    matrix colnames `beta_compare' = Standard TreatDep
    
    // Build row names from standard model
    local rnames ""
    forvalues i = 1/`K' {
        local pname : word `i' of `param_names_std'
        local rnames "`rnames' `pname'"
    }
    matrix rownames `beta_compare' = `rnames'
    
    forvalues i = 1/`K' {
        matrix `beta_compare'[`i', 1] = `b_std'[1, `i']
        if `i' <= `K_td' {
            matrix `beta_compare'[`i', 2] = `b_td'[1, `i']
        }
    }
    
    // ================================================================
    // Step 6: Build evolution parameter comparison (TASK-008)
    // ================================================================
    
    local rho_cols_std = 0
    local rho_cols_td = 0
    if `rho_std_ok' local rho_cols_std = colsof(`rho_std')
    if `rho_td_ok' local rho_cols_td = colsof(`rho_td')
    local rho_max = max(`rho_cols_std', `rho_cols_td')
    
    tempname rho_compare
    if `rho_max' > 0 {
        matrix `rho_compare' = J(`rho_max', 2, .)
        matrix colnames `rho_compare' = Standard TreatDep
        
        // Build row names
        local rho_rnames ""
        forvalues i = 1/`rho_max' {
            local rho_rnames "`rho_rnames' rho_`i'"
        }
        matrix rownames `rho_compare' = `rho_rnames'
        
        if `rho_std_ok' {
            forvalues i = 1/`rho_cols_std' {
                matrix `rho_compare'[`i', 1] = `rho_std'[1, `i']
            }
        }
        if `rho_td_ok' {
            forvalues i = 1/`rho_cols_td' {
                matrix `rho_compare'[`i', 2] = `rho_td'[1, `i']
            }
        }
    }
    
    // ================================================================
    // Step 7: Compute ATT differences (TASK-010, TASK-011, TASK-012)
    // ================================================================
    
    // Determine how many periods have valid ATT
    local n_att_periods = 0
    forvalues nt = 0/`max_nt' {
        if !missing(`att_std_`nt'') & !missing(`att_td_`nt'') {
            local n_att_periods = `nt' + 1
        }
        else {
            continue, break
        }
    }
    if `n_att_periods' == 0 local n_att_periods = 1
    
    // Compute differences
    local n_att_rows = `n_att_periods'
    if !missing(`att_std_pooled') & !missing(`att_td_pooled') {
        local n_att_rows = `n_att_rows' + 1
        local has_pooled = 1
    }
    else {
        local has_pooled = 0
    }
    
    tempname att_compare
    matrix `att_compare' = J(`n_att_rows', 4, .)
    matrix colnames `att_compare' = Standard TreatDep Difference PctChange
    
    // Row names
    local att_rnames ""
    forvalues nt = 0/`=`n_att_periods'-1' {
        local att_rnames "`att_rnames' nt`nt'"
    }
    if `has_pooled' local att_rnames "`att_rnames' Pooled"
    matrix rownames `att_compare' = `att_rnames'
    
    forvalues nt = 0/`=`n_att_periods'-1' {
        local row = `nt' + 1
        matrix `att_compare'[`row', 1] = `att_std_`nt''
        matrix `att_compare'[`row', 2] = `att_td_`nt''
        
        local att_diff = `att_std_`nt'' - `att_td_`nt''
        matrix `att_compare'[`row', 3] = `att_diff'
        
        if `att_std_`nt'' != 0 & !missing(`att_std_`nt'') {
            matrix `att_compare'[`row', 4] = (`att_diff' / `att_std_`nt'') * 100
        }
    }
    
    if `has_pooled' {
        local prow = `n_att_rows'
        matrix `att_compare'[`prow', 1] = `att_std_pooled'
        matrix `att_compare'[`prow', 2] = `att_td_pooled'
        local att_diff_pooled = `att_std_pooled' - `att_td_pooled'
        matrix `att_compare'[`prow', 3] = `att_diff_pooled'
        if `att_std_pooled' != 0 & !missing(`att_std_pooled') {
            matrix `att_compare'[`prow', 4] = (`att_diff_pooled' / `att_std_pooled') * 100
        }
    }
    
    // ================================================================
    // Step 8: Model selection recommendation (TASK-013)
    // ================================================================
    
    local strength = -1
    local recommendation ""
    local reason ""
    
    if missing(`joint_F_p') {
        local strength = -1
        local recommendation "Inconclusive: Parameter test results not available"
        local reason "Run _pte_treatdep_test first for model selection guidance"
    }
    else if `joint_F_p' < 0.01 {
        local strength = 3
        local recommendation "Strong: Use treatment-dependent model"
        local reason "Joint F test highly significant (p < 0.01)"
    }
    else if `joint_F_p' < 0.05 {
        local strength = 2
        local recommendation "Moderate: Consider treatment-dependent model"
        local reason "Joint F test significant at 5% level"
    }
    else if `joint_F_p' < 0.10 {
        local strength = 1
        local recommendation "Weak: Treatment-dependent model may be appropriate"
        local reason "Joint F test marginally significant at 10% level"
    }
    else {
        local strength = 0
        local recommendation "Standard model appears sufficient"
        local reason "Joint F test not significant (p >= 0.10)"
    }
    
    // ================================================================
    // Step 9: Display results (TASK-014~017)
    // ================================================================
    
    if "`nolog'" == "" {
        di as text ""
        di as text _dup(79) "="
        di as text "  Standard vs Treatment-Dependent Model Comparison"
        di as text _dup(79) "="
        
        // --- Production function parameters ---
        di as text ""
        di as text "  Production Function Parameters:"
        di as text _dup(79) "-"
        di as text %14s "Parameter" "   Standard    TreatDep"
        di as text _dup(79) "-"
        
        forvalues i = 1/`K' {
            local pname : word `i' of `param_names_std'
            local v1 = `beta_compare'[`i', 1]
            local v2 = `beta_compare'[`i', 2]
            di as text %14s "`pname'" as result `format' `v1' `format' `v2'
        }
        di as text _dup(79) "-"
        
        // --- Evolution parameters ---
        if `rho_max' > 0 {
            di as text ""
            di as text "  Evolution Parameters:"
            di as text _dup(79) "-"
            di as text %14s "Parameter" "   Standard    TreatDep"
            di as text _dup(79) "-"
            
            forvalues i = 1/`rho_max' {
                local v1 = `rho_compare'[`i', 1]
                local v2 = `rho_compare'[`i', 2]
                if missing(`v1') {
                    di as text %14s "rho_`i'" "          -" as result `format' `v2'
                }
                else if missing(`v2') {
                    di as text %14s "rho_`i'" as result `format' `v1' "          -"
                }
                else {
                    di as text %14s "rho_`i'" as result `format' `v1' `format' `v2'
                }
            }
            di as text _dup(79) "-"
        }
        
        // --- ATT comparison ---
        di as text ""
        di as text "  ATT Comparison:"
        di as text _dup(79) "-"
        di as text %14s "Period" "   Standard    TreatDep  Difference   PctChange"
        di as text _dup(79) "-"
        
        forvalues r = 1/`n_att_rows' {
            local rname : word `r' of `att_rnames'
            local v1 = `att_compare'[`r', 1]
            local v2 = `att_compare'[`r', 2]
            local v3 = `att_compare'[`r', 3]
            local v4 = `att_compare'[`r', 4]
            
            if "`rname'" == "Pooled" {
                di as text _dup(50) "."
            }
            
            if missing(`v4') {
                di as text %14s "`rname'" as result `format' `v1' `format' `v2' `format' `v3' "          -"
            }
            else {
                di as text %14s "`rname'" as result `format' `v1' `format' `v2' `format' `v3' %10.1f `v4' "%"
            }
        }
        di as text _dup(79) "-"
        
        // --- Diagnostic / Recommendation ---
        di as text ""
        if !missing(`joint_F') {
            di as text "  Joint F-test: F(" as result `joint_F_df1' as text "," as result `joint_F_df2' as text ") = " as result %8.4f `joint_F' as text "  p = " as result %8.4f `joint_F_p'
        }
        di as text ""
        di as text "  Recommendation: " as result "`recommendation'"
        di as text "  Reason: `reason'"
        di as text _dup(79) "="
    }
    
    // ================================================================
    // Step 10: Store return values (TASK-018)
    // ================================================================
    
    // ATT difference scalars
    forvalues nt = 0/`=`n_att_periods'-1' {
        ereturn scalar att_diff_`nt' = `att_compare'[`nt'+1, 3]
        ereturn scalar att_diff_pct_`nt' = `att_compare'[`nt'+1, 4]
    }
    if `has_pooled' {
        ereturn scalar att_diff_pooled = `att_compare'[`n_att_rows', 3]
        ereturn scalar att_diff_pct_pooled = `att_compare'[`n_att_rows', 4]
    }
    
    // Test results
    ereturn scalar recommendation_strength = `strength'
    ereturn scalar joint_F = `joint_F'
    ereturn scalar joint_F_pvalue = `joint_F_p'
    
    // Matrices
    ereturn matrix beta_compare = `beta_compare'
    if `rho_max' > 0 {
        ereturn matrix rho_compare = `rho_compare'
    }
    ereturn matrix att_compare = `att_compare'
    if `has_delta_t' {
        ereturn matrix delta_beta_t = `delta_beta_t'
    }
    
    // Macros
    ereturn local cmd_compare "pte_treatdep_compare"
    ereturn local recommendation "`recommendation'"
    ereturn local recommendation_reason "`reason'"
    
end
