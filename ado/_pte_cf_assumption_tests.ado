*! _pte_cf_assumption_tests.ado
*! Tests stationarity (D.3) and distributional comparability (D.4)
*! for counterfactual treatment effect estimation

version 14.0
program define _pte_cf_assumption_tests, rclass
    version 14.0

    // =========================================================================
    // Task 1: Program definition framework (eclass)
    // Task 2: Syntax parsing
    // =========================================================================

    local _pte_cf_raw0 `"`0'"'
    syntax , t0(integer) s(integer) ///
             targetvar(varname) omega(varname) ///
             [omegapoly(integer 3) panelvar(varname) timevar(varname) ///
              treatvar(name) midvar(name) ///
              cohortvar(name) statusvar(name) ///
              alpha(real 0.05) overlap_threshold(real 0.8) noreport]
    local _pte_cf_noreport = regexm(lower(`"`_pte_cf_raw0'"'), "(^|[ ,])noreport($|[ ,])")

    // =========================================================================
    // Task 3: Default values and temporary variables
    // =========================================================================

    if "`panelvar'" == "" local panelvar "firm"
    if "`timevar'" == "" local timevar "year"
    if "`treatvar'" == "" {
        capture confirm variable _pte_treat, exact
        if _rc == 0 local treatvar "_pte_treat"
        else local treatvar "treated"
    }
    if "`midvar'" == "" {
        capture confirm variable _pte_mid, exact
        if _rc == 0 local midvar "_pte_mid"
        else local midvar "mid"
    }
    if "`cohortvar'" == "" {
        capture confirm variable _pte_treat_year, exact
        if _rc == 0 local cohortvar "_pte_treat_year"
        else {
            capture confirm variable treat_year, exact
            if _rc == 0 local cohortvar "treat_year"
        }
    }

    tempvar late_period group_for_ks
    local _pte_cf_treat_year ""
    tempname d3_stat d3_pval d3_df d4_stat d4_pval
    tempname omega_min omega_max overlap_ratio
    tempname n_target n_treated_pre n_in_support
    tempname d3_pass d4_pass overlap_ok
    tempname _pte_cf_prev_est _pte_cf_base_d3 _pte_cf_interact_d3
    local _pte_cf_has_prev_est = 0
    local _pte_cf_exec_rc = 0

    // =========================================================================
    // Task 4: Check treat_year variable — generate if not present
    // =========================================================================

    capture confirm variable `treatvar', exact
    if _rc {
        di as error "treatvar variable '`treatvar'' not found"
        exit 111
    }

    capture confirm variable `midvar', exact
    if _rc {
        di as error "midvar variable '`midvar'' not found"
        exit 111
    }

    local _pte_cf_treat_year "`cohortvar'"
    if "`_pte_cf_treat_year'" != "" {
        capture confirm variable `_pte_cf_treat_year', exact
        if _rc {
            di as error "cohortvar variable '`_pte_cf_treat_year'' not found"
            exit 111
        }
    }
    else {
        local _pte_cf_statusvar "`statusvar'"
        if "`_pte_cf_statusvar'" == "" {
            capture confirm variable _pte_D, exact
            if _rc == 0 local _pte_cf_statusvar "_pte_D"
            else {
                capture confirm variable D, exact
                if _rc == 0 local _pte_cf_statusvar "D"
            }
        }

        if "`_pte_cf_statusvar'" == "" {
            di as error "Treatment timing not found"
            di as error "  Specify cohortvar() or statusvar(), or provide _pte_treat_year/treat_year/_pte_D/D"
            exit 198
        }

        capture confirm variable `_pte_cf_statusvar', exact
        if _rc {
            di as error "statusvar variable '`_pte_cf_statusvar'' not found"
            exit 111
        }

        tempvar _pte_cf_treat_year_tmp
        qui bys `panelvar': egen `_pte_cf_treat_year_tmp' = ///
            min(cond(`_pte_cf_statusvar' == 1, `timevar', .))
        local _pte_cf_treat_year "`_pte_cf_treat_year_tmp'"
    }

    // =========================================================================
    // Task 5: Validate target group sample size at t0+s-1
    // =========================================================================

    qui count if `targetvar' == 1 & `timevar' == `t0' + `s' - 1
    scalar `n_target' = r(N)
    if `n_target' == 0 {
        di as error "Target group is empty (no obs at t0+s-1 = `=`t0'+`s'-1')"
        exit 3006
    }

    // =========================================================================
    // Task 6: Validate treated group pre-treatment sample size
    // =========================================================================

    qui count if `treatvar' == 1 & `timevar' == `_pte_cf_treat_year' - 1
    scalar `n_treated_pre' = r(N)
    if `n_treated_pre' == 0 {
        di as error "Treated group has no pre-treatment observations"
        exit 3010
    }

    // =========================================================================
    // Task 7: Compute sample period midpoint
    // =========================================================================

    local mid_year = round((`t0' + `t0' + `s') / 2)

    // =========================================================================
    // Task 8: Generate late_period indicator
    // =========================================================================

    qui gen byte `late_period' = (`timevar' >= `mid_year')

    // Preserve the caller's e() context. This helper is rclass and should not
    // strand downstream consumers on the internal regression results used for
    // the D.3 LR test.
    capture _estimates hold `_pte_cf_prev_est', copy
    if !_rc local _pte_cf_has_prev_est = 1

    // =========================================================================
    // Task 9-10: Base regression (AR model without late_period interactions)
    // =========================================================================

    capture noisily {
        if `omegapoly' == 1 {
            qui reg `omega' L.`omega' if `midvar' == 0
        }
        else if `omegapoly' == 2 {
            qui reg `omega' L.`omega' c.L.`omega'#c.L.`omega' if `midvar' == 0
        }
        else if `omegapoly' == 3 {
            qui reg `omega' L.`omega' c.L.`omega'#c.L.`omega' ///
                    c.L.`omega'#c.L.`omega'#c.L.`omega' if `midvar' == 0
        }
        estimates store `_pte_cf_base_d3'

        // =====================================================================
        // Task 11: Interaction regression (base + late_period main + interactions)
        // df = omegapoly + 1 (intercept interaction + slope interactions)
        // =====================================================================

        if `omegapoly' == 1 {
            qui reg `omega' L.`omega' ///
                    `late_period' c.`late_period'#c.L.`omega' ///
                    if `midvar' == 0
        }
        else if `omegapoly' == 2 {
            qui reg `omega' L.`omega' c.L.`omega'#c.L.`omega' ///
                    `late_period' c.`late_period'#(c.L.`omega' ///
                    c.L.`omega'#c.L.`omega') if `midvar' == 0
        }
        else if `omegapoly' == 3 {
            qui reg `omega' L.`omega' c.L.`omega'#c.L.`omega' ///
                    c.L.`omega'#c.L.`omega'#c.L.`omega' ///
                    `late_period' c.`late_period'#(c.L.`omega' ///
                    c.L.`omega'#c.L.`omega' ///
                    c.L.`omega'#c.L.`omega'#c.L.`omega') if `midvar' == 0
        }
        estimates store `_pte_cf_interact_d3'

        // =====================================================================
        // Task 12: LR test execution
        // =====================================================================

        capture lrtest `_pte_cf_base_d3' `_pte_cf_interact_d3'
        if _rc == 0 {
            scalar `d3_stat' = r(chi2)
            scalar `d3_pval' = r(p)
            scalar `d3_df' = r(df)
        }
        else {
            di as text "Warning: LR test failed, D.3 test skipped"
            scalar `d3_stat' = .
            scalar `d3_pval' = .
            scalar `d3_df' = .
        }

        // =====================================================================
        // Task 13: D.3 pass/fail determination and cleanup
        // =====================================================================

        if !missing(`d3_pval') {
            scalar `d3_pass' = (`d3_pval' >= `alpha')
        }
        else {
            scalar `d3_pass' = .
        }

        // =====================================================================
        // Task 14: Generate K-S group indicator
        //   group=1: target group at t0+s-1
        //   group=0: treated group at pre-treatment period
        // =====================================================================

        qui gen byte `group_for_ks' = .
        qui replace `group_for_ks' = 1 if `targetvar' == 1 & `timevar' == `t0' + `s' - 1
        qui replace `group_for_ks' = 0 if `treatvar' == 1 & `timevar' == `_pte_cf_treat_year' - 1

        // =====================================================================
        // Task 15: Execute two-sample Kolmogorov-Smirnov test
        // =====================================================================

        qui ksmirnov `omega' if !missing(`group_for_ks'), by(`group_for_ks')
        scalar `d4_stat' = r(D)
        capture scalar `d4_pval' = r(p)
        if _rc {
            scalar `d4_pval' = r(p_cor)
        }

        // =====================================================================
        // Task 16: D.4 pass/fail determination
        // =====================================================================

        scalar `d4_pass' = (`d4_pval' >= `alpha')

        // =====================================================================
        // Task 17: Compute treated group omega support bounds
        // =====================================================================

        qui sum `omega' if `treatvar' == 1 & `timevar' == `_pte_cf_treat_year' - 1
        scalar `omega_min' = r(min)
        scalar `omega_max' = r(max)

        // =====================================================================
        // Task 18: Compute overlap ratio (target obs within treated support)
        // =====================================================================

        qui count if `targetvar' == 1 & `timevar' == `t0' + `s' - 1 & ///
                     inrange(`omega', `omega_min', `omega_max')
        scalar `n_in_support' = r(N)
        scalar `overlap_ratio' = `n_in_support' / `n_target'
        scalar `overlap_ok' = (`overlap_ratio' >= `overlap_threshold')

        // =====================================================================
        // Task 19: Cleanup (tempvars auto-dropped, no explicit action needed)
        // =====================================================================

        // =====================================================================
        // Task 20: Diagnostic table (suppressed if noreport specified)
        // =====================================================================

        if !`_pte_cf_noreport' {
            di as text "{hline 72}"
            di as text "| Test                 | Statistic  | df       | p-value | Result  |"
            di as text "{hline 72}"

            if !missing(`d3_pval') {
                local d3_result = cond(`d3_pass', "PASS", "FAIL")
                di as text "| D.3 (Time Stability) | " ///
                    %10.4f `d3_stat' " | " ///
                    %8.0f `d3_df' " | " ///
                    %7.4f `d3_pval' " | " ///
                    as result "`d3_result'" as text "    |"
            }

            local d4_result = cond(`d4_pass', "PASS", "FAIL")
            di as text "| D.4 (Dist. Compar.)  | " ///
                %10.4f `d4_stat' " |    -     | " ///
                %7.4f `d4_pval' " | " ///
                as result "`d4_result'" as text "    |"

            di as text "{hline 72}"
        }

        // =====================================================================
        // Task 21: Overlap assessment output
        // =====================================================================

        if !`_pte_cf_noreport' {
            di as text ""
            di as text "Overlap Assessment:"
            di as text "  Treated support: [" ///
                %7.4f `omega_min' ", " %7.4f `omega_max' "]"
            di as text "  Target in support: " ///
                `=scalar(`n_in_support')' "/" ///
                `=scalar(`n_target')' " = " ///
                %5.1f (`=scalar(`overlap_ratio')'*100) "%"
            local overlap_result = cond(`overlap_ok', "OK", "LOW")
            di as text "  Overlap ratio: " ///
                %5.3f `overlap_ratio' "  " ///
                as result "`overlap_result'"
        }

        // =====================================================================
        // Task 22: Decision tree recommendation output
        // =====================================================================

        if !`_pte_cf_noreport' {
            di as text ""
            di as text "{hline 72}"
            di as text "Method Recommendation:"
            di as text "{hline 72}"

            local d3_ok = cond(missing(`d3_pass'), 1, `d3_pass')

            if `d3_ok' & `d4_pass' & `overlap_ok' {
                di as text "Recommendation: Use Proposition D.4 (matching method)"
                di as text "  Both assumptions hold, matching approach is valid"
            }
            else if `d3_ok' & (!`d4_pass' | !`overlap_ok') {
                di as text "Recommendation: Use Proposition D.3 (divergent evolution method)"
                di as text "  D.3 holds but D.4 fails or low overlap"
            }
            else if !`d3_ok' & `d4_pass' & `overlap_ok' {
                di as error "Warning: Assumption D.3 (time stability) violated"
                di as text "  Consider: shorter time windows, structural break tests"
            }
            else {
                di as error "Warning: Both D.3 and D.4 may be violated"
                di as text "  Counterfactual ATE estimates may be unreliable"
            }

            di as text "{hline 72}"
        }

        // =====================================================================
        // Task 23: Store all r() return values
        // =====================================================================

        return clear
        return scalar assumption_d3_stat = `d3_stat'
        return scalar assumption_d3_pval = `d3_pval'
        return scalar assumption_d3_df   = `d3_df'
        return scalar assumption_d4_stat = `d4_stat'
        return scalar assumption_d4_pval = `d4_pval'
        return scalar overlap_ratio      = `overlap_ratio'
        return scalar n_target           = `n_target'
        return scalar n_treated_pre      = `n_treated_pre'
        return scalar omega_support_min  = `omega_min'
        return scalar omega_support_max  = `omega_max'
        return scalar d3_pass            = `d3_pass'
        return scalar d4_pass            = `d4_pass'
        return scalar overlap_ok         = `overlap_ok'
    }
    local _pte_cf_exec_rc = _rc
    capture estimates drop `_pte_cf_base_d3' `_pte_cf_interact_d3'
    if `_pte_cf_has_prev_est' {
        capture _estimates unhold `_pte_cf_prev_est'
    }
    if `_pte_cf_exec_rc' != 0 {
        exit `_pte_cf_exec_rc'
    }

end
