*! pte_diagnose.ado
*! Run the public diagnostics suite for omega and untreated-shock objects left by pte.

version 14.0
capture program drop pte_diagnose
program define pte_diagnose, rclass
    version 14.0
    
    syntax , [PARallel KStest CONDitional CDF ALL ///
              omega(name) eps0(name) ///
              PREperiods(integer 4) bins(integer 3) ///
              baseyear(integer -1) minobs(integer 30) ///
              alpha(real 0.05) Level(cilevel) ///
              SAVing(string) NOTRIMeps STRICTcontrol QUIetly]
    
    // Default to the full suite unless the caller selects a subset explicitly.
    local do_parallel = 0
    local do_kstest = 0
    local do_conditional = 0
    local do_cdf = 0
    
    if "`all'" != "" {
        local do_parallel = 1
        local do_kstest = 1
        local do_conditional = 1
        local do_cdf = 1
    }
    else {
        if "`parallel'" != "" local do_parallel = 1
        if "`kstest'" != "" local do_kstest = 1
        if "`conditional'" != "" local do_conditional = 1
        if "`cdf'" != "" local do_cdf = 1
    }
    
    // Preserve the same default when no selector option is supplied.
    if `do_parallel' == 0 & `do_kstest' == 0 & `do_conditional' == 0 & `do_cdf' == 0 {
        local do_parallel = 1
        local do_kstest = 1
        local do_conditional = 1
        local do_cdf = 1
    }

    // Assumption 3.3 is the identification gate for the full released
    // diagnostic suite. It runs only when the caller requests the whole
    // public bundle (default, all, or the four explicit public branches).
    local do_assumption33 = (`do_parallel' & `do_kstest' & `do_conditional' & `do_cdf')

    if "`saving'" != "" & `do_cdf' == 0 {
        di as error "saving() requires cdf or all"
        exit 198
    }

    if `do_parallel' & `preperiods' < 2 {
        di as error "preperiods() must be at least 2"
        exit 198
    }

    // Public override names must survive syntax parsing as the caller wrote
    // them; otherwise Stata unique-abbreviation fallback can silently redirect
    // the diagnostics to a different shadow variable.
    if "`omega'" != "" {
        capture confirm variable `omega', exact
        if _rc != 0 {
            di as error "omega() variable `omega' not found; specify an exact existing variable name"
            exit 111
        }
        capture confirm numeric variable `omega'
        if _rc != 0 {
            di as error "omega() variable `omega' must be numeric"
            exit 111
        }
    }

    if "`eps0'" != "" {
        capture confirm variable `eps0', exact
        if _rc != 0 {
            di as error "eps0() variable `eps0' not found; specify an exact existing variable name"
            exit 111
        }
        capture confirm numeric variable `eps0'
        if _rc != 0 {
            di as error "eps0() variable `eps0' must be numeric"
            exit 111
        }
    }

    // Public wrapper contract: invalid conditional-branch parameters are
    // rejected up front. baseyear() also defines the initial-productivity
    // support directly, so impossible baseyear() requests must be rejected at
    // the wrapper before the conditional worker can be silently reclassified
    // as a skipped diagnostic.
    if `do_conditional' {
        if `bins' < 2 | `bins' > 10 {
            di as error "bins() must be between 2 and 10"
            exit 198
        }
        if `minobs' < 10 {
            di as error "minobs() must be at least 10"
            exit 198
        }
        local pte_conditional_missing_default = 0
        if "`omega'" == "" {
            capture confirm numeric variable _pte_omega, exact
            if _rc != 0 {
                local pte_conditional_missing_default = 1
            }
        }
        if "`eps0'" == "" {
            capture confirm numeric variable _pte_eps0, exact
            if _rc != 0 {
                local pte_conditional_missing_default = 1
            }
        }
        if `baseyear' != -1 & !`pte_conditional_missing_default' {
            local _pte_conditional_omega "_pte_omega"
            if "`omega'" != "" local _pte_conditional_omega "`omega'"

            local _pte_conditional_timevar ""
            capture noisily _pte_diag_panel_contract, context("conditional diagnostics") ///
                allowsetupmissingxtdelta
            local _pte_conditional_contract_rc = _rc
            if `_pte_conditional_contract_rc' != 0 {
                exit `_pte_conditional_contract_rc'
            }
            local _pte_conditional_timevar "`r(timevar)'"

            capture confirm numeric variable `_pte_conditional_omega', exact
            if _rc == 0 & "`_pte_conditional_timevar'" != "" {
                capture confirm variable `_pte_conditional_timevar', exact
                if _rc != 0 {
                    di as error "Stored time variable `_pte_conditional_timevar' not found in data."
                    di as error "Re-run pte on the current dataset before pte_diagnose."
                    exit 111
                }

                local _pte_conditional_scope ""
                if "`strictcontrol'" != "" {
                    capture confirm variable _pte_treat, exact
                    if _rc == 0 {
                        local _pte_conditional_scope " & _pte_treat == 0"
                    }
                }
                quietly count if `_pte_conditional_timevar' == `baseyear' ///
                    & !missing(`_pte_conditional_omega')`_pte_conditional_scope'
                if r(N) == 0 {
                    di as error "baseyear(`baseyear') is outside the observed support of `_pte_conditional_timevar' for nonmissing `_pte_conditional_omega'"
                    exit 198
                }
            }
        }
    }

    if (`do_kstest' | `do_conditional') {
        if `alpha' <= 0 | `alpha' >= 1 {
            di as error "alpha() must be between 0 and 1"
            exit 198
        }
    }

    // Reset wrapper r() state so the current diagnostic subset does not
    // inherit stale returns from an earlier pte_diagnose call.
    return clear
    
    if "`quietly'" == "" {
        di as text ""
        di as text "{hline 70}"
        di as text "{bf:PTE Diagnostic Tests}"
        di as text "{hline 70}"
    }
    
    // Count only diagnostics attempted in this call.
    local n_tests = 0
    local n_pass = 0
    local n_fail = 0
    local n_skip = 0
    local has_pretrend = 0
    local pretrend_F = .
    local pretrend_p = .
    local pretrend_pass = .
    local pretrend_skipped_public = .
    local has_ks = 0
    local ks_D_public = .
    local ks_p_public = .
    local ks_pass_public = .
    local ks_D_treat_public = .
    local ks_p_treat_public = .
    local ks_D_plus_public = .
    local ks_p_plus_public = .
    local ks_D_minus_public = .
    local ks_p_minus_public = .
    local ks_N_treated_public = .
    local ks_N_control_public = .
    local ks_D_group_public = .
    local ks_D1_group_public = .
    local ks_D2_group_public = .
    local ks_p_group_public = .
    local group_pass_public = .
    local n_treated_pretreat_public = .
    local n_control_group_public = .
    local min_pretreat_year_public = .
    local max_pretreat_year_public = .
    local group_stability_skipped_public = .
    local group_stability_fallback_public = .
    local group_prewindow_public = .
    local ks_prewindow_public = .
    local group_sample_type_public ""
    local has_norm = 0
    local norm_pass_public = .
    local ks_D_norm_public = .
    local ks_p_norm_public = .
    local sktest_chi2_public = .
    local sktest_p_public = .
    local N_eps0_norm_public = .
    local eps0_mean_public = .
    local eps0_sd_public = .
    local eps0_skewness_public = .
    local eps0_kurtosis_public = .
    local has_conditional = 0
    local conditional_pass_public = .
    local has_assumption33 = 0
    local assumption33_pass_public = .
    local n_stable_0_public = .
    local n_stable_1_public = .
    local n_transition_public = .
    local n_trans_in_public = .
    local n_trans_out_public = .
    local n_first_period_public = .
    local n_valid_public = .
    local pct_transition_public = .

    if `do_assumption33' {
        local n_tests = `n_tests' + 1

        capture confirm numeric variable _pte_D, exact
        if _rc != 0 {
            di as error "Identification check requires the exact current-treatment variable _pte_D."
            di as error "Re-run pte on the current dataset before pte_diagnose."
            exit 111
        }

        local assumption33_quiet ""
        if "`quietly'" != "" local assumption33_quiet "quietly"

        capture _pte_check_assumption33 _pte_D, nonfatal `assumption33_quiet'
        local assumption33_rc = _rc
        if `assumption33_rc' != 0 {
            if "`quietly'" == "" {
                di as error "Assumption 3.3 check failed (rc = `assumption33_rc')"
            }
            exit `assumption33_rc'
        }

        capture local assumption33_pass = r(assumption33_passed)
        if _rc != 0 {
            di as error "Assumption 3.3 check returned rc=0 but did not publish r(assumption33_passed)"
            exit 498
        }

        local has_assumption33 = 1
        local assumption33_pass_public = `assumption33_pass'
        local n_stable_0_public = r(n_stable_0)
        local n_stable_1_public = r(n_stable_1)
        local n_transition_public = r(n_transition)
        local n_trans_in_public = r(n_trans_in)
        local n_trans_out_public = r(n_trans_out)
        local n_first_period_public = r(n_first_period)
        local n_valid_public = r(n_valid)
        local pct_transition_public = r(pct_transition)

        if `assumption33_pass' == 1 {
            local n_pass = `n_pass' + 1
        }
        else {
            local n_fail = `n_fail' + 1
        }
    }
    
    // This diagnostic compares pre-entry omega dynamics on untreated support,
    // which is the observable implication relevant for the entry-period design.
    if `do_parallel' {
        local n_tests = `n_tests' + 1
        
        capture {
            local omega_opt ""
            if "`omega'" != "" local omega_opt "omega(`omega')"
            
            _pte_diag_pretrend, `omega_opt' preperiods(`preperiods') level(`level')
        }
        
        if _rc == 0 {
            capture local pt_skip = r(pretrend_skipped)
            if _rc != 0 | missing(`pt_skip') {
                local pt_skip = 0
            }

            if `pt_skip' == 1 {
                local pretrend_skipped_public = 1
                local n_skip = `n_skip' + 1
            }
            else {
                local pt_pass = r(pretrend_pass)
                local has_pretrend = 1
                local pretrend_F = r(F_pretrend)
                local pretrend_p = r(p_pretrend)
                local pretrend_pass = `pt_pass'
                local pretrend_skipped_public = 0
                
                if `pt_pass' == 1 {
                    local n_pass = `n_pass' + 1
                }
                else {
                    local n_fail = `n_fail' + 1
                }
            }
        }
        else {
            if "`quietly'" == "" {
                di as error "Pre-trend test failed (rc = " _rc ")"
            }
            exit _rc
        }
    }
    
    // Counterfactual simulation reuses untreated eps0 draws, so temporal
    // stability of that pool matters for the simulation design.
    if `do_kstest' {
        local n_tests = `n_tests' + 1

        local eps0_opt ""
        if "`eps0'" != "" local eps0_opt "eps0(`eps0')"
        local trim_opt ""
        if "`notrimeps'" != "" local trim_opt "notrimeps"

        if "`quietly'" != "" {
            capture qui _pte_diag_kstest, `eps0_opt' alpha(`alpha') `trim_opt'
        }
        else {
            capture _pte_diag_kstest, `eps0_opt' alpha(`alpha') `trim_opt'
        }

        local kstest_rc = _rc
        if `kstest_rc' != 0 {
            if "`quietly'" == "" {
                di as error "K-S test failed (rc = `kstest_rc')"
            }
            exit `kstest_rc'
        }

        capture local ks_pass = r(ks_pass)
        if _rc {
            di as error "K-S test returned rc=0 but did not publish r(ks_pass)"
            exit 498
        }

        local ks_D_treat_public = r(ks_D_treat)
        local ks_p_treat_public = r(ks_p_treat)
        local ks_D_plus_public = r(ks_D_plus)
        local ks_p_plus_public = r(ks_p_plus)
        local ks_D_minus_public = r(ks_D_minus)
        local ks_p_minus_public = r(ks_p_minus)
        local ks_N_treated_public = r(ks_N_treated)
        local ks_N_control_public = r(ks_N_control)
        local ks_D_group_public = r(ks_D_group)
        local ks_D1_group_public = r(ks_D1_group)
        local ks_D2_group_public = r(ks_D2_group)
        local ks_p_group_public = r(ks_p_group)
        local group_pass_public = r(group_pass)
        local n_treated_pretreat_public = r(n_treated_pretreat)
        local n_control_group_public = r(n_control_group)
        local min_pretreat_year_public = r(min_pretreat_year)
        local max_pretreat_year_public = r(max_pretreat_year)
        local group_stability_skipped_public = r(group_stability_skipped)
        local group_stability_fallback_public = r(group_stability_fallback)
        local group_prewindow_public = r(group_prewindow)
        local ks_prewindow_public = r(prewindow)
        local group_sample_type_public `"`r(group_sample_type)'"'

        tempname ks_D_time_scalar ks_p_time_scalar

        capture scalar `ks_D_time_scalar' = r(ks_D_time)
        local has_ks_d = (_rc == 0)
        capture scalar `ks_p_time_scalar' = r(ks_p_time)
        local has_ks_p = (_rc == 0)

        if !`has_ks_d' | !`has_ks_p' {
            di as error "K-S test returned rc=0 but r(ks_D_time)/r(ks_p_time) contract is broken"
            exit 498
        }

        // _pte_diag_kstest may legitimately skip time-stability and return
        // both statistics as missing; treat this as skip, not a fatal error.
        local ks_d_missing = missing(`ks_D_time_scalar')
        local ks_p_missing = missing(`ks_p_time_scalar')
        if `ks_d_missing' != `ks_p_missing' {
            di as error "K-S test returned inconsistent time-stability stats (one missing, one non-missing)"
            exit 498
        }

        local ks_incomplete = missing(`ks_pass')

        if `ks_d_missing' & !`ks_incomplete' {
            di as error "K-S test returned skipped time-stability stats but a nonmissing r(ks_pass)"
            exit 498
        }

        if `ks_d_missing' {
            local has_ks = 1
            local ks_D_public = .
            local ks_p_public = .
            local ks_pass_public = .
            local n_skip = `n_skip' + 1
        }
        else if `ks_incomplete' {
            local has_ks = 1
            local ks_D_public = `ks_D_time_scalar'
            local ks_p_public = `ks_p_time_scalar'
            local ks_pass_public = .
        }
        else {
            local has_ks = 1
            local ks_D_public = `ks_D_time_scalar'
            local ks_p_public = `ks_p_time_scalar'
            local ks_pass_public = `ks_pass'

            if `ks_pass' == 1 {
                local n_pass = `n_pass' + 1
            }
            else {
                local n_fail = `n_fail' + 1
            }
        }

        // Normality is only a simulation diagnostic. Identification relies on
        // untreated-shock recovery, not on Gaussianity itself, so keep its
        // output in r() but exclude it from the public summary counters.
        
        capture {
            local eps0_opt ""
            if "`eps0'" != "" local eps0_opt "eps0(`eps0')"
            local norm_trim_opt ""
            if "`notrimeps'" != "" local norm_trim_opt "notrimeps"
            
            if "`quietly'" != "" {
                qui _pte_diag_kstest_norm, `eps0_opt' `norm_trim_opt'
            }
            else {
                _pte_diag_kstest_norm, `eps0_opt' `norm_trim_opt'
            }
        }
        
        if _rc == 0 {
            capture local norm_pass = r(norm_pass)
            if !_rc & !missing(`norm_pass') {
                local has_norm = 1
                local norm_pass_public = `norm_pass'
                local ks_D_norm_public = r(ks_D_norm)
                local ks_p_norm_public = r(ks_p_norm)
                local sktest_chi2_public = r(sktest_chi2)
                local sktest_p_public = r(sktest_p)
                local N_eps0_norm_public = r(N_eps0_norm)
                local eps0_mean_public = r(eps0_mean)
                local eps0_sd_public = r(eps0_sd)
                local eps0_skewness_public = r(eps0_skewness)
                local eps0_kurtosis_public = r(eps0_kurtosis)
                
            }
            else {
                local has_norm = 1
                local norm_pass_public = .
            }
        }
        else {
            if "`quietly'" == "" {
                di as error "Normality test failed (rc = " _rc ")"
            }
            local has_norm = 1
            local norm_pass_public = .
        }
    }
    
    // Compare eps0 across omega bins to assess whether untreated shocks vary
    // with latent productivity, which would weaken shock reuse.

    if `do_conditional' {
        local n_tests = `n_tests' + 1

        local cond_missing_source = 0
        if "`omega'" == "" {
            capture confirm numeric variable _pte_omega, exact
            if _rc != 0 {
                local cond_missing_source = 1
            }
        }
        if "`eps0'" == "" {
            capture confirm numeric variable _pte_eps0, exact
            if _rc != 0 {
                local cond_missing_source = 1
            }
        }

        if `cond_missing_source' {
            local n_skip = `n_skip' + 1
            local has_conditional = 1
            local conditional_pass_public = .
        }
        else capture {
            local eps0_opt ""
            if "`eps0'" != "" local eps0_opt "eps0(`eps0')"
            local omega_opt ""
            if "`omega'" != "" local omega_opt "omega(`omega')"
            local trim_opt ""
            if "`notrimeps'" != "" local trim_opt "notrimeps"
            local strict_opt ""
            if "`strictcontrol'" != "" local strict_opt "strictcontrol"
            local by_opt ""
            if `baseyear' != -1 local by_opt "baseyear(`baseyear')"
            local quiet_opt ""
            if "`quietly'" != "" local quiet_opt "quietly"
            
            _pte_diag_conditional, `eps0_opt' `omega_opt' bins(`bins') ///
                minobs(`minobs') alpha(`alpha') `trim_opt' `strict_opt' `by_opt' `quiet_opt'
        }

        if `cond_missing_source' == 0 {
            local conditional_rc = _rc
            if `conditional_rc' == 0 {
                tempname conditional_pass_scalar
                capture scalar `conditional_pass_scalar' = r(conditional_pass)
                if _rc != 0 {
                    di as error "Conditional test returned rc=0 but did not publish r(conditional_pass)"
                    exit 498
                }

                local cond_pass = `conditional_pass_scalar'
                if !missing(`cond_pass') {
                    local has_conditional = 1
                    local conditional_pass_public = `cond_pass'
                    
                    if `cond_pass' == 1 {
                        local n_pass = `n_pass' + 1
                    }
                    else if `cond_pass' == 0 {
                        local n_fail = `n_fail' + 1
                    }
                    else {
                        local n_skip = `n_skip' + 1
                    }
                }
                else {
                    local n_skip = `n_skip' + 1
                    local has_conditional = 1
                    local conditional_pass_public = .
                }
            }
            else {
                if "`quietly'" == "" {
                    di as error "Conditional test failed (rc = `conditional_rc')"
                }
                exit `conditional_rc'
            }
        }
    }
    
    // The CDF branch is descriptive when it succeeds; a worker failure on a
    // requested diagnostic must still surface as a nonzero public rc.
    
    if `do_cdf' {
        local n_tests = `n_tests' + 1

        if "`eps0'" != "" {
            capture confirm variable `eps0', exact
            if _rc != 0 {
                di as error "eps0() variable `eps0' not found; specify an exact existing variable name"
                exit 111
            }
            capture confirm numeric variable `eps0', exact
            if _rc != 0 {
                di as error "eps0() variable `eps0' must be numeric"
                exit 111
            }
        }

        capture {
            local eps0_opt ""
            if "`eps0'" != "" local eps0_opt "eps0(`eps0')"
            local save_opt ""
            if "`saving'" != "" local save_opt "saving(`saving')"
            local trim_opt ""
            if "`notrimeps'" != "" local trim_opt "notrimeps"
            local quiet_opt ""
            if "`quietly'" != "" local quiet_opt "quietly"
            
            _pte_diag_cdf, `eps0_opt' `save_opt' `trim_opt' `quiet_opt'
        }

        local cdf_rc = _rc
        if `cdf_rc' == 0 {
            // CDF is a requested descriptive diagnostic. Successful graph
            // generation should count as executed work, not as a skipped test.
        }
        else {
            if "`quietly'" == "" {
                di as error "CDF plot failed (rc = `cdf_rc')"
            }
            exit `cdf_rc'
        }
    }
    
    // Summarize only the diagnostics attempted in this call.
    
    if "`quietly'" == "" {
        di as text ""
        di as text "{hline 70}"
        di as text "{bf:Diagnostic Summary}"
        di as text "{hline 70}"
        di as text "Tests run:    `n_tests'"
        di as text "  Passed:     `n_pass'"
        di as text "  Failed:     `n_fail'"
        di as text "  Skipped:    `n_skip'"
        di as text ""
        
        if `n_fail' == 0 & `n_pass' > 0 {
            di as result "Overall: All diagnostic tests PASSED"
            di as result "PTE assumptions appear to be supported by the data."
        }
        else if `n_fail' > 0 {
            di as error "Overall: Some diagnostic tests FAILED"
            di as error "Review individual test results above for details."
        }
        else if `n_tests' > 0 & `n_pass' == 0 & `n_fail' == 0 {
            di as text "Overall: Descriptive diagnostics completed"
            di as text "No pass/fail diagnostic test was requested in this call."
        }
        else if `n_tests' == 0 {
            di as text "No tests were executed."
        }
        
        di as text "{hline 70}"
    }
    
    // Return compact pass/fail counts for programmatic callers.
    return clear

    return scalar pretrend_F = `pretrend_F'
    return scalar pretrend_p = `pretrend_p'
    return scalar pretrend_pass = `pretrend_pass'
    return scalar pretrend_skipped = `pretrend_skipped_public'
    return scalar ks_D = `ks_D_public'
    return scalar ks_p = `ks_p_public'
    return scalar ks_pass = `ks_pass_public'
    return scalar norm_pass = `norm_pass_public'
    return scalar ks_D_norm = `ks_D_norm_public'
    return scalar ks_p_norm = `ks_p_norm_public'
    return scalar sktest_chi2 = `sktest_chi2_public'
    return scalar sktest_p = `sktest_p_public'
    return scalar N_eps0_norm = `N_eps0_norm_public'
    return scalar eps0_mean = `eps0_mean_public'
    return scalar eps0_sd = `eps0_sd_public'
    return scalar eps0_skewness = `eps0_skewness_public'
    return scalar eps0_kurtosis = `eps0_kurtosis_public'
    return scalar conditional_pass = `conditional_pass_public'
    return scalar assumption33_pass = `assumption33_pass_public'
    return scalar n_stable_0 = `n_stable_0_public'
    return scalar n_stable_1 = `n_stable_1_public'
    return scalar n_transition = `n_transition_public'
    return scalar n_trans_in = `n_trans_in_public'
    return scalar n_trans_out = `n_trans_out_public'
    return scalar n_first_period = `n_first_period_public'
    return scalar n_valid = `n_valid_public'
    return scalar pct_transition = `pct_transition_public'

    return scalar ks_D_treat = `ks_D_treat_public'
    return scalar ks_p_treat = `ks_p_treat_public'
    return scalar ks_D_plus = `ks_D_plus_public'
    return scalar ks_p_plus = `ks_p_plus_public'
    return scalar ks_D_minus = `ks_D_minus_public'
    return scalar ks_p_minus = `ks_p_minus_public'
    return scalar ks_N_treated = `ks_N_treated_public'
    return scalar ks_N_control = `ks_N_control_public'
    return scalar ks_D_group = `ks_D_group_public'
    return scalar ks_D1_group = `ks_D1_group_public'
    return scalar ks_D2_group = `ks_D2_group_public'
    return scalar ks_p_group = `ks_p_group_public'
    return scalar group_pass = `group_pass_public'
    return scalar n_treated_pretreat = `n_treated_pretreat_public'
    return scalar n_control_group = `n_control_group_public'
    return scalar min_pretreat_year = `min_pretreat_year_public'
    return scalar max_pretreat_year = `max_pretreat_year_public'
    return scalar group_stability_skipped = `group_stability_skipped_public'
    return scalar group_stability_fallback = `group_stability_fallback_public'
    return scalar group_prewindow = `group_prewindow_public'
    return scalar prewindow = `ks_prewindow_public'
    return local group_sample_type "`group_sample_type_public'"
    
    return scalar n_tests = `n_tests'
    return scalar n_pass = `n_pass'
    return scalar n_fail = `n_fail'
    return scalar n_skip = `n_skip'
    
    local overall = 1
    if `n_fail' > 0 local overall = 0
    if `n_tests' == 0 | (`n_pass' == 0 & `n_fail' == 0) local overall = .
    return scalar overall_pass = `overall'
    
end
