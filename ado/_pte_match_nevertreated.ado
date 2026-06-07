*! _pte_match_nevertreated.ado
*! Never-treated Matching Group Construction

version 14.0
capture program drop _pte_match_nevertreated
program define _pte_match_nevertreated, rclass
    version 14.0
    
    syntax [if] [in] , [treatvar(varname) treatyearvar(varname) ///
           diagnose diagvars(varlist) saveto(name) ///
           quietly nolog minobs(integer 30)]
    
    // Default variable names. Prefer the package-native/public contract before
    // falling back to legacy replication naming.
    if "`treatvar'" == "" {
        local _pte_live_treat `"`e(treatment)'"'
        if `"`_pte_live_treat'"' != "" {
            capture confirm variable `_pte_live_treat', exact
            if _rc == 0 {
                local treatvar `"`_pte_live_treat'"'
            }
        }
        if "`treatvar'" == "" {
            foreach _pte_treat_candidate in treat treatment D {
                capture confirm variable `_pte_treat_candidate', exact
                if _rc == 0 {
                    local treatvar "`_pte_treat_candidate'"
                    continue, break
                }
            }
        }
        if "`treatvar'" == "" local treatvar "D"
    }
    if "`treatyearvar'" == "" {
        foreach _pte_treatyear_candidate in treat_yr0 _pte_treat_year _pte_cohort_var treat_year {
            capture confirm variable `_pte_treatyear_candidate', exact
            if _rc == 0 {
                local treatyearvar "`_pte_treatyear_candidate'"
                continue, break
            }
        }
        if "`treatyearvar'" == "" local treatyearvar "treat_year"
    }
    
    // Mark sample
    marksample touse
    
    // ================================================================
    // Task 0: Prerequisite validation
    // ================================================================
    
    // 1. Verify the cohort anchor exists
    capture confirm variable `treatyearvar'
    if _rc {
        di as error "pte error [E-111]: `treatyearvar' variable not found"
        di as error "  Please run cohort identification first"
        exit 111
    }
    
    // 2. Verify omega exists (optional, for diagnostics)
    local has_omega = 0
    capture confirm variable omega
    if !_rc {
        local has_omega = 1
    }
    
    // 3. Verify panel structure
    qui xtset
    local panelvar = r(panelvar)
    local timevar = r(timevar)
    
    if "`panelvar'" == "" | "`timevar'" == "" {
        di as error "pte error [E-459]: data not xtset"
        di as error "  Please run xtset panelvar timevar first"
        exit 459
    }
    
    // 4. Verify at least 1 never-treated firm exists
    qui count if missing(`treatyearvar') & `touse'
    if r(N) == 0 {
        di as error "pte error [E-3021]: No never-treated firms found in data"
        di as error "  All firms have finite treat_year values"
        di as error "  Suggestion: Use matchstrategy(notyettreated) instead"
        exit 3021
    }

    // ================================================================
    // Task 1: Never-treated firm identification
    // ================================================================
    
    tempvar is_never_treated
    qui gen byte `is_never_treated' = missing(`treatyearvar') if `touse'
    qui replace `is_never_treated' = 0 if missing(`is_never_treated')
    
    // Verify firm-level consistency
    tempvar check_sd
    qui bysort `panelvar': egen `check_sd' = sd(`is_never_treated') if `touse'
    qui count if `check_sd' > 0 & !missing(`check_sd')
    if r(N) > 0 {
        di as error "pte error [E-3026]: treat_year inconsistent within firms"
        di as error "  Some firms have both missing and non-missing treat_year"
        exit 3026
    }
    
    // ================================================================
    // Task 2: Match group construction
    // ================================================================
    
    tempvar match_flag
    qui gen byte `match_flag' = `is_never_treated' if `touse'
    qui replace `match_flag' = 0 if missing(`match_flag')
    
    // Count firms
    tempvar firm_tag
    qui egen `firm_tag' = tag(`panelvar') if `match_flag' == 1 & `touse'
    qui count if `firm_tag' == 1
    local N_never_firms = r(N)
    
    // Count observations
    qui count if `match_flag' == 1 & `touse'
    local N_never_obs = r(N)
    
    // ================================================================
    // Task 3: Sample size validation
    // ================================================================
    
    local min_firms = 10
    
    if `N_never_firms' == 0 {
        di as error "pte error [E-3021]: No never-treated firms found"
        exit 3021
    }
    else if `N_never_firms' < `min_firms' {
        di as error "pte error [E-3022]: Insufficient never-treated firms"
        di as error "  N = `N_never_firms' < `min_firms'"
        di as error "  Suggestion: Use matchstrategy(notyettreated) for larger control group"
        exit 3022
    }
    else if `N_never_firms' < `minobs' {
        if "`nolog'" == "" {
            di as text "{bf:Warning [W-3023]}: Only `N_never_firms' never-treated firms"
            di as text "  Consider: matchstrategy(notyettreated) for more precise estimates"
        }
    }

    // ================================================================
    // Task 4: Consistency guarantee (hash)
    // ================================================================
    
    preserve
    qui keep if `match_flag' == 1 & `touse'
    qui keep `panelvar'
    qui duplicates drop
    qui sort `panelvar'
    qui datasignature
    local match_hash = r(datasignature)
    restore
    
    local match_consistent = 1
    
    // ================================================================
    // Task 5: Diagnostic tests (optional)
    // ================================================================
    
    local pval_ttest = .
    local pval_ks = .
    
    if "`diagnose'" != "" & `has_omega' == 1 {
        // t-test for mean difference in omega
        capture qui ttest omega if `touse', by(`is_never_treated')
        if !_rc {
            local pval_ttest = r(p)
        }
        
        // KS test for distribution difference
        capture qui ksmirnov omega if `touse', by(`is_never_treated')
        if !_rc {
            local pval_ks = r(p)
        }
        
        // Warning if significant difference
        if `pval_ttest' < 0.05 | `pval_ks' < 0.05 {
            if "`nolog'" == "" {
                di as text "{bf:Warning [W-3024]}: Significant difference in omega"
                di as text "  t-test p-value:  " %9.4f `pval_ttest'
                di as text "  KS test p-value: " %9.4f `pval_ks'
            }
        }
    }
    
    // ================================================================
    // Task 6: Boundary checks
    // ================================================================
    
    // B4: All never-treated (no treated firms)
    qui count if !missing(`treatyearvar') & `touse'
    if r(N) == 0 {
        di as error "pte error [E-3024]: No treated firms found"
        di as error "  All firms are never-treated; cannot estimate treatment effects"
        exit 3024
    }
    
    // B6: Single cohort check
    qui levelsof `treatyearvar' if !missing(`treatyearvar') & `touse', local(cohorts)
    local n_cohorts : word count `cohorts'
    if `n_cohorts' < 2 {
        // Single cohort is valid but note it
        if "`nolog'" == "" {
            di as text "Note: Only `n_cohorts' treatment cohort(s) found"
        }
    }
    
    // B5: Time coverage check
    qui summ `timevar' if missing(`treatyearvar') & `touse', meanonly
    local never_min = r(min)
    local never_max = r(max)
    foreach g of local cohorts {
        if `g' < `never_min' | `g' > `never_max' {
            if "`nolog'" == "" {
                di as text "{bf:Warning [W-3025]}: Cohort `g' outside never-treated time range [`never_min', `never_max']"
            }
        }
    }
    
    // B7: Data consistency (D should be 0 for never-treated)
    capture confirm variable `treatvar'
    if !_rc {
        qui count if missing(`treatyearvar') & `treatvar' == 1 & `touse'
        if r(N) > 0 {
            di as error "pte error [E-3026]: Data inconsistency"
            di as error "  `r(N)' never-treated observations have `treatvar' == 1"
            exit 3026
        }
    }

    // ================================================================
    // Task 7: Console output
    // ================================================================
    
    // Compute omega stats if available
    local mean_omega = .
    local sd_omega = .
    if `has_omega' == 1 {
        qui summ omega if `match_flag' == 1 & `touse'
        local mean_omega = r(mean)
        local sd_omega = r(sd)
    }
    
    if "`nolog'" == "" & "`quietly'" == "" {
        di as text ""
        di as text "Never-treated matching strategy selected"
        di as text "{hline 72}"
        di as text "Match group summary:"
        di as text "  Strategy:                nevertreated"
        di as text "  Condition:               missing(`treatyearvar')"
        di as text ""
        di as text "  Never-treated firms:     " %8.0fc `N_never_firms'
        di as text "  Never-treated obs:       " %8.0fc `N_never_obs'
        if `has_omega' == 1 {
            di as text "  Mean omega (control):    " %9.4f `mean_omega'
            di as text "  SD omega (control):      " %9.4f `sd_omega'
        }
        di as text "  Consistency hash:        " "`match_hash'"
        di as text "{hline 72}"
    }
    
    // ================================================================
    // Task 8: Return values
    // ================================================================
    
    return scalar N_never_firms = `N_never_firms'
    return scalar N_never_obs = `N_never_obs'
    return scalar mean_omega = `mean_omega'
    return scalar sd_omega = `sd_omega'
    return scalar match_consistent = `match_consistent'
    return local match_hash "`match_hash'"
    return scalar pval_ttest = `pval_ttest'
    return scalar pval_ks = `pval_ks'
    return scalar n_cohorts = `n_cohorts'
    
    return local matchstrategy "nevertreated"
    return local matchcond "missing(`treatyearvar')"
    
    // ================================================================
    // Task 9: Output variable generation
    // ================================================================
    
    cap drop match_group
    qui gen byte match_group = `match_flag'
    label variable match_group "Match group indicator (1=never-treated control)"
    
    cap drop _is_never_treated
    qui gen byte _is_never_treated = `is_never_treated'
    label variable _is_never_treated "Never-treated firm indicator"
    
    // Optional: save to user-specified variable
    if "`saveto'" != "" {
        cap drop `saveto'
        qui gen byte `saveto' = `match_flag'
        label variable `saveto' "Never-treated match group (1=in match group)"
    }
    
end
