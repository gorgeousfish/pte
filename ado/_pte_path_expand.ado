*! _pte_path_expand.ado
*! Expands treated ATT observations into multiple Monte Carlo simulation paths.
*! Core logic:
*! - Smart nsim default based on omegapoly (linear=1, nonlinear=100)
*! - Uses Stata expand to replicate treated ATT observations
*! - Generates copy_id and firm_sim_id identifiers
*! - Re-tsset so lag operators work within each path

version 14.0
capture program drop _pte_path_expand
program define _pte_path_expand
    // Note: NOT eclass — avoid ereturn clear destroying upstream e() values
    version 14.0
    
    // ================================================================
    // Syntax parsing (IMPL-002)
    // Required: firm(varname), nt(varname)
    // Optional: nsim(integer -1), omegapoly(integer 0), treatment(varname)
    //   nsim sentinel = -1 (not 0, since nsim=0 is illegal and should error)
    //   omegapoly sentinel = 0 (means "not specified by user")
    // ================================================================
    syntax, FIrm(varname) NT(varname) [NSim(integer -1) OMEGAPOLY(integer 0) TREATment(varname)]
    
    // ================================================================
    // Step 1: Obtain omegapoly (IMPL-003)
    // Priority: user-specified > e(omegapoly) > default 3
    // ================================================================
    if `omegapoly' == 0 {
        // User did not specify — try to retrieve from e()
        capture confirm scalar e(omegapoly)
        if _rc == 0 {
            local omegapoly = e(omegapoly)
        }
        else {
            local omegapoly = 3
            di as text "Note: omegapoly not found in e(), using default 3"
        }
    }
    
    // ================================================================
    // Step 2: nsim smart default based on omegapoly (IMPL-004)
    // omegapoly=1 (linear evolution) => current public ATT worker still
    //                                   follows the single-path DO-style
    //                                   simulation contract, so nsim=1
    // omegapoly>=2 (nonlinear)       => Monte Carlo needed, nsim=100
    // User-specified nsim overrides the default
    // ================================================================
    if `nsim' == -1 {
        // User did not specify nsim — apply smart default
        if `omegapoly' == 1 {
            local nsim = 1
            di as text "Note: omegapoly=1 (linear evolution), using nsim=1"
        }
        else {
            local nsim = 100
            di as text "Note: omegapoly>=2 (nonlinear evolution), using nsim=100"
        }
    }
    else {
        // User explicitly specified nsim — validate (IMPL-005)
        if `nsim' < 1 {
            di as error "Error: nsim must be >= 1, got `nsim'"
            exit 198
        }
        di as text "Using user-specified nsim=`nsim'"
    }
    
    // ================================================================
    // Step 3: nsim validation — redundant safety check (IMPL-005)
    // Catches any edge case where nsim ends up < 1
    // ================================================================
    if `nsim' < 1 {
        di as error "Error: nsim must be >= 1, got `nsim'"
        exit 198
    }
    
    // nsim > 10000 warning (large memory consumption)
    if `nsim' > 10000 {
        di as text "Warning: nsim=`nsim' is very large, this may consume significant memory"
    }
    
    // ================================================================
    // Step 4: Identify the treated ATT sample
    // Proposition 4.3 simulates counterfactual paths for treated firms only;
    // controls identify G_epsilon^0 but must not be replicated into paths.
    // ================================================================

    // Record original observation count
    qui count
    local N_original = r(N)

    tempvar _pte_expand_ever _pte_expand_n
    local treatment_var ""

    if "`treatment'" != "" {
        capture confirm variable `treatment', exact
        if _rc != 0 {
            di as error "Error: treatment variable `treatment' not found"
            exit 111
        }
        local treatment_var "`treatment'"
    }
    else {
        foreach _candidate in _pte_treat_group treat_post treat D {
            capture confirm variable `_candidate', exact
            if _rc == 0 {
                local treatment_var "`_candidate'"
                continue, break
            }
        }
    }

    if "`treatment_var'" != "" {
        capture confirm numeric variable `treatment_var'
        if _rc != 0 {
            di as error "Error: treatment variable `treatment_var' must be numeric"
            exit 111
        }
        capture assert inlist(`treatment_var', 0, 1) if !missing(`treatment_var')
        if _rc {
            di as error "Error: treatment variable `treatment_var' must be binary (0/1)"
            exit 450
        }
        quietly bysort `firm': egen byte `_pte_expand_ever' = max(`treatment_var')
        quietly count if `_pte_expand_ever' == 1
        local N_treated_original = r(N)
        quietly count if `_pte_expand_ever' == 0
        local N_control_original = r(N)
        quietly gen int `_pte_expand_n' = cond(`_pte_expand_ever' == 1, `nsim', 1)
    }
    else {
        quietly gen byte `_pte_expand_ever' = 1
        quietly gen int `_pte_expand_n' = `nsim'
        local N_treated_original = `N_original'
        local N_control_original = 0
        di as text "Note: no treatment variable detected; assuming current data are already the treated ATT sample"
    }

    if `N_treated_original' == 0 {
        di as error "Error: no treated ATT observations detected for path expansion"
        exit 2000
    }
    
    // ================================================================
    // Step 5: Data expansion — expand treated rows only (IMPL-006)
    // ================================================================
    
    // Check for variable name conflicts — drop if already exist
    foreach var in copy_id firm_sim_id {
        capture confirm variable `var'
        if _rc == 0 {
            di as text "Warning: Variable `var' already exists, replacing"
            drop `var'
        }
    }
    
    // Execute treated-only expand (controls remain single-copy)
    if `nsim' > 1 {
        qui expand `_pte_expand_n'
        di as text "Expanded treated ATT rows: " as result %10.0fc `N_treated_original' ///
            as text " x " as result `nsim' as text "; controls kept once"
    }
    else {
        di as text "nsim=1, no path replication needed"
    }
    
    // Verify expanded observation count
    qui count
    local N_expanded = r(N)
    local N_expected = `N_control_original' + `N_treated_original' * `nsim'
    if `N_expanded' != `N_expected' {
        di as error "Error: Expected `N_expected' obs after treated-only expansion, got `N_expanded'"
        exit 459
    }
    
    // ================================================================
    // Step 6: Generate copy_id within (firm, nt) groups (IMPL-007)
    //   bys firm nt: g copy_id = _n
    // ================================================================
    
    qui bysort `firm' `nt': gen int copy_id = _n
    label variable copy_id "Path copy identifier within (firm, nt)"
    
    // Verify copy_id range: treated rows use [1, nsim], controls stay at 1.
    qui summ copy_id if `_pte_expand_ever' == 1
    if r(min) != 1 | r(max) != `nsim' {
        di as error "Error: treated copy_id range [" r(min) ", " r(max) "] expected [1, `nsim']"
        exit 459
    }
    qui count if `_pte_expand_ever' == 0 & copy_id != 1
    if r(N) > 0 {
        di as error "Error: untreated/control observations should not be copied"
        exit 459
    }
    
    // ================================================================
    // Step 7: Generate firm_sim_id — unique path identifier (IMPL-008)
    //   egen firm_id = group(firm copy_id)
    // ================================================================
    
    qui egen long firm_sim_id = group(`firm' copy_id)
    label variable firm_sim_id "Unique path identifier for panel operations"
    
    // Sort by (firm_sim_id, nt) for isid and tsset
    sort firm_sim_id `nt'
    
    // Verify (firm_sim_id, nt) uniquely identifies observations
    capture isid firm_sim_id `nt'
    if _rc != 0 {
        di as error "Error: (firm_sim_id, `nt') is not unique after expansion"
        exit 459
    }
    
    // ================================================================
    // Step 8: Re-tsset with firm_sim_id as panelvar (IMPL-009)
    //   qui tsset firm_id nt
    // This ensures L.omega operates within each simulation path,
    // not across paths (copy_id=1 nt=0 must NOT lag from copy_id=2)
    // ================================================================
    
    qui tsset firm_sim_id `nt'
    
    // Verify tsset is correctly configured
    qui tsset
    if "`r(panelvar)'" != "firm_sim_id" {
        di as error "Error: tsset panelvar should be firm_sim_id, got `r(panelvar)'"
        exit 459
    }
    if "`r(timevar)'" != "`nt'" {
        di as error "Error: tsset timevar should be `nt', got `r(timevar)'"
        exit 459
    }
    
    // ================================================================
    // Step 9: Post-expansion validation (IMPL-010)
    // Verify: obs count, L.omega within-path correctness,
    //         omega consistency across copies within (firm, nt)
    // ================================================================
    
    // 7a. Verify observation count = controls + treated * nsim
    qui count
    assert r(N) == `N_expected'
    
    // 7b. Verify omega consistency: all copies within (firm, nt) have same omega
    capture confirm variable omega
    if _rc == 0 {
        tempvar omega_first omega_ok
        qui bysort `firm' `nt' (copy_id): gen double `omega_first' = omega[1]
        qui gen byte `omega_ok' = (omega == `omega_first') | ///
                                  (mi(omega) & mi(`omega_first'))
        qui count if `omega_ok' == 0
        if r(N) > 0 {
            di as error "Warning: omega not consistent within (firm, nt) in " r(N) " obs"
        }
    }
    
    // 7c. Spot-check L.omega within-path correctness (only if omega exists)
    capture confirm variable omega
    if _rc == 0 {
        // Re-sort after bysort in 7b changed sort order
        qui sort firm_sim_id `nt'
        tempvar test_lag manual_lag lag_ok
        qui gen double `test_lag' = L.omega
        qui bysort `firm' copy_id (`nt'): gen double `manual_lag' = omega[_n-1]
        qui gen byte `lag_ok' = (`test_lag' == `manual_lag') | ///
                                (mi(`test_lag') & mi(`manual_lag'))
        qui count if `lag_ok' == 0
        if r(N) > 0 {
            di as error "Warning: L.omega mismatch detected in " r(N) " observations"
        }
    }
    
    // ================================================================
    // Step 10: Store return values (IMPL-011)
    // CRITICAL: Do NOT use ereturn clear — it destroys upstream e() values
    //           from (_pte_omega). Use c_local + scalar instead.
    // ================================================================
    
    // Pass results to caller via c_local (accessible as local macros in caller)
    c_local nsim `nsim'
    c_local N_original `N_original'
    c_local N_expanded `N_expanded'
    c_local omegapoly `omegapoly'
    c_local N_treated_original `N_treated_original'
    c_local N_control_original `N_control_original'
    
    // Also store as global scalars for cross-program access
    scalar _pte_nsim = `nsim'
    scalar _pte_N_original = `N_original'
    scalar _pte_N_expanded = `N_expanded'
    scalar _pte_omegapoly = `omegapoly'
    scalar _pte_N_treated_original = `N_treated_original'
    scalar _pte_N_control_original = `N_control_original'
    
    // ================================================================
    // Step 11: Diagnostic summary output
    // ================================================================
    
    di as text ""
    di as text "Path expansion complete:"
    di as text "  omegapoly     = " as result `omegapoly'
    di as text "  nsim          = " as result `nsim'
    di as text "  N_original    = " as result %10.0fc `N_original'
    di as text "  N_treated     = " as result %10.0fc `N_treated_original'
    di as text "  N_control     = " as result %10.0fc `N_control_original'
    di as text "  N_expanded    = " as result %10.0fc `N_expanded'
    di as text "  panelvar      = " as result "firm_sim_id"
    di as text "  timevar       = " as result "`nt'"

end
