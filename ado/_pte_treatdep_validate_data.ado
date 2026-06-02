*! _pte_treatdep_validate_data.ado
*! Data Validation for Treatment-Dependent Mode

version 14.0
capture program drop _pte_treatdep_validate_data
program define _pte_treatdep_validate_data, rclass
    version 14.0
    
    // ================================================================
    // Syntax parsing
    // ================================================================
    
    syntax [if] [in], treatment(varname) ///
        [interact_vars(varlist) free(varlist) state(varlist) ///
         proxy(varname) control(varlist) VERbose]
    
    marksample touse
    
    // ================================================================
    // Set defaults
    // ================================================================
    
    if "`interact_vars'" == "" {
        local interact_vars "lnl_tp lnk_tp"
    }
    
    // Initialize counters
    local warning_count = 0
    local min_sample_size = 30
    local min_stable_obs = 50
    
    // ================================================================
    // Step 1: xtset verification
    // ================================================================
    
    capture xtset
    if _rc != 0 {
        di as error "Error: Panel data not set"
        di as error "Please use: xtset panelvar timevar"
        exit 459
    }
    
    local panelvar = r(panelvar)
    local timevar = r(timevar)
    
    // ================================================================
    // Step 2: Binary check + sample size
    // ================================================================
    
    // Check binary treatment
    qui tab `treatment' if `touse'
    local n_unique = r(r)
    if `n_unique' != 2 {
        di as error "Error: Treatment variable must be binary (0/1)"
        di as error "Found `n_unique' unique value(s) in `treatment'"
        exit 450
    }
    
    // Count by treatment status
    qui count if `treatment' == 0 & `touse'
    local n_d0 = r(N)
    
    qui count if `treatment' == 1 & `touse'
    local n_d1 = r(N)
    
    // Check minimum sample size
    if `n_d0' < `min_sample_size' | `n_d1' < `min_sample_size' {
        di as error "Error: Insufficient sample size for treatment-dependent estimation"
        di as error "D=0: `n_d0' observations (minimum: `min_sample_size')"
        di as error "D=1: `n_d1' observations (minimum: `min_sample_size')"
        exit 2001
    }
    
    // ================================================================
    // Step 3: Stable observations (Assumption 3.3)
    // ================================================================
    
    local n_stable_0 = 0
    local n_stable_1 = 0
    local n_transition = 0
    local n_first_period = 0
    
    // Check if _pte_mid exists (preferred path)
    capture confirm variable _pte_mid, exact
    local has_pte_mid = (_rc == 0)
    
    if `has_pte_mid' {
        // Path A: Use _pte_mid variable
        qui count if _pte_mid == 0 & `treatment' == 0 & `touse'
        local n_stable_0 = r(N)
        
        qui count if _pte_mid == 0 & `treatment' == 1 & `touse'
        local n_stable_1 = r(N)
        
        qui count if _pte_mid == 1 & `touse'
        local n_transition = r(N)
        
        // First period = total - stable - transition
        local n_first_period = `n_d0' + `n_d1' - `n_stable_0' - `n_stable_1' - `n_transition'
    }
    else {
        // Path B: Fallback to L.treatment
        tempvar lag_D
        qui gen `lag_D' = L.`treatment' if `touse'
        
        // Stable D=0: D==0 & L.D==0 & !missing(L.D)
        qui count if `treatment' == 0 & `lag_D' == 0 & !missing(`lag_D') & `touse'
        local n_stable_0 = r(N)
        
        // Stable D=1: D==1 & L.D==1 & !missing(L.D)
        qui count if `treatment' == 1 & `lag_D' == 1 & !missing(`lag_D') & `touse'
        local n_stable_1 = r(N)
        
        // Transition: D != L.D & !missing(L.D)
        qui count if `treatment' != `lag_D' & !missing(`lag_D') & `touse'
        local n_transition = r(N)
        
        // First period: missing(L.D)
        qui count if missing(`lag_D') & `touse'
        local n_first_period = r(N)
    }

    // Check Assumption 3.3: Must have stable observations in both groups
    if `n_stable_0' == 0 | `n_stable_1' == 0 {
        di as error "Error: Assumption 3.3 violated - no stable observations"
        if `n_stable_0' == 0 {
            di as error "No stable D=0 observations (D_t == D_{t-1} == 0)"
        }
        if `n_stable_1' == 0 {
            di as error "No stable D=1 observations (D_t == D_{t-1} == 1)"
        }
        di as error "Treatment-dependent estimation requires stable observations in both groups"
        exit 2003
    }
    
    // Warning for low stable observations
    if `n_stable_0' < `min_stable_obs' {
        local ++warning_count
        if "`verbose'" != "" {
            di as text "WARNING: Low stable D=0 observations (`n_stable_0' < `min_stable_obs')"
        }
    }
    
    if `n_stable_1' < `min_stable_obs' {
        local ++warning_count
        if "`verbose'" != "" {
            di as text "WARNING: Low stable D=1 observations (`n_stable_1' < `min_stable_obs')"
        }
    }
    
    // ================================================================
    // Step 4: Interaction term variation
    // ================================================================
    
    local sd_lnl_tp = .
    local sd_lnk_tp = .
    local var_idx = 1
    
    foreach var of local interact_vars {
        // Check variable exists
        capture confirm variable `var'
        if _rc != 0 {
            di as error "Error: Interaction variable `var' not found"
            exit 111
        }
        
        // Check variation
        qui sum `var' if `touse'
        local sd_var = r(sd)
        
        if missing(`sd_var') | `sd_var' == 0 {
            di as error "Error: Interaction variable `var' has no variation (sd=0)"
            di as error "This typically occurs when treatment is constant in the sample"
            exit 2002
        }
        
        // Store first two variable SDs
        if `var_idx' == 1 {
            local sd_lnl_tp = `sd_var'
        }
        else if `var_idx' == 2 {
            local sd_lnk_tp = `sd_var'
        }
        local ++var_idx
    }
    
    // ================================================================
    // Step 5: Variable overlap check
    // ================================================================
    
    // Only check if all variable lists are specified
    if "`free'" != "" & "`state'" != "" & "`proxy'" != "" {
        // Check 6 pairs for overlap (following treatpolyprodest.ado logic)
        
        // 1. free vs state
        local overlap : list free & state
        if "`overlap'" != "" {
            di as error "Error: Variable overlap between free() and state(): `overlap'"
            exit 198
        }
        
        // 2. free vs proxy
        local proxy_list "`proxy'"
        local overlap : list free & proxy_list
        if "`overlap'" != "" {
            di as error "Error: Variable overlap between free() and proxy(): `overlap'"
            exit 198
        }
        
        // 3. free vs control
        if "`control'" != "" {
            local overlap : list free & control
            if "`overlap'" != "" {
                di as error "Error: Variable overlap between free() and control(): `overlap'"
                exit 198
            }
        }
        
        // 4. state vs proxy
        local overlap : list state & proxy_list
        if "`overlap'" != "" {
            di as error "Error: Variable overlap between state() and proxy(): `overlap'"
            exit 198
        }
        
        // 5. state vs control
        if "`control'" != "" {
            local overlap : list state & control
            if "`overlap'" != "" {
                di as error "Error: Variable overlap between state() and control(): `overlap'"
                exit 198
            }
        }
        
        // 6. proxy vs control
        if "`control'" != "" {
            local overlap : list proxy_list & control
            if "`overlap'" != "" {
                di as error "Error: Variable overlap between proxy() and control(): `overlap'"
                exit 198
            }
        }
    }

    // ================================================================
    // Step 6: Validation report
    // ================================================================
    
    local total_N = `n_d0' + `n_d1'
    
    if "`verbose'" != "" {
        // Verbose mode: Full 3-part report
        di as text ""
        di as text "{hline 64}"
        di as text "Treatment-Dependent Data Validation Report"
        di as text "{hline 64}"
        di as text ""
        
        // Part 1: Sample size
        di as text "{ul:Part 1: Sample Size}"
        di as text "  Total observations:     " as result %10.0fc `total_N'
        di as text "  D=0 observations:       " as result %10.0fc `n_d0'
        di as text "  D=1 observations:       " as result %10.0fc `n_d1'
        di as text "  Minimum required:       " as result %10.0fc `min_sample_size'
        di as text ""
        
        // Part 2: Stable observations
        di as text "{ul:Part 2: Stable Observations (Assumption 3.3)}"
        di as text "  Stable D=0 (D_t=D_{t-1}=0): " as result %10.0fc `n_stable_0' _c
        if `n_stable_0' < `min_stable_obs' {
            di as text " WARNING"
        }
        else {
            di as text ""
        }
        di as text "  Stable D=1 (D_t=D_{t-1}=1): " as result %10.0fc `n_stable_1' _c
        if `n_stable_1' < `min_stable_obs' {
            di as text " WARNING"
        }
        else {
            di as text ""
        }
        di as text "  Transition (D_t!=D_{t-1}):  " as result %10.0fc `n_transition'
        di as text "  First period (no lag):      " as result %10.0fc `n_first_period'
        di as text "  Minimum stable recommended: " as result %10.0fc `min_stable_obs'
        di as text ""
        
        // Part 3: Interaction term variation
        di as text "{ul:Part 3: Interaction Term Variation}"
        di as text "  SD(lnl_tp):             " as result %8.4f `sd_lnl_tp'
        di as text "  SD(lnk_tp):             " as result %8.4f `sd_lnk_tp'
        di as text ""
        
        di as text "{hline 64}"
        if `warning_count' == 0 {
            di as result "Validation: PASSED"
        }
        else {
            di as result "Validation: PASSED with `warning_count' warning(s)"
        }
        di as text "{hline 64}"
        di as text ""
    }
    else {
        // Non-verbose: Single line summary
        if `warning_count' == 0 {
            di as result "Validation: PASSED"
        }
        else {
            di as result "Validation: PASSED with `warning_count' warning(s)"
        }
    }
    
    // ================================================================
    // Step 7: Return values
    // ================================================================
    
    return scalar validation_passed = 1
    return scalar n_d0 = `n_d0'
    return scalar n_d1 = `n_d1'
    return scalar n_stable_0 = `n_stable_0'
    return scalar n_stable_1 = `n_stable_1'
    return scalar n_transition = `n_transition'
    return scalar n_first_period = `n_first_period'
    return scalar sd_lnl_tp = `sd_lnl_tp'
    return scalar sd_lnk_tp = `sd_lnk_tp'
    return scalar warning_count = `warning_count'
    return scalar min_sample_size = `min_sample_size'
    return scalar min_stable_obs = `min_stable_obs'
    
end
