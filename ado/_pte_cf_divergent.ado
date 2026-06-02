*! _pte_cf_divergent.ado
*! Dynamic counterfactual ATE estimation (Divergent Evolution)
*! Implements Proposition D.3: ATE_{s,ell}^{count}
*! Simulates omega^1 (h_1^+ -> h_bar_1) and omega^0 (h_bar_0)

version 14.0
capture program drop _pte_cf_divergent
program define _pte_cf_divergent, eclass
    version 14.0
    
    // ================================================================
    // Syntax parsing
    // ================================================================
    
    syntax , ///
        TARGETgroup(varname)     /// 0/1 variable identifying target group G
        REFERENCEtime(integer)   /// t0: first treatment period
        EXPANSIONtime(integer)   /// t0+s: planned expansion period
        [                        ///
        ATTperiods(integer 0)    /// max ell for dynamic ATE
        NSIM(integer 100)        /// number of simulation paths
        SEED(integer 123456)     /// inner seed for simulation
        BOOTstrap(integer 0)     /// number of bootstrap replications
        Level(integer 95)        /// confidence level
        KEEPfirm                 /// store firm-level effects
        QUIET                    /// suppress display
        DIAGnose                 /// run D.3/D.4 assumption tests
        ALPHA(real 0.05)         /// significance level for assumption tests
        OVERLAP_threshold(real 0.8) /// overlap threshold for D.4
        ]

    // The public seed() drives two internal Monte Carlo streams:
    // eps1 uses seed(), while eps0 uses seed() + 7654321 in the Mata helper.
    // Guard the entry domain so the reported seed contract maps to valid
    // integer seeds for both streams instead of relying on implicit wraparound.
    local _pte_cf_seed_offset = 7654321
    local _pte_cf_seed_max = 2147483647 - `_pte_cf_seed_offset'
    if `seed' < 1 {
        di as error "{bf:pte error}: seed() must be a positive integer"
        exit 198
    }
    if `seed' > `_pte_cf_seed_max' {
        di as error "{bf:pte error}: seed() must be <= `_pte_cf_seed_max'"
        di as error "  The divergent counterfactual path uses an internal eps0 seed offset of +`_pte_cf_seed_offset'."
        exit 198
    }

    capture _xt, trequired
    if _rc != 0 {
        di as error "{bf:pte error}: data must be xtset as panel"
        exit 459
    }
    local panelvar = r(ivar)
    local timevar = r(tvar)
    local t0 = `referencetime'
    local s_val = `expansiontime' - `referencetime'
    local _pte_exact_inst = (`attperiods' == 0 & `s_val' <= 0)
    if `attperiods' > 0 & `s_val' <= 0 {
        di as error "{bf:pte error}: attperiods()>0 requires expansiontime() > referencetime() on the divergent dynamic path"
        di as error "  Proposition D.2 identifies only the instantaneous object when s <= 0."
        di as error "  Use attperiods(0), or increase expansiontime() so that s > 0."
        exit 198
    }
    
    // ================================================================
    // Task 1: Verify h_1^+ existence
    // ================================================================
    
    // ================================================================
    // Optional: Run D.3/D.4 assumption tests before estimation
    // ================================================================
    
    local _pte_run_diag = ("`diagnose'" != "" & !`_pte_exact_inst')

    if `_pte_run_diag' {
        tempname _diag_h_plus _diag_rho_0 _diag_rho_1 _diag_gamma _diag_delta_scalar _diag_sigma_eps_scalar _diag_sigma_eps_trim_scalar _diag_omegapoly_scalar
        local _diag_has_h_plus = 0
        local _diag_has_rho_0 = 0
        local _diag_has_rho_1 = 0
        local _diag_has_gamma = 0
        local _diag_delta = .
        local _diag_sigma_eps = .
        local _diag_sigma_eps_trim = .
        local _diag_omegapoly_state = .

        capture confirm matrix e(h_plus)
        if !_rc {
            matrix `_diag_h_plus' = e(h_plus)
            local _diag_has_h_plus = 1
        }
        capture confirm matrix e(rho_0)
        if !_rc {
            matrix `_diag_rho_0' = e(rho_0)
            local _diag_has_rho_0 = 1
        }
        capture confirm matrix e(rho_1)
        if !_rc {
            matrix `_diag_rho_1' = e(rho_1)
            local _diag_has_rho_1 = 1
        }
        capture confirm matrix e(gamma)
        if !_rc {
            matrix `_diag_gamma' = e(gamma)
            local _diag_has_gamma = 1
        }
        capture scalar `_diag_delta_scalar' = e(delta)
        if !_rc local _diag_delta = scalar(`_diag_delta_scalar')
        capture scalar `_diag_sigma_eps_scalar' = e(sigma_eps)
        if !_rc local _diag_sigma_eps = scalar(`_diag_sigma_eps_scalar')
        capture scalar `_diag_sigma_eps_trim_scalar' = e(sigma_eps_trim)
        if !_rc local _diag_sigma_eps_trim = scalar(`_diag_sigma_eps_trim_scalar')
        capture scalar `_diag_omegapoly_scalar' = e(omegapoly)
        if !_rc local _diag_omegapoly_state = scalar(`_diag_omegapoly_scalar')
        local _diag_d3_pass = .
        local _diag_d4_pass = .
        local _diag_overlap_ok = .
        local _diag_d3_pval = .
        local _diag_d4_pval = .
        local _diag_overlap_ratio = .

        // Determine panel/time/treat variables from data context
        local _diag_panelvar "`panelvar'"
        local _diag_timevar "`timevar'"
        local _diag_treatvar "_pte_treat"
        capture confirm variable `_diag_treatvar', exact
        if _rc != 0 local _diag_treatvar "treated"
        local _diag_midvar "_pte_mid"
        capture confirm variable `_diag_midvar', exact
        if _rc != 0 local _diag_midvar "mid"

        local _diag_timing_opts ""
        capture confirm variable _pte_treat_year, exact
        if _rc == 0 {
            local _diag_timing_opts "cohortvar(_pte_treat_year)"
        }
        else {
            capture confirm variable treat_year, exact
            if _rc == 0 {
                local _diag_timing_opts "cohortvar(treat_year)"
            }
            else {
                capture confirm variable _pte_D, exact
                if _rc == 0 local _diag_timing_opts "statusvar(_pte_D)"
                else {
                    capture confirm variable D, exact
                    if _rc == 0 local _diag_timing_opts "statusvar(D)"
                }
            }
        }
        
        // Compute s from expansion - reference
        local _diag_s = `s_val'
        
        // Determine omegapoly from e() if available
        local _diag_omegapoly = e(omegapoly)
        if `_diag_omegapoly' == . local _diag_omegapoly = 3
        
        // Determine noreport from quiet option
        local _diag_noreport ""
        if "`quiet'" != "" local _diag_noreport "noreport"
        
        capture noisily _pte_cf_assumption_tests, ///
            t0(`referencetime') s(`_diag_s') ///
            targetvar(`targetgroup') ///
            omega(omega) ///
            omegapoly(`_diag_omegapoly') ///
            panelvar(`_diag_panelvar') timevar(`_diag_timevar') ///
            treatvar(`_diag_treatvar') midvar(`_diag_midvar') ///
            `_diag_timing_opts' ///
            alpha(`alpha') overlap_threshold(`overlap_threshold') ///
            `_diag_noreport'
        
        if _rc == 0 {
            // Store assumption test results for later retrieval
            local _diag_d3_pass = r(d3_pass)
            local _diag_d4_pass = r(d4_pass)
            local _diag_overlap_ok = r(overlap_ok)
            local _diag_d3_pval = r(assumption_d3_pval)
            local _diag_d4_pval = r(assumption_d4_pval)
            local _diag_overlap_ratio = r(overlap_ratio)
        }
        else {
            if "`quiet'" == "" {
                di as text "  Note: Assumption tests failed (rc=`=_rc'), continuing with estimation"
            }
        }

        ereturn clear
        if `_diag_has_h_plus' {
            ereturn matrix h_plus = `_diag_h_plus'
        }
        if `_diag_has_rho_0' {
            ereturn matrix rho_0 = `_diag_rho_0'
        }
        if `_diag_has_rho_1' {
            ereturn matrix rho_1 = `_diag_rho_1'
        }
        if `_diag_has_gamma' {
            ereturn matrix gamma = `_diag_gamma'
        }
        if !missing(`_diag_delta') {
            ereturn scalar delta = `_diag_delta'
        }
        if !missing(`_diag_sigma_eps') {
            ereturn scalar sigma_eps = `_diag_sigma_eps'
        }
        if !missing(`_diag_sigma_eps_trim') {
            ereturn scalar sigma_eps_trim = `_diag_sigma_eps_trim'
        }
        if !missing(`_diag_omegapoly_state') {
            ereturn scalar omegapoly = `_diag_omegapoly_state'
        }
    }
    
    // ================================================================
    // Task 1 (original): Verify h_1^+ existence
    // ================================================================
    
    capture confirm matrix e(h_plus)
    if _rc {
        di as error "{bf:pte error 3009}: Counterfactual with cfmethod(divergent) requires h_1^+ estimation"
        di as error "  Solution: Run pte ..., evolution(divergent) estimatetransition"
        exit 3009
    }
    tempname H_plus
    matrix `H_plus' = e(h_plus)
    
    // ================================================================
    // Task 2: Extract h_1^+ parameters
    // ================================================================
    
    local omegapoly = e(omegapoly)
    if `omegapoly' == . {
        local omegapoly = colsof(`H_plus') - 1
    }
    
    // Validate dimension
    if colsof(`H_plus') != `omegapoly' + 1 {
        di as error "{bf:pte error 3014}: h_plus dimension mismatch"
        exit 3014
    }
    
    forvalues j = 0/`omegapoly' {
        local h_plus_`j' = `H_plus'[1, `j'+1]
    }
    
    // ================================================================
    // Task 3: Extract rho_0 parameters (h_bar_0, only rho)
    // ================================================================
    
    capture confirm matrix e(rho_0)
    if _rc {
        di as error "{bf:pte error 3010}: Missing evolution parameters rho_0"
        exit 3010
    }
    tempname Rho_0
    matrix `Rho_0' = e(rho_0)
    
    if colsof(`Rho_0') != `omegapoly' + 1 {
        di as error "{bf:pte error 3014}: rho_0 dimension mismatch"
        exit 3014
    }
    
    forvalues j = 0/`omegapoly' {
        local rho_0_`j' = `Rho_0'[1, `j'+1]
    }
    
    // ================================================================
    // Task 4: Construct h_bar_1 parameters (rho + gamma/delta)
    // ================================================================
    
    // Get delta
    local delta_val = e(delta)
    if `delta_val' == . {
        local delta_val = 0
        if "`quiet'" == "" {
            di as text "  Note: e(delta) not found, using delta=0"
        }
    }
    
    // Construct the treated steady-state law h_bar_1 from the live
    // contract. Standard upstream workers publish e(rho_1) and gamma scalars,
    // but not necessarily a dedicated e(gamma) matrix.
    capture confirm matrix e(rho_1)
    if !_rc {
        tempname Rho_1
        matrix `Rho_1' = e(rho_1)
        if colsof(`Rho_1') != `omegapoly' + 1 {
            di as error "{bf:pte error 3014}: rho_1 dimension mismatch"
            exit 3014
        }
        forvalues j = 0/`omegapoly' {
            local rho_h1_`j' = `Rho_1'[1, `j' + 1]
        }
    }
    else {
        capture confirm matrix e(gamma)
        if !_rc {
            tempname Gamma
            matrix `Gamma' = e(gamma)
            local rho_h1_0 = `rho_0_0' + `delta_val'
            forvalues j = 1/`omegapoly' {
                local gamma_`j' = `Gamma'[1, `j']
                local rho_h1_`j' = `rho_0_`j'' + `gamma_`j''
            }
        }
        else {
            local has_gamma_scalars = 1
            forvalues j = 1/`omegapoly' {
                capture local gamma_scalar_`j' = e(gamma`j')
                if _rc != 0 {
                    local has_gamma_scalars = 0
                }
            }
            if `has_gamma_scalars' {
                local rho_h1_0 = `rho_0_0' + `delta_val'
                forvalues j = 1/`omegapoly' {
                    local rho_h1_`j' = `rho_0_`j'' + `gamma_scalar_`j''
                }
            }
            else {
                di as error "{bf:pte error 3010}: Missing treated evolution parameters rho_1 / gamma"
                exit 3010
            }
        }
    }
    
    // ================================================================
    // Task 5: Get shock standard deviations
    // ================================================================
    
    local sigma_eps0_raw = e(sigma_eps)
    // A zero untreated sigma is a valid degenerate innovation law. Only
    // missing or negative scales should block the divergent simulation.
    if missing(`sigma_eps0_raw') | `sigma_eps0_raw' < 0 {
        di as error "{bf:pte error 3015}: Missing or invalid sigma_eps from production function estimation"
        exit 3015
    }
    local sigma_eps0_trim = e(sigma_eps_trim)
    // A zero trimmed sigma is a valid degenerate innovation law. Only a
    // missing trimmed scale should fall back to the raw untreated sigma.
    if !missing(`sigma_eps0_trim') & `sigma_eps0_trim' < 0 {
        di as error "{bf:pte error 3015}: sigma_eps_trim cannot be negative"
        exit 3015
    }
    if missing(`sigma_eps0_trim') {
        local sigma_eps0_trim = `sigma_eps0_raw'
    }
    local sigma_eps0 = `sigma_eps0_trim'
    local target_year = `t0' + `s_val' - 1
    
    // ================================================================
    // Task 6-10: Estimate G_epsilon^1 distribution
    // ================================================================
    
    // Save current e() results
    tempname e_h_plus e_rho_0 e_gamma_save
    matrix `e_h_plus' = e(h_plus)
    matrix `e_rho_0' = e(rho_0)
    capture matrix `e_gamma_save' = e(gamma)
    local e_delta_save = e(delta)
    local e_sigma_eps_save = e(sigma_eps)
    local e_omegapoly_save = e(omegapoly)
    
    if !`_pte_exact_inst' {
        preserve

        // --- Task 6: G_eps1 sample selection ---
        // Condition 1: treated group
        // Reuse the package-standard flag when it already exists. Otherwise,
        // generate an isolated tempvar to avoid colliding with user/package data.
        tempvar _pte_treat_flag
        unab _pte_cf_allvars : _all
        local _pte_has_exact_treat : list posof "_pte_treat" in _pte_cf_allvars
        if `_pte_has_exact_treat' {
            local _pte_treat_flag "_pte_treat"
        }
        else {
            capture confirm variable treat
            if _rc {
                // Try D-based identification
                capture confirm variable D
                if _rc {
                    di as error "{bf:pte error 3016}: Neither treat nor D variable found"
                    restore
                    exit 3016
                }
                // Use D to identify treated firms
                qui gen byte `_pte_treat_flag' = (D == 1)
            }
            else {
                qui gen byte `_pte_treat_flag' = (treat == 1)
            }
        }
        
        // Keep treated firms; include t0-1 for lag computation
        keep if `_pte_treat_flag' == 1
        keep if `timevar' >= `t0' - 1 & `timevar' < `t0' + `s_val'
        
        // Need panel structure for lags
        capture confirm variable `panelvar'
        if !_rc {
            qui tsset `panelvar' `timevar'
        }
        
        // Compute lags BEFORE filtering (so lags are available)
        qui gen double _pte_omega_lag = L.omega
        
        // Condition 3: stable treatment state (D==1 & L.D==1)
        capture confirm variable D
        if !_rc {
            qui gen byte _pte_Dlag = L.D
            // Now restrict to target window [t0, t0+s) AND stable treatment
            keep if `timevar' >= `t0' & `timevar' < `t0' + `s_val'
            keep if D == 1 & _pte_Dlag == 1 & !missing(_pte_Dlag)
        }
        else {
            // No D variable: just restrict to target window
            keep if `timevar' >= `t0' & `timevar' < `t0' + `s_val'
        }
        
        // Condition 4: entry year constraint (if available)
        capture confirm variable entry_year
        if !_rc {
            keep if entry_year <= `t0'
        }
        
        // Drop obs with missing omega or lag
        drop if missing(_pte_omega_lag) | missing(omega)
        
        local n_eps1_raw = _N
        
        if `n_eps1_raw' == 0 {
            di as error "{bf:pte error 3017}: No observations for G_eps1 estimation"
            restore
            exit 3017
        }
        
        qui gen double _pte_h1_pred = `rho_h1_0'
        forvalues j = 1/`omegapoly' {
            qui replace _pte_h1_pred = _pte_h1_pred + `rho_h1_`j'' * (_pte_omega_lag^`j')
        }
        
        // --- Task 8: Compute eps1 residuals ---
        qui gen double _pte_eps1_raw = omega - _pte_h1_pred
        
        // --- Task 9: Winsorize eps1 ---
        capture which winsor2
        if _rc == 0 {
            qui winsor2 _pte_eps1_raw, cuts(1 99) replace
        }
        else {
            // Manual winsorize at 1-99%
            qui sum _pte_eps1_raw, detail
            local p1 = r(p1)
            local p99 = r(p99)
            qui replace _pte_eps1_raw = `p1' if _pte_eps1_raw < `p1'
            qui replace _pte_eps1_raw = `p99' if _pte_eps1_raw > `p99'
        }
        
        // --- Task 10: Estimate sigma_eps1 ---
        qui sum _pte_eps1_raw
        local sigma_eps1 = r(sd)
        local n_eps1_sample = r(N)
        
        restore
        
        // Sample size check
        if `n_eps1_sample' < 10 {
            di as error "{bf:pte error 3018}: G_eps1 sample size (`n_eps1_sample') too small (< 10)"
            exit 3018
        }
        if `n_eps1_sample' < 50 & "`quiet'" == "" {
            di as text "  Warning: G_eps1 sample size (`n_eps1_sample') < 50, estimates may be imprecise"
        }
    }
    else {
        local sigma_eps1 = 0
        local n_eps1_sample = 0
    }
    
    // ================================================================
    // Task 11-13: Target group processing
    // ================================================================
    
    // Validate time range
    qui sum `timevar'
    if `target_year' < r(min) | `target_year' > r(max) {
        di as error "{bf:pte error 3013}: Target period `target_year' out of data range"
        exit 3013
    }
    
    preserve
    
    // --- Task 11: Filter target group ---
    keep if `targetgroup' == 1 & `timevar' == `target_year'
    local n_target = _N
    
    if `n_target' == 0 {
        di as error "{bf:pte error 3012}: No observations in target group at year `target_year'"
        restore
        exit 3012
    }
    
    // Verify G subset of untreated
    capture confirm variable D
    if !_rc {
        qui count if D == 1
        if r(N) > 0 {
            di as error "{bf:pte error 3011}: Target group contains `r(N)' treated firms"
            restore
            exit 3011
        }
    }
    
    // --- Task 12: Get starting productivity ---
    // omega at t0+s-1 is the simulation starting point
    drop if missing(omega)
    local n_target = _N
    if `n_target' == 0 {
        di as error "{bf:pte error 3012}: No valid omega in target group"
        restore
        exit 3012
    }
    
    // ================================================================
    // Task 13-24: ATE aggregation
    // Proposition D.2 exact branch covers attperiods(0) with s<=0 and does
    // not require G_eps1. All other paths keep the D.3 simulation law.
    // ================================================================
    
    // --- Build rho_h1 Stata matrix for Mata ---
    tempname Rho_h1
    matrix `Rho_h1' = J(1, `omegapoly' + 1, .)
    forvalues j = 0/`omegapoly' {
        matrix `Rho_h1'[1, `j' + 1] = `rho_h1_`j''
    }
    
    // --- Prepare result matrices ---
    tempname ATE_count ATE_se
    
    if !`_pte_exact_inst' {
        // --- Call Mata for simulation and aggregation ---
        mata: _pte_cf_divergent_sim( ///
            "`H_plus'", "`Rho_h1'", "`Rho_0'", ///
            `sigma_eps1', `sigma_eps0', ///
            `attperiods', `nsim', `seed', ///
            "`ATE_count'", "`ATE_se'")
    }
    else {
        tempvar _pte_hplus_pred _pte_h0_pred _pte_cf_exact
        qui gen double `_pte_hplus_pred' = `H_plus'[1, 1]
        qui gen double `_pte_h0_pred' = `Rho_0'[1, 1]
        forvalues j = 1/`omegapoly' {
            if `j' == 1 {
                qui replace `_pte_hplus_pred' = `_pte_hplus_pred' + `H_plus'[1, 2] * omega
                qui replace `_pte_h0_pred' = `_pte_h0_pred' + `Rho_0'[1, 2] * omega
            }
            else {
                qui replace `_pte_hplus_pred' = `_pte_hplus_pred' + `H_plus'[1, `=`j' + 1'] * (omega^`j')
                qui replace `_pte_h0_pred' = `_pte_h0_pred' + `Rho_0'[1, `=`j' + 1'] * (omega^`j')
            }
        }
        qui gen double `_pte_cf_exact' = `_pte_hplus_pred' - `_pte_h0_pred'
        qui sum `_pte_cf_exact'
        local _pte_exact_ate = r(mean)
        local _pte_exact_se = cond(r(N) > 1, r(sd) / sqrt(r(N)), .)
        matrix `ATE_count' = (`_pte_exact_ate')
        matrix `ATE_se' = (`_pte_exact_se')
    }
    
    // --- Set column names on result matrices ---
    local colnames ""
    forvalues ell = 0/`attperiods' {
        local colnames "`colnames' ell_`ell'"
    }
    matrix colnames `ATE_count' = `colnames'
    matrix colnames `ATE_se' = `colnames'
    
    restore
    
    // ================================================================
    // Task 25A-25C: Bootstrap inference
    // ================================================================
    
    // Tempnames for bootstrap results (declared outside if-block)
    tempname ATE_boot ATE_boot_se ATE_boot_ci_lo ATE_boot_ci_hi
    local n_periods = `attperiods' + 1
    local did_bootstrap = 0
    
    if `bootstrap' > 0 {
        
        if "`quiet'" == "" {
            di as text ""
            di as text "Bootstrap inference: `bootstrap' replications"
        }
        
        matrix `ATE_boot' = J(`bootstrap', `n_periods', .)
        
        // --- Determine stratification variable ---
        // Need a firm-level ever-treated indicator for bsample strata
        tempvar boot_strata
        capture confirm variable treat
        if !_rc {
            qui gen byte `boot_strata' = treat
        }
        else {
            capture confirm variable D
            if !_rc {
                qui bys `panelvar': egen byte `boot_strata' = max(D)
            }
            else {
                di as error "{bf:pte error 3020}: Bootstrap requires treat or D variable for stratification"
                exit 3020
            }
        }
        
        // --- Bootstrap loop ---
        // Save original data to tempfile (avoid nested preserve — Stata
        // only supports one active preserve at a time, and the inner
        // G_eps1 and target-sim blocks each need their own preserve)
        tempfile _pte_boot_origdata
        qui save `_pte_boot_origdata'
        
        forvalues b = 1/`bootstrap' {
            if "`quiet'" == "" & mod(`b', 50) == 0 {
                di as text "  Bootstrap iteration `b'/`bootstrap'"
            }
            
            // Outer seed for resampling
            qui use `_pte_boot_origdata', clear
            qui set seed `b'
            qui bsample, strata(`boot_strata') cluster(`panelvar') idcluster(_pte_firm_b)
            
            if !`_pte_exact_inst' {
                // ---- Re-estimate sigma_eps0 from the resampled untreated
                // innovation support, then sigma_eps1 from the treated support.
                quietly _pte_cf_divergent_sigma0_support, ///
                    fallbackraw(`sigma_eps0_raw') fallbacktrim(`sigma_eps0_trim')
                local sigma_eps0_b = r(sigma_eps0)

                // ---- Re-estimate sigma_eps1 (Tasks 6-10 on resampled data) ----
                local sigma_eps1_b = `sigma_eps1'  // fallback to point estimate
                local eps1_ok = 0
                
                preserve
                
                // G_eps1 sample selection on resampled data
                local has_treat_var = 0
                capture confirm variable treat
                if !_rc {
                    qui gen byte _pte_treat_b = (treat == 1)
                    local has_treat_var = 1
                }
                else {
                    capture confirm variable D
                    if !_rc {
                        qui gen byte _pte_treat_b = (D == 1)
                        local has_treat_var = 1
                    }
                }
                
                if `has_treat_var' {
                    qui keep if _pte_treat_b == 1
                    qui keep if `timevar' >= `t0' - 1 & `timevar' < `t0' + `s_val'
                    
                    // Need lags: tsset with bootstrap firm ID
                    capture qui tsset _pte_firm_b `timevar'
                    if !_rc {
                        qui gen double _pte_omega_lag_b = L.omega
                        
                        // Stable treatment state filter
                        capture confirm variable D
                        if !_rc {
                            qui gen byte _pte_Dlag_b = L.D
                            qui keep if `timevar' >= `t0' & `timevar' < `t0' + `s_val'
                            qui keep if D == 1 & _pte_Dlag_b == 1 & !missing(_pte_Dlag_b)
                        }
                        else {
                            qui keep if `timevar' >= `t0' & `timevar' < `t0' + `s_val'
                        }
                        
                        // Entry year constraint
                        capture confirm variable entry_year
                        if !_rc {
                            qui keep if entry_year <= `t0'
                        }
                        
                        // Drop missing
                        qui drop if missing(_pte_omega_lag_b) | missing(omega)
                        
                        if _N >= 10 {
                            // Compute h_bar_1 prediction
                            qui gen double _pte_h1_pred_b = `rho_h1_0'
                            forvalues j = 1/`omegapoly' {
                                qui replace _pte_h1_pred_b = _pte_h1_pred_b + `rho_h1_`j'' * (_pte_omega_lag_b^`j')
                            }
                            
                            // Compute eps1 residuals
                            qui gen double _pte_eps1_b = omega - _pte_h1_pred_b
                            
                            // Winsorize
                            capture which winsor2
                            if _rc == 0 {
                                qui winsor2 _pte_eps1_b, cuts(1 99) replace
                            }
                            else {
                                qui sum _pte_eps1_b, detail
                                local p1_b = r(p1)
                                local p99_b = r(p99)
                                qui replace _pte_eps1_b = `p1_b' if _pte_eps1_b < `p1_b'
                                qui replace _pte_eps1_b = `p99_b' if _pte_eps1_b > `p99_b'
                            }
                            
                            // Estimate sigma_eps1
                            qui sum _pte_eps1_b
                            local sigma_eps1_b = r(sd)
                            local eps1_ok = 1
                        }
                    }
                }
                // Fallback: sigma_eps1_b stays at point estimate value
                
                restore  // back to resampled data
            }
            
            // ---- Re-filter target group and simulate (Tasks 11-24) ----
            preserve
            
            local target_year_b = `t0' + `s_val' - 1
            qui keep if `targetgroup' == 1 & `timevar' == `target_year_b'
            qui drop if missing(omega)
            local n_target_b = _N
            
            if `n_target_b' > 0 {
                if !`_pte_exact_inst' {
                    // Build parameter matrices for Mata
                    tempname H_plus_b Rho_h1_b Rho_0_b ATE_b SE_b
                    matrix `H_plus_b' = `e_h_plus'
                    matrix `Rho_0_b' = `e_rho_0'
                    matrix `Rho_h1_b' = J(1, `omegapoly' + 1, .)
                    forvalues j = 0/`omegapoly' {
                        matrix `Rho_h1_b'[1, `j' + 1] = `rho_h1_`j''
                    }
                    
                    // Call Mata simulation with INNER seed (fixed)
                    mata: _pte_cf_divergent_sim( ///
                        "`H_plus_b'", "`Rho_h1_b'", "`Rho_0_b'", ///
                        `sigma_eps1_b', `sigma_eps0_b', ///
                        `attperiods', `nsim', `seed', ///
                        "`ATE_b'", "`SE_b'")
                    
                    // Store bootstrap ATE row
                    forvalues j = 1/`n_periods' {
                        matrix `ATE_boot'[`b', `j'] = `ATE_b'[1, `j']
                    }
                }
                else {
                    tempvar _pte_hplus_pred_b _pte_h0_pred_b _pte_cf_exact_b
                    qui gen double `_pte_hplus_pred_b' = `e_h_plus'[1, 1]
                    qui gen double `_pte_h0_pred_b' = `e_rho_0'[1, 1]
                    forvalues j = 1/`omegapoly' {
                        if `j' == 1 {
                            qui replace `_pte_hplus_pred_b' = `_pte_hplus_pred_b' + `e_h_plus'[1, 2] * omega
                            qui replace `_pte_h0_pred_b' = `_pte_h0_pred_b' + `e_rho_0'[1, 2] * omega
                        }
                        else {
                            qui replace `_pte_hplus_pred_b' = `_pte_hplus_pred_b' + `e_h_plus'[1, `=`j' + 1'] * (omega^`j')
                            qui replace `_pte_h0_pred_b' = `_pte_h0_pred_b' + `e_rho_0'[1, `=`j' + 1'] * (omega^`j')
                        }
                    }
                    qui gen double `_pte_cf_exact_b' = `_pte_hplus_pred_b' - `_pte_h0_pred_b'
                    qui sum `_pte_cf_exact_b', meanonly
                    matrix `ATE_boot'[`b', 1] = r(mean)
                }
            }
            // else: row stays as missing
            
            restore  // back to resampled data (from target-sim preserve)
        }
        
        // Restore original data after bootstrap loop
        qui use `_pte_boot_origdata', clear
        
        // --- Task 25B: Compute bootstrap SE ---
        // --- Task 25C: Compute bootstrap CI ---
        local did_bootstrap = 1
        local boot_alpha = (100 - `level') / 100
        
        mata: _pte_cf_divergent_boot_agg( ///
            "`ATE_boot'", "`ATE_boot_se'", ///
            "`ATE_boot_ci_lo'", "`ATE_boot_ci_hi'")
        
        // Set column names on bootstrap result matrices
        matrix colnames `ATE_boot_se' = `colnames'
        matrix colnames `ATE_boot_ci_lo' = `colnames'
        matrix colnames `ATE_boot_ci_hi' = `colnames'
        
        if "`quiet'" == "" {
            di as text "  Bootstrap completed: `n_boot_valid'/`bootstrap' valid iterations"
        }
    }
    
    // ================================================================
    // Task 25: Store e() returns and display results
    // ================================================================
    
    if "`quiet'" == "" {
        di as text ""
        di as text "{hline 70}"
        if !`_pte_exact_inst' {
            di as text "Dynamic Counterfactual Treatment Effect (Proposition D.3)"
            di as text "Method: Divergent Evolution"
        }
        else {
            di as text "Instantaneous Counterfactual Treatment Effect (Proposition D.2)"
            di as text "Method: Divergent exact branch for s<=0"
        }
        di as text "{hline 70}"
        di as text ""
        di as text "  Reference time (t0):     " as result %4.0f `t0'
        di as text "  Expansion time (t0+s):   " as result %4.0f `expansiontime'
        di as text "  Delay (s):               " as result %4.0f `s_val'
        di as text "  Target group N:          " as result %9.0f `n_target'
        di as text "  Simulation paths (nsim): " as result %9.0f `nsim'
        if !`_pte_exact_inst' {
            di as text "  G_eps1 sample size:      " as result %9.0f `n_eps1_sample'
        }
        else {
            di as text "  Exact branch:            " as result "Yes (no G_eps1 needed)"
        }
        di as text "  sigma_eps0:              " as result %12.6f `sigma_eps0'
        di as text "  sigma_eps1:              " as result %12.6f `sigma_eps1'
        if `did_bootstrap' {
            di as text "  Bootstrap replications:  " as result %9.0f `bootstrap'
            di as text "  Bootstrap valid:         " as result %9.0f `n_boot_valid'
            di as text "  Confidence level:        " as result %9.0f `level' "%"
        }
        di as text ""
        di as text "{hline 70}"
        if `did_bootstrap' {
            di as text %12s "Period" %12s "ATE_count" %12s "Boot SE" %12s "[`level'% CI Lo" %12s "CI Hi]"
        }
        else {
            di as text %20s "Period (ell)" %15s "ATE_count" %15s "Std. Err."
        }
        di as text "{hline 70}"
        
        forvalues ell = 0/`attperiods' {
            local ate_val = `ATE_count'[1, `ell' + 1]
            if `did_bootstrap' {
                local bse_val = `ATE_boot_se'[1, `ell' + 1]
                local bci_lo = `ATE_boot_ci_lo'[1, `ell' + 1]
                local bci_hi = `ATE_boot_ci_hi'[1, `ell' + 1]
                if `bse_val' < . {
                    di as text %12.0f `ell' as result %12.6f `ate_val' %12.6f `bse_val' %12.6f `bci_lo' %12.6f `bci_hi'
                }
                else {
                    di as text %12.0f `ell' as result %12.6f `ate_val' %12s "N/A" %12s "N/A" %12s "N/A"
                }
            }
            else {
                local se_val = `ATE_se'[1, `ell' + 1]
                if `se_val' < . {
                    di as text %20.0f `ell' as result %15.6f `ate_val' %15.6f `se_val'
                }
                else {
                    di as text %20.0f `ell' as result %15.6f `ate_val' %15s "N/A"
                }
            }
        }
        
        di as text "{hline 70}"
        di as text ""
        if !`_pte_exact_inst' {
            di as text "  omega1: ell=0 uses h_1^+ (transition), ell>=1 uses h_bar_1 (steady)"
            di as text "  omega0: all periods use h_bar_0 (control evolution, rho only)"
        }
        else {
            di as text "  omega1: exact h_1^+(omega_{t0+s-1}) branch"
            di as text "  omega0: exact h_bar_0(omega_{t0+s-1}) branch"
        }
        di as text "{hline 70}"
    }
    
    // Rebuild a clean counterfactual eclass result so stale upstream
    // estimation state does not leak into the Appendix D object.
    tempvar _pte_cf_esample
    quietly gen byte `_pte_cf_esample' = (`targetgroup' == 1 ///
        & `timevar' == `target_year' & !missing(omega))
    quietly count if `_pte_cf_esample'
    local _pte_cf_esample_n = r(N)

    tempname __b __V __SE
    tempname _pte_cf_ate_graph _pte_cf_ate_graph_se
    tempname _pte_cf_ate_graph_lb _pte_cf_ate_graph_ub
    tempname _pte_cf_attperiods_graph _pte_cf_attperiods_graph_vec
    local _pte_cf_bnames ""
    tempname _pte_cf_attperiods_vec
    local _pte_cf_period_colnames ""
    forvalues ell = 0/`attperiods' {
        local _pte_cf_bnames "`_pte_cf_bnames' ATE_count_`ell'"
        local _pte_cf_period_colnames "`_pte_cf_period_colnames' nt`ell'"
    }

    matrix `_pte_cf_attperiods_vec' = J(1, `attperiods' + 1, .)
    forvalues ell = 0/`attperiods' {
        matrix `_pte_cf_attperiods_vec'[1, `ell' + 1] = `ell'
    }
    matrix colnames `_pte_cf_attperiods_vec' = `_pte_cf_period_colnames'
    matrix rownames `_pte_cf_attperiods_vec' = period

    matrix `__b' = `ATE_count'
    matrix colnames `__b' = `_pte_cf_bnames'
    matrix rownames `__b' = ATE_count
    matrix coleq `__b' = ""

    if `did_bootstrap' {
        matrix `__SE' = `ATE_boot_se'
    }
    else {
        matrix `__SE' = `ATE_se'
    }

    local _pte_cf_k = colsof(`__b')
    matrix `__V' = J(`_pte_cf_k', `_pte_cf_k', 0)
    forvalues j = 1/`_pte_cf_k' {
        local _pte_cf_sej = `__SE'[1, `j']
        if !missing(`_pte_cf_sej') {
            matrix `__V'[`j', `j'] = `=(`_pte_cf_sej')^2'
        }
        else {
            matrix `__V'[`j', `j'] = .
        }
    }
    matrix rownames `__V' = `_pte_cf_bnames'
    matrix colnames `__V' = `_pte_cf_bnames'
    matrix roweq `__V' = ""
    matrix coleq `__V' = ""

    matrix `_pte_cf_ate_graph' = `ATE_count'
    matrix `_pte_cf_ate_graph_se' = `ATE_se'
    matrix `_pte_cf_attperiods_graph' = `_pte_cf_attperiods_vec'
    matrix `_pte_cf_attperiods_graph_vec' = `_pte_cf_attperiods_vec'
    if `did_bootstrap' {
        matrix `_pte_cf_ate_graph_lb' = `ATE_boot_ci_lo'
        matrix `_pte_cf_ate_graph_ub' = `ATE_boot_ci_hi'
    }

    ereturn clear
    ereturn post `__b' `__V', esample(`_pte_cf_esample') obs(`_pte_cf_esample_n') depname("ATE_count")

    // Store e() returns
    ereturn matrix ate_counterfactual = `ATE_count'
    ereturn matrix ate_counterfactual_se = `ATE_se'
    ereturn matrix ate_count = `_pte_cf_ate_graph'
    ereturn matrix ate_count_se = `_pte_cf_ate_graph_se'
    ereturn matrix attperiods = `_pte_cf_attperiods_graph'
    ereturn matrix attperiods_vec = `_pte_cf_attperiods_graph_vec'
    
    // Bootstrap results
    if `did_bootstrap' {
        ereturn matrix ate_counterfactual_se_boot = `ATE_boot_se'
        ereturn matrix ate_counterfactual_ci_lower = `ATE_boot_ci_lo'
        ereturn matrix ate_counterfactual_ci_upper = `ATE_boot_ci_hi'
        ereturn matrix ate_counterfactual_boot = `ATE_boot'
        ereturn matrix ate_count_lb = `_pte_cf_ate_graph_lb'
        ereturn matrix ate_count_ub = `_pte_cf_ate_graph_ub'
        ereturn scalar bootstrap = `bootstrap'
        ereturn scalar n_boot_valid = `n_boot_valid'
    }
    else {
        ereturn scalar bootstrap = 0
    }
    
    ereturn scalar sigma_eps1 = `sigma_eps1'
    ereturn scalar sigma_eps0 = `sigma_eps0'
    ereturn scalar n_eps1_sample = `n_eps1_sample'
    ereturn scalar n_target_group = `n_target'
    ereturn scalar t0 = `t0'
    ereturn scalar expansion_time = `expansiontime'
    ereturn scalar s = `s_val'
    ereturn scalar attperiods_cf = `attperiods'
    ereturn scalar attperiods_max = `attperiods'
    ereturn scalar nsim = `nsim'
    ereturn scalar seed = `seed'
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar level = `level'
    ereturn scalar level_cf = `level'
    
    ereturn local cfmethod "divergent"
    ereturn local subcmd_cf "counterfactual_divergent"
    ereturn local cmd "_pte_cf_divergent"
    ereturn local title "PTE Divergent Counterfactual ATE"
    
    // Store parameter vectors for verification
    tempname h_plus_vec rho_0_vec rho_h1_vec
    matrix `h_plus_vec' = `e_h_plus'
    matrix `rho_0_vec' = `e_rho_0'
    
    matrix `rho_h1_vec' = J(1, `omegapoly' + 1, .)
    forvalues j = 0/`omegapoly' {
        matrix `rho_h1_vec'[1, `j' + 1] = `rho_h1_`j''
    }
    
    ereturn matrix h_plus_used = `h_plus_vec'
    ereturn matrix rho_0_used = `rho_0_vec'
    ereturn matrix rho_h1_used = `rho_h1_vec'
    
    // Store assumption test results if diagnose was run
    if `_pte_run_diag' {
        ereturn scalar assumption_d3_pval = `_diag_d3_pval'
        ereturn scalar assumption_d4_pval = `_diag_d4_pval'
        ereturn scalar assumption_d3_pass = `_diag_d3_pass'
        ereturn scalar assumption_d4_pass = `_diag_d4_pass'
        ereturn scalar assumption_overlap_ok = `_diag_overlap_ok'
        ereturn scalar assumption_overlap_ratio = `_diag_overlap_ratio'
    }
    
end

capture program drop _pte_cf_divergent_sigma0_support
program define _pte_cf_divergent_sigma0_support, rclass
    version 14.0

    syntax, FALLBACKraw(real) FALLBACKtrim(real)

    local sigma_eps0_raw = `fallbackraw'
    local sigma_eps0_trim = `fallbacktrim'
    local sigma_eps0_use = `sigma_eps0_trim'
    local sigma0_source "fallback_eclass"

    capture confirm variable _pte_eps0, exact
    local has_eps0 = (_rc == 0)
    capture confirm variable _pte_eps0_ind, exact
    local has_eps0_ind = (_rc == 0)

    if `has_eps0' & `has_eps0_ind' {
        capture confirm numeric variable _pte_eps0
        if _rc != 0 {
            di as error "{bf:pte error 3015}: _pte_eps0 must be numeric"
            exit 3015
        }
        capture confirm numeric variable _pte_eps0_ind
        if _rc != 0 {
            di as error "{bf:pte error 3015}: _pte_eps0_ind must be numeric"
            exit 3015
        }
        capture assert inlist(_pte_eps0_ind, 0, 1) if !missing(_pte_eps0_ind)
        if _rc != 0 {
            di as error "{bf:pte error 3015}: _pte_eps0_ind must be binary (0/1)"
            exit 3015
        }

        quietly count if _pte_eps0_ind == 1 & !missing(_pte_eps0)
        local N_eps0 = r(N)

        if `N_eps0' > 0 {
            quietly summarize _pte_eps0 if _pte_eps0_ind == 1, meanonly
            local sigma_eps0_raw_live = r(sd)
            if `N_eps0' == 1 & missing(`sigma_eps0_raw_live') {
                local sigma_eps0_raw_live = 0
            }

            local sigma_eps0_trim_live = .
            quietly _pctile _pte_eps0 if _pte_eps0_ind == 1, p(1 99)
            local eps0_p1 = r(r1)
            local eps0_p99 = r(r2)
            tempvar _pte_eps0_trim_work
            quietly gen double `_pte_eps0_trim_work' = _pte_eps0 if _pte_eps0_ind == 1
            quietly replace `_pte_eps0_trim_work' = . if ///
                `_pte_eps0_trim_work' < `eps0_p1' | `_pte_eps0_trim_work' > `eps0_p99'
            quietly summarize `_pte_eps0_trim_work', meanonly
            local sigma_eps0_trim_live = r(sd)
            local N_eps0_trim = r(N)

            if `N_eps0_trim' == 1 & missing(`sigma_eps0_trim_live') {
                local sigma_eps0_trim_live = 0
            }
            if missing(`sigma_eps0_trim_live') {
                local sigma_eps0_trim_live = `sigma_eps0_raw_live'
            }

            if !missing(`sigma_eps0_raw_live') & `sigma_eps0_raw_live' >= 0 {
                local sigma_eps0_raw = `sigma_eps0_raw_live'
            }
            if !missing(`sigma_eps0_trim_live') & `sigma_eps0_trim_live' >= 0 {
                local sigma_eps0_trim = `sigma_eps0_trim_live'
                local sigma_eps0_use = `sigma_eps0_trim_live'
                local sigma0_source "live_eps0_support"
            }
            else if !missing(`sigma_eps0_raw_live') & `sigma_eps0_raw_live' >= 0 {
                local sigma_eps0_trim = `sigma_eps0_raw_live'
                local sigma_eps0_use = `sigma_eps0_raw_live'
                local sigma0_source "live_eps0_support_raw"
            }
        }
    }

    return scalar sigma_eps0 = `sigma_eps0_use'
    return scalar sigma_eps0_raw = `sigma_eps0_raw'
    return scalar sigma_eps0_trim = `sigma_eps0_trim'
    return local source "`sigma0_source'"
end

// ====================================================================
// Mata helper: _pte_cf_divergent_sim
// Orchestrates omega1/omega0 simulation and ATE aggregation
// Called from _pte_cf_divergent.ado
// ====================================================================

mata:

void _pte_cf_divergent_sim(
    string scalar h_plus_name,
    string scalar rho_h1_name,
    string scalar rho_0_name,
    real scalar sigma_eps1,
    real scalar sigma_eps0,
    real scalar attperiods,
    real scalar nsim,
    real scalar seed,
    string scalar ate_mat_name,
    string scalar se_mat_name)
{
    // Local declarations
    real colvector omega_start
    real rowvector h_plus, rho_h1, rho_0
    real matrix omega1_mat, omega0_mat, tt_mat
    real matrix tt_ell
    real colvector firm_tt
    real rowvector ate_vec, se_vec
    real scalar N, n_ell, ell, m
    real rowvector cols_ell

    // --- Extract omega starting values from current Stata data ---
    omega_start = st_data(., "omega")
    N = rows(omega_start)

    // --- Get parameter vectors from Stata matrices ---
    h_plus = st_matrix(h_plus_name)
    rho_h1 = st_matrix(rho_h1_name)
    rho_0  = st_matrix(rho_0_name)

    // --- Simulate omega^1 paths ---
    // ell=0: h_1^+ (transition), ell>=1: h_bar_1 (steady treated)
    omega1_mat = _pte_simulate_omega1(
        omega_start, h_plus, rho_h1,
        sigma_eps1, attperiods, nsim, seed)

    // --- Simulate omega^0 paths ---
    // ALL periods use h_bar_0 (control evolution, rho only)
    // Pass rho_0 for BOTH h_plus and rho_h1 parameters
    // CRITICAL: Use different seed (seed + 7654321) to ensure eps0 draws
    // are independent from eps1 draws. Same seed would create perfect
    // correlation between omega1 and omega0 shocks, biasing TT.
    omega0_mat = _pte_simulate_omega1(
        omega_start, rho_0, rho_0,
        sigma_eps0, attperiods, nsim, seed + 7654321)

    // --- Compute TT = omega1 - omega0 (element-wise) ---
    tt_mat = omega1_mat - omega0_mat

    // --- Aggregate: ATE_{s,ell}^{count} for each period ---
    n_ell = attperiods + 1
    ate_vec = J(1, n_ell, .)
    se_vec  = J(1, n_ell, .)

    for (ell = 0; ell <= attperiods; ell++) {
        // Collect columns for this period across all nsim paths
        // For path m (1-indexed), period ell:
        //   col = (m-1) * (attperiods+1) + ell + 1
        cols_ell = J(1, nsim, .)
        for (m = 1; m <= nsim; m++) {
            cols_ell[m] = (m - 1) * n_ell + ell + 1
        }

        // N x nsim submatrix for this period
        tt_ell = tt_mat[., cols_ell]

        // Mean across paths for each firm: N x 1
        firm_tt = rowsum(tt_ell) / nsim

        // ATE = mean across firms
        ate_vec[1, ell + 1] = mean(firm_tt)

        // SE = sd across firms / sqrt(N)
        if (N > 1) {
            se_vec[1, ell + 1] = sqrt(variance(firm_tt)) / sqrt(N)
        }
    }

    // --- Store results back to Stata matrices ---
    st_matrix(ate_mat_name, ate_vec)
    st_matrix(se_mat_name, se_vec)
}

end

// ====================================================================
// Mata helper: _pte_cf_divergent_boot_agg
// Computes bootstrap SE and percentile CI from bootstrap ATE matrix
// Called from _pte_cf_divergent.ado after bootstrap loop
// ====================================================================

mata:

void _pte_cf_divergent_boot_agg(
    string scalar ate_boot_name,
    string scalar ate_se_name,
    string scalar ate_ci_lo_name,
    string scalar ate_ci_hi_name)
{
    real matrix ATE_boot
    real rowvector SE, CI_lo, CI_hi
    real scalar B, n_periods, n_valid, j, alpha_half
    real colvector col_j, valid_col
    real scalar lo_idx, hi_idx, n_v
    string scalar boot_alpha_str

    // Read bootstrap ATE matrix from Stata
    ATE_boot = st_matrix(ate_boot_name)
    B = rows(ATE_boot)
    n_periods = cols(ATE_boot)

    // Read alpha from Stata local
    boot_alpha_str = st_local("boot_alpha")
    if (boot_alpha_str == "") {
        alpha_half = 0.025
    }
    else {
        alpha_half = strtoreal(boot_alpha_str) / 2
    }

    // Initialize output vectors
    SE = J(1, n_periods, .)
    CI_lo = J(1, n_periods, .)
    CI_hi = J(1, n_periods, .)

    // Track minimum valid count across periods
    n_valid = 0

    // Compute SE and CI for each period
    for (j = 1; j <= n_periods; j++) {
        col_j = ATE_boot[., j]

        // Find non-missing rows
        valid_col = select(col_j, col_j :< .)
        if (length(valid_col) < 2) {
            SE[1, j] = .
            CI_lo[1, j] = .
            CI_hi[1, j] = .
            continue
        }

        // Track valid count
        if (j == 1) {
            n_valid = length(valid_col)
        }
        else {
            if (length(valid_col) < n_valid) {
                n_valid = length(valid_col)
            }
        }

        // Bootstrap SE = standard deviation of bootstrap estimates
        SE[1, j] = sqrt(variance(valid_col))

        // Percentile CI: sort and pick quantiles
        _sort(valid_col, 1)
        n_v = length(valid_col)
        lo_idx = max((1, ceil(alpha_half * n_v)))
        hi_idx = min((n_v, floor((1 - alpha_half) * n_v) + 1))

        CI_lo[1, j] = valid_col[lo_idx]
        CI_hi[1, j] = valid_col[hi_idx]
    }

    // Store results back to Stata
    st_matrix(ate_se_name, SE)
    st_matrix(ate_ci_lo_name, CI_lo)
    st_matrix(ate_ci_hi_name, CI_hi)

    // Set n_boot_valid as Stata local
    st_local("n_boot_valid", strofreal(n_valid))
}

end
