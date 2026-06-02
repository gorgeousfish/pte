*! _pte_match_custom.ado
*! Custom Matching Group Construction

version 14.0
capture program drop _pte_match_custom
program define _pte_match_custom, rclass
    version 14.0
    
    syntax , cohort(integer) matchexpr(string) max_periods(integer) ///
            [treatvar(varname) treatyearvar(varname) strict nolog]
    
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
    
    // Store matching condition
    local matchcond `"`matchexpr'"'
    
    // ================================================================
    // Step 1: Verify panel structure
    // ================================================================
    
    qui xtset
    local panelvar = r(panelvar)
    local timevar = r(timevar)
    
    // ================================================================
    // Step 2: Identify treatment and matching groups
    // ================================================================
    
    // Treatment group: firms whose observed cohort anchor equals the target cohort
    tempvar treat_group match_group
    qui gen byte `treat_group' = (`treatyearvar' == `cohort') if !missing(`treatyearvar')
    qui replace `treat_group' = 0 if missing(`treat_group')
    
    // Matching group: satisfies custom expression AND not in treatment group
    qui gen byte `match_group' = (`matchexpr') if `treat_group' == 0
    qui replace `match_group' = 0 if missing(`match_group')
    
    // ================================================================
    // Step 3: Generate relative time nt
    // ================================================================
    
    cap drop nt
    qui gen int nt = `timevar' - `cohort'
    
    // ================================================================
    // Step 4: Keep only relevant observations (time window)
    // ================================================================
    
    qui keep if (`treat_group' == 1 | `match_group' == 1)
    qui keep if nt >= -1 & nt <= `max_periods'
    
    // ================================================================
    // Step 5: D=0 constraint verification for matching group
    // ================================================================
    
    qui count if `match_group' == 1 & nt >= 0 & `treatvar' == 1
    if r(N) > 0 {
        local n_violations = r(N)
        di as error "{bf:pte error E-3012}: Control group has D=1 observations in nt >= 0"
        di as error "  Cohort: `cohort'"
        di as error "  matchexpr: `matchexpr'"
        di as error "  Violation count: `n_violations'"
        exit 3012
    }
    
    // ================================================================
    // Step 6: Sample size validation
    // ================================================================
    
    // Count matching group firms
    tempvar firm_tag_m
    qui egen `firm_tag_m' = tag(`panelvar') if `match_group' == 1
    qui count if `firm_tag_m' == 1
    local N_match_firms = r(N)
    
    // Count matching group observations in analysis window (nt >= 0)
    qui count if `match_group' == 1 & nt >= 0
    local N_match_obs = r(N)
    
    // Count treatment group firms
    tempvar firm_tag_t
    qui egen `firm_tag_t' = tag(`panelvar') if `treat_group' == 1
    qui count if `firm_tag_t' == 1
    local N_treat_firms = r(N)
    
    // Count treatment group observations
    qui count if `treat_group' == 1
    local N_treat_obs = r(N)
    
    // Validate
    local skip = 0
    if `N_match_obs' == 0 {
        if "`strict'" != "" {
            di as error "{bf:pte error E-3020}: Cohort `cohort' has no valid matches"
            exit 3020
        }
        else {
            if "`nolog'" == "" {
                di as text "{bf:Warning W-3020}: Cohort `cohort' has no valid matches for custom condition"
                di as text "  Skipping this cohort"
            }
            local skip = 1
        }
    }
    else if `N_match_firms' < 10 {
        if "`nolog'" == "" {
            di as text "{bf:Warning W-3016}: Cohort `cohort' has only `N_match_firms' control firms (< 10)"
            di as text "  Skipping this cohort due to insufficient sample size"
        }
        local skip = 1
    }
    else if `N_match_firms' < 30 {
        if "`nolog'" == "" {
            di as text "{bf:Warning W-3010}: Cohort `cohort' has only `N_match_firms' control firms (< 30)"
            di as text "  ATT estimates may have low precision"
        }
    }
    
    // ================================================================
    // Step 7: Diagnostic output
    // ================================================================
    
    if "`nolog'" == "" {
        di as text ""
        di as text "Cohort g = `cohort': Custom matching group construction"
        di as text "{hline 72}"
        di as text "  Strategy:              custom"
        di as text "  Condition:             `matchexpr'"
        di as text "  Treated firms:         " %8.0fc `N_treat_firms'
        di as text "  Treated obs:           " %8.0fc `N_treat_obs'
        di as text "  Control firms:         " %8.0fc `N_match_firms'
        di as text "  Control obs (nt>=0):   " %8.0fc `N_match_obs'
        if `skip' {
            di as text "  Status:                SKIPPED"
        }
        else {
            di as text "  Status:                OK"
        }
        di as text "{hline 72}"
    }
    
    // ================================================================
    // Step 8: Generate output variables
    // ================================================================
    
    cap drop match_group
    qui gen byte match_group = `match_group'
    label variable match_group "Custom match group (1=control)"
    
    cap drop treat_group
    qui gen byte treat_group = `treat_group'
    label variable treat_group "Treatment group (1=treated)"
    
    // ================================================================
    // Step 9: Return values
    // ================================================================
    
    return scalar N_treat_firms = `N_treat_firms'
    return scalar N_treat_obs = `N_treat_obs'
    return scalar N_match_firms = `N_match_firms'
    return scalar N_match_obs = `N_match_obs'
    return scalar cohort = `cohort'
    return scalar max_periods = `max_periods'
    return scalar skip = `skip'
    
    return local matchstrategy "custom"
    return local matchcond `"`matchexpr'"'
    
end
