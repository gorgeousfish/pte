*! _pte_winsorize.ado
*! Theory: After trimming outliers (1%-99%), assume eps0 ~ N(0, sigma^2)

version 14.0
capture program drop _pte_winsorize
program define _pte_winsorize, eclass
    version 14.0
    
    // ================================================================
    // Syntax parsing
    // ================================================================
    // Snapshot the caller's live estimation state before syntax validation so
    // failure paths can roll back to the prior trim bridge instead of wiping
    // downstream consumers.
    tempname _pte_prev_est
    local _pte_has_prev_est = 0
    capture estimates store `_pte_prev_est', copy
    if _rc == 0 {
        local _pte_has_prev_est = 1
    }
    local _pte_clear_eclass ///
        "quietly _pte_winsorize_restore, estname(`_pte_prev_est') hasest(`_pte_has_prev_est')"
    capture noisily syntax, [NOTRIMeps NODIAGnose KSTEST treatment(name)]
    if _rc != 0 {
        local _pte_syntax_rc = _rc
        `_pte_clear_eclass'
        exit `_pte_syntax_rc'
    }
    local _pte_has_explicit_treatment = ("`treatment'" != "")
    
    // ================================================================
    // Step 1: Input validation (Task 1-4)
    // ================================================================
    
    local has_evo_state = 0
    local bridge_cmd `"`e(cmd)'"'
    tempname _pte_win_rho_0 _pte_win_rho_1
    local evo_idvar `"`e(idvar)'"'
    if `"`evo_idvar'"' == "" {
        local evo_idvar `"`e(id)'"'
    }
    local evo_timevar `"`e(timevar)'"'
    if `"`evo_timevar'"' == "" {
        local evo_timevar `"`e(time)'"'
    }
    local evo_has_xtdelta = 0
    local evo_xtdelta = .
    tempname _pte_win_xtdelta
    capture scalar `_pte_win_xtdelta' = e(xtdelta)
    if _rc == 0 & !missing(`_pte_win_xtdelta') {
        local evo_has_xtdelta = 1
        local evo_xtdelta = `_pte_win_xtdelta'
    }
    capture confirm matrix e(rho_0)
    if _rc == 0 & inlist("`bridge_cmd'", "_pte_eps0_sample", "_pte_omega", "_pte_winsorize", "pte") {
        local has_evo_state = 1
        matrix `_pte_win_rho_0' = e(rho_0)
        local evo_has_treated_state = 0

        local evo_omegapoly = e(omegapoly)
        local evo_rho0 = e(rho0)
        local evo_rho1 = e(rho1)
        if `evo_omegapoly' >= 2 local evo_rho2 = e(rho2)
        if `evo_omegapoly' >= 3 local evo_rho3 = e(rho3)
        if `evo_omegapoly' >= 4 local evo_rho4 = e(rho4)
        local evo_has_N_lag_untreated = 0
        local evo_has_N_lag_treated = 0
        local evo_has_lag_supported = 0
        local evo_has_eps0window = 0
        local evo_N_lag_untreated = .
        local evo_N_lag_treated = .
        local evo_lag_supported = .
        local evo_eps0window = .
        capture local evo_N_lag_untreated = e(N_lag_untreated)
        if _rc == 0 {
            local evo_has_N_lag_untreated = 1
        }
        capture local evo_N_lag_treated = e(N_lag_treated)
        if _rc == 0 {
            local evo_has_N_lag_treated = 1
        }
        capture local evo_lag_supported = e(lag_treated_supported)
        if _rc == 0 {
            local evo_has_lag_supported = 1
        }
        if `evo_has_lag_supported' & `evo_lag_supported' {
            capture confirm matrix e(rho_1)
            if _rc == 0 {
                matrix `_pte_win_rho_1' = e(rho_1)
                local evo_has_treated_state = 1
            }
        }
        if `evo_has_treated_state' {
            local evo_gamma1 = e(gamma1)
            if `evo_omegapoly' >= 2 local evo_gamma2 = e(gamma2)
            if `evo_omegapoly' >= 3 local evo_gamma3 = e(gamma3)
            if `evo_omegapoly' >= 4 local evo_gamma4 = e(gamma4)
            local evo_delta = e(delta)
        }
        capture local evo_eps0window = e(eps0window)
        if _rc == 0 & !missing(`evo_eps0window') {
            local evo_has_eps0window = 1
        }
        local evo_N_evo = .
        local evo_r2 = .
        local evo_rmse = .
        capture local evo_N_evo = e(N_evo)
        capture local evo_r2 = e(r2)
        if _rc != 0 | missing(`evo_r2') {
            capture local evo_r2 = e(r2_evo)
        }
        capture local evo_rmse = e(rmse)
        if _rc != 0 | missing(`evo_rmse') {
            capture local evo_rmse = e(rmse_evo)
        }
        local evo_treatment `"`e(treatment)'"'
        local evo_prodfunc `"`e(prodfunc)'"'
        if "`evo_prodfunc'" == "" {
            local evo_prodfunc `"`e(pfunc)'"'
        }
        local evo_pfunc `"`e(pfunc)'"'
        if "`evo_pfunc'" == "" {
            local evo_pfunc `"`evo_prodfunc'"'
        }
    }

    // 1.1 Validate _pte_eps0 variable exists and is numeric.
    // eps0 is the untreated innovation residual, so type errors must be
    // rejected at the entry contract rather than misdiagnosed as a
    // downstream variance/sample-size failure.
    local _varlist : char _dta[_pte_eps0_exists]
    capture confirm variable _pte_eps0, exact
    if _rc != 0 {
        di as error "[pte] Error: variable '_pte_eps0' not found"
        di as error "[pte] Please run _pte_eps0_sample first"
        `_pte_clear_eclass'
        exit 111
    }
    capture confirm numeric variable _pte_eps0
    if _rc != 0 {
        di as error "[pte] Error: variable '_pte_eps0' must be numeric"
        di as error "[pte]        eps0 is the untreated innovation residual from _pte_eps0_sample"
        `_pte_clear_eclass'
        exit 111
    }
    
    // 1.2 Validate _pte_eps0_ind sample indicator exists (use exact match)
    capture confirm variable _pte_eps0_ind, exact
    if _rc != 0 {
        di as error "[pte] Error: variable '_pte_eps0_ind' not found"
        di as error "[pte] Please run _pte_eps0_sample first"
        `_pte_clear_eclass'
        exit 111
    }
    capture confirm numeric variable _pte_eps0_ind
    if _rc != 0 {
        di as error "[pte] Error: variable '_pte_eps0_ind' must be numeric"
        di as error "[pte]        _pte_eps0_ind is the untreated innovation support indicator from _pte_eps0_sample"
        `_pte_clear_eclass'
        exit 111
    }
    capture assert inlist(_pte_eps0_ind, 0, 1) if !missing(_pte_eps0_ind)
    if _rc != 0 {
        di as error "[pte] Error: variable '_pte_eps0_ind' must be binary (0/1)"
        di as error "[pte]        _pte_eps0_ind is the exact untreated innovation support indicator from _pte_eps0_sample"
        `_pte_clear_eclass'
        exit 450
    }

    // 1.3 Validate eps0 sample is non-empty
    quietly count if _pte_eps0_ind == 1 & !missing(_pte_eps0)
    if r(N) == 0 {
        di as error "[pte] Error: no observations in eps0 sample"
        di as error "[pte] Check output"
        `_pte_clear_eclass'
        exit 2000
    }
    
    // 1.4 Parse notrimeps option
    if "`notrimeps'" == "" {
        local trimeps_flag = 1
    }
    else {
        local trimeps_flag = 0
    }
    
    // ================================================================
    // Step 2: Compute original statistics (Task 5-6)
    // ================================================================
    
    quietly summarize _pte_eps0 if _pte_eps0_ind == 1
    local sigma_eps = r(sd)
    local mean_eps0 = r(mean)
    local N_eps0 = r(N)
    
    // Health check: mean should be approximately zero (OLS property)
    if abs(`mean_eps0') > 0.1 {
        if "`nodiagnose'" == "" {
            di as text ""
            di as text "{bf:Note}: Mean eps0 = " %9.6f `mean_eps0'
            di as text "       Expected value is approximately 0 (OLS residual property)."
            di as text ""
        }
    }
    
    // ================================================================
    // Step 3: Sample-size / variance diagnostics
    // Paper Section 6.3.3 and the official DOs continue with whatever
    // finite eps0 pool is available; small samples are a warning, not a
    // separate admissibility condition. The true hard failures are an
    // empty pool (checked above) or a negative variance. A singleton support
    // is a valid degenerate innovation law, so map Stata's missing sample-sd
    // on N==1 to sigma=0 instead of hard-failing.
    // ================================================================

    if `N_eps0' == 1 & missing(`sigma_eps') {
        local sigma_eps = 0
    }

    if missing(`sigma_eps') {
        di as error "[pte] Error: insufficient eps0 sample size to estimate variance"
        di as error "[pte]        Need at least two finite eps0 observations"
        `_pte_clear_eclass'
        exit 2002
    }

    if `sigma_eps' < 0 {
        di as error "[pte] Error: eps0 variance cannot be negative"
        `_pte_clear_eclass'
        exit 2003
    }

    if `N_eps0' < 30 {
        if "`nodiagnose'" == "" {
            di as text ""
            di as text "{bf:Warning}: Small eps0 sample size (N=`N_eps0')"
            di as text "          Percentile estimates may be unstable."
            di as text "          Continuing with the available shock pool, matching the paper and DOs."
            di as text ""
        }
    }
    else if `N_eps0' < 100 {
        if "`nodiagnose'" == "" {
            di as text "{bf:Note}: Moderate eps0 sample size (N=`N_eps0')"
        }
    }
    
    // ================================================================
    // Step 4: Compute percentiles and execute Winsorize (Task 7-11)
    // ================================================================
    
    tempvar _pte_eps0_work
    quietly gen double `_pte_eps0_work' = _pte_eps0 if _pte_eps0_ind == 1
    
    // Initialize locals for percentiles
    local p1 = .
    local p99 = .
    local _trim_method ""
    
    if `trimeps_flag' == 1 {
        // 4.1 Compute percentiles P1, P99
        quietly _pctile _pte_eps0 if _pte_eps0_ind == 1, p(1 99)
        local p1 = r(r1)
        local p99 = r(r2)
        
        // 4.2 Check winsor2 availability
        capture which winsor2
        local _winsor2_available = (_rc == 0)
        
        // 4.3 Execute trimming
        if `_winsor2_available' == 1 {
            // Method 1: winsor2 trim (matches replication code form)
            // Note: use manual method for reliability across winsor2 versions
            // winsor2 with if + trim + replace can behave inconsistently
            // Fall through to manual method for deterministic behavior
            local _winsor2_available = 0
        }
        
        if `_winsor2_available' == 1 {
            // winsor2 path (currently disabled, see note above)
            quietly winsor2 `_pte_eps0_work', ///
                cuts(1 99) trim replace
            local _trim_method "winsor2"
        }
        else {
            // Manual trimming (preferred: deterministic behavior)
            // Equivalent to: winsor2 eps0, cuts(1 99) trim replace,
            // but the raw eps0 pool must remain available for ATT resampling.
            quietly replace `_pte_eps0_work' = . ///
                if `_pte_eps0_work' < `p1' | `_pte_eps0_work' > `p99'
            local _trim_method "manual"
        }
        
        // 4.4 Compute trimmed statistics
        quietly summarize `_pte_eps0_work'
        local sigma_eps_trim = r(sd)
        local N_eps0_trim = r(N)
        
        // 4.5 Post-trim validation
        if `N_eps0_trim' == 0 {
            di as error "[pte] Error: no observations remain after trimming"
            `_pte_clear_eclass'
            exit 2002
        }

        if `N_eps0_trim' == 1 & missing(`sigma_eps_trim') {
            local sigma_eps_trim = 0
        }

        if missing(`sigma_eps_trim') {
            di as error "[pte] Error: insufficient trimmed eps0 sample size to estimate variance"
            di as error "[pte]        Need at least two finite trimmed eps0 observations"
            `_pte_clear_eclass'
            exit 2002
        }

        if `sigma_eps_trim' < 0 {
            di as error "[pte] Error: trimmed eps0 variance cannot be negative"
            `_pte_clear_eclass'
            exit 2003
        }

        // Trimming proportion check
        local trim_pct = (`N_eps0' - `N_eps0_trim') / `N_eps0' * 100
        if `trim_pct' > 5 {
            if "`nodiagnose'" == "" {
                di as text "{bf:Note}: Trimming removed " ///
                    %4.1f `trim_pct' "% of observations (expected ~2%)."
            }
        }
        
        // Sanity check: trimmed sd should be smaller
        if `sigma_eps_trim' > `sigma_eps' * 1.01 {
            if "`nodiagnose'" == "" {
                di as text "{bf:Warning}: Trimmed std dev > raw std dev. Unusual."
            }
        }
    }
    else {
        // notrimeps path: skip Winsorize
        local sigma_eps_trim = `sigma_eps'
        local N_eps0_trim = `N_eps0'
        local _trim_method "none"
        
        if "`nodiagnose'" == "" {
            di as text ""
            di as text "{bf:Warning}: Winsorize disabled (notrimeps option)"
            di as text "          This is NOT recommended per paper Section 6.3.3."
            di as text "          The TT estimate may be sensitive to outliers."
            di as text ""
        }
    }

    // ================================================================
    // Step 5: Compute higher moments (Task 12)
    // ================================================================
    
    // Compute skewness and kurtosis for normality assessment
    quietly summarize `_pte_eps0_work', detail
    local eps0_skewness = r(skewness)
    local eps0_kurtosis = r(kurtosis)
    
    // Normality warnings based on skewness/kurtosis
    if "`nodiagnose'" == "" {
        if abs(`eps0_skewness') >= 2 {
            di as text "{bf:Warning}: Highly skewed eps0 distribution"
            di as text "          Skewness = " %6.3f `eps0_skewness' " (|skew| >= 2)"
            di as text "          Normal approximation may be poor."
        }
        else if abs(`eps0_skewness') >= 1 {
            di as text "{bf:Note}: Moderate skewness in eps0 distribution"
            di as text "       Skewness = " %6.3f `eps0_skewness'
        }
        
        // Kurtosis check (normal = 3)
        if abs(`eps0_kurtosis' - 3) >= 3 {
            di as text "{bf:Warning}: Heavy/light tails in eps0 distribution"
            di as text "          Kurtosis = " %6.3f `eps0_kurtosis' " (normal = 3)"
        }
    }
    
    // ================================================================
    // Step 5b: K-S test for Assumption 4.3 (Task 91, PT-003)
    // Paper Appendix E.3, Table E.3
    // Tests H0: eps0 distribution is identical for treated and control
    // ================================================================
    
    local ks_D = .
    local ks_p = .
    local ks_p_exact = .
    local ks_n_treat = 0
    local ks_n_ctrl = 0
    local ks_n_treat_raw = 0
    local ks_n_ctrl_raw = 0
    local ks_result ""
    
    if "`kstest'" != "" {
        // Determine treatment variable
        local treat_var "`treatment'"
        local ks_group_var ""
        local ks_group_source ""
        local ks_has_treatyear = 0
        local has_trusted_bridge = 0
        local _ks_fallback_current = 0
        local _ks_used_raw_group = 0
        if inlist("`e(cmd)'", "_pte_eps0_sample", "_pte_omega", "_pte_winsorize", "pte") {
            local has_trusted_bridge = 1
        }
        if "`treat_var'" != "" {
            capture confirm variable `treat_var', exact
            if _rc != 0 {
                di as error "[pte] Error: treatment variable '`treat_var'' not found"
                `_pte_clear_eclass'
                exit 111
            }
            capture confirm numeric variable `treat_var'
            if _rc != 0 {
                di as error "[pte] Error: treatment variable '`treat_var'' must be numeric"
                `_pte_clear_eclass'
                exit 111
            }
            if `_pte_has_explicit_treatment' {
                // The K-S contract is defined on the live innovation support.
                // Sample-out codes must not veto a valid treated/control split.
                capture assert inlist(`treat_var', 0, 1) if !missing(`_pte_eps0_work')
                if _rc != 0 {
                    di as error "[pte] Error: treatment variable '`treat_var'' must be binary (0/1)"
                    di as error "[pte]        K-S grouping compares treated vs control units"
                    `_pte_clear_eclass'
                    exit 450
                }
            }
        }
        // _pte_eps0_sample already materializes the eventual-treatment
        // cohort identity. Keep that metadata available for K-S grouping,
        // but do not silently override an explicit static grouping variable.
        capture confirm variable _pte_treat_year, exact
        if _rc == 0 {
            capture confirm numeric variable _pte_treat_year
            if _rc == 0 {
                local ks_has_treatyear = 1
            }
        }
        if "`treat_var'" == "" & `ks_has_treatyear' {
            tempvar _pte_ks_group_from_year
            quietly gen byte `_pte_ks_group_from_year' = ///
                !missing(_pte_treat_year) if !missing(`_pte_eps0_work')
            local ks_group_var "`_pte_ks_group_from_year'"
            local ks_group_source "_pte_treat_year"
        }
        if "`treat_var'" == "" & "`ks_group_var'" == "" & `has_trusted_bridge' == 1 {
            // Reuse the live treatment state before falling back to
            // legacy helper names. The K-S diagnostic must compare the same
            // treated/control partition that generated the current eps0 pool.
            local treat_var `"`e(treatment)'"'
            if "`treat_var'" != "" {
                capture confirm variable `treat_var', exact
                if _rc != 0 {
                    local treat_var ""
                }
                else {
                    capture confirm numeric variable `treat_var'
                    if _rc != 0 {
                        local treat_var ""
                    }
                }
            }
        }
        if "`treat_var'" == "" & "`ks_group_var'" == "" {
            // Try to find treat variable in data
            capture confirm variable treat, exact
            if _rc == 0 {
                local treat_var "treat"
            }
            else {
                capture confirm variable treat_post, exact
                if _rc == 0 {
                    // Need ever-treated indicator, not treat_post
                    // treat_post = treat * post, we need treat (ever-treated)
                    local treat_var "treat_post"
                    local _ks_fallback_current = 1
                }
            }
        }
        
        if "`ks_group_var'" == "" & "`treat_var'" != "" {
            // Appendix E.3 compares treated vs control units in the
            // pre-treatment eps0 sample, so the grouping must be based on the
            // firm-level ever-treated status rather than the current-period D_t.
            capture _xt, trequired
            if _rc == 0 {
                local _ks_panelvar = r(ivar)
                tempvar _pte_ks_min _pte_ks_max _pte_ks_group
                local _ks_explicit_dynamic_full = 0
                local _ks_has_fullpath_group = 0
                if `_pte_has_explicit_treatment' {
                    tempvar _pte_ks_min_all _pte_ks_max_all _pte_ks_group_all
                    quietly bysort `_ks_panelvar': egen double `_pte_ks_min_all' = ///
                        min(cond(!missing(`treat_var'), `treat_var', .))
                    quietly bysort `_ks_panelvar': egen double `_pte_ks_max_all' = ///
                        max(cond(!missing(`treat_var'), `treat_var', .))
                    quietly bysort `_ks_panelvar': egen byte `_pte_ks_group_all' = ///
                        max(cond(!missing(`treat_var'), `treat_var', .))
                    quietly count if !missing(`_pte_eps0_work') & ///
                        `_pte_ks_min_all' != `_pte_ks_max_all'
                    if r(N) > 0 {
                        local _ks_explicit_dynamic_full = 1
                        local _ks_has_fullpath_group = 1
                    }
                }
                quietly bysort `_ks_panelvar': egen double `_pte_ks_min' = ///
                    min(cond(!missing(`_pte_eps0_work'), `treat_var', .))
                quietly bysort `_ks_panelvar': egen double `_pte_ks_max' = ///
                    max(cond(!missing(`_pte_eps0_work'), `treat_var', .))
                quietly count if !missing(`_pte_eps0_work') & `_pte_ks_min' != `_pte_ks_max'
                if r(N) > 0 & `ks_has_treatyear' {
                    tempvar _pte_ks_group_from_year
                    quietly gen byte `_pte_ks_group_from_year' = ///
                        !missing(_pte_treat_year) if !missing(`_pte_eps0_work')
                    local ks_group_var "`_pte_ks_group_from_year'"
                    local ks_group_source "_pte_treat_year"
                }
                else {
                    quietly bysort `_ks_panelvar': egen byte `_pte_ks_group' = ///
                        max(cond(!missing(`_pte_eps0_work'), `treat_var', .))
                    if `_ks_explicit_dynamic_full' & !`ks_has_treatyear' & `_ks_has_fullpath_group' {
                        local ks_group_var "`_pte_ks_group_all'"
                        local ks_group_source "`treat_var'"
                    }
                    else {
                    local _ks_use_treatyear = 0
                    // Respect an explicit static treatment() grouping when it
                    // still splits the live support. But if the explicit
                    // grouping collapses to one side on the untreated support
                    // while _pte_treat_year still identifies eventual-treated
                    // donors, fall back to _pte_treat_year so Appendix E.3
                    // keeps comparing treated-vs-control firms rather than
                    // current D_t on a pre-treatment-only slice.
                    if `ks_has_treatyear' {
                        quietly count if !missing(`_pte_eps0_work') & `_pte_ks_group' == 1
                        local _ks_explicit_treat = r(N)
                        quietly count if !missing(`_pte_eps0_work') & `_pte_ks_group' == 0
                        local _ks_explicit_ctrl = r(N)
                        quietly count if !missing(`_pte_eps0_work') & !missing(_pte_treat_year)
                        local _ks_treatyear_treat = r(N)
                        quietly count if !missing(`_pte_eps0_work') & missing(_pte_treat_year)
                        local _ks_treatyear_ctrl = r(N)
                        if (`_ks_explicit_treat' == 0 & `_ks_treatyear_treat' > 0) | ///
                           (`_ks_explicit_ctrl' == 0 & `_ks_treatyear_ctrl' > 0) {
                            local _ks_use_treatyear = 1
                        }
                    }
                    if `_ks_use_treatyear' {
                        tempvar _pte_ks_group_from_year
                        quietly gen byte `_pte_ks_group_from_year' = ///
                            !missing(_pte_treat_year) if !missing(`_pte_eps0_work')
                        local ks_group_var "`_pte_ks_group_from_year'"
                        local ks_group_source "_pte_treat_year"
                    }
                    else {
                        local ks_group_var "`_pte_ks_group'"
                        local ks_group_source "`treat_var'"
                    }
                    }
                }
            }
            else if `_ks_fallback_current' == 0 {
                local ks_group_var "`treat_var'"
                local _ks_used_raw_group = 1
                local ks_group_source "`treat_var'"
            }
        }

        if "`ks_group_var'" != "" {
            // Count treated and control on the effective K-S support.
            // When trimming is active, this must use the already-trimmed
            // `_pte_eps0_work` sample so Appendix E-style K-S diagnostics
            // align with the same trimmed innovation pool used elsewhere.
            quietly count if _pte_eps0_ind == 1 & `ks_group_var' == 1
            local ks_n_treat_raw = r(N)
            quietly count if _pte_eps0_ind == 1 & `ks_group_var' == 0
            local ks_n_ctrl_raw = r(N)

            quietly count if !missing(`_pte_eps0_work') & `ks_group_var' == 1
            local ks_n_treat = r(N)
            quietly count if !missing(`_pte_eps0_work') & `ks_group_var' == 0
            local ks_n_ctrl = r(N)
            
            if `_ks_used_raw_group' == 1 & `ks_n_treat_raw' == 0 {
                quietly count if `treat_var' == 1
                if r(N) > 0 {
                    local ks_group_var ""
                    local ks_n_treat = 0
                    local ks_n_ctrl = 0
                }
            }
            
            if "`ks_group_var'" == "" {
                local ks_result "No treatment var"
                if "`nodiagnose'" == "" {
                    di as text "{bf:Note}: K-S test skipped: no treatment variable found"
                    di as text "       Specify treatment() option or ensure 'treat' variable exists"
                }
            }
            else if `ks_n_treat' >= 5 & `ks_n_ctrl' >= 5 {
                // Run two-sample K-S test
                quietly ksmirnov `_pte_eps0_work' if !missing(`_pte_eps0_work'), by(`ks_group_var')
                local ks_D = r(D)
                local ks_p = r(p_cor)
                local ks_p_exact = r(p)
                
                if `ks_p' > 0.05 {
                    local ks_result "Cannot reject H0"
                }
                else {
                    local ks_result "Reject H0"
                }
            }
            else {
                local ks_result "Insufficient obs"
                if "`nodiagnose'" == "" {
                    di as text "{bf:Note}: K-S test skipped: insufficient obs"
                    di as text "       Treated N=`ks_n_treat', Control N=`ks_n_ctrl' (need >= 5 each)"
                    if "`ks_group_source'" == "_pte_treat_year" {
                        di as text "       Grouping source: eventual-treated cohorts from _pte_treat_year"
                    }
                }
            }
        }
        else {
            local ks_result "No treatment var"
            if "`nodiagnose'" == "" {
                di as text "{bf:Note}: K-S test skipped: no treatment variable found"
                di as text "       Specify treatment() option or ensure 'treat' variable exists"
            }
        }
    }
    
    // ================================================================
    // Step 6: Store e() return values (Task 13)
    // ================================================================
    
    tempvar touse
    quietly gen byte `touse' = !missing(`_pte_eps0_work')

    // Clear any previous ereturn
    ereturn clear
    ereturn post, esample(`touse') obs(`N_eps0_trim')
    
    // Store scalars
    ereturn scalar sigma_eps = `sigma_eps'
    ereturn scalar sigma_eps_trim = `sigma_eps_trim'
    ereturn scalar N_eps0 = `N_eps0'
    ereturn scalar N_eps0_trim = `N_eps0_trim'
    ereturn scalar eps0_p1 = `p1'
    ereturn scalar eps0_p99 = `p99'
    ereturn scalar eps0_skewness = `eps0_skewness'
    ereturn scalar eps0_kurtosis = `eps0_kurtosis'
    ereturn scalar trimeps = `trimeps_flag'
    
    // K-S test results (if kstest option was specified)
    if "`kstest'" != "" {
        ereturn scalar ks_D = `ks_D'
        ereturn scalar ks_p = `ks_p'
        ereturn scalar ks_p_exact = `ks_p_exact'
        ereturn scalar ks_n_treat = `ks_n_treat'
        ereturn scalar ks_n_ctrl = `ks_n_ctrl'
        ereturn local ks_result "`ks_result'"
    }
    
    // Store macros
    ereturn local eps0_dist "normal"
    ereturn local trim_method "`_trim_method'"
    ereturn local cmd "_pte_winsorize"
    ereturn local title "PTE eps0 distribution estimation"
    
    if `has_evo_state' {
        ereturn scalar omegapoly = `evo_omegapoly'
        ereturn scalar rho0 = `evo_rho0'
        ereturn scalar rho1 = `evo_rho1'
        if `evo_omegapoly' >= 2 {
            ereturn scalar rho2 = `evo_rho2'
        }
        if `evo_omegapoly' >= 3 {
            ereturn scalar rho3 = `evo_rho3'
        }
        if `evo_omegapoly' >= 4 {
            ereturn scalar rho4 = `evo_rho4'
        }
        if `evo_has_treated_state' {
            ereturn scalar gamma1 = `evo_gamma1'
            if `evo_omegapoly' >= 2 {
                ereturn scalar gamma2 = `evo_gamma2'
            }
            if `evo_omegapoly' >= 3 {
                ereturn scalar gamma3 = `evo_gamma3'
            }
            if `evo_omegapoly' >= 4 {
                ereturn scalar gamma4 = `evo_gamma4'
            }
            ereturn scalar delta = `evo_delta'
        }
        if `evo_has_N_lag_untreated' {
            ereturn scalar N_lag_untreated = `evo_N_lag_untreated'
        }
        if `evo_has_N_lag_treated' {
            ereturn scalar N_lag_treated = `evo_N_lag_treated'
        }
        if `evo_has_lag_supported' {
            ereturn scalar lag_treated_supported = `evo_lag_supported'
        }
        if `evo_has_eps0window' {
            ereturn scalar eps0window = `evo_eps0window'
        }
        capture ereturn scalar N_evo = `evo_N_evo'
        if !missing(`evo_r2') {
            ereturn scalar r2 = `evo_r2'
            ereturn scalar r2_evo = `evo_r2'
        }
        if !missing(`evo_rmse') {
            ereturn scalar rmse = `evo_rmse'
            ereturn scalar rmse_evo = `evo_rmse'
        }
        ereturn matrix rho_0 = `_pte_win_rho_0'
        if `evo_has_treated_state' {
            capture ereturn matrix rho_1 = `_pte_win_rho_1'
        }
        local pte_treatsig ""
        if `"`evo_idvar'"' != "" & `"`evo_timevar'"' != "" & `"`evo_treatment'"' != "" {
            capture quietly _pte_treatment_signature, ///
                panelvar(`evo_idvar') timevar(`evo_timevar') treatment(`evo_treatment')
            if _rc == 0 {
                local pte_treatsig `"`r(signature)'"'
            }
        }
        ereturn local treatment = "`evo_treatment'"
        ereturn local treatsig `"`pte_treatsig'"'
        ereturn local pfunc = "`evo_pfunc'"
        ereturn local prodfunc = "`evo_prodfunc'"
        if `"`evo_idvar'"' != "" {
            ereturn local id = "`evo_idvar'"
            ereturn local idvar = "`evo_idvar'"
        }
        if `"`evo_timevar'"' != "" {
            ereturn local time = "`evo_timevar'"
            ereturn local timevar = "`evo_timevar'"
        }
        if `evo_has_xtdelta' {
            ereturn scalar xtdelta = `evo_xtdelta'
        }
    }
    
    // ================================================================
    // Step 7: Diagnostic output (Task 14)
    // ================================================================
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "eps0 Distribution Estimation"
        di as text "{hline 60}"
        di as text ""
        di as text "  Original observations:    " %9.0f `N_eps0'
        di as text "  Trimmed observations:     " %9.0f `N_eps0_trim'
        di as text ""
        di as text "  Std. dev. (raw):          " %12.6f `sigma_eps'
        di as text "  Std. dev. (trimmed):      " %12.6f `sigma_eps_trim' "  [used by ATT]"
        di as text ""
        if `trimeps_flag' == 1 {
            di as text "  Winsorize:                Enabled (1%-99% trim)"
            di as text "  Trim method:              `_trim_method'"
            di as text "  P1 cutoff:                " %12.6f `p1'
            di as text "  P99 cutoff:               " %12.6f `p99'
        }
        else {
            di as text "  Winsorize:                Disabled (notrimeps)"
        }
        di as text ""
        di as text "  Distribution assumption:  Normal N(0, sigma^2)"
        di as text "  Skewness:                 " %9.4f `eps0_skewness'
        di as text "  Kurtosis:                 " %9.4f `eps0_kurtosis'
        di as text "{hline 60}"
        di as text ""
        
        // K-S test output (Assumption 4.3 validation)
        if "`kstest'" != "" & "`ks_result'" != "No treatment var" {
            di as text "{hline 60}"
            di as text "Assumption 4.3 Validation (K-S Test)"
            di as text "{hline 60}"
            di as text ""
            di as text "  Test: eps0 distribution comparison"
            di as text "        (treated vs control, pre-treatment period)"
            di as text "  H0:   Distributions are identical"
            di as text ""
            di as text "  Treated N:                " %9.0f `ks_n_treat'
            di as text "  Control N:                " %9.0f `ks_n_ctrl'
            if `ks_D' != . {
                di as text "  K-S statistic (D):        " %12.4f `ks_D'
                di as text "  p-value (corrected):      " %12.4f `ks_p'
                di as text "  p-value (exact):          " %12.4f `ks_p_exact'
                di as text ""
                if `ks_p' > 0.05 {
                    di as result "  Conclusion: Cannot reject H0 (p > 0.05)"
                }
                else {
                    di as text "  {bf:Conclusion: Reject H0 (p <= 0.05)}"
                    di as text "  {bf:Warning}: Assumption 4.3 may not hold"
                }
            }
            else {
                di as text "  Result: `ks_result'"
            }
            di as text "{hline 60}"
            di as text ""
        }
    }

    if `_pte_has_prev_est' {
        capture estimates drop `_pte_prev_est'
        local _pte_has_prev_est = 0
    }

end
