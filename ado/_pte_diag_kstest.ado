*! _pte_diag_kstest.ado
*! K-S Test Suite: Parallel Trends Diagnostic
*!
*! Implements TWO independent K-S tests:
*!   Test 1 (Treatment vs Control): Compares eps0 distribution between
*!          treated and control groups in pre-treatment period.
*!          Reproduces paper Table E.3.
*!   Test 2 (Time Stability): Compares eps0 distribution before vs after
*!          a reference year within control group.

version 14.0
program define _pte_diag_kstest, rclass
    version 14.0
    syntax , [eps0(varname) PREwindow(integer 3) reference_year(integer 0) ///
              BYIndustry(varname) NOTime Level(cilevel) ///
              Alpha(real 0.05) NOTRIMeps]

    // =============================================================
    // 1. Variable validation
    // =============================================================

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
        context("K-S diagnostics")
    local eps0_sample_if `"`r(sample_if)'"'

    // Verify _pte_treat exists
    capture confirm variable _pte_treat, exact
    if _rc != 0 {
        di as error "Error: _pte_treat not found. Run pte_setup first."
        exit 111
    }
    _pte_validate_internal_state _pte_treat binary ///
        "K-S diagnostics require _pte_treat to remain the certified binary ever-treated indicator."

    // Verify _pte_nt exists (needed for treated group pre-treatment window)
    capture confirm variable _pte_nt, exact
    if _rc != 0 {
        di as error "Error: _pte_nt not found. Run pte_setup first."
        exit 111
    }
    _pte_validate_internal_state _pte_nt integer ///
        "K-S diagnostics require _pte_nt to remain the certified integer event-time index."

    // Match the stored estimation-time calendar support whenever available.
    _pte_diag_panel_contract, context("K-S diagnostics") allowsetupmissingxtdelta
    local idvar = r(idvar)
    local timevar = r(timevar)

    // Validate prewindow
    if `prewindow' < 0 {
        di as error "Error: prewindow() must be >= 0"
        exit 198
    }

    // Set significance level
    if "`level'" != "" {
        local alpha = 1 - `level' / 100
    }

    if `alpha' <= 0 | `alpha' >= 1 {
        di as error "Error: alpha() must be strictly between 0 and 1"
        exit 198
    }

    // =============================================================
    // 2. Output header
    // =============================================================

    di as text ""
    di as text "K-S Test Suite: Parallel Trends Diagnostic"
    di as text "{hline 60}"

    // Initialize overall pass flag
    local overall_pass = 1
    local overall_incomplete = 0

    // =============================================================
    // PART A: Treatment vs Control K-S (Paper Table E.3)
    // =============================================================

    di as text ""
    di as text "Test 1: Treatment vs Control (Paper Table E.3)"
    di as text "  H0: eps0 distribution is the same for treated and control"

    // Initialize Part A return values
    local ks_D_treat = .
    local ks_p_treat = .
    local ks_D_plus = .
    local ks_p_plus = .
    local ks_D_minus = .
    local ks_p_minus = .
    local ks_N_treated = 0
    local ks_N_control = 0
    local ks_window_min = .
    local ks_window_max = .
    local part_a_skipped = 0

    preserve

    // --- Sample selection ---
    // Treated group: pre-treatment observations within window
    if `prewindow' > 0 {
        di as text "  Pre-treatment window: `prewindow' years" ///
            " (nt >= -`prewindow' & nt < 0)"
        tempvar treat_sample
        gen byte `treat_sample' = (_pte_treat == 1) & ///
            (_pte_nt >= -`prewindow') & (_pte_nt < 0) & `eps0_sample_if'
    }
    else {
        di as text "  Pre-treatment window: ALL pre-treatment (nt < 0)"
        tempvar treat_sample
        gen byte `treat_sample' = (_pte_treat == 1) & ///
            (_pte_nt < 0) & `eps0_sample_if'
    }

    // Match controls to the exact calendar years that contain treated
    // pre-period support; a min/max envelope can absorb unsupported gap years.
    qui count if `treat_sample'
    local ks_N_treated = r(N)
    if `ks_N_treated' > 0 {
        qui summ `timevar' if `treat_sample', meanonly
        local ks_window_min = r(min)
        local ks_window_max = r(max)
    }

    tempvar ctrl_sample window_year
    gen byte `ctrl_sample' = 0
    if `ks_N_treated' > 0 {
        qui bysort `timevar': egen byte `window_year' = max(`treat_sample')
        qui replace `ctrl_sample' = (_pte_treat == 0) & `eps0_sample_if' ///
            & `window_year' == 1
    }

    // Count samples
    qui count if `ctrl_sample'
    local ks_N_control = r(N)

    if `ks_N_treated' > 0 {
        di as text "  Calendar window: [`ks_window_min', `ks_window_max']"
    }
    di as text "  N_treated = `ks_N_treated', N_control = `ks_N_control'"

    // Check minimum sample sizes
    if `ks_N_treated' == 0 | `ks_N_control' == 0 {
        di as error "  SKIPPED: One or both groups have 0 observations"
        local part_a_skipped = 1
    }
    else if `ks_N_treated' < 10 | `ks_N_control' < 10 {
        di as text "  Warning: Small sample size (< 10 in a group)"
    }

    if `part_a_skipped' == 0 {
        // Keep only relevant observations
        qui keep if `treat_sample' | `ctrl_sample'

        // Create group indicator: 0 = control, 1 = treated
        tempvar ks_group
        gen byte `ks_group' = `treat_sample'

        if "`notrimeps'" == "" {
            // Match the replication trim law with the package-owned
            // deterministic worker instead of depending on winsor2.
            qui _pte_trim_var `eps0'

            // Drop observations that became missing after winsorize
            qui drop if missing(`eps0')
        }

        // Recount after winsorize
        qui count if `ks_group' == 1
        local ks_N_treated = r(N)
        qui count if `ks_group' == 0
        local ks_N_control = r(N)

        if `ks_N_treated' == 0 | `ks_N_control' == 0 {
            di as error "  SKIPPED: Insufficient obs after winsorize"
            local part_a_skipped = 1
        }
    }

    if `part_a_skipped' == 0 {
        // Execute K-S test
        // ksmirnov groups by sorted values of groupvar:
        //   group1 = 0 (control), group2 = 1 (treated)
        //   D_1 = D+ (sup where F_control < F_treated)
        //   D_2 = D- (sup where F_treated < F_control)
        qui ksmirnov `eps0', by(`ks_group')

        local ks_D_treat = r(D)
        local ks_p_treat = r(p)
        local ks_D_plus  = r(D_1)
        local ks_p_plus  = r(p_1)
        local ks_D_minus = r(D_2)
        local ks_p_minus = r(p_2)

        di as text ""
        di as text "  Combined:          D = " %8.4f `ks_D_treat' ///
            "    p = " %8.4f `ks_p_treat'
        di as text "  D+ (Ctrl < Treat): D = " %8.4f `ks_D_plus' ///
            "    p = " %8.4f `ks_p_plus'
        di as text "  D- (Treat < Ctrl): D = " %8.4f `ks_D_minus' ///
            "    p = " %8.4f `ks_p_minus'
        di as text ""

        if `ks_p_treat' < `alpha' {
            di as error "  Result: FAIL - Distributions differ" ///
                " (p = " %6.4f `ks_p_treat' ")"
            local overall_pass = 0
        }
        else {
            di as text "  Result: PASS - Distributions are similar" ///
                " (p = " %6.4f `ks_p_treat' ")"
        }
    }
    else {
        di as text "  Result: SKIPPED (insufficient data)"
        local overall_pass = 0
    }

    restore

    // =============================================================
    // PART B: Time Stability K-S (Replication code L91-109)
    // =============================================================

    // Initialize Part B return values
    local ks_D_time = .
    local ks_p_time = .
    local ks_N_early = 0
    local ks_N_late = 0
    local ks_mid_year = .
    local part_b_skipped = 0

    if "`notime'" != "" {
        local part_b_skipped = 1
    }

    if `part_b_skipped' == 0 {

        di as text ""
        di as text "Test 2: Time Stability (iid over time)"
        di as text "  H0: eps0 distribution is stable over time"

        preserve

        // Keep the same time-stability sampling law as the dedicated helper:
        // prefer never-treated support, then fall back to all D=0 support when
        // never-treated observations are too sparse to identify the split.
        qui count if _pte_treat == 0 & `eps0_sample_if'
        local n_never_treated = r(N)

        if `n_never_treated' >= 30 {
            qui keep if _pte_treat == 0 & `eps0_sample_if'
            di as text "  Sample: never-treated only (N = `n_never_treated')"
        }
        else {
            capture confirm variable _pte_D, exact
            if _rc != 0 {
                di as text "  SKIPPED: Never-treated sample too small" ///
                    " (N = `n_never_treated') and _pte_D is unavailable"
                local part_b_skipped = 1
            }
        else {
            _pte_validate_internal_state _pte_D binary ///
                "K-S time-stability fallback requires _pte_D to remain the certified binary current-treatment indicator."
            qui keep if _pte_D == 0 & `eps0_sample_if'
            qui count
            local n_d0_total = r(N)
                di as text "  Sample: fallback to all D=0 observations" ///
                    " (never-treated N = `n_never_treated', D=0 N = `n_d0_total')"
                if `n_d0_total' < 30 {
                    di as text "  SKIPPED: D=0 fallback sample too small" ///
                        " (N = `n_d0_total', need >= 30)"
                    local part_b_skipped = 1
                }
            }
        }

        if `part_b_skipped' == 0 {
            // Determine reference year
            if `reference_year' != 0 {
                // User-specified reference year
                local ks_mid_year = `reference_year'
                di as text "  Reference year: `ks_mid_year'" ///
                    " (user-specified, split at year >= " ///
                    %4.0f (`ks_mid_year' + 1) ")"
            }
            else {
                // Match the helper/default diagnose law: split at the midpoint
                // of the observed support on the active untreated sample.
                qui summ `timevar', meanonly
                local min_year = r(min)
                local max_year = r(max)
                local ks_mid_year = floor((`min_year' + `max_year') / 2)
                di as text "  Reference year: `ks_mid_year'" ///
                    " (midpoint, split at year >= " ///
                    %4.0f (`ks_mid_year' + 1) ")"
            }

            if "`notrimeps'" == "" {
                // Match the replication trim law with the package-owned
                // deterministic worker instead of depending on winsor2.
                qui _pte_trim_var `eps0'

                // Drop observations that became missing after winsorize
                qui drop if missing(`eps0')
            }

            // Create time period indicator
            // period = 1 if year >= reference_year + 1 (i.e., after reference)
            // Matches replication code: g group = (year>=2011) with ref=2010
            tempvar period
            gen byte `period' = (`timevar' >= `ks_mid_year' + 1)

            // Count group sizes
            qui count if `period' == 0
            local ks_N_early = r(N)
            qui count if `period' == 1
            local ks_N_late = r(N)

            di as text "  N_early (year <= `ks_mid_year') = `ks_N_early'"
            di as text "  N_late  (year >= " ///
                %4.0f (`ks_mid_year' + 1) ") = `ks_N_late'"

            // Keep the suite on the same executable contract as the direct
            // time-stability worker: the split must leave at least 15
            // untreated-shock observations on each side, otherwise the branch
            // is skipped and public callers must see missing ks_D/ks_p.
            if `ks_N_early' < 15 | `ks_N_late' < 15 {
                if `ks_N_early' == 0 | `ks_N_late' == 0 {
                    di as text "  SKIPPED: Empty group"
                }
                else {
                    di as text "  SKIPPED: Insufficient observations (need >= 15 each)"
                }
                local part_b_skipped = 1
            }

            if `part_b_skipped' == 0 {
                // Execute K-S test
                qui ksmirnov `eps0', by(`period')

                local ks_D_time = r(D)
                local ks_p_time = r(p)

                di as text ""
                di as text "  D = " %8.4f `ks_D_time' ///
                    "    p = " %8.4f `ks_p_time'
                di as text ""

                if `ks_p_time' < `alpha' {
                    di as error "  Result: FAIL - Distribution" ///
                        " unstable over time (p = " ///
                        %6.4f `ks_p_time' ")"
                    local overall_pass = 0
                }
                else {
                    di as text "  Result: PASS - Distribution" ///
                        " stable over time (p = " ///
                        %6.4f `ks_p_time' ")"
                }
            }
        }

        if `part_b_skipped' {
            di as text "  Result: SKIPPED (insufficient data)"
            local overall_incomplete = 1
        }

        restore
    }

    // =============================================================
    // PART B2: Group Consistency K-S (Test 3)
    // =============================================================

    // Initialize group test return values
    local ks_D_group = .
    local ks_D1_group = .
    local ks_D2_group = .
    local ks_p_group = .
    local group_pass = .
    local n_treated_pretreat = 0
    local n_control_group = 0
    local min_pretreat_year = .
    local max_pretreat_year = .
    local group_stability_skipped = 0
    local group_stability_fallback = 0
    local group_prewindow = .
    local group_sample_type ""

    // Convert integer prewindow to string for group test
    // prewindow=0 means "all years" -> pass "." to group test
    if `prewindow' == 0 {
        local pw_str "."
    }
    else {
        local pw_str "`prewindow'"
    }

    // Call group consistency test on a preserved copy because the grouped
    // worker may apply the same trim law as the public K-S branch.
    preserve
    local group_trim_opt ""
    if "`notrimeps'" != "" local group_trim_opt "notrimeps"
    _pte_diag_kstest_group, eps0(`eps0') prewindow(`pw_str') `group_trim_opt'
    restore

    // Capture return values from group test
    local ks_D_group = r(ks_D_group)
    local ks_D1_group = r(ks_D1_group)
    local ks_D2_group = r(ks_D2_group)
    local ks_p_group = r(ks_p_group)
    local group_pass = r(group_pass)
    local n_treated_pretreat = r(n_treated_pretreat)
    local n_control_group = r(n_control_group)
    local min_pretreat_year = r(min_pretreat_year)
    local max_pretreat_year = r(max_pretreat_year)
    local group_stability_skipped = r(group_stability_skipped)
    local group_stability_fallback = r(group_stability_fallback)
    local group_prewindow = r(prewindow)
    local group_sample_type "`r(sample_type)'"

    // Update overall_pass: FAIL (0) affects it, SKIPPED (.) does not
    if `group_pass' == 0 {
        local overall_pass = 0
    }
    else if missing(`group_pass') {
        local overall_incomplete = 1
    }

    // =============================================================
    // PART C: By-Industry K-S (if byindustry specified)
    // =============================================================

    local has_industry = 0

    if "`byindustry'" != "" {

        // Verify industry variable exists and is numeric
        capture confirm numeric var `byindustry'
        if _rc != 0 {
            di as error "Error: `byindustry' must be a numeric variable"
            exit 198
        }

        di as text ""
        di as text "By-Industry Results (Treatment vs Control):"

        preserve

        // Get distinct industry levels
        qui levelsof `byindustry', local(ind_levels)
        local n_industries : word count `ind_levels'

        if `n_industries' == 0 {
            di as text "  No industry levels found. Skipping."
            restore
        }
        else {
            // Create results matrix: [n_industries x 6]
            // Columns: industry, D, p, D_plus, D_minus, N_total
            matrix _ks_ind = J(`n_industries', 6, .)

            // Table header
            di as text "  {hline 62}"
            di as text "  " _col(3) "Industry" _col(16) "|" ///
                _col(20) "D" _col(30) "|" ///
                _col(34) "p" _col(44) "|" ///
                _col(46) "D+" _col(54) "|" ///
                _col(56) "D-" _col(62) "| Result"
            di as text "  {hline 62}"

            local row = 0

            foreach ind of local ind_levels {
                local ++row

                // Store industry level
                matrix _ks_ind[`row', 1] = `ind'
                tempvar ind_treat_sample ind_window_year ind_sample_keep

                // Count treated and control for this industry
                if `prewindow' > 0 {
                    qui gen byte `ind_treat_sample' = `byindustry' == `ind' ///
                        & _pte_treat == 1 & _pte_nt >= -`prewindow' ///
                        & _pte_nt < 0 & `eps0_sample_if'
                }
                else {
                    qui gen byte `ind_treat_sample' = `byindustry' == `ind' ///
                        & _pte_treat == 1 & _pte_nt < 0 & `eps0_sample_if'
                }
                qui count if `ind_treat_sample'
                local n_t_ind = r(N)

                local n_c_ind = 0
                if `n_t_ind' > 0 {
                    qui bysort `timevar': egen byte `ind_window_year' = max(`ind_treat_sample')
                    qui count if `byindustry' == `ind' & _pte_treat == 0 ///
                        & `eps0_sample_if' & `ind_window_year' == 1
                    local n_c_ind = r(N)
                }

                local n_total_ind = `n_t_ind' + `n_c_ind'
                matrix _ks_ind[`row', 6] = `n_total_ind'

                if `n_t_ind' < 10 | `n_c_ind' < 10 {
                    // Insufficient sample for this industry
                    di as text "  " _col(3) "`ind'" _col(16) "|" ///
                        _col(18) "  ---  " _col(30) "|" ///
                        _col(32) "  ---  " _col(44) "|" ///
                        _col(46) " ---  " _col(54) "|" ///
                        _col(56) " ---  " "| SKIP (N<10)"
                    continue
                }

                // Run K-S test for this industry
                qui {
                    gen byte `ind_sample_keep' = `ind_treat_sample' | ///
                        (`byindustry' == `ind' & _pte_treat == 0 ///
                        & `eps0_sample_if' & `ind_window_year' == 1)
                    keep if `ind_sample_keep'

                    if "`notrimeps'" == "" {
                        // Match the replication trim law with the package-owned
                        // deterministic worker instead of depending on winsor2.
                        _pte_trim_var `eps0'
                        drop if missing(`eps0')
                    }

                    // K-S test
                    ksmirnov `eps0', by(_pte_treat)
                }

                local d_ind = r(D)
                local p_ind = r(p)
                local dp_ind = r(D_1)
                local dm_ind = r(D_2)

                matrix _ks_ind[`row', 2] = `d_ind'
                matrix _ks_ind[`row', 3] = `p_ind'
                matrix _ks_ind[`row', 4] = `dp_ind'
                matrix _ks_ind[`row', 5] = `dm_ind'

                // Determine pass/fail
                if `p_ind' < `alpha' {
                    local ind_result "FAIL"
                }
                else {
                    local ind_result "PASS"
                }

                di as text "  " _col(3) "`ind'" _col(16) "|" ///
                    _col(17) %8.4f `d_ind' _col(30) "|" ///
                    _col(31) %8.4f `p_ind' _col(44) "|" ///
                    _col(45) %7.4f `dp_ind' _col(54) "|" ///
                    _col(55) %7.4f `dm_ind' "| `ind_result'"

                // Reload full data for next industry
                restore, preserve
            }

            di as text "  {hline 62}"

            local has_industry = 1
            // Matrix column names
            matrix colnames _ks_ind = industry D p D_plus D_minus N
        }

        restore
    }

    // =============================================================
    // 3. Footer
    // =============================================================

    di as text ""
    di as text "{hline 60}"
    if `overall_pass' & !`overall_incomplete' {
        di as text "Overall: PASS - Parallel trends assumption supported"
    }
    else {
        di as error "Overall: FAIL or INCOMPLETE - Review results above"
    }
    di as text "{hline 60}"

    // =============================================================
    // 4. Return values
    // =============================================================

    // --- Part A: Treatment vs Control ---
    return scalar ks_D_treat  = `ks_D_treat'
    return scalar ks_p_treat  = `ks_p_treat'
    return scalar ks_D_plus   = `ks_D_plus'
    return scalar ks_p_plus   = `ks_p_plus'
    return scalar ks_D_minus  = `ks_D_minus'
    return scalar ks_p_minus  = `ks_p_minus'
    return scalar ks_N_treated = `ks_N_treated'
    return scalar ks_N_control = `ks_N_control'

    // --- Part B: Time Stability ---
    if "`notime'" == "" {
        return scalar ks_D_time  = `ks_D_time'
        return scalar ks_p_time  = `ks_p_time'
        return scalar ks_N_early = `ks_N_early'
        return scalar ks_N_late  = `ks_N_late'
        return scalar ks_mid_year = `ks_mid_year'
    }

    // --- Test 3: Group Consistency ---
    return scalar ks_D_group  = `ks_D_group'
    return scalar ks_D1_group = `ks_D1_group'
    return scalar ks_D2_group = `ks_D2_group'
    return scalar ks_p_group  = `ks_p_group'
    return scalar group_pass  = `group_pass'
    return scalar n_treated_pretreat = `n_treated_pretreat'
    return scalar n_control_group = `n_control_group'
    return scalar min_pretreat_year = `min_pretreat_year'
    return scalar max_pretreat_year = `max_pretreat_year'
    return scalar group_stability_skipped = `group_stability_skipped'
    return scalar group_stability_fallback = `group_stability_fallback'
    return scalar group_prewindow = `group_prewindow'
    return local  group_sample_type "`group_sample_type'"

    // --- Overall ---
    if `overall_incomplete' {
        return scalar ks_pass = .
    }
    else {
        return scalar ks_pass = `overall_pass'
    }
    return scalar prewindow  = `prewindow'

    // --- Part C: By-Industry matrix ---
    if `has_industry' {
        return matrix ks_industry = _ks_ind
    }

end
