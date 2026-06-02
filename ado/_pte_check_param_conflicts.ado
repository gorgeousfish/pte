*! _pte_check_param_conflicts.ado
*! Validates extension feature parameter combinations before estimation
*!
*! Checks performed:
*!   Check 1: FR-015 + FR-019 mutual exclusion (nonabsorbing vs counterfactual)
*!   Check 2: FR-015 + FR-016 sample sufficiency (nonabsorbing + treatdependent)
*!   Check 3: FR-017 cohort count (>= 2 required)
*!   Check 4: FR-018 panel length (>= lagperiods + 1 consecutive periods)
*!   Check 5: noatt + counterfactual mutual exclusion
*!   Check 6: FR-019 group definition (targetgroup valid iff counterfactual)

version 14.0
capture program drop _pte_check_param_conflicts
program define _pte_check_param_conflicts, rclass
    version 14.0

    syntax, TREATment(varname) ///
            [NONABsorbing TREATDEPendent ///
             COHort(varname) LAGperiods(integer 0) ///
             COUNTERfactual TARGETgroup(varname) NOATT ///
             PERSISTperiods(integer 0) ///
             SWITCHdirection(string) ///
             DETAIL TOUSE(name)]

    if "`touse'" == "" {
        tempvar touse
        quietly gen byte `touse' = 1
    }
    else {
        capture confirm variable `touse', exact
        if _rc {
            di as error "[pte] Error: touse variable '`touse'' not found"
            exit 111
        }
        capture confirm numeric variable `touse'
        if _rc {
            di as error "[pte] Error: touse variable '`touse'' must be numeric"
            exit 111
        }
    }

    // Initialize counters
    local n_checks = 0
    local n_passed = 0
    local n_skipped = 0

    // Extract option flags
    local has_nonabsorbing = ("`nonabsorbing'" != "")
    local has_treatdependent = ("`treatdependent'" != "")
    local has_cohort = ("`cohort'" != "")
    local has_counterfactual = ("`counterfactual'" != "")
    local has_targetgroup = ("`targetgroup'" != "")
    local has_noatt = ("`noatt'" != "")

    // Detail mode header
    if "`detail'" != "" {
        di as text ""
        di as text "Parameter Combination Conflict Check"
        di as text _dup(60) "-"
    }

    // ================================================================
    // Check 1: FR-015 + FR-019 mutual exclusion
    // ================================================================
    local ++n_checks
    if `has_nonabsorbing' & `has_counterfactual' {
        _pte_error, errcode(3007) ///
            msg("Options nonabsorbing and counterfactual are mutually exclusive") ///
            suggestion("Counterfactual analysis (FR-019) assumes absorbing treatment (Assumption 4.1). Use nonabsorbing alone for treatment switching, or counterfactual alone for absorbing treatment.")
    }
    else if `has_nonabsorbing' | `has_counterfactual' {
        local ++n_passed
        if "`detail'" != "" {
            di as text "  Check 1: FR-015 + FR-019 mutual exclusion ... " as result "PASS"
        }
    }
    else {
        local ++n_skipped
        if "`detail'" != "" {
            di as text "  Check 1: FR-015 + FR-019 mutual exclusion ... " as text "SKIP"
        }
    }

    // ================================================================
    // Check 2: FR-015 + FR-016 sample sufficiency
    // ================================================================
    local ++n_checks
    if `has_nonabsorbing' & `has_treatdependent' {
        // Compute four-category sample sizes
        tempvar _G
        quietly gen `_G' = `treatment' - L.`treatment' if `touse'

        quietly count if `touse' & `treatment' == 0 & `_G' == 0
        local n_d0g0 = r(N)
        quietly count if `touse' & `treatment' == 1 & `_G' == 1
        local n_d1g1 = r(N)
        quietly count if `touse' & `treatment' == 0 & `_G' == -1
        local n_d0gm1 = r(N)
        quietly count if `touse' & `treatment' == 1 & `_G' == 0
        local n_d1g0 = r(N)

        local min_n = min(`n_d0g0', `n_d1g1', `n_d0gm1', `n_d1g0')

        if `min_n' < 30 {
            _pte_error, errcode(3008) ///
                msg("Insufficient observations for nonabsorbing+treatdependent combination") ///
                suggestion("Minimum 30 observations per cell required. Cell counts: D=0,G=0: `n_d0g0', D=1,G=1: `n_d1g1', D=0,G=-1: `n_d0gm1', D=1,G=0: `n_d1g0'")
        }
        else {
            local ++n_passed
            if "`detail'" != "" {
                di as text "  Check 2: FR-015 + FR-016 sample size ...... " as result "PASS" ///
                    as text " (min cell=`min_n')"
            }
            _pte_warn "Combining nonabsorbing with treatdependent requires estimating FOUR production functions. Cell counts: D=0,G=0:`n_d0g0' D=1,G=1:`n_d1g1' D=0,G=-1:`n_d0gm1' D=1,G=0:`n_d1g0'"
        }
    }
    else {
        local ++n_skipped
        if "`detail'" != "" {
            di as text "  Check 2: FR-015 + FR-016 sample size ...... " as text "SKIP"
        }
    }

    // ================================================================
    // Check 3: FR-017 cohort count
    // ================================================================
    local ++n_checks
    if `has_cohort' {
        quietly tab `cohort' if `touse' & `treatment' == 1
        local n_cohorts = r(r)

        if `n_cohorts' < 2 {
            _pte_error, errcode(3004) ///
                msg("cohort() requires at least 2 treatment cohorts, found `n_cohorts'") ///
                suggestion("Check cohort variable or remove cohort() option")
        }
        else {
            local ++n_passed
            if "`detail'" != "" {
                di as text "  Check 3: FR-017 cohort count ............. " as result "PASS" ///
                    as text " (`n_cohorts' cohorts)"
            }
        }
    }
    else {
        local ++n_skipped
        if "`detail'" != "" {
            di as text "  Check 3: FR-017 cohort count ............. " as text "SKIP"
        }
    }

    // ================================================================
    // Check 4: FR-018 panel length
    // ================================================================
    local ++n_checks
    if `lagperiods' > 0 {
        quietly xtset
        local panelvar = r(panelvar)
        local timevar = r(timevar)

        tempvar _panel_break _panel_run _run_len _panel_max_run _panel_tag
        quietly bysort `panelvar' (`timevar'): gen byte `_panel_break' = (`touse' == 1)
        quietly bysort `panelvar' (`timevar'): replace `_panel_break' = 0 ///
            if `touse' & L.`touse' == 1 & !missing(L.`timevar')
        quietly bysort `panelvar' (`timevar'): gen long `_panel_run' = sum(`_panel_break') if `touse'
        quietly bysort `panelvar' `_panel_run': egen long `_run_len' = total(`touse') if `touse'
        quietly bysort `panelvar': egen long `_panel_max_run' = max(`_run_len') if `touse'
        quietly egen byte `_panel_tag' = tag(`panelvar') if `touse'
        quietly summarize `_panel_max_run' if `_panel_tag', meanonly
        local min_panel_len = r(min)

        local required_len = `lagperiods' + 1

        if `min_panel_len' < `required_len' {
            _pte_error, errcode(3005) ///
                msg("Insufficient panel length for lagperiods(`lagperiods')") ///
                suggestion("FR-018 extended moments require at least `required_len' consecutive periods. Minimum consecutive support in data: `min_panel_len'")
        }
        else {
            local ++n_passed
            if "`detail'" != "" {
                di as text "  Check 4: FR-018 panel length ............. " as result "PASS" ///
                    as text " (min=`min_panel_len')"
            }
        }
    }
    else {
        local ++n_skipped
        if "`detail'" != "" {
            di as text "  Check 4: FR-018 panel length ............. " as text "SKIP"
        }
    }

    // ================================================================
    // Check 5: noatt + counterfactual mutual exclusion
    // ================================================================
    local ++n_checks
    if `has_noatt' & `has_counterfactual' {
        _pte_error, errcode(3007) ///
            msg("Options noatt and counterfactual are mutually exclusive") ///
            suggestion("counterfactual analysis is a treatment-effect estimation step. Remove noatt to run counterfactual analysis.")
    }
    else if `has_noatt' | `has_counterfactual' {
        local ++n_passed
        if "`detail'" != "" {
            di as text "  Check 5: noatt + counterfactual exclusion ... " as result "PASS"
        }
    }
    else {
        local ++n_skipped
        if "`detail'" != "" {
            di as text "  Check 5: noatt + counterfactual exclusion ... " as text "SKIP"
        }
    }

    // ================================================================
    // Check 6: FR-019 group definition
    // ================================================================
    local ++n_checks
    if `has_targetgroup' & !`has_counterfactual' {
        _pte_error, errcode(3006) ///
            msg("targetgroup() requires counterfactual") ///
            suggestion("Use targetgroup() only with counterfactual, or remove targetgroup() from the baseline ATT path")
    }
    else if `has_counterfactual' {
        // 6a: targetgroup must be specified
        if !`has_targetgroup' {
            _pte_error, errcode(3006) ///
                msg("counterfactual requires targetgroup() specification") ///
                suggestion("Usage: pte ..., counterfactual targetgroup(varname)")
        }

        // 6b: targetgroup must be binary (0/1, missing allowed)
        capture assert inlist(`targetgroup', 0, 1, .) if `touse'
        if _rc {
            _pte_error, errcode(3006) ///
                msg("targetgroup() must be coded 0/1 (missing allowed)") ///
                suggestion("Recode targetgroup so target=1 and reference=0 before running counterfactual analysis")
        }

        // 6c: both groups must be non-empty
        quietly count if `touse' & `targetgroup' == 1
        local n_target = r(N)
        quietly count if `touse' & `targetgroup' == 0
        local n_reference = r(N)

        if `n_target' == 0 | `n_reference' == 0 {
            _pte_error, errcode(3006) ///
                msg("Empty target or reference group for counterfactual analysis") ///
                suggestion("Target group (`targetgroup'==1): `n_target' obs, Reference group (`targetgroup'==0): `n_reference' obs")
        }
        else {
            local ++n_passed
            if "`detail'" != "" {
                di as text "  Check 6: FR-019 group definition ......... " as result "PASS" ///
                    as text " (target=`n_target', ref=`n_reference')"
            }
        }
    }
    else {
        local ++n_skipped
        if "`detail'" != "" {
            di as text "  Check 6: FR-019 group definition ......... " as text "SKIP"
        }
    }

    // ================================================================
    // Check 7: FR-015 persistperiods range
    // ================================================================
    if `persistperiods' < 0 {
        local ++n_checks
        _pte_error, errcode(198) ///
            msg("persistperiods() must be non-negative") ///
            suggestion("Use persistperiods(0) to disable the filter, or a positive integer with nonabsorbing")
    }
    if `persistperiods' > 0 {
        local ++n_checks
        if !`has_nonabsorbing' {
            _pte_error, errcode(198) ///
                msg("persistperiods() requires nonabsorbing") ///
                suggestion("Use persistperiods() only with nonabsorbing, or remove it from the baseline absorbing-treatment path")
        }
        quietly xtset
        local panelvar = r(panelvar)
        tempvar _plen
        bysort `panelvar': egen `_plen' = total(`touse')
        quietly summarize `_plen' if `touse', meanonly
        local _half_T = floor(r(max) / 2)

        if `persistperiods' > `_half_T' {
            _pte_error, errcode(3001) ///
                msg("persistperiods(`persistperiods') exceeds T/2 (`_half_T')") ///
                suggestion("Reduce persistperiods or use longer panel")
        }
        else {
            local ++n_passed
            if "`detail'" != "" {
                di as text "  Check 7: FR-015 persistperiods range ..... " as result "PASS"
            }
        }
    }

    // ================================================================
    // Check 8: FR-015 switchdirection validity
    // ================================================================
    if "`switchdirection'" != "" {
        local switchdirection = lower(strtrim("`switchdirection'"))
        local ++n_checks
        if !`has_nonabsorbing' {
            _pte_error, errcode(198) ///
                msg("switchdirection() requires nonabsorbing") ///
                suggestion("Use switchdirection() only with nonabsorbing, or remove it from the baseline absorbing-treatment path")
        }
        if !inlist("`switchdirection'", "both", "on", "off") {
            _pte_error, errcode(3002) ///
                msg("switchdirection() must be 'both', 'on', or 'off'") ///
                suggestion("See help pte for valid switchdirection() values")
        }
        else {
            local ++n_passed
            if "`detail'" != "" {
                di as text "  Check 8: FR-015 switchdirection .......... " as result "PASS"
            }
        }
    }

    // Detail mode summary
    if "`detail'" != "" {
        di as text _dup(60) "-"
        di as text "  Total: `n_checks'  Passed: `n_passed'  Skipped: `n_skipped'"
    }

    // Return values
    return scalar checks_total = `n_checks'
    return scalar checks_passed = `n_passed'
    return scalar checks_skipped = `n_skipped'
end
