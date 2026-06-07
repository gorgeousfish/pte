*! _pte_cohort_validate.ado
*! Cohort Identification and Data Structure Validation

version 14.0
capture program drop _pte_cohort_validate
program define _pte_cohort_validate, rclass
    version 14.0
    
    // ================================================================
    // Syntax parsing
    // ================================================================
    
    syntax [if] [in], panelvar(varname) timevar(varname) ///
        treatvar(varname) [cohortvar(varname) strict]
    
    marksample touse
    
    // ================================================================
    // Step 0: Basic validation
    // ================================================================
    
    // Check panel is set
    capture _xt, trequired
    if _rc != 0 {
        di as error "Error: Panel data not set"
        di as error "Please use: xtset `panelvar' `timevar'"
        exit 459
    }
    local pte_prev_panelvar = r(ivar)
    local pte_prev_timevar = r(tvar)
    local pte_xtset_switched = 0
    
    capture confirm numeric variable `treatvar'
    if _rc != 0 {
        di as error "Error: Treatment variable must be numeric (0/1)"
        exit 198
    }

    qui count if `touse' & !missing(`treatvar')
    if r(N) > 0 {
        qui summ `treatvar' if `touse' & !missing(`treatvar'), meanonly
        if r(min) < 0 | r(max) > 1 {
            di as error "Error: Treatment variable must be binary (0/1)"
            di as error "Found range [`=r(min)', `=r(max)'] in `treatvar'"
            exit 198
        }
    }

    // Check treatment is binary
    qui tab `treatvar' if `touse'
    local n_unique = r(r)
    if `n_unique' > 2 {
        di as error "Error: Treatment variable must be binary (0/1)"
        di as error "Found `n_unique' unique values in `treatvar'"
        exit 198
    }
    
    // Check for empty data
    qui count if `touse'
    if r(N) == 0 {
        di as error "Error: No observations in sample"
        exit 2000
    }
    
    // ================================================================
    // Step 1: Compute treat_year from observed 0->1 entry events
    // ================================================================
    
    tempvar cohort_temp
    
    if "`cohortvar'" != "" {
        // Path B: User provided cohort variable - validate it
        // Check cohort is constant within panel
        tempvar cohort_sd
        qui bys `panelvar': egen `cohort_sd' = sd(`cohortvar') if `touse'
        qui count if `cohort_sd' > 0 & !missing(`cohort_sd') & `touse'
        if r(N) > 0 {
            di as error "Error: Cohort variable must be constant within each panel unit"
            exit 198
        }
        qui gen `cohort_temp' = `cohortvar' if `touse'
    }
    else {
        // Path A: Auto-compute the observed treatment-entry year. A firm
        // already treated at its first observed period is left-censored and
        // must keep missing cohort timing instead of receiving a fabricated
        // cohort based on min{t : D_t = 1} in the truncated sample.
        tempvar entry_obs
        qui bys `panelvar' (`timevar'): gen byte `entry_obs' = ///
            (L.`treatvar' == 0 & `treatvar' == 1) if _n > 1 & `touse'
        qui bys `panelvar': egen double `cohort_temp' = ///
            min(cond(`entry_obs' == 1, `timevar', .)) if `touse'
    }
    
    // Store cohort variable for later use
    capture drop _pte_cohort_var
    qui gen _pte_cohort_var = `cohort_temp'
    
    // ================================================================
    // Step 2: Absorbing treatment validation
    // ================================================================
    
    if ("`pte_prev_panelvar'" != "`panelvar'") | ("`pte_prev_timevar'" != "`timevar'") {
        capture quietly xtset `panelvar' `timevar'
        local pte_xtset_switched = 1
    }
    
    tempvar D_lead violation
    qui gen `D_lead' = F.`treatvar' if `touse'
    
    // Violation: D=1 followed by D=0 (non-absorbing)
    qui gen `violation' = (`treatvar' == 1 & `D_lead' == 0) if `touse'
    qui count if `violation' == 1 & `touse'
    
    if r(N) > 0 {
        di as error "Error: Non-absorbing treatment detected (D=1 followed by D=0)"
        di as error "Found `r(N)' violation(s)"
        di as error "Cohort analysis requires absorbing treatment"
        di as error "For non-absorbing treatment, use: pte ..., nonabsorbing"
        if `pte_xtset_switched' {
            capture quietly xtset `pte_prev_panelvar' `pte_prev_timevar'
        }
        exit 3021
    }
    
    if `pte_xtset_switched' {
        capture quietly xtset `pte_prev_panelvar' `pte_prev_timevar'
    }

    // ================================================================
    // Step 3: Cohort list and sample size statistics
    // ================================================================
    
    // Get unique cohort values (excluding never-treated)
    qui levelsof _pte_cohort_var if !missing(_pte_cohort_var) & `touse', local(all_cohorts)
    
    local valid_cohorts ""
    local n_cohorts = 0
    local warning_count = 0
    
    // Temporary matrices for cohort info
    tempname cohort_list cohort_sizes cohort_obs
    
    // Count cohorts and filter by sample size
    local n_all_cohorts : word count `all_cohorts'
    
    if `n_all_cohorts' > 0 {
        matrix `cohort_list' = J(`n_all_cohorts', 1, .)
        matrix `cohort_sizes' = J(`n_all_cohorts', 1, .)
        matrix `cohort_obs' = J(`n_all_cohorts', 1, .)
        
        local idx = 1
        foreach g of local all_cohorts {
            // Count unique firms in this cohort
            qui tab `panelvar' if _pte_cohort_var == `g' & `touse'
            local n_firms = r(r)
            
            // Count observations in this cohort
            qui count if _pte_cohort_var == `g' & `touse'
            local n_obs = r(N)
            
            // Filter by sample size
            if `n_firms' < 10 {
                // W-3016: Skip cohort with N < 10
                di as text "Warning (W-3016): Cohort `g' has only `n_firms' firms (< 10), skipping"
                local ++warning_count
            }
            else {
                if `n_firms' < 30 {
                    // W-3010: Warning for 10 <= N < 30
                    di as text "Warning (W-3010): Cohort `g' has only `n_firms' firms (< 30)"
                    local ++warning_count
                }
                
                // Add to valid cohorts
                local valid_cohorts "`valid_cohorts' `g'"
                local ++n_cohorts
                
                matrix `cohort_list'[`idx', 1] = `g'
                matrix `cohort_sizes'[`idx', 1] = `n_firms'
                matrix `cohort_obs'[`idx', 1] = `n_obs'
                local ++idx
            }
        }
        
        // Trim matrices to actual size
        if `n_cohorts' > 0 {
            matrix _pte_cohort_list = `cohort_list'[1..`n_cohorts', 1]
            matrix _pte_cohort_sizes = `cohort_sizes'[1..`n_cohorts', 1]
            matrix _pte_cohort_obs = `cohort_obs'[1..`n_cohorts', 1]
        }
    }
    
    // Check minimum cohort requirement
    if `n_cohorts' < 2 {
        di as error "Error: Insufficient cohorts for cohort analysis"
        di as error "Found `n_cohorts' valid cohort(s), minimum required: 2"
        if "`strict'" != "" {
            exit 3011
        }
        else {
            di as text "Note: Use standard pte without cohort() option for single-cohort analysis"
            exit 3011
        }
    }
    
    // ================================================================
    // Step 4: Never-treated identification
    // ================================================================
    
    qui tab `panelvar' if missing(_pte_cohort_var) & `touse'
    local n_nevertreated = r(r)
    if missing(`n_nevertreated') local n_nevertreated = 0
    
    // ================================================================
    // Step 5: Display summary
    // ================================================================
    
    di as text ""
    di as text "{hline 64}"
    di as text "Cohort Identification Summary"
    di as text "{hline 64}"
    di as text ""
    di as text "Number of valid cohorts:    " as result %5.0f `n_cohorts'
    di as text "Never-treated firms:        " as result %5.0f `n_nevertreated'
    di as text "Warnings:                   " as result %5.0f `warning_count'
    di as text ""
    
    // Display cohort details
    di as text "{ul:Cohort Details}"
    di as text "  Cohort Year    Firms    Observations"
    di as text "  {hline 40}"
    
    forv i = 1/`n_cohorts' {
        local g = _pte_cohort_list[`i', 1]
        local nf = _pte_cohort_sizes[`i', 1]
        local no = _pte_cohort_obs[`i', 1]
        di as text "  " %10.0f `g' "  " %7.0f `nf' "  " %12.0f `no'
    }
    
    di as text ""
    di as text "{hline 64}"
    
    // ================================================================
    // Step 6: Return values (via c_local and matrices)
    // ================================================================
    
    // Return scalars
    return scalar n_cohorts = `n_cohorts'
    return scalar n_nevertreated = `n_nevertreated'
    return scalar warning_count = `warning_count'
    
    // Return local for valid cohorts list
    c_local valid_cohorts "`valid_cohorts'"
    c_local n_cohorts "`n_cohorts'"
    c_local n_nevertreated "`n_nevertreated'"
    
    // Matrices are already stored as _pte_cohort_list, _pte_cohort_sizes, _pte_cohort_obs
    
end
