*! _pte_compare_endog.ado
*! Endogenous Productivity + TWFE Implementation (Method II)
*!
*! Theory: Paper Section 5, Equation (14)
*!
*! Key differences from Expost:
*!   - GMM: 8-column OMEGA_lag_pol (WITH interaction terms)
*!   - Sample: Full sample (no transition period exclusion, same as expost)
*!   - Evolution: h_tilde(omega, D, D_lag) includes treatment interactions
*! Key differences from CLK (pte main):
*!   - Does NOT exclude transition period (mid != 1)
*!   - Uses all observations including D_t != D_{t-1}

version 14.0
capture program drop _pte_compare_endog
program define _pte_compare_endog, eclass
    version 14.0
    
    syntax , treatment(varname) ///
        [SPECs(numlist integer min=1 max=3 >0 <4) ///
         OMEGApoly(integer 3) ///
         ABsorb(string) VCE(string) INDustry(varname) ///
         LAGTreatment DIAGnose noREPort]

    if "`industry'" != "" {
        di as error "Error 198: industry() is not supported by _pte_compare_endog."
        di as error "The released comparison workflow does not implement a general by-industry public interface."
        di as error "Subset the data before calling, or use a dedicated industry comparison workflow."
        exit 198
    }

    // Validate omegapoly range (1-4)
    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "Error: omegapoly(`omegapoly') out of range. Must be 1, 2, 3, or 4."
        exit 198
    }
    
    // =========================================================================
    // Step 0: Validate prerequisites
    // =========================================================================
    
    // Check pte has been run
    if "`e(cmd)'" != "pte" {
        di as error "Error 301: pte has not been run."
        di as error "Please run {bf:pte} first, then call {bf:pte_compare}."
        exit 301
    }
    
    // Check reghdfe is installed
    capture which reghdfe
    if _rc {
        di as error "Error 601: reghdfe is required but not installed."
        di as error "Please install: {stata ssc install reghdfe}"
        exit 601
    }
    
    // Save pte results before they get overwritten
    local pte_free    "`e(free)'"
    local pte_state   "`e(state)'"
    local pte_proxy   "`e(proxy)'"
    local pte_depvar  "`e(depvar)'"
    local pte_panelvar "`e(panelvar)'"
    local pte_timevar  "`e(timevar)'"
    local pte_prodfunc "`e(prodfunc)'"
    local pte_xtdelta ""
    tempname _pte_compare_live_xtdelta
    capture scalar `_pte_compare_live_xtdelta' = e(xtdelta)
    if _rc == 0 & !missing(`_pte_compare_live_xtdelta') {
        local pte_xtdelta = strofreal(`_pte_compare_live_xtdelta')
    }
    local _pte_compare_live_delta_opt ""
    if "`pte_xtdelta'" != "" {
        local _pte_compare_live_delta_opt ", delta(`pte_xtdelta')"
    }
    local _pte_compare_had_xtset 0
    local _pte_compare_prev_panel ""
    local _pte_compare_prev_time ""
    local _pte_compare_prev_delta ""
    capture quietly xtset
    if _rc == 0 {
        local _pte_compare_had_xtset 1
        local _pte_compare_prev_panel "`r(panelvar)'"
        local _pte_compare_prev_time "`r(timevar)'"
        local _pte_compare_prev_delta "`r(tdelta)'"
    }
    
    // Default specs: all three (m4, m5, m6 in reproduction code)
    if "`specs'" == "" local specs "1 2 3"
    
    // Default absorb: firm + year FE (paper Eq.18)
    if "`absorb'" == "" local absorb "`pte_panelvar' `pte_timevar'"
    
    // Default VCE: reghdfe default robust
    local vce_opt ""
    if "`vce'" != "" local vce_opt "vce(`vce')"
    
    di as text ""
    di as text "{hline 70}"
    di as text "  Endogenous Productivity (Method II)"
    di as text "{hline 70}"
    di as text ""
    
    // =========================================================================
    // Step 1: Endogenous ACF Production Function Estimation
    // =========================================================================
    
    di as text "  Step 1: Endogenous ACF production function estimation..."
    di as text "    Key: includes treatment interaction terms, full sample"
    di as text "    omegapoly = `omegapoly' (OMEGA_lag_pol: " 2*`omegapoly'+2 " columns)"
    
    // Preserve data for GMM estimation
    preserve
    
    // Generate polynomial variables for first stage
    local l "`pte_free'"
    local k "`pte_state'"
    local m "`pte_proxy'"
    local y "`pte_depvar'"

    // DOs use a canonical grouped time trend t. Recreate it from the
    // stored pte timevar inside the preserved working sample instead of
    // assuming the caller's dataset already contains a variable named t.
    tempvar _pte_cmp_t
    qui egen `_pte_cmp_t' = group(`pte_timevar')
    capture drop t
    qui gen long t = `_pte_cmp_t'
    label variable t "PTE compare internal grouped time trend"
    
    cap drop l1 l2 l3 k1 k2 k3 m1 m2 m3
    cap drop l1m1 l1k1 m1k1 l1m2 l1k2 m1k2 m1l2 k1l2 k1m2 k1l1m1
    
    qui gen double l1 = `l'
    qui gen double l2 = `l'^2
    qui gen double l3 = `l'^3
    qui gen double k1 = `k'
    qui gen double k2 = `k'^2
    qui gen double k3 = `k'^3
    qui gen double m1 = `m'
    qui gen double m2 = `m'^2
    qui gen double m3 = `m'^3
    qui gen double l1m1 = `l' * `m'
    qui gen double l1k1 = `l' * `k'
    qui gen double m1k1 = `m' * `k'
    qui gen double l1m2 = `l' * `m'^2
    qui gen double l1k2 = `l' * `k'^2
    qui gen double m1k2 = `m' * `k'^2
    qui gen double m1l2 = `m' * `l'^2
    qui gen double k1l2 = `k' * `l'^2
    qui gen double k1m2 = `k' * `m'^2
    qui gen double k1l1m1 = `k' * `m' * `l'
    
    // First-stage regression: phi = E[y | l_poly, k_poly, m_poly, t]
    qui reg `y' l1* m1* k1* k2* l2* m2* k3 l3 m3 t
    cap drop phi
    qui predict double phi
    
    // Remove time trend (subtract controls, NOT input variables)
    scalar _pte_beta_t_endog = _b[t]
    qui replace phi = phi - _pte_beta_t_endog * t

    // Preserve the endogenous-method first-stage phi before the GMM prep drops
    // lagless rows. Method II's omega must come from this phi, not from the
    // active pte run's main-chain _pte_phi.
    tempfile _pte_compare_endog_phi
    sort `pte_panelvar' `pte_timevar'
    quietly save `"_pte_compare_endog_phi"', replace
    
    // OLS initial values for GMM
    qui reg `y' `l' `k' l2 k2 l1k1 t
    
    // Ensure panel is set
    qui xtset `pte_panelvar' `pte_timevar'`_pte_compare_live_delta_opt'
    
    // Generate lagged variables for GMM
    cap drop *_lag
    foreach var in phi `k' `l' `m' l2 k2 l1k1 `treatment' _pte_mid {
        cap gen double `var'_lag = L.`var'
    }
    // Mixed lag instrument: l_{t-1} * k_t (capital is state variable)
    cap drop kl_lag
    qui gen double kl_lag = `l'_lag * `k'
    qui gen double const = 1
    
    // Generate treat_post_lag for Mata (interaction term variable)
    cap drop treat_post_lag
    qui gen double treat_post_lag = `treatment'_lag
    
    // Drop first period (no lag available)
    // NOTE: Do NOT drop transition period - this is the key difference from CLK
    qui bys `pte_panelvar' (t): drop if _n == 1

    // Canonical pte inputs often already use lnl/lnk. Snapshot those live
    // source columns before the alias block drops the canonical names, or the
    // worker will self-destruct on `gen lnl = lnl'.
    local _pte_l_src "`l'"
    local _pte_k_src "`k'"
    local _pte_l_lag_src "`l'_lag"
    local _pte_k_lag_src "`k'_lag"
    if "`l'" == "lnl" {
        tempvar _pte_l_src_hold _pte_l_lag_hold
        qui gen double `_pte_l_src_hold' = `l'
        qui gen double `_pte_l_lag_hold' = `l'_lag
        local _pte_l_src "`_pte_l_src_hold'"
        local _pte_l_lag_src "`_pte_l_lag_hold'"
    }
    if "`k'" == "lnk" {
        tempvar _pte_k_src_hold _pte_k_lag_hold
        qui gen double `_pte_k_src_hold' = `k'
        qui gen double `_pte_k_lag_hold' = `k'_lag
        local _pte_k_src "`_pte_k_src_hold'"
        local _pte_k_lag_src "`_pte_k_lag_hold'"
    }
    
    // Rename for Mata compatibility without recomputing lags after sample trimming.
    cap drop lnl lnk lnl_lag lnk_lag
    qui gen double lnl = `_pte_l_src'
    qui gen double lnk = `_pte_k_src'
    qui gen double lnl_lag = `_pte_l_lag_src'
    qui gen double lnk_lag = `_pte_k_lag_src'
    
    // Drop observations with missing lags
    qui drop if missing(phi_lag) | missing(lnl_lag) | missing(lnk_lag)
    qui drop if missing(treat_post_lag)
    
    di as text "    First stage: phi estimated (N = " _N ")"
    
    // =========================================================================
    // Step 1b: GMM Estimation (Mata)
    // =========================================================================
    
    // Compile and run Mata GMM
    cap mata: mata drop _pte_gmm_endog()
    cap mata: mata drop _pte_model_endog()
    
    // Resolve the companion Mata source from adopath/project root instead of
    // assuming the caller's current working directory has a sibling ado/ tree.
    local mata_file ""
    capture quietly _pte_mata_findpath, file(_pte_compare_endog_gmm.mata)
    if _rc == 0 & r(found) == 1 {
        local mata_file `"`r(filepath)'"'
    }
    
    if `"`mata_file'"' == "" {
        di as error "Error: Cannot find _pte_compare_endog_gmm.mata"
        restore
        if `_pte_compare_had_xtset' {
            local _pte_compare_restore_delta_opt ""
            if `"`_pte_compare_prev_delta'"' != "" {
                local _pte_compare_restore_delta_opt "delta(`_pte_compare_prev_delta')"
            }
            capture quietly xtset `_pte_compare_prev_panel' `_pte_compare_prev_time', `_pte_compare_restore_delta_opt'
        }
        else {
            capture quietly xtset, clear
        }
        exit 601
    }
    
    qui do "`mata_file'"
    
    // Set omegapoly scalar for Mata to read
    scalar _pte_omegapoly_endog = `omegapoly'
    
    // Run GMM optimization
    mata: _pte_model_endog()
    
    // Extract results
    tempname beta_endog
    matrix `beta_endog' = _pte_beta_endog
    local fval_endog = _pte_fval_endog
    
    // Name the columns
    matrix colnames `beta_endog' = beta_l beta_k beta_ll beta_kk beta_lk
    
    scalar _pte_endog_bl  = `beta_endog'[1, 1]
    scalar _pte_endog_bk  = `beta_endog'[1, 2]
    scalar _pte_endog_bll = `beta_endog'[1, 3]
    scalar _pte_endog_bkk = `beta_endog'[1, 4]
    scalar _pte_endog_blk = `beta_endog'[1, 5]
    
    di as text "    GMM converged: fval = " %12.8f `fval_endog'
    di as text "    beta_l = " %9.6f _pte_endog_bl ///
               "  beta_k = " %9.6f _pte_endog_bk
    
    restore
    
    // =========================================================================
    // Step 2: Productivity Recovery
    // =========================================================================
    
    di as text ""
    di as text "  Step 2: Recovering endogenous productivity (omega_end)..."
    
    // omega_end = phi - beta_l*l - beta_k*k - beta_ll*l^2 - beta_kk*k^2 - beta_lk*l*k
    
    capture drop _pte_phi_endog_cmp
    tempvar _pte_phi_master_hold
    local _pte_compare_has_master_phi = 0
    capture confirm variable phi, exact
    if !_rc {
        local _pte_compare_has_master_phi = 1
        rename phi `_pte_phi_master_hold'
    }
    capture noisily merge 1:1 `pte_panelvar' `pte_timevar' using `"_pte_compare_endog_phi"', ///
        nogen keep(master match) keepusing(phi)
    local _pte_compare_merge_rc = _rc
    if `_pte_compare_merge_rc' == 0 {
        rename phi _pte_phi_endog_cmp
    }
    if `_pte_compare_has_master_phi' {
        rename `_pte_phi_master_hold' phi
    }
    if `_pte_compare_merge_rc' {
        if `_pte_compare_had_xtset' {
            local _pte_compare_restore_delta_opt ""
            if `"`_pte_compare_prev_delta'"' != "" {
                local _pte_compare_restore_delta_opt "delta(`_pte_compare_prev_delta')"
            }
            capture quietly xtset `_pte_compare_prev_panel' `_pte_compare_prev_time', `_pte_compare_restore_delta_opt'
        }
        else {
            capture quietly xtset, clear
        }
        exit `_pte_compare_merge_rc'
    }

    cap drop _pte_omega_end _pte_omega_end2 _pte_omega_end3
    
    qui gen double _pte_omega_end = _pte_phi_endog_cmp ///
        - _pte_endog_bl  * `pte_free' ///
        - _pte_endog_bk  * `pte_state' ///
        - _pte_endog_bll * `pte_free'^2 ///
        - _pte_endog_bkk * `pte_state'^2 ///
        - _pte_endog_blk * `pte_free' * `pte_state'
    
    // Generate polynomial terms
    qui gen double _pte_omega_end2 = _pte_omega_end^2
    qui gen double _pte_omega_end3 = _pte_omega_end^3
    
    label variable _pte_omega_end  "Endogenous productivity (omega_end)"
    label variable _pte_omega_end2 "omega_end squared"
    label variable _pte_omega_end3 "omega_end cubed"
    capture drop _pte_phi_endog_cmp
    
    qui count if !missing(_pte_omega_end)
    di as text "    omega_end recovered: N = " r(N)
    
    // =========================================================================
    // Step 3: TWFE Regressions (m4, m5, m6 in reproduction code)
    // =========================================================================
    
    di as text ""
    di as text "  Step 3: TWFE regressions..."
    
    // Ensure panel is set
    qui xtset `pte_panelvar' `pte_timevar'`_pte_compare_live_delta_opt'
    
    // Determine treatment variable
    // Default: L.D_it (reproduction code uses L.treat_post for m4-m6)
    local treat_var "L.`treatment'"
    if "`lagtreatment'" == "" {
        // Default for endogenous method: use L.treatment per reproduction code
        di as text "    Using L.`treatment' (lagged treatment, per reproduction code)"
    }
    else {
        di as text "    Using L.`treatment' (lagged treatment)"
    }
    di as text "    Absorb: `absorb'"
    
    // Initialize result matrices
    tempname coef_mat se_mat ci_mat r2_mat n_mat
    matrix `coef_mat' = J(1, 3, .)
    matrix `se_mat'   = J(1, 3, .)
    matrix `ci_mat'   = J(3, 2, .)
    matrix `r2_mat'   = J(1, 3, .)
    matrix `n_mat'    = J(1, 3, .)
    
    // Run each specification
    foreach s of local specs {
        
        if `s' == 1 {
            // Spec 1 (m4): No controls
            // reghdfe omega_end L.treat_post, absorb(indid_adj year)
            capture noisily reghdfe _pte_omega_end `treat_var', ///
                absorb(`absorb') `vce_opt'
            local _pte_compare_reg_rc = _rc
            if `_pte_compare_reg_rc' {
                if `_pte_compare_had_xtset' {
                    local _pte_compare_restore_delta_opt ""
                    if `"`_pte_compare_prev_delta'"' != "" {
                        local _pte_compare_restore_delta_opt "delta(`_pte_compare_prev_delta')"
                    }
                    capture quietly xtset `_pte_compare_prev_panel' `_pte_compare_prev_time', `_pte_compare_restore_delta_opt'
                }
                else {
                    capture quietly xtset, clear
                }
                exit `_pte_compare_reg_rc'
            }
            
            local coef_s1 = _b[`treat_var']
            local se_s1   = _se[`treat_var']
            local r2_s1   = e(r2_a)
            local n_s1    = e(N)

            matrix `coef_mat'[1, 1] = `coef_s1'
            matrix `se_mat'[1, 1]   = `se_s1'
            matrix `ci_mat'[1, 1]   = `coef_s1' - 1.96 * `se_s1'
            matrix `ci_mat'[1, 2]   = `coef_s1' + 1.96 * `se_s1'
            matrix `r2_mat'[1, 1]   = `r2_s1'
            matrix `n_mat'[1, 1]    = `n_s1'
            
            capture estimates store _endog_m4, nocopy
            if _rc {
                if `_pte_compare_had_xtset' {
                    local _pte_compare_restore_delta_opt ""
                    if `"`_pte_compare_prev_delta'"' != "" {
                        local _pte_compare_restore_delta_opt "delta(`_pte_compare_prev_delta')"
                    }
                    capture quietly xtset `_pte_compare_prev_panel' `_pte_compare_prev_time', `_pte_compare_restore_delta_opt'
                }
                else {
                    capture quietly xtset, clear
                }
                exit _rc
            }
            
            di as text "    Spec 1/m4 (no control): delta = " ///
                %9.4f `coef_s1' " (SE = " %9.4f `se_s1' ")"
        }
        
        if `s' == 2 {
            // Spec 2 (m5): 1st order lag
            // reghdfe omega_end L.omega_end L.treat_post, absorb(indid_adj year)
            capture noisily reghdfe _pte_omega_end L._pte_omega_end `treat_var', ///
                absorb(`absorb') `vce_opt'
            local _pte_compare_reg_rc = _rc
            if `_pte_compare_reg_rc' {
                if `_pte_compare_had_xtset' {
                    local _pte_compare_restore_delta_opt ""
                    if `"`_pte_compare_prev_delta'"' != "" {
                        local _pte_compare_restore_delta_opt "delta(`_pte_compare_prev_delta')"
                    }
                    capture quietly xtset `_pte_compare_prev_panel' `_pte_compare_prev_time', `_pte_compare_restore_delta_opt'
                }
                else {
                    capture quietly xtset, clear
                }
                exit `_pte_compare_reg_rc'
            }
            
            local coef_s2 = _b[`treat_var']
            local se_s2   = _se[`treat_var']
            local r2_s2   = e(r2_a)
            local n_s2    = e(N)

            matrix `coef_mat'[1, 2] = `coef_s2'
            matrix `se_mat'[1, 2]   = `se_s2'
            matrix `ci_mat'[2, 1]   = `coef_s2' - 1.96 * `se_s2'
            matrix `ci_mat'[2, 2]   = `coef_s2' + 1.96 * `se_s2'
            matrix `r2_mat'[1, 2]   = `r2_s2'
            matrix `n_mat'[1, 2]    = `n_s2'
            
            capture estimates store _endog_m5, nocopy
            if _rc {
                if `_pte_compare_had_xtset' {
                    local _pte_compare_restore_delta_opt ""
                    if `"`_pte_compare_prev_delta'"' != "" {
                        local _pte_compare_restore_delta_opt "delta(`_pte_compare_prev_delta')"
                    }
                    capture quietly xtset `_pte_compare_prev_panel' `_pte_compare_prev_time', `_pte_compare_restore_delta_opt'
                }
                else {
                    capture quietly xtset, clear
                }
                exit _rc
            }
            
            di as text "    Spec 2/m5 (1st order): delta = " ///
                %9.4f `coef_s2' " (SE = " %9.4f `se_s2' ")"
        }
        
        if `s' == 3 {
            // Spec 3 (m6): 3rd order polynomial
            // reghdfe omega_end L.omega_end L.omega_end2 L.omega_end3 L.treat_post, absorb(indid_adj year)
            capture noisily reghdfe _pte_omega_end L._pte_omega_end ///
                L._pte_omega_end2 L._pte_omega_end3 `treat_var', ///
                absorb(`absorb') `vce_opt'
            local _pte_compare_reg_rc = _rc
            if `_pte_compare_reg_rc' {
                if `_pte_compare_had_xtset' {
                    local _pte_compare_restore_delta_opt ""
                    if `"`_pte_compare_prev_delta'"' != "" {
                        local _pte_compare_restore_delta_opt "delta(`_pte_compare_prev_delta')"
                    }
                    capture quietly xtset `_pte_compare_prev_panel' `_pte_compare_prev_time', `_pte_compare_restore_delta_opt'
                }
                else {
                    capture quietly xtset, clear
                }
                exit `_pte_compare_reg_rc'
            }
            
            local coef_s3 = _b[`treat_var']
            local se_s3   = _se[`treat_var']
            local r2_s3   = e(r2_a)
            local n_s3    = e(N)

            matrix `coef_mat'[1, 3] = `coef_s3'
            matrix `se_mat'[1, 3]   = `se_s3'
            matrix `ci_mat'[3, 1]   = `coef_s3' - 1.96 * `se_s3'
            matrix `ci_mat'[3, 2]   = `coef_s3' + 1.96 * `se_s3'
            matrix `r2_mat'[1, 3]   = `r2_s3'
            matrix `n_mat'[1, 3]    = `n_s3'
            
            capture estimates store _endog_m6, nocopy
            if _rc {
                if `_pte_compare_had_xtset' {
                    local _pte_compare_restore_delta_opt ""
                    if `"`_pte_compare_prev_delta'"' != "" {
                        local _pte_compare_restore_delta_opt "delta(`_pte_compare_prev_delta')"
                    }
                    capture quietly xtset `_pte_compare_prev_panel' `_pte_compare_prev_time', `_pte_compare_restore_delta_opt'
                }
                else {
                    capture quietly xtset, clear
                }
                exit _rc
            }
            
            di as text "    Spec 3/m6 (3rd order): delta = " ///
                %9.4f `coef_s3' " (SE = " %9.4f `se_s3' ")"
        }
    }
    
    // =========================================================================
    // Step 4: Results Output
    // =========================================================================
    
    if "`report'" != "noreport" {
        di as text ""
        di as text "{hline 70}"
        di as text "  Endogenous Productivity TWFE Results (Method II)"
        di as text "{hline 70}"
        di as text ""
        di as text "  Production function: Translog (endogenous productivity)"
        di as text "  GMM: " 2*`omegapoly'+2 "-column OMEGA_lag_pol (with treatment interactions, omegapoly=`omegapoly')"
        di as text "  Sample: Full (transition period NOT excluded)"
        di as text "  Absorb: `absorb'"
        di as text "  Treatment: L.`treatment' (lagged)"
        di as text ""
        di as text "  {hline 66}"
        di as text "                        No Control    1st Order    3rd Order"
        di as text "                          (m4)          (m5)          (m6)"
        di as text "  {hline 66}"
        
        // Treatment coefficient
        di as text "  Treatment effect     " ///
            %9.4f `coef_mat'[1,1] ///
            "      " %9.4f `coef_mat'[1,2] ///
            "      " %9.4f `coef_mat'[1,3]
        
        // Standard errors
        di as text "                       (" ///
            %7.4f `se_mat'[1,1] ")    (" ///
            %7.4f `se_mat'[1,2] ")    (" ///
            %7.4f `se_mat'[1,3] ")"
        
        // Significance stars
        local stars1 ""
        local stars2 ""
        local stars3 ""
        forvalues s = 1/3 {
            if `se_mat'[1,`s'] != . & `se_mat'[1,`s'] > 0 {
                local p = 2 * (1 - normal(abs(`coef_mat'[1,`s'] / `se_mat'[1,`s'])))
                if `p' < 0.01      local stars`s' "***"
                else if `p' < 0.05 local stars`s' "**"
                else if `p' < 0.10 local stars`s' "*"
            }
        }
        di as text "  Significance         " ///
            _col(26) "`stars1'" ///
            _col(39) "`stars2'" ///
            _col(52) "`stars3'"
        
        // Sample size
        di as text "  N                    " ///
            %9.0f `n_mat'[1,1] ///
            "      " %9.0f `n_mat'[1,2] ///
            "      " %9.0f `n_mat'[1,3]
        
        // Adjusted R-squared
        di as text "  Adj. R-squared       " ///
            %9.4f `r2_mat'[1,1] ///
            "      " %9.4f `r2_mat'[1,2] ///
            "      " %9.4f `r2_mat'[1,3]
        
        di as text "  {hline 66}"
        di as text "  Note: * p<0.10, ** p<0.05, *** p<0.01"
        
        // Bias analysis (if diagnose option)
        if "`diagnose'" != "" {
            di as text ""
            di as text "  Bias Sources (Paper Section 5, Equation 14):"
            di as text "  {hline 66}"
            di as text "  Problem 1 (Unobserved Heterogeneity):"
            di as text "    Firms observe (omega0, omega1) but econometrician only omega"
            di as text "    Selection into treatment depends on potential outcomes"
            di as text ""
            di as text "  Problem 2 (Causal Misinterpretation):"
            di as text "    h_tilde(omega, D=1, D_lag=0) conflates selection + treatment"
            di as text "    Cannot separate causal effect from selection bias"
            di as text ""
            di as text "  Problem 3 (Misleading ATE):"
            di as text "    Conditional unconfoundedness fails at transition"
            di as text "    TWFE delta != ATT even with correct controls"
            di as text ""
            di as text "  Expected Bias (Table E.5):"
            di as text "    m4 (no control): POSITIVE bias (overestimate)"
            di as text "    m5/m6 (with controls): NEGATIVE bias (underestimate)"
            di as text "  {hline 66}"
        }
        
        di as text "{hline 70}"
    }
    
    // =========================================================================
    // Step 5: Store e() return values
    // =========================================================================
    
    // Name matrices
    matrix colnames `coef_mat' = spec1 spec2 spec3
    matrix colnames `se_mat'   = spec1 spec2 spec3
    matrix rownames `ci_mat'   = spec1 spec2 spec3
    matrix colnames `ci_mat'   = ci_lower ci_upper
    matrix colnames `r2_mat'   = spec1 spec2 spec3
    matrix colnames `n_mat'    = spec1 spec2 spec3
    tempvar _pte_compare_esample
    capture quietly gen byte `_pte_compare_esample' = e(sample)
    if _rc {
        if `_pte_compare_had_xtset' {
            local _pte_compare_restore_delta_opt ""
            if `"`_pte_compare_prev_delta'"' != "" {
                local _pte_compare_restore_delta_opt "delta(`_pte_compare_prev_delta')"
            }
            capture quietly xtset `_pte_compare_prev_panel' `_pte_compare_prev_time', `_pte_compare_restore_delta_opt'
        }
        else {
            capture quietly xtset, clear
        }
        exit _rc
    }

    // Method II also needs a temporary firm-year panel declaration for lagged
    // treatment and lagged omega regressors. Restore the caller's ambient
    // xtset contract before publishing the compare results.
    if `_pte_compare_had_xtset' {
        local _pte_compare_restore_delta_opt ""
        if `"`_pte_compare_prev_delta'"' != "" {
            local _pte_compare_restore_delta_opt "delta(`_pte_compare_prev_delta')"
        }
        capture quietly xtset `_pte_compare_prev_panel' `_pte_compare_prev_time', `_pte_compare_restore_delta_opt'
    }
    else {
        capture quietly xtset, clear
    }
    
    ereturn clear
    ereturn post, esample(`_pte_compare_esample')
    
    // Scalars
    ereturn scalar att_endog_1 = `coef_mat'[1, 1]
    ereturn scalar att_endog_2 = `coef_mat'[1, 2]
    ereturn scalar att_endog_3 = `coef_mat'[1, 3]
    ereturn scalar se_endog_1  = `se_mat'[1, 1]
    ereturn scalar se_endog_2  = `se_mat'[1, 2]
    ereturn scalar se_endog_3  = `se_mat'[1, 3]
    ereturn scalar fval_endog  = `fval_endog'
    ereturn scalar omegapoly   = `omegapoly'
    
    // Matrices
    ereturn matrix coef_endog  = `coef_mat'
    ereturn matrix se_endog    = `se_mat'
    ereturn matrix ci_endog    = `ci_mat'
    ereturn matrix r2_endog    = `r2_mat'
    ereturn matrix n_endog     = `n_mat'
    ereturn matrix beta_endog  = `beta_endog'

    // Publish the same 1x3 chart interface used by the other single-method
    // compare producers so pte_compare's documented contract stays uniform.
    tempname compare_coef compare_se
    matrix `compare_coef' = `coef_mat'
    matrix `compare_se'   = `se_mat'
    matrix colnames `compare_coef' = spec1 spec2 spec3
    matrix colnames `compare_se'   = spec1 spec2 spec3
    ereturn matrix compare_coef = `compare_coef'
    ereturn matrix compare_se   = `compare_se'
    
    // Strings
    ereturn local cmd "pte_compare"
    ereturn local method "endog"
    ereturn local treatment "`treatment'"
    ereturn local absorb "`absorb'"
    ereturn local specs "`specs'"
    
end
