*! _pte_diag_kstest_group.ado
*! K-S Group Consistency Test for eps0
*!
*! Tests whether the distribution of eps0 (productivity shocks)
*! is the same for treated (pre-treatment) and control firms.
*! Validates Assumption 4.3 (iid) - group dimension.

version 14.0
program define _pte_diag_kstest_group, rclass
    version 14.0
    syntax , [eps0(varname) PREWindow(string) STRICTcontrol Quietly NOTRIMeps]
    
    // =========================================================
    // 1. Variable validation
    // =========================================================
    
    // Determine eps0 variable
    if "`eps0'" == "" {
        capture confirm variable _pte_eps0, exact
        if _rc == 0 {
            local eps0 "_pte_eps0"
        }
        else {
            di as error "Error: Specify eps0() or ensure _pte_eps0 exists"
            exit 111
        }
    }
    
    // Verify eps0 is numeric
    capture confirm numeric var `eps0'
    if _rc != 0 {
        di as error "Error: `eps0' must be numeric"
        exit 198
    }

    quietly _pte_diag_eps0_support_if, epsvar(`eps0') ///
        context("group K-S diagnostics")
    local eps0_sample_if `"`r(sample_if)'"'
    
    // Verify _pte_treat exists
    capture confirm variable _pte_treat, exact
    if _rc != 0 {
        di as error "Error: _pte_treat not found. Run pte_setup first."
        exit 111
    }
    _pte_validate_internal_state _pte_treat binary ///
        "Group K-S diagnostics require _pte_treat to remain the certified binary ever-treated indicator."
    
    // Verify _pte_nt exists
    capture confirm variable _pte_nt, exact
    if _rc != 0 {
        di as error "Error: _pte_nt not found. Run pte_setup first."
        exit 111
    }
    _pte_validate_internal_state _pte_nt integer ///
        "Group K-S diagnostics require _pte_nt to remain the certified integer event-time index."
    
    // Group-consistency windows follow the same stored calendar support as
    // the main K-S branch.
    _pte_diag_panel_contract, context("group K-S diagnostics") allowsetupmissingxtdelta
    local idvar = r(idvar)
    local timevar = r(timevar)
    
    // =========================================================
    // 2. Parse prewindow option
    // =========================================================
    
    // Default prewindow = 3 (paper E.3: "three years preceding")
    // prewindow(.) = use all pre-treatment years
    local pw_val = 3
    local pw_is_missing = 0
    if "`prewindow'" != "" {
        if "`prewindow'" == "." {
            local pw_is_missing = 1
        }
        else {
            capture confirm integer number `prewindow'
            if _rc != 0 {
                di as error "Error: prewindow() must be a positive integer or ."
                exit 198
            }
            if `prewindow' <= 0 {
                di as error "Error: prewindow() must be a positive integer or ."
                exit 198
            }
            local pw_val = `prewindow'
        }
    }
    
    // =========================================================
    // 3. Initialize return values and flags
    // =========================================================
    
    local group_stability_skipped = 0
    local group_stability_fallback = 0
    local sample_type "time_matched"
    local ks_D_group = .
    local ks_D1_group = .
    local ks_D2_group = .
    local ks_p_group = .
    local group_pass = .
    local n_treated = 0
    local n_control = 0
    local min_pretreat = .
    local max_pretreat = .
    
    // =========================================================
    // 4. Output header
    // =========================================================
    
    if "`quietly'" == "" {
        di as text _n "K-S Test 3: Group Equality (Pre-treatment only)"
        di as text "{hline 50}"
        di as text "H0: Same shock distribution for treated and control"
        di as text "(Using pre-treatment observations only, same time window)"
        di as text ""
    }
    
    // =========================================================
    // 5. Select treated pre-treatment sample
    // =========================================================
    
    tempvar treated_pretreat control_matched sample_ind group_ind year_in_window
    gen byte `treated_pretreat' = 0
    gen byte `control_matched' = 0
    
    if `pw_is_missing' == 1 {
        // prewindow(.) -> all pre-treatment years
        qui replace `treated_pretreat' = 1 ///
            if _pte_treat == 1 & _pte_nt < 0 & `eps0_sample_if'
    }
    else {
        // prewindow(k) -> only k years before treatment
        qui replace `treated_pretreat' = 1 ///
            if _pte_treat == 1 & _pte_nt < 0 ///
            & _pte_nt >= -`pw_val' & `eps0_sample_if'
    }
    
    qui count if `treated_pretreat' == 1
    local n_treated = r(N)
    
    // Check: no treated pre-treatment observations
    if `n_treated' == 0 {
        if "`quietly'" == "" {
            di as text "Warning: No pre-treatment observations for treated firms"
        }
        local group_stability_skipped = 1
    }
    
    // =========================================================
    // 6. Get treated pretreatment support
    // =========================================================
    
    if `group_stability_skipped' == 0 {
        qui summ `timevar' if `treated_pretreat' == 1
        local min_pretreat = r(min)
        local max_pretreat = r(max)
    }
    
    // =========================================================
    // 7. Select control group in the same treated support years
    // =========================================================

    if `group_stability_skipped' == 0 {
        // Match controls to the exact calendar years where treated
        // pretreatment support exists; a min/max envelope can absorb
        // unsupported gap years when adoption timing is staggered.
        qui bysort `timevar': egen byte `year_in_window' = max(`treated_pretreat')
        qui replace `control_matched' = 1 ///
            if _pte_treat == 0 & `eps0_sample_if' & `year_in_window' == 1
        
        qui count if `control_matched' == 1
        local n_control_window = r(N)
        
        // =====================================================
        // 8. Fallback strategy if control sample insufficient
        // =====================================================
        
        if `n_control_window' < 15 {
            if "`quietly'" == "" {
                di as text "Note: Time-window-matched control sample < 15," ///
                    " skipping group-equality test"
            }
            local group_stability_skipped = 1
        }
        
        // Final control count
        qui count if `control_matched' == 1
        local n_control = r(N)
    }
    
    // =========================================================
    // 9. Check minimum sample sizes
    // =========================================================
    
    if `group_stability_skipped' == 0 {
        if `n_treated' < 15 | `n_control' < 15 {
            if "`quietly'" == "" {
                di as text "Insufficient observations for group" ///
                    " consistency test"
                di as text "  Treated pre-treatment: `n_treated'"
                di as text "  Control group: `n_control'"
                di as text "  Minimum required: 15 per group"
            }
            local group_stability_skipped = 1
        }
    }
    
    // =========================================================
    // 10. Display sample info
    // =========================================================
    
    // =========================================================
    // 11. Execute two-sample K-S test
    // =========================================================
    
    if `group_stability_skipped' == 0 {
        // Build combined sample indicator and group indicator
        gen byte `sample_ind' = (`treated_pretreat' == 1 | ///
            `control_matched' == 1)
        gen byte `group_ind' = .
        qui replace `group_ind' = 1 if `treated_pretreat' == 1
        qui replace `group_ind' = 0 if `control_matched' == 1 ///
            & `treated_pretreat' == 0

        if "`notrimeps'" == "" {
            // Match the main public K-S branch: trim only the grouped exact
            // support that actually enters the test, then recount support.
            qui _pte_trim_var `eps0' if `sample_ind' == 1
        }

        qui count if `sample_ind' == 1 & `group_ind' == 1 & !missing(`eps0')
        local n_treated = r(N)
        qui count if `sample_ind' == 1 & `group_ind' == 0 & !missing(`eps0')
        local n_control = r(N)

        if `n_treated' < 15 | `n_control' < 15 {
            if "`quietly'" == "" {
                di as text "Insufficient observations for group" ///
                    " consistency test after trim"
                di as text "  Treated pre-treatment: `n_treated'"
                di as text "  Control group: `n_control'"
                di as text "  Minimum required: 15 per group"
            }
            local group_stability_skipped = 1
        }
    }

    if `group_stability_skipped' == 0 & "`quietly'" == "" {
        if `group_stability_fallback' == 0 {
            di as text "Time window: `min_pretreat' - `max_pretreat'"
        }
        else {
            di as text "Time window: [FALLBACK - all control periods]"
        }
        if `pw_is_missing' == 1 {
            di as text "Pre-window: all pre-treatment years"
        }
        else {
            di as text "Pre-window: `pw_val' years"
        }
        di as text "Treated pre-treatment obs: " %8.0f `n_treated'
        di as text "Control obs:               " %8.0f `n_control'
        di as text ""
    }

    if `group_stability_skipped' == 0 {
        // Execute K-S test on the post-trim grouped exact support.
        qui ksmirnov `eps0' if `sample_ind' == 1 & !missing(`eps0'), by(`group_ind')
        local ks_D_group = r(D)
        local ks_D1_group = r(D_1)
        local ks_D2_group = r(D_2)
        local ks_p_group = r(p)
        
        // Display results
        if "`quietly'" == "" {
            di as text "D     = " %8.4f `ks_D_group'
            di as text "D+    = " %8.4f `ks_D1_group'
            di as text "D-    = " %8.4f `ks_D2_group'
            di as text "Prob > D = " %8.4f `ks_p_group'
            di as text ""
            
            if `ks_p_group' < 0.05 {
                di as error "Result: FAIL - Different distributions detected"
                di as error "Assumption 4.3 (iid shocks across firms)" ///
                    " may be violated"
            }
            else {
                di as text "Result: PASS - No significant" ///
                    " distribution difference"
            }
        }
    }
    else {
        if "`quietly'" == "" {
            di as text "Result: SKIPPED (insufficient data)"
            if `n_treated' > 0 | `n_control' > 0 {
                di as text "  Treated pre-treatment: `n_treated'"
                di as text "  Control group: `n_control'"
            }
        }
    }
    
    if "`quietly'" == "" {
        di as text "{hline 50}"
    }
    
    // =========================================================
    // 12. Compute group_pass and store return values
    // =========================================================
    
    // group_pass: . if skipped, 1 if p>=0.05, 0 if p<0.05
    // Note: Stata treats missing >= 0.05 as TRUE, so check skipped first
    if `group_stability_skipped' == 1 {
        local group_pass = .
    }
    else {
        local group_pass = cond(`ks_p_group' >= 0.05, 1, 0)
    }
    
    // Return scalars
    return scalar ks_D_group = `ks_D_group'
    return scalar ks_D1_group = `ks_D1_group'
    return scalar ks_D2_group = `ks_D2_group'
    return scalar ks_p_group = `ks_p_group'
    return scalar group_pass = `group_pass'
    return scalar n_treated_pretreat = `n_treated'
    return scalar n_control_group = `n_control'
    return scalar min_pretreat_year = `min_pretreat'
    return scalar max_pretreat_year = `max_pretreat'
    return scalar group_stability_skipped = `group_stability_skipped'
    return scalar group_stability_fallback = `group_stability_fallback'
    if `pw_is_missing' == 1 {
        return scalar prewindow = .
    }
    else {
        return scalar prewindow = `pw_val'
    }
    return local sample_type "`sample_type'"
    
end
