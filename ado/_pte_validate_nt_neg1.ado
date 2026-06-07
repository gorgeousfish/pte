*! _pte_validate_nt_neg1.ado
*! Validates that nt=-1 observations exist and are complete for all
*! treated firms. Required for counterfactual simulation starting point
*! (Proposition 4.3: L.omega at nt=0 must come from nt=-1).
*!
*! Error codes:
*!   E-3002: Missing nt=-1 observations (global - zero nt=-1 in data)
*!   E-3003: L.omega mismatch at nt=0 vs omega at nt=-1

version 14.0
capture program drop _pte_validate_nt_neg1
program define _pte_validate_nt_neg1, rclass
    version 14.0

    syntax, firm(name) nt(name) [omega(name)] [Verbose] [Debug]

    capture confirm variable `firm', exact
    if _rc != 0 {
        di as error "[pte] variable `firm' not found"
        exit 111
    }

    capture confirm variable `nt', exact
    if _rc != 0 {
        di as error "[pte] variable `nt' not found"
        exit 111
    }
    capture confirm numeric variable `nt'
    if _rc != 0 {
        di as error "[pte] variable `nt' must be numeric"
        exit 111
    }

    if "`omega'" != "" {
        capture confirm variable `omega', exact
        if _rc != 0 {
            di as error "[pte] variable `omega' not found"
            exit 111
        }
        capture confirm numeric variable `omega'
        if _rc != 0 {
            di as error "[pte] variable `omega' must be numeric"
            exit 111
        }
    }

    // ================================================================
    // Step 1: Validate nt=-1 observations exist
    // ================================================================

    quietly count if `nt' == -1
    local n_neg1 = r(N)

    if `n_neg1' == 0 {
        di as error ""
        di as error "{bf:pte error E-3002}: No nt=-1 observations found"
        di as error "{hline 70}"
        di as error "PROBLEM:"
        di as error "  The data contains no observations with nt = -1."
        di as error "  This period is required to provide L.omega for"
        di as error "  counterfactual simulation at nt = 0 (Proposition 4.3)."
        di as error ""
        di as error "SOLUTION:"
        di as error "  1. Check sample selection: ensure nt >= -1 is kept"
        di as error "  2. Verify data includes year = treat_year - 1"
        di as error "  3. Check treat_year calculation"
        di as error "{hline 70}"
        exit 3002
    }

    if "`verbose'" != "" {
        di as text "  nt=-1 observations found: `n_neg1'"
    }

    // ================================================================
    // Step 2: Per-firm nt=-1 completeness
    // Check every firm has at least one nt=-1 observation. A missing anchor is
    // not a recoverable state because dropping firms changes the ATT target.
    // ================================================================

    tempvar has_neg1
    quietly bysort `firm': egen byte `has_neg1' = max(`nt' == -1)

    quietly count if `has_neg1' == 0
    local n_missing_obs = r(N)

    if `n_missing_obs' > 0 {
        // Count distinct firms missing nt=-1
        tempvar tag_missing
        quietly egen byte `tag_missing' = tag(`firm') if `has_neg1' == 0
        quietly count if `tag_missing' == 1
        local n_missing_firms = r(N)

        quietly levelsof `firm' if `tag_missing' == 1, local(missing_list)

        di as error ""
        di as error "{bf:pte error E-3002}: `n_missing_firms' firms missing nt=-1"
        di as error "{hline 70}"

        // Show first 10 affected firms
        local n_show = min(`n_missing_firms', 10)
        di as error "AFFECTED FIRMS (first `n_show'):"
        forvalues i = 1/`n_show' {
            local f : word `i' of `missing_list'
            di as error "  - Firm `f'"
        }
        if `n_missing_firms' > 10 {
            local n_more = `n_missing_firms' - 10
            di as error "  - ... and `n_more' more"
        }
        di as error "{hline 70}"

        di as error "These firms cannot be silently dropped because that would change the ATT target."
        di as error "Rebuild the ATT sample so every treated firm has nt=-1 support."
        exit 3002
    }

    // ================================================================
    // Step 2b: Anchor completeness with observed omega at nt=-1
    // Proposition 4.3 starts ATT_0 from the observed omega_{e_i-1}, so
    // a bare nt=-1 row is insufficient when omega() is supplied.
    // ================================================================

    if "`omega'" != "" {
        tempvar has_anchor_omega
        quietly bysort `firm': egen byte `has_anchor_omega' = ///
            max(`nt' == -1 & !missing(`omega'))

        quietly count if `has_anchor_omega' == 0
        local n_bad_anchor_obs = r(N)

        if `n_bad_anchor_obs' > 0 {
            tempvar tag_bad_anchor
            quietly egen byte `tag_bad_anchor' = tag(`firm') if `has_anchor_omega' == 0
            quietly count if `tag_bad_anchor' == 1
            local n_bad_anchor_firms = r(N)

            quietly levelsof `firm' if `tag_bad_anchor' == 1, local(bad_anchor_list)

            di as error ""
            di as error "{bf:pte error E-3002}: `n_bad_anchor_firms' firms missing observed omega at nt=-1"
            di as error "{hline 70}"

            local n_show = min(`n_bad_anchor_firms', 10)
            di as error "AFFECTED FIRMS (first `n_show'):"
            forvalues i = 1/`n_show' {
                local f : word `i' of `bad_anchor_list'
                di as error "  - Firm `f'"
            }
            if `n_bad_anchor_firms' > 10 {
                local n_more = `n_bad_anchor_firms' - 10
                di as error "  - ... and `n_more' more"
            }
            di as error "{hline 70}"

            di as error "These firms cannot be silently dropped because ATT_0 is anchored at omega_{e_i-1}."
            di as error "Re-run the upstream omega step on a sample with nonmissing nt=-1 productivity."
            exit 3002
        }
    }

    // Count validated firms
    tempvar tag_firm
    quietly egen byte `tag_firm' = tag(`firm')
    quietly count if `tag_firm' == 1
    local n_firms = r(N)

    if "`verbose'" != "" {
        di as text "  All `n_firms' firms have usable nt=-1 anchor"
    }

    // ================================================================
    // Step 3: L.omega validation (debug mode only)
    // Verify L.omega at nt=0 equals omega at nt=-1 for each firm.
    // ================================================================

    if "`debug'" != "" & "`omega'" != "" {
        // Save current tsset state
        quietly tsset
        local orig_panel = r(panelvar)
        local orig_time  = r(timevar)
        local orig_delta "`r(tdelta)'"

        // Set panel for lag operator
        quietly tsset `firm' `nt'

        // Create verification variables
        tempvar L_omega omega_neg1 omega_neg1_filled diff_omega

        quietly gen double `L_omega' = L.`omega' if `nt' == 0
        quietly gen double `omega_neg1' = `omega' if `nt' == -1
        quietly bysort `firm': egen double `omega_neg1_filled' = max(`omega_neg1')
        quietly gen double `diff_omega' = abs(`L_omega' - `omega_neg1_filled') if `nt' == 0

        quietly summarize `diff_omega', meanonly
        local max_diff = r(max)

        if `max_diff' > 1e-10 {
            di as error ""
            di as error "{bf:pte error E-3003}: L.omega mismatch at nt=0"
            di as error "{hline 70}"
            di as error "PROBLEM:"
            di as error "  L.omega at nt=0 does not equal omega at nt=-1"
            di as error "  Maximum difference: `max_diff'"
            di as error ""
            di as error "POSSIBLE CAUSES:"
            di as error "  1. Panel not sorted correctly"
            di as error "  2. tsset not configured properly"
            di as error "  3. Data inconsistency"
            di as error "{hline 70}"

            // Restore original tsset
            if "`orig_panel'" != "" & "`orig_time'" != "" {
                local orig_delta_opt ""
                if "`orig_delta'" != "" {
                    local orig_delta_opt "delta(`orig_delta')"
                }
                quietly tsset `orig_panel' `orig_time', `orig_delta_opt'
            }
            exit 3003
        }

        if "`verbose'" != "" {
            di as text "  L.omega validation passed (max diff < 1e-10)"
        }

        // Restore original tsset
        if "`orig_panel'" != "" & "`orig_time'" != "" {
            local orig_delta_opt ""
            if "`orig_delta'" != "" {
                local orig_delta_opt "delta(`orig_delta')"
            }
            quietly tsset `orig_panel' `orig_time', `orig_delta_opt'
        }
    }

    // ================================================================
    // Step 4: Return results
    // ================================================================

    return scalar n_neg1  = `n_neg1'
    return scalar n_firms = `n_firms'
    return scalar valid   = 1

    if "`verbose'" != "" {
        di as text "  nt=-1 validation passed"
    }

end
