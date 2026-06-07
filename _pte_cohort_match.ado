*! _pte_cohort_match.ado
*! Matching Group Construction (notyettreated/nevertreated/custom)

version 14.0
capture program drop _pte_cohort_match
program define _pte_cohort_match, rclass
    version 14.0
    
    // ================================================================
    // Task-2: Parameter parsing
    // ================================================================
    
    syntax , cohort(integer) [max_periods(integer 4) ///
             matchstrategy(string) matchexpr(string) treatvar(varname) ///
             treatyearvar(varname) strict nolog minobs(integer 30)]
    
    // Default variable names
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
        // Prefer the public/DO cohort anchor before any private scratch state.
        foreach _pte_treatyear_candidate in treat_yr0 _pte_treat_year _pte_cohort_var treat_year {
            capture confirm variable `_pte_treatyear_candidate', exact
            if _rc == 0 {
                local treatyearvar "`_pte_treatyear_candidate'"
                continue, break
            }
        }
        if "`treatyearvar'" == "" local treatyearvar "treat_year"
    }
    if "`matchstrategy'" == "" local matchstrategy "notyettreated"
    
    // Parameter range validation
    if `max_periods' < 0 | `max_periods' > 10 {
        di as error "max_periods() must be between 0 and 10"
        exit 198
    }
    
    if `minobs' < 10 {
        di as error "minobs() must be at least 10"
        exit 198
    }
    
    // ================================================================
    // Task-3: Panel structure validation
    // ================================================================
    
    confirm variable `treatvar'
    confirm variable `treatyearvar'
    
    qui xtset
    local idvar = r(panelvar)
    local timevar = r(timevar)
    local panel_delta "`r(tdelta)'"
    
    if "`idvar'" == "" | "`timevar'" == "" {
        di as error "Data must be xtset"
        exit 459
    }
    local pte_time_delta = real("`panel_delta'")
    if missing(`pte_time_delta') | `pte_time_delta' <= 0 {
        local pte_time_delta = 1
    }
    
    // ================================================================
    // Task-4/5: Matching condition generation
    // ================================================================
    
    local g = `cohort'
    local L = `max_periods'
    local g_plus_L = `g' + (`L' * `pte_time_delta')
    
    if "`matchstrategy'" == "notyettreated" {
        // g' = {i* : e_{i*} > g + L} ∪ {i* : e_{i*} = ∞}
        local matchcond "(`treatyearvar' > `g_plus_L') | missing(`treatyearvar')"
    }
    else if "`matchstrategy'" == "nevertreated" {
        // g' = {i* : e_{i*} = ∞} (never-treated only)
        local matchcond "missing(`treatyearvar')"
    }
    else if "`matchstrategy'" == "custom" {
        if `"`matchexpr'"' == "" {
            di as error "{bf:pte error E-3017}: matchstrategy(custom) requires matchexpr()"
            exit 198
        }
        local matchcond `"`matchexpr'"'
    }
    else {
        di as error "Unknown matchstrategy: `matchstrategy'"
        di as error "Valid options: notyettreated, nevertreated, custom"
        exit 198
    }
    
    // ================================================================
    // Task-7: Treatment group marking
    // ================================================================
    
    tempvar treat_group match_group nt_var
    
    // Treatment group: firms whose observed cohort anchor equals g
    qui gen byte `treat_group' = (`treatyearvar' == `g') if !missing(`treatyearvar')
    qui replace `treat_group' = 0 if missing(`treat_group')
    
    // ================================================================
    // Task-8: Matching group marking
    // ================================================================
    
    qui gen byte `match_group' = (`matchcond') if !missing(`treatyearvar') | missing(`treatyearvar')
    // Ensure treatment group is NOT in matching group
    qui replace `match_group' = 0 if `treat_group' == 1
    qui replace `match_group' = 0 if missing(`match_group')
    
    // ================================================================
    // Task-9: Mutual exclusivity verification
    // ================================================================
    
    qui count if `treat_group' == 1 & `match_group' == 1
    if r(N) > 0 {
        di as error "Error: Treatment and matching groups overlap"
        exit 198
    }

    // ================================================================
    // Task-10: nt (relative time) calculation
    // Computed on full data BEFORE keep filtering
    // ================================================================
    
    cap drop nt
    qui gen double nt = (`timevar' - `g') / `pte_time_delta'
    qui replace nt = round(nt) if !missing(nt) & abs(nt - round(nt)) <= 1e-10
    label var nt "Relative time ((time - `g') / delta)"
    
    // ================================================================
    // Milestone 5: Sample size statistics & boundary handling
    // MUST execute BEFORE M6 (keep filtering), because fallback
    // may update match_group
    // ================================================================
    
    // Task-13: Sample size statistics
    
    // Treatment group firm count
    tempvar treat_firm
    qui egen `treat_firm' = tag(`idvar') if `treat_group' == 1
    qui count if `treat_firm' == 1
    local N_treat = r(N)
    
    // Not-yet-treated firm count
    tempvar nyt_firm
    qui egen `nyt_firm' = tag(`idvar') if `treatyearvar' > `g_plus_L' & !missing(`treatyearvar')
    qui count if `nyt_firm' == 1
    local N_notyettreated = r(N)
    
    // Never-treated firm count
    tempvar nevt_firm
    qui egen `nevt_firm' = tag(`idvar') if missing(`treatyearvar')
    qui count if `nevt_firm' == 1
    local N_nevertreated = r(N)
    
    // Matching group observations in analysis window (nt >= 0)
    qui count if `match_group' == 1 & nt >= 0
    local N_match_obs = r(N)

    // ================================================================
    // Task-14: Fallback mechanism
    // If no not-yet-treated, fall back to never-treated
    // ================================================================
    
    local fallback = 0
    
    if `N_notyettreated' == 0 & "`matchstrategy'" == "notyettreated" {
        if `N_nevertreated' > 0 {
            // Fall back to never-treated
            if "`nolog'" == "" {
                di as text "{bf:Warning W-3015}: Cohort `g' has no not-yet-treated controls"
                di as text "  Falling back to never-treated controls (N = `N_nevertreated')"
            }
            
            local matchcond "missing(`treatyearvar')"
            qui replace `match_group' = (`matchcond')
            qui replace `match_group' = 0 if `treat_group' == 1
            qui replace `match_group' = 0 if missing(`match_group')
            local fallback = 1
            
            // Recount match obs after fallback
            qui count if `match_group' == 1 & nt >= 0
            local N_match_obs = r(N)
        }
        else {
            // No valid control group at all
            if "`strict'" != "" {
                di as error "Error E-3012: Cohort `g' has no valid control group"
                exit 3012
            }
            else {
                if "`nolog'" == "" {
                    di as text "{bf:Warning}: Cohort `g' has no valid control group - Skipping"
                }
                return scalar skip = 1
                return scalar cohort = `g'
                exit 0
            }
        }
    }

    // ================================================================
    // Task-15: Sample size threshold warnings
    // ================================================================
    
    if `N_match_obs' == 0 {
        if "`strict'" != "" {
            di as error "Error E-3012: Cohort `g' has no control observations in window"
            exit 3012
        }
        else {
            if "`nolog'" == "" {
                di as text "{bf:Warning}: Cohort `g' has no control observations - Skipping"
            }
            return scalar skip = 1
            return scalar cohort = `g'
            exit 0
        }
    }
    else if `N_match_obs' < 10 {
        if "`nolog'" == "" {
            di as text "{bf:Warning W-3016}: Cohort `g' has only `N_match_obs' control observations (< 10)"
            di as text "  Skipping this cohort"
        }
        return scalar skip = 1
        return scalar cohort = `g'
        exit 0
    }
    else if `N_match_obs' < `minobs' {
        if "`nolog'" == "" {
            di as text "{bf:Warning W-3010}: Cohort `g' has only `N_match_obs' control observations (< `minobs')"
            di as text "  ATT estimates may have low precision"
        }
    }
    
    // ================================================================
    // Milestone 6: Data filtering & verification
    // Executed AFTER M5 so match_group is finalized
    // ================================================================
    
    // Task-11: Keep only treatment and matching group firms
    qui keep if `treat_group' == 1 | `match_group' == 1
    
    // Task-12: Time window filtering
    qui keep if nt >= -1 & nt <= `L'

    // ================================================================
    // Task-12a: D=0 verification for matching group
    // ================================================================
    
    qui count if `match_group' == 1 & nt >= 0 & `treatvar' == 1
    local N_violations = r(N)
    
    if `N_violations' > 0 {
        di as error "Error E-3012: Control group has D=1 observations in nt >= 0"
        di as error "  Found `N_violations' violations in cohort `g'"
        exit 3012
    }
    
    // ================================================================
    // Task-12b: Post-filter sample size verification
    // ================================================================
    
    qui count if `match_group' == 1 & nt >= 0
    local N_match_obs = r(N)
    
    if `N_match_obs' == 0 {
        di as error "Error E-3012: No valid control observations after filtering"
        exit 3012
    }
    else if `N_match_obs' < 10 {
        if "`nolog'" == "" {
            di as text "{bf:Warning W-3016}: Cohort `g' has only `N_match_obs' control obs after filtering (< 10)"
            di as text "  Skipping this cohort"
        }
        return scalar skip = 1
        return scalar N_match_obs = `N_match_obs'
        return scalar cohort = `g'
        exit 0
    }
    else if `N_match_obs' < `minobs' {
        if "`nolog'" == "" {
            di as text "{bf:Warning W-3010}: Cohort `g' has only `N_match_obs' control obs after filtering (< `minobs')"
            di as text "  ATT estimates may have low precision"
        }
    }

    // ================================================================
    // Task-16: Diagnostic output
    // ================================================================
    
    if "`nolog'" == "" {
        di as text ""
        di as text "Cohort g = `g': Matching group construction"
        di as text "  Strategy: `matchstrategy'" _c
        if `fallback' == 1 {
            di as text " (fallback to nevertreated)"
        }
        else {
            di ""
        }
        if "`matchstrategy'" == "custom" {
            di as text "  Custom expr: `matchexpr'"
        }
        di as text "  Condition: `matchcond'"
        di as text "  Treated firms     (n = `N_treat')"
        di as text "  Not-yet-treated   (n = `N_notyettreated')"
        di as text "  Never-treated     (n = `N_nevertreated')"
        di as text "  Control obs in window (N = `N_match_obs')"
    }
    
    // ================================================================
    // Task-17: Return values
    // ================================================================
    
    return scalar N_treat = `N_treat'
    return scalar N_notyettreated = `N_notyettreated'
    return scalar N_nevertreated = `N_nevertreated'
    return scalar N_match = `N_notyettreated' + `N_nevertreated'
    return scalar N_match_obs = `N_match_obs'
    return local matchcond "`matchcond'"
    return local matchstrategy "`matchstrategy'"
    if "`matchstrategy'" == "custom" {
        return local matchexpr `"`matchexpr'"'
    }
    return scalar fallback = `fallback'
    return scalar cohort = `g'
    return scalar max_periods = `L'
    return scalar skip = 0
    
end
