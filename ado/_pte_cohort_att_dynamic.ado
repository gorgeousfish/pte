*! _pte_cohort_att_dynamic.ado
*! Dynamic Cohort ATT Estimation
*! Formula: ATT_{g,l} = E[omega_{g+l} - omega^0_{g+l} | i in g]
*! where omega^0 is simulated via h_bar_0 recursion with MC paths

version 14.0
capture program drop _pte_cohort_att_dynamic
program define _pte_cohort_att_dynamic, rclass
    version 14.0
    
    syntax , cohort(integer) rho(name) omegapoly(integer) ///
            maxperiods(integer) sigmaeps(real) ///
            [nsim(integer -1) seed(integer 123456) ///
             panelvar(varname) timevar(varname) omega(varname) ///
             cohortvar(varname) nolog]
    
    // ================================================================
    // Task 1: Framework setup
    // ================================================================
    
    // Default parameter handling
    if "`panelvar'" == "" | "`timevar'" == "" {
        qui xtset
        if "`panelvar'" == "" local panelvar = r(panelvar)
        if "`timevar'" == "" local timevar = r(timevar)
    }
    if "`omega'" == "" local omega "_pte_omega"
    if "`cohortvar'" == "" {
        // Prefer the public/DO cohort anchor before any private scratch state.
        foreach _pte_cohort_candidate in treat_yr0 _pte_treat_year _pte_cohort_var treat_year {
            capture confirm variable `_pte_cohort_candidate', exact
            if _rc == 0 {
                local cohortvar "`_pte_cohort_candidate'"
                continue, break
            }
        }
        if "`cohortvar'" == "" local cohortvar "treat_year"
    }

    // Preserve the caller's panel declaration. Internal event-time recursion
    // needs temporary xtset/tsset changes, but those should not leak out.
    local pte_prev_panel ""
    local pte_prev_time ""
    local pte_had_xtset 0
    capture quietly xtset
    if _rc == 0 {
        local pte_had_xtset 1
        local pte_prev_panel "`r(panelvar)'"
        local pte_prev_time "`r(timevar)'"
        local pte_prev_delta "`r(tdelta)'"
    }
    local pte_restore_xtset `"capture quietly xtset, clear"'
    if `pte_had_xtset' {
        local pte_restore_xtset `"capture quietly xtset `pte_prev_panel' `pte_prev_time'"'
        if "`pte_prev_delta'" != "" {
            local pte_restore_xtset ///
                `"capture quietly xtset `pte_prev_panel' `pte_prev_time', delta(`pte_prev_delta')"'
        }
    }
    local pte_orig_rngstate `"`c(rngstate)'"'
    local pte_restore_rng `"capture set rngstate `pte_orig_rngstate'"'
    local pte_clip_tau = 50
    
    // ================================================================
    // Task 2: Parameter validation
    // ================================================================
    
    // Verify rho matrix exists
    cap confirm matrix `rho'
    if _rc != 0 {
        di as error "{bf:pte error E-3018}: Matrix `rho' not found"
        exit 3018
    }
    
    // Verify rho dimension: 1 x (omegapoly+1)
    local expected_cols = `omegapoly' + 1
    if colsof(`rho') != `expected_cols' {
        di as error "{bf:pte error E-3020}: rho dimension mismatch"
        di as error "  Expected: 1 x `expected_cols'"
        di as error "  Found: 1 x " colsof(`rho')
        exit 3020
    }
    
    // Proposition 4.3 permits a degenerate innovation law. When sigmaeps=0,
    // the counterfactual path collapses to deterministic recursion rather than
    // becoming an invalid input.
    if `sigmaeps' < 0 {
        di as error "{bf:pte error}: sigmaeps must be non-negative, got `sigmaeps'"
        exit 198
    }

    // Keep the cohort dynamic helper on the same omitted-nsim contract as
    // the main ATT/bootstrap chain: linear recursion uses one path, while
    // higher-order nonlinear laws default to 100 simulation paths.
    if `nsim' == -1 {
        if `omegapoly' == 1 {
            local nsim = 1
        }
        else {
            local nsim = 100
        }
    }

    if `nsim' < 1 {
        di as error "{bf:pte error}: nsim must be >= 1, got `nsim'"
        exit 198
    }
    
    // Proposition 4.1 / C.2 defines ATT_{g,l} for l >= 0.
    // maxperiods(0) is the instantaneous ATT_{g,0} case.
    if `maxperiods' < 0 {
        di as error "{bf:pte error}: maxperiods must be >= 0, got `maxperiods'"
        exit 198
    }
    
    // Verify omega variable exists
    cap confirm variable `omega'
    if _rc != 0 {
        di as error "{bf:pte error E-3018}: Variable `omega' not found"
        exit 3018
    }
    
    // ================================================================
    // Task 3: Panel setup
    // ================================================================
    
    local pte_work_delta_opt ""
    if `pte_had_xtset' & ///
        "`panelvar'" == "`pte_prev_panel'" & ///
        "`timevar'" == "`pte_prev_time'" & ///
        "`pte_prev_delta'" != "" {
        local pte_work_delta_opt ", delta(`pte_prev_delta')"
    }
    qui xtset `panelvar' `timevar'`pte_work_delta_opt'
    quietly xtset
    local pte_time_delta = real("`r(tdelta)'")
    if missing(`pte_time_delta') | `pte_time_delta' <= 0 {
        local pte_time_delta = 1
    }
    
    // ================================================================
    // Task 4: Compute lag variable BEFORE any filtering
    // CRITICAL: L.omega must be computed on full dataset
    // ================================================================
    
    tempvar omega_lag
    qui gen double `omega_lag' = L.`omega'
    
    // ================================================================
    // Task 5-6: Relative time and sample identification
    // ================================================================
    
    tempvar nt treat_flag
    qui gen double `nt' = (`timevar' - `cohort') / `pte_time_delta'
    qui replace `nt' = round(`nt') if ///
        !missing(`nt') & abs(`nt' - round(`nt')) <= 1e-10
    qui gen byte `treat_flag' = (`cohortvar' == `cohort')
    
    // Validate nt=-1 observations exist for treated cohort
    qui count if `treat_flag' == 1 & `nt' == -1
    local n_lag = r(N)
    if `n_lag' == 0 {
        `pte_restore_xtset'
        di as error "{bf:pte error E-3019}: No nt=-1 observations for cohort `cohort'"
        exit 3019
    }
    
    // Validate the Proposition C.2 anchor: observed omega at nt=-1.
    // A single pre-treatment period is sufficient; nt=-2 is not required.
    qui count if `treat_flag' == 1 & `nt' == -1 & !missing(`omega')
    if r(N) == 0 {
        `pte_restore_xtset'
        di as error "{bf:pte error E-3019}: No valid omega at nt=-1 for cohort `cohort'"
        exit 3019
    }
    
    // Count treated firms at nt=0
    qui count if `treat_flag' == 1 & `nt' == 0
    local n_treat = r(N)
    
    if `n_lag' < `n_treat' * 0.8 & "`nolog'" == "" {
        di as text "{bf:Warning W-3017}: Insufficient nt=-1 observations"
        di as text "  nt=-1: `n_lag', nt=0: `n_treat'"
    }
    
    // ================================================================
    // Task 6: Preserve data and filter to cohort sample
    // Keep treated firms with nt in [-1, maxperiods]
    // ================================================================
    
    preserve
    
    qui keep if `treat_flag' == 1 & `nt' >= -1 & `nt' <= `maxperiods'
    
    // Verify we have observations
    qui count
    if r(N) == 0 {
        di as error "{bf:pte error}: No observations after filtering for cohort `cohort'"
        restore
        `pte_restore_xtset'
        exit 2000
    }
    
    // Keep essential variables and rename tempvars for clarity
    qui gen int _dyn_nt = `nt'
    qui gen double _dyn_omega = `omega'
    qui gen double _dyn_omega_lag = `omega_lag'
    
    // Sort for tsset
    sort `panelvar' _dyn_nt
    qui xtset `panelvar' _dyn_nt
    
    // ================================================================
    // Task 7: Path expansion (expand nsim)
    // Each firm-period gets nsim simulation paths
    // ================================================================
    
    qui expand `nsim'
    qui bysort `panelvar' _dyn_nt: gen int _sim_id = _n
    qui egen long _firm_sim = group(`panelvar' _sim_id)
    
    // Re-tsset on expanded panel
    sort _firm_sim _dyn_nt
    qui tsset _firm_sim _dyn_nt
    
    if "`nolog'" == "" {
        qui count
        di as text "  Path expansion: " r(N) " obs (" `nsim' " paths per firm)"
    }
    
    // ================================================================
    // Task 8: Draw iid shocks from N(0, sigma_eps)
    // Match the main ATT chain's deterministic seed contract: assign draws in
    // event-time-major order, then restore the recursion panel sort.
    // ================================================================
    
    sort _dyn_nt _firm_sim
    set seed `seed'
    qui gen double _eps0_sim = rnormal(0, `sigmaeps')
    sort _firm_sim _dyn_nt
    qui tsset _firm_sim _dyn_nt
    
    // ================================================================
    // Task 9: Initialize counterfactual omega at nt=-1
    // Starting point: actual realized omega (shared across all paths)
    // ================================================================
    
    qui gen double _omega_0 = _dyn_omega if _dyn_nt == -1
    
    // ================================================================
    // Task 10: Recursive counterfactual simulation (nt=0..maxperiods)
    // Formula: omega^0_t = rho_0 + sum_{j=1}^{p} rho_j * (omega^0_{t-1})^j + eps^0_t
    // 
    // CRITICAL: Following reproduction code pattern exactly:
    //   - Polynomial powers must be computed at nt=t-1 BEFORE L. is used at nt=t
    //   - This is because Stata's L. operator works on the tsset time variable
    //   - omega_02 = omega_0^2 at nt=t-1, then L.omega_02 at nt=t
    // ================================================================
    
    // Generate polynomial power variables (for omegapoly >= 2)
    if `omegapoly' >= 2 {
        qui gen double _omega_02 = .
    }
    if `omegapoly' >= 3 {
        qui gen double _omega_03 = .
    }
    if `omegapoly' >= 4 {
        qui gen double _omega_04 = .
    }
    
    // nt=0: use the observed omega at nt=-1 as starting point
    // omega^0_0 = rho_0 + rho_1*omega_{-1} + rho_2*omega_{-1}^2 + ... + eps^0_0
    qui replace _omega_0 = `rho'[1,1] + `rho'[1,2] * L._dyn_omega ///
        if _dyn_nt == 0
    
    if `omegapoly' >= 2 {
        qui replace _omega_0 = _omega_0 + `rho'[1,3] * (L._dyn_omega)^2 ///
            if _dyn_nt == 0
    }
    if `omegapoly' >= 3 {
        qui replace _omega_0 = _omega_0 + `rho'[1,4] * (L._dyn_omega)^3 ///
            if _dyn_nt == 0
    }
    if `omegapoly' >= 4 {
        qui replace _omega_0 = _omega_0 + `rho'[1,5] * (L._dyn_omega)^4 ///
            if _dyn_nt == 0
    }
    
    // Match Appendix C.2 / industry DO timing: event time t consumes the
    // current untreated innovation eps_t^0. The nt=-1 row remains only as the
    // lagged omega anchor for h_bar_0 at treatment onset.
    qui replace _omega_0 = _omega_0 + _eps0_sim if _dyn_nt == 0
    quietly replace _omega_0 = `pte_clip_tau' if _dyn_nt == 0 & _omega_0 > `pte_clip_tau' & !missing(_omega_0)
    quietly replace _omega_0 = -`pte_clip_tau' if _dyn_nt == 0 & _omega_0 < -`pte_clip_tau' & !missing(_omega_0)
    
    // Recursive simulation for nt=1..maxperiods
    // Following reproduction code pattern: update power vars at nt=s-1, then use L. at nt=s
    if `maxperiods' >= 1 {
        forvalues s = 1/`maxperiods' {
            // Update polynomial powers at nt=s-1
            if `omegapoly' >= 2 {
                qui replace _omega_02 = _omega_0^2 if _dyn_nt == `s' - 1
            }
            if `omegapoly' >= 3 {
                qui replace _omega_03 = _omega_0^3 if _dyn_nt == `s' - 1
            }
            if `omegapoly' >= 4 {
                qui replace _omega_04 = _omega_0^4 if _dyn_nt == `s' - 1
            }
            
            // omega^0_s = rho_0 + rho_1*L.omega_0 + ... + eps0_sim
            if `omegapoly' == 1 {
                qui replace _omega_0 = `rho'[1,1] ///
                    + `rho'[1,2] * L._omega_0 ///
                    + _eps0_sim ///
                    if _dyn_nt == `s'
            }
            else if `omegapoly' == 2 {
                qui replace _omega_0 = `rho'[1,1] ///
                    + `rho'[1,2] * L._omega_0 ///
                    + `rho'[1,3] * L._omega_02 ///
                    + _eps0_sim ///
                    if _dyn_nt == `s'
            }
            else if `omegapoly' == 3 {
                qui replace _omega_0 = `rho'[1,1] ///
                    + `rho'[1,2] * L._omega_0 ///
                    + `rho'[1,3] * L._omega_02 ///
                    + `rho'[1,4] * L._omega_03 ///
                    + _eps0_sim ///
                    if _dyn_nt == `s'
            }
            else if `omegapoly' == 4 {
                qui replace _omega_0 = `rho'[1,1] ///
                    + `rho'[1,2] * L._omega_0 ///
                    + `rho'[1,3] * L._omega_02 ///
                    + `rho'[1,4] * L._omega_03 ///
                    + `rho'[1,5] * L._omega_04 ///
                    + _eps0_sim ///
                    if _dyn_nt == `s'
            }

            quietly replace _omega_0 = `pte_clip_tau' ///
                if _dyn_nt == `s' & _omega_0 > `pte_clip_tau' & !missing(_omega_0)
            quietly replace _omega_0 = -`pte_clip_tau' ///
                if _dyn_nt == `s' & _omega_0 < -`pte_clip_tau' & !missing(_omega_0)
        }
    }
    
    // ================================================================
    // Task 11: Recursion diagnostics
    // ================================================================
    
    qui count if missing(_omega_0) & _dyn_nt >= 0
    local n_miss_cf = r(N)
    if `n_miss_cf' > 0 & "`nolog'" == "" {
        di as text "{bf:Warning}: `n_miss_cf' missing counterfactual values"
    }
    
    // Numerical stability check
    qui summ _omega_0 if _dyn_nt == `maxperiods'
    if r(N) > 0 {
        if r(min) < -100 | r(max) > 100 {
            if "`nolog'" == "" {
                di as text "{bf:Warning}: Counterfactual values may be unstable"
                di as text "  Range: [" %8.2f r(min) ", " %8.2f r(max) "]"
            }
        }
    }
    
    // ================================================================
    // Task 12: Cross-path mean of counterfactual omega
    // For each (firm, nt), average omega_0 across nsim paths
    // ================================================================
    
    qui bysort `panelvar' _dyn_nt: egen double _omega_0_mean = mean(_omega_0)
    
    // ================================================================
    // Task 13: TT calculation
    // TT = omega - mean(omega^0) for treated firms at nt >= 1
    // Also compute TT at nt=0 for completeness
    // ================================================================
    
    qui gen double _TT = _dyn_omega - _omega_0_mean if _dyn_nt >= 0
    
    // ================================================================
    // Task 14: Deduplicate and compute ATT by period
    // Keep one observation per (firm, nt) since _omega_0_mean is identical across paths
    // ================================================================
    
    qui bysort `panelvar' _dyn_nt: keep if _sim_id == 1
    
    // Initialize result matrices
    tempname ATT_dynamic ATT_dynamic_se N_dynamic
    matrix `ATT_dynamic' = J(1, `maxperiods' + 1, .)
    matrix `ATT_dynamic_se' = J(1, `maxperiods' + 1, .)
    matrix `N_dynamic' = J(1, `maxperiods' + 1, .)
    
    // Compute ATT for each period (nt=0..maxperiods)
    forvalues t = 0/`maxperiods' {
        qui summ _TT if _dyn_nt == `t'
        local col = `t' + 1
        if r(N) > 0 {
            matrix `ATT_dynamic'[1, `col'] = r(mean)
            if r(N) > 1 {
                matrix `ATT_dynamic_se'[1, `col'] = r(sd) / sqrt(r(N))
            }
            else {
                matrix `ATT_dynamic_se'[1, `col'] = .
            }
            matrix `N_dynamic'[1, `col'] = r(N)
        }
    }
    
    // Set column names
    local colnames ""
    forvalues t = 0/`maxperiods' {
        local colnames "`colnames' ATT_`t'"
    }
    matrix colnames `ATT_dynamic' = `colnames'
    matrix colnames `ATT_dynamic_se' = `colnames'
    matrix colnames `N_dynamic' = `colnames'
    
    // ================================================================
    // Task 15-17: Store results, diagnostic output, and clean up
    // NOTE: Diagnostic output BEFORE return matrix (which moves the matrix)
    // ================================================================
    
    restore
    `pte_restore_xtset'
    `pte_restore_rng'
    
    // Diagnostic output (must be before return matrix)
    if "`nolog'" == "" {
        di as text ""
        di as text "Cohort `cohort' dynamic ATT (Prop C.2, nsim=`nsim'):"
        forvalues t = 0/`maxperiods' {
            local col = `t' + 1
            local _att_val = `ATT_dynamic'[1,`col']
            local _se_val = `ATT_dynamic_se'[1,`col']
            local _n_val = `N_dynamic'[1,`col']
            di as text "  ATT_{g,`t'} = " %9.6f `_att_val' ///
                       " (SE = " %7.5f `_se_val' ", N = " `_n_val' ")"
        }
    }
    
    // Return scalars for instantaneous ATT (nt=0)
    return scalar att_g_0 = `ATT_dynamic'[1, 1]
    return scalar att_g_0_se = `ATT_dynamic_se'[1, 1]
    return scalar n_g = `N_dynamic'[1, 1]
    return scalar cohort = `cohort'
    return scalar omegapoly = `omegapoly'
    return scalar maxperiods = `maxperiods'
    return scalar nsim = `nsim'
    return scalar seed = `seed'
    return scalar sigmaeps = `sigmaeps'
    return scalar n_missing_cf = `n_miss_cf'
    
    // Return matrices for dynamic ATT (moves the matrices)
    return matrix att_dynamic = `ATT_dynamic'
    return matrix att_dynamic_se = `ATT_dynamic_se'
    return matrix n_dynamic = `N_dynamic'
    
end
