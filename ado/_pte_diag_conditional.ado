*! _pte_diag_conditional.ado
*! Conditional Distribution Test for Assumption 4.1
*!
*! Tests whether eps0 distributions are stable over time WITHIN
*! each initial productivity bin. Validates Assumption 4.1
*! (conditional parallel trends).
*!
*! Algorithm:
*!   1. Compute initial productivity (omega_init)
*!      - Treated: omega at _pte_nt == -1
*!      - Control: omega at a common pre-entry anchor when identified,
*!        otherwise first-year omega (or explicit baseyear)
*!   2. Bin firms by omega_init using xtile (default 3 bins)
*!   3. Split time into early/late at the common entry boundary when
*!      identified, otherwise at the observed midpoint year
*!   4. Winsorize eps0 (unless notrimeps)
*!   5. For each bin, run ksmirnov eps0 by time_group
*!   6. Summarize: all pass -> 1, any fail -> 0, all skipped -> .

version 14.0
program define _pte_diag_conditional, rclass
    version 14.0
    
    syntax , [eps0(varname) omega(varname) bins(integer 3) ///
              initomega(varname) baseyear(integer -1) ///
              minobs(integer 30) alpha(real 0.05) ///
              NOTRIMeps STRICTcontrol QUIetly]

    // Fail-closed worker contract: if any prerequisite gate below aborts,
    // callers must not inherit stale conditional diagnostics from an earlier
    // successful run in the same session.
    return clear
    
    // =========================================================
    // 1. Parameter validation
    // =========================================================
    
    if `bins' < 2 | `bins' > 10 {
        di as error "bins() must be between 2 and 10"
        exit 198
    }
    
    if `minobs' < 10 {
        di as error "minobs() must be at least 10"
        exit 198
    }
    
    if `alpha' <= 0 | `alpha' >= 1 {
        di as error "alpha() must be between 0 and 1"
        exit 198
    }
    
    // Determine variable names
    if "`eps0'" == "" {
        local eps0 "_pte_eps0"
    }
    if "`omega'" == "" {
        local omega "_pte_omega"
    }
    
    // Check required variables exist
    capture confirm numeric variable `eps0', exact
    if _rc != 0 {
        di as error "Variable `eps0' not found or not numeric. Run pte estimation first."
        exit 111
    }
    
    capture confirm numeric variable `omega', exact
    if _rc != 0 {
        di as error "Variable `omega' not found or not numeric. Run pte estimation first."
        exit 111
    }

    quietly _pte_diag_eps0_support_if, epsvar(`eps0') ///
        context("conditional diagnostics")
    local use_support = r(uses_support)
    
    capture confirm variable _pte_treat, exact
    if _rc != 0 {
        di as error "Variable _pte_treat not found. Run pte_setup first."
        exit 111
    }
    _pte_validate_internal_state _pte_treat binary ///
        "Conditional diagnostics require _pte_treat to remain the certified binary ever-treated indicator."
    
    capture confirm variable _pte_nt, exact
    if _rc != 0 {
        di as error "Variable _pte_nt not found. Run pte_setup first."
        exit 111
    }
    _pte_validate_internal_state _pte_nt integer ///
        "Conditional diagnostics require _pte_nt to remain the certified integer event-time index."
    
    // =========================================================
    // 2. Get panel structure
    // =========================================================
    // The conditional diagnostic shares the same panel/time contract as the
    // K-S and pretrend branches. Use the shared resolver so setup-selected
    // panel/time overrides survive after pte_setup restores caller xtset.
    _pte_diag_panel_contract, context("conditional diagnostics") allowsetupmissingxtdelta
    local idvar = r(idvar)
    local timevar = r(timevar)

    tempvar _pte_conditional_scope
    gen byte `_pte_conditional_scope' = 1
    if "`strictcontrol'" != "" {
        replace `_pte_conditional_scope' = (_pte_treat == 0)
    }

    // baseyear() pins initial productivity to a specific calendar year.
    // Without an explicit baseyear(), prefer the common treatment-entry
    // boundary identified by the live event-time support. This matches the
    // official identification_check design on common-entry fixtures while
    // retaining a midpoint fallback when no common pre-entry anchor exists.
    local effective_baseyear = `baseyear'
    local inferred_anchor = 0
    if `effective_baseyear' == -1 {
        quietly levelsof `timevar' if _pte_treat == 1 & _pte_nt == 0 ///
            & !missing(`omega'), local(entry_years)
        local n_entry_years : word count `entry_years'
        if `n_entry_years' == 1 {
            local entry_year : word 1 of `entry_years'
            local candidate_baseyear = `entry_year' - 1
            quietly count if `_pte_conditional_scope' == 1 ///
                & `timevar' == `candidate_baseyear' & !missing(`omega')
            if r(N) > 0 {
                local effective_baseyear = `candidate_baseyear'
                local inferred_anchor = 1
            }
        }
    }

    // If the active baseyear is completely absent from the relevant omega
    // support, the conditional-bin construction is unidentified and should
    // fail explicitly instead of bubbling up as an xtile() no-observation
    // error. strictcontrol must validate support on the control-only sample,
    // because treated-only support must not anchor a control-only diagnostic.
    if `effective_baseyear' != -1 {
        quietly count if `_pte_conditional_scope' == 1 ///
            & `timevar' == `effective_baseyear' & !missing(`omega')
        if r(N) == 0 {
            di as error "baseyear(`effective_baseyear') is outside the observed support of `timevar' for nonmissing `omega'"
            exit 198
        }
    }
    
    // =========================================================
    // 3. Compute initial productivity (omega_init)
    // =========================================================
    
    tempvar omega_init omega_pre omega_first omega_first_max valid_init
    
    if "`initomega'" != "" {
        // User-specified initial omega
        gen double `omega_init' = `initomega'
    }
    else if `effective_baseyear' != -1 {
        // Replication mode: use specified year for all firms
        if "`quietly'" == "" {
            if `inferred_anchor' {
                di as text "Using inferred entry anchor: year == `effective_baseyear'"
            }
            else {
                di as text "Using baseyear mode: year == `effective_baseyear'"
            }
        }
        
        gen double `omega_init' = .
        bys `idvar': replace `omega_init' = `omega' if `timevar' == `effective_baseyear'
        // Fill down
        bys `idvar' (`timevar'): replace `omega_init' = `omega_init'[_n-1] if missing(`omega_init')
        // Fill up
        gsort `idvar' -`timevar'
        bys `idvar': replace `omega_init' = `omega_init'[_n-1] if missing(`omega_init')
        sort `idvar' `timevar'
    }
    else {
        // Generalized mode:
        //   Treated: omega at _pte_nt == -1 (one period before treatment)
        //   Control: omega at first year of data
        
        // Step 3a: Treated firms - use omega at _pte_nt == -1
        bys `idvar': egen double `omega_pre' = mean(`omega') if _pte_nt == -1
        bys `idvar': egen double `omega_init' = max(`omega_pre')
        
        // Step 3b: Control firms (never treated) - use first year omega
        qui summ `timevar' if `_pte_conditional_scope' == 1 & !missing(`omega')
        local first_year = r(min)
        
        bys `idvar': egen double `omega_first' = mean(`omega') if `timevar' == `first_year'
        bys `idvar': egen double `omega_first_max' = max(`omega_first')
        replace `omega_init' = `omega_first_max' if missing(`omega_init') & _pte_treat == 0
    }
    
    // Check missing rate for treated firms
    qui count if missing(`omega_init') & _pte_treat == 1
    local n_miss_treat = r(N)
    qui count if _pte_treat == 1
    local n_treat_total = r(N)
    
    if `n_treat_total' > 0 {
        local miss_rate = `n_miss_treat' / `n_treat_total' * 100
        if `miss_rate' > 10 & "`quietly'" == "" {
            di as error "Warning: " %4.1f `miss_rate' "% of treated firms missing omega_init"
        }
    }
    
    // Mark valid observations (have omega_init)
    gen byte `valid_init' = !missing(`omega_init')
    
    // =========================================================
    // 4. Quantile binning (on firm-level unique values)
    // =========================================================
    // Replication code approach: xtile omgBins = omega if year==..., n(3)
    // We use tag to get one obs per firm, avoiding panel duplicates
    
    tempvar omega_bins tag_firm bins_max
    egen byte `tag_firm' = tag(`idvar') if `valid_init' & `_pte_conditional_scope' == 1
    qui xtile `omega_bins' = `omega_init' if `tag_firm' == 1, n(`bins')
    
    // Fill bins across all periods within each firm
    bys `idvar': egen byte `bins_max' = max(`omega_bins')
    replace `omega_bins' = `bins_max' if missing(`omega_bins') & `valid_init'
    
    // =========================================================
    // 5. Time group definition
    // =========================================================
    
    qui summ `timevar' if `_pte_conditional_scope' == 1
    local min_year = r(min)
    local max_year = r(max)
    local time_span = `max_year' - `min_year' + 1
    
    if `effective_baseyear' != -1 {
        // baseyear mode: split at baseyear + 1
        // Replication code L147: g group = (year>=2011) i.e. baseyear+1
        local mid_year = `effective_baseyear' + 1
    }
    else {
        // Default: median year split
        local mid_year = floor((`min_year' + `max_year') / 2)
    }
    
    if `time_span' < 3 & "`quietly'" == "" {
        di as error "Warning: Time span (`time_span' years) may be too short"
    }
    
    tempvar time_group
    gen byte `time_group' = (`timevar' >= `mid_year')
    
    // =========================================================
    // 5A. eps0 Winsorization
    // =========================================================
    // Replication code L144: winsor2 eps0_a, replace cuts(1 99) trim
    
    tempvar eps0_use
    gen double `eps0_use' = `eps0'
    if `use_support' {
        quietly replace `eps0_use' = . if _pte_eps0_ind != 1
    }
    
    if "`notrimeps'" == "" {
        if "`strictcontrol'" != "" {
            quietly _pte_trim_var `eps0_use' if `_pte_conditional_scope' == 1
        }
        else {
            // Match the replication trim law with the package-owned
            // deterministic worker instead of depending on winsor2.
            qui _pte_trim_var `eps0_use'
        }
    }
    
    // =========================================================
    // 6. Output header
    // =========================================================
    
    if "`quietly'" == "" {
        di as text _n "{hline 70}"
        di as text "{bf:Conditional Distribution Test (by Initial Productivity)}"
        di as text "{hline 70}"
        di as text "Testing Assumption 4.1: Conditional parallel trends"
        di as text "Number of productivity bins: `bins'"
        di as text "Time split: year < `mid_year' (early) vs year >= `mid_year' (late)"
        di as text "Significance level: alpha = `alpha'"
        local half_minobs = floor(`minobs' / 2)
        di as text "Minimum sample size: `minobs' (total), `half_minobs' (each period)"
        if "`strictcontrol'" != "" {
            di as text "Sample: control group only (strictcontrol)"
        }
        else {
            di as text "Sample: all non-missing eps0"
        }
        if "`notrimeps'" == "" {
            di as text "eps0 Winsorized: 1%-99% (trim)"
        }
        else {
            di as text "eps0 Winsorized: no (notrimeps)"
        }
        di as text "{hline 70}"
    }
    
    // =========================================================
    // 7. K-S test loop over bins
    // =========================================================
    
    local all_pass = 1
    local any_executed = 0
    local incomplete = 0
    
    forv b = 1/`bins' {
        // Get omega range for this bin
        qui summ `omega_init' if `omega_bins' == `b' & `valid_init' ///
            & `_pte_conditional_scope' == 1
        local omega_min`b' = r(min)
        local omega_max`b' = r(max)
        
        if "`quietly'" == "" {
            di as text _n "Bin `b': omega_init in [" %7.4f `omega_min`b'' ", " %7.4f `omega_max`b'' "]"
        }
        
        // Count samples based on selection mode
        // Default: all non-missing eps0 (matches replication code)
        // strictcontrol: only _pte_treat == 0
        if "`strictcontrol'" != "" {
            qui count if `omega_bins' == `b' & _pte_treat == 0 & !missing(`eps0_use')
            local n_total = r(N)
            qui count if `omega_bins' == `b' & _pte_treat == 0 & !missing(`eps0_use') & `time_group' == 0
            local n_early = r(N)
            qui count if `omega_bins' == `b' & _pte_treat == 0 & !missing(`eps0_use') & `time_group' == 1
            local n_late = r(N)
        }
        else {
            qui count if `omega_bins' == `b' & !missing(`eps0_use')
            local n_total = r(N)
            qui count if `omega_bins' == `b' & !missing(`eps0_use') & `time_group' == 0
            local n_early = r(N)
            qui count if `omega_bins' == `b' & !missing(`eps0_use') & `time_group' == 1
            local n_late = r(N)
        }
        
        // Store sample counts
        return scalar n_cond`b' = `n_total'
        return scalar n_early`b' = `n_early'
        return scalar n_late`b' = `n_late'
        return scalar omega_min`b' = `omega_min`b''
        return scalar omega_max`b' = `omega_max`b''
        
        // Check minimum sample size
        local half_minobs = floor(`minobs' / 2)
        if `n_total' < `minobs' | `n_early' < `half_minobs' | `n_late' < `half_minobs' {
            if "`quietly'" == "" {
                di as text "  N = `n_total' (early=`n_early', late=`n_late')"
                di as text "  {bf:Skipped}: Insufficient observations"
            }
            
            return scalar ks_D_cond`b' = .
            return scalar ks_p_cond`b' = .
            local incomplete = 1
        }
        else {
            // Execute K-S test (using Winsorized eps0)
            if "`strictcontrol'" != "" {
                qui ksmirnov `eps0_use' if `omega_bins' == `b' & _pte_treat == 0 & !missing(`eps0_use'), by(`time_group')
            }
            else {
                qui ksmirnov `eps0_use' if `omega_bins' == `b' & !missing(`eps0_use'), by(`time_group')
            }
            local ks_D = r(D)
            local ks_p = r(p)
            
            local any_executed = 1
            
            if "`quietly'" == "" {
                di as text "  N = `n_total' (early=`n_early', late=`n_late')"
                di as text "  D = " %7.4f `ks_D' ", p = " %7.4f `ks_p' _c
            }
            
            if `ks_p' < `alpha' {
                if "`quietly'" == "" {
                    di as error "  FAIL"
                }
                local all_pass = 0
            }
            else {
                if "`quietly'" == "" {
                    di as result "  PASS"
                }
            }
            
            return scalar ks_D_cond`b' = `ks_D'
            return scalar ks_p_cond`b' = `ks_p'
        }
    }
    
    // =========================================================
    // 8. Summary judgment
    // =========================================================
    
    if "`quietly'" == "" {
        di as text _n "{hline 70}"
    }
    
    if `any_executed' == 0 {
        if "`quietly'" == "" {
            di as error "Overall: All bins skipped due to insufficient samples"
            di as error "         Cannot assess conditional parallel trends"
        }
        return scalar conditional_pass = .
    }
    else if `all_pass' == 1 {
        if "`quietly'" == "" {
            di as result "Overall: Conditional parallel trends supported"
        }
        return scalar conditional_pass = 1
    }
    else {
        if "`quietly'" == "" {
            di as error "Overall: Conditional parallel trends may be violated"
        }
        return scalar conditional_pass = 0
    }
    
    if `incomplete' == 1 & "`quietly'" == "" {
        di as text "Note: Some bins were skipped due to insufficient samples"
    }
    
    if "`quietly'" == "" {
        di as text "{hline 70}"
    }
    
    // =========================================================
    // 9. Return other results
    // =========================================================
    
    return scalar ks_incomplete = `incomplete'
    return scalar bins = `bins'
    return scalar mid_year = `mid_year'
    return scalar alpha = `alpha'
    return scalar minobs = `minobs'
    return local sample_mode = cond("`strictcontrol'" != "", "strictcontrol", "all_nonmissing")
    return local winsorized = cond("`notrimeps'" == "", "yes", "no")
    
end
