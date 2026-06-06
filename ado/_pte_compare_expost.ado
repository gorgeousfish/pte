*! _pte_compare_expost.ado
*! Ex-post Regression + TWFE Implementation (Method I)
*!
*! Theory: Paper Section 5, Section 6.4.3, Equations (18)-(19)
*!
*! Key differences from CLK (pte main):
*!   - GMM: 4-column OMEGA_lag_pol (no interaction terms)
*!   - Sample: Full sample (no transition period exclusion)
*!   - Evolution: h_bar_0 = h_bar_1 (forced equal)
*!   - ATT: TWFE regression instead of counterfactual simulation

version 14.0
capture program drop _pte_compare_expost
program define _pte_compare_expost, eclass
    version 14.0
    
    syntax , treatment(varname) ///
        [SPECs(numlist integer min=1 max=3 >0 <4) ///
         ABsorb(string) VCE(string) INDustry(varname) ///
         LAGTreatment DIAGnose noREPort]

    if "`industry'" != "" {
        di as error "Error 198: industry() is not supported by _pte_compare_expost."
        di as error "The released comparison workflow does not implement a general by-industry public interface."
        di as error "Subset the data before calling, or use a dedicated industry comparison workflow."
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

    // pte_compare is postestimation for the active pte fit. Method I keeps
    // transition observations, but it must not leave the caller's pte sample.
    capture confirm variable _pte_active_sample, exact
    if _rc {
        di as error "Error 459: active pte sample marker _pte_active_sample not found."
        di as error "Re-run {bf:pte} on the current data before {bf:pte_compare}."
        exit 459
    }
    capture confirm numeric variable _pte_active_sample
    if _rc {
        di as error "Error 459: active pte sample marker _pte_active_sample must be numeric."
        di as error "Re-run {bf:pte} on the current data before {bf:pte_compare}."
        exit 459
    }
    tempvar _pte_compare_active_sample
    qui gen byte `_pte_compare_active_sample' = ///
        (_pte_active_sample != 0 & !missing(_pte_active_sample))
    qui count if `_pte_compare_active_sample'
    if r(N) == 0 {
        di as error "Error 459: active pte sample marker _pte_active_sample is empty."
        di as error "Re-run {bf:pte} on the current data before {bf:pte_compare}."
        exit 459
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
    
    // Default specs: all three
    if "`specs'" == "" local specs "1 2 3"
    
    // Default absorb: firm + year FE (paper Eq.18, 疑点53 confirmed)
    if "`absorb'" == "" local absorb "`pte_panelvar' `pte_timevar'"
    
    // Default VCE: reghdfe default robust (疑点55 resolved)
    local vce_opt ""
    if "`vce'" != "" local vce_opt "vce(`vce')"
    
    di as text ""
    di as text "{hline 70}"
    di as text "  Ex-post Regression (Method I)"
    di as text "{hline 70}"
    di as text ""
    
    // =========================================================================
    // Step 1: Ex-post ACF Production Function Estimation
    // =========================================================================
    
    di as text "  Step 1: Ex-post ACF production function estimation..."
    
    // Preserve data for GMM estimation
    preserve
    qui keep if `_pte_compare_active_sample'
    
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
    scalar _pte_beta_t_expost = _b[t]
    qui replace phi = phi - _pte_beta_t_expost * t

    // Preserve the method-specific first-stage phi before the GMM prep drops
    // lagless rows. Method I's omega must be built from this ex-post phi, not
    // from the active pte run's CLK-corrected _pte_phi.
    tempfile _pte_compare_expost_phi
    sort `pte_panelvar' `pte_timevar'
    quietly save `"_pte_compare_expost_phi"', replace
    
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
    
    // Drop first period (no lag available)
    qui bys `pte_panelvar' (t): drop if _n == 1

    // The bysort above leaves the data ordered by the grouped time-trend t
    // rather than the active xtset clock. Re-sort on the live panel key
    // before using additional L. operators.
    qui sort `pte_panelvar' `pte_timevar'

    // When the active pte contract already uses the canonical lnl/lnk names,
    // the Mata alias block must not drop the live source columns and then try
    // to rebuild them from their own erased names.
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
    
    // Rename for Mata compatibility
    // Mata reads: lnl, lnk, l2, k2, l1k1, phi, phi_lag, etc.
    foreach _pte_alias in lnl lnk lnl_lag lnk_lag l2_lag k2_lag l1k1_lag phi_lag {
        capture drop `_pte_alias'
    }
    qui gen double lnl = `_pte_l_src'
    qui gen double lnk = `_pte_k_src'
    qui gen double lnl_lag = `_pte_l_lag_src'
    qui gen double lnk_lag = `_pte_k_lag_src'
    qui gen double l2_lag = L.l2
    qui gen double k2_lag = L.k2
    qui gen double l1k1_lag = L.l1k1
    qui gen double phi_lag = L.phi
    
    // Drop observations with missing lags
    qui drop if missing(phi_lag) | missing(lnl_lag) | missing(lnk_lag)
    
    // NOTE: Do NOT drop transition period - this is the key difference from CLK
    // Ex-post method uses full sample
    
    di as text "    First stage: phi estimated (N = " _N ")"
    
    // =========================================================================
    // Step 1b: GMM Estimation (Mata)
    // =========================================================================
    
    // Compile and run Mata GMM
    // The Mata file defines _pte_gmm_expost() and _pte_model_expost()
    cap mata: mata drop _pte_gmm_expost()
    cap mata: mata drop _pte_model_expost()
    
    // Resolve the companion Mata source from adopath/project root instead of
    // assuming the caller's current working directory has a sibling ado/ tree.
    local mata_file ""
    capture quietly _pte_mata_findpath, file(_pte_compare_expost_gmm.mata)
    if _rc == 0 & r(found) == 1 {
        local mata_file `"`r(filepath)'"'
    }
    
    if `"`mata_file'"' == "" {
        di as error "Error: Cannot find _pte_compare_expost_gmm.mata"
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
    
    // Run GMM optimization
    mata: _pte_model_expost()
    
    // Extract results
    tempname beta_expost
    matrix `beta_expost' = _pte_beta_expost
    local fval_expost = _pte_fval_expost
    
    // Name the columns
    matrix colnames `beta_expost' = beta_l beta_k beta_ll beta_kk beta_lk
    
    scalar _pte_expost_bl  = `beta_expost'[1, 1]
    scalar _pte_expost_bk  = `beta_expost'[1, 2]
    scalar _pte_expost_bll = `beta_expost'[1, 3]
    scalar _pte_expost_bkk = `beta_expost'[1, 4]
    scalar _pte_expost_blk = `beta_expost'[1, 5]
    
    di as text "    GMM converged: fval = " %12.8f `fval_expost'
    di as text "    beta_l = " %9.6f _pte_expost_bl ///
               "  beta_k = " %9.6f _pte_expost_bk
    
    restore
    
    // =========================================================================
    // Step 2: Productivity Recovery
    // =========================================================================
    
    di as text ""
    di as text "  Step 2: Recovering ex-post productivity (omega_exg)..."
    
    // omega_exg = phi - beta_l*l - beta_k*k - beta_ll*l^2 - beta_kk*k^2 - beta_lk*l*k
    
    capture drop _pte_phi_expost_cmp
    tempvar _pte_phi_master_hold
    local _pte_compare_has_master_phi = 0
    capture confirm variable phi, exact
    if !_rc {
        local _pte_compare_has_master_phi = 1
        rename phi `_pte_phi_master_hold'
    }
    capture noisily merge 1:1 `pte_panelvar' `pte_timevar' using `"_pte_compare_expost_phi"', ///
        nogen keep(master match) keepusing(phi)
    local _pte_compare_merge_rc = _rc
    if `_pte_compare_merge_rc' == 0 {
        rename phi _pte_phi_expost_cmp
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

    cap drop _pte_omega_exg _pte_omega_exg2 _pte_omega_exg3
    
    qui gen double _pte_omega_exg = _pte_phi_expost_cmp ///
        - _pte_expost_bl  * `pte_free' ///
        - _pte_expost_bk  * `pte_state' ///
        - _pte_expost_bll * `pte_free'^2 ///
        - _pte_expost_bkk * `pte_state'^2 ///
        - _pte_expost_blk * `pte_free' * `pte_state' ///
        if `_pte_compare_active_sample'
    
    // Generate polynomial terms
    qui gen double _pte_omega_exg2 = _pte_omega_exg^2
    qui gen double _pte_omega_exg3 = _pte_omega_exg^3
    
    label variable _pte_omega_exg  "Ex-post productivity (omega_exg)"
    label variable _pte_omega_exg2 "omega_exg squared"
    label variable _pte_omega_exg3 "omega_exg cubed"
    capture drop _pte_phi_expost_cmp
    
    qui count if `_pte_compare_active_sample' & !missing(_pte_omega_exg)
    di as text "    omega_exg recovered: N = " r(N)
    
    // =========================================================================
    // Step 3: TWFE Regressions
    // =========================================================================
    
    di as text ""
    di as text "  Step 3: TWFE regressions..."
    
    // Ensure panel is set
    qui xtset `pte_panelvar' `pte_timevar'`_pte_compare_live_delta_opt'
    
    // Equation (18) in pte_paper.md uses the contemporaneous treatment
    // indicator. Keep lagtreatment as an explicit replication/compatibility
    // switch for DO paths that used L.treatment.
    local treat_var "`treatment'"
    local treatment_label "`treatment' (contemporaneous, Eq. 18)"
    if "`lagtreatment'" != "" {
        local treat_var "L.`treatment'"
        local treatment_label "L.`treatment' (lagged, compatibility)"
        di as text "    Using lagged treatment (L.`treatment')"
    }
    else {
        di as text "    Using contemporaneous treatment (`treatment') per Eq. (18)"
    }
    di as text "    Absorb: `absorb'"
    
    // Initialize result matrices
    tempname coef_mat se_mat ci_mat r2_mat n_mat
    matrix `coef_mat' = J(1, 3, .)
    matrix `se_mat'   = J(1, 3, .)
    matrix `ci_mat'   = J(3, 2, .)
    matrix `r2_mat'   = J(1, 3, .)
    matrix `n_mat'    = J(1, 3, .)
    tempvar _pte_compare_esample
    local _pte_compare_esample_ready = 0
    
    // Run each specification
    foreach s of local specs {
        
        if `s' == 1 {
            // Spec 1: No controls (m1)
            // reghdfe omega_exg [L.]treat_post, absorb(firm year)
            capture noisily reghdfe _pte_omega_exg `treat_var' ///
                if `_pte_compare_active_sample', ///
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

            if !`_pte_compare_esample_ready' {
                capture quietly gen byte `_pte_compare_esample' = e(sample)
                local _pte_compare_esample_rc = _rc
                if `_pte_compare_esample_rc' {
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
                    exit `_pte_compare_esample_rc'
                }
                local _pte_compare_esample_ready = 1
            }
            
            capture estimates store _expost_m1, nocopy
            local _pte_compare_store_rc = _rc
            if `_pte_compare_store_rc' {
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
                exit `_pte_compare_store_rc'
            }
            
            di as text "    Spec 1 (no control): delta = " ///
                %9.4f `coef_s1' " (SE = " %9.4f `se_s1' ")"
        }
        
        if `s' == 2 {
            // Spec 2: 1st order lag (m2)
            // reghdfe omega_exg L.omega_exg [L.]treat_post, absorb(firm year)
            capture noisily reghdfe _pte_omega_exg L._pte_omega_exg `treat_var' ///
                if `_pte_compare_active_sample', ///
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

            if !`_pte_compare_esample_ready' {
                capture quietly gen byte `_pte_compare_esample' = e(sample)
                local _pte_compare_esample_rc = _rc
                if `_pte_compare_esample_rc' {
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
                    exit `_pte_compare_esample_rc'
                }
                local _pte_compare_esample_ready = 1
            }
            
            capture estimates store _expost_m2, nocopy
            local _pte_compare_store_rc = _rc
            if `_pte_compare_store_rc' {
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
                exit `_pte_compare_store_rc'
            }
            
            di as text "    Spec 2 (1st order): delta = " ///
                %9.4f `coef_s2' " (SE = " %9.4f `se_s2' ")"
        }
        
        if `s' == 3 {
            // Spec 3: 3rd order polynomial (m3)
            // reghdfe omega_exg L.omega_exg L.omega_exg2 L.omega_exg3 [L.]treat_post, absorb(firm year)
            capture noisily reghdfe _pte_omega_exg L._pte_omega_exg ///
                L._pte_omega_exg2 L._pte_omega_exg3 `treat_var' ///
                if `_pte_compare_active_sample', ///
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

            if !`_pte_compare_esample_ready' {
                capture quietly gen byte `_pte_compare_esample' = e(sample)
                local _pte_compare_esample_rc = _rc
                if `_pte_compare_esample_rc' {
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
                    exit `_pte_compare_esample_rc'
                }
                local _pte_compare_esample_ready = 1
            }
            
            capture estimates store _expost_m3, nocopy
            local _pte_compare_store_rc = _rc
            if `_pte_compare_store_rc' {
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
                exit `_pte_compare_store_rc'
            }
            
            di as text "    Spec 3 (3rd order): delta = " ///
                %9.4f `coef_s3' " (SE = " %9.4f `se_s3' ")"
        }
    }
    
    // =========================================================================
    // Step 4: Results Output
    // =========================================================================
    
    if "`report'" != "noreport" {
        di as text ""
        di as text "{hline 70}"
        di as text "  Ex-post TWFE Results (Method I)"
        di as text "{hline 70}"
        di as text ""
        di as text "  Production function: Translog (exogenous productivity)"
        di as text "  Absorb: `absorb'"
        di as text "  Treatment: `treatment_label'"
        di as text ""
        di as text "  {hline 66}"
        di as text "                        No Control    1st Order    3rd Order"
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
            local p = 2 * (1 - normal(abs(`coef_mat'[1,`s'] / `se_mat'[1,`s'])))
            if `p' < 0.01      local stars`s' "***"
            else if `p' < 0.05 local stars`s' "**"
            else if `p' < 0.10 local stars`s' "*"
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
        
        // T4.3: Bias analysis report (Paper Section 5)
        if "`diagnose'" != "" {
            di as text ""
            di as text "  Bias Source Analysis (Paper Section 5):"
            di as text "  {hline 66}"
            di as text "  Problem 1 (Unobserved Heterogeneity):      YES"
            di as text "    Firm observes (omega0, omega1) but econometrician"
            di as text "    only observes realized omega. Selection into treatment"
            di as text "    depends on potential outcomes -> omitted variable bias."
            di as text ""
            di as text "  Problem 2 (Misleading Causal Interpretation): YES"
            di as text "    Exogenous process forces h0 = h1, conflating"
            di as text "    instantaneous effect with dynamic evolution."
            di as text "    Cannot separate causal effect from selection."
            di as text ""
            di as text "  Problem 3 (Misleading ATE):                YES"
            di as text "    TWFE estimates ATE (average over all firms),"
            di as text "    not ATT on the treated. Conditional unconfoundedness"
            di as text "    fails at transition period."
            di as text ""
            di as text "  Expected Bias Direction (Table E.5):"
            di as text "    Spec 1 (no control):  POSITIVE (overestimate)"
            di as text "      Selection effect dominates without controls."
            di as text "    Spec 2/3 (with lags): NEGATIVE (underestimate)"
            di as text "      Lag controls absorb dynamics, attenuate effect."
            di as text "  {hline 66}"
            
            // Quantitative bias vs pte ATT (if available)
            capture confirm matrix e(att)
            if !_rc {
                tempname att_pte
                matrix `att_pte' = e(att)
                local ncols_att = colsof(`att_pte')
                local att_sum = 0
                local att_cnt = `ncols_att'
                if `ncols_att' > 1 local att_cnt = `ncols_att' - 1
                forvalues j = 1/`att_cnt' {
                    local att_sum = `att_sum' + `att_pte'[1, `j']
                }
                local att_mean = `att_sum' / `att_cnt'
                
                di as text ""
                di as text "  Quantitative Bias (vs pte ATT mean):"
                di as text "  pte ATT mean:  " %10.6f `att_mean'
                forvalues s = 1/3 {
                    if `coef_mat'[1, `s'] != . {
                        local bias_abs = `coef_mat'[1, `s'] - `att_mean'
                        local bias_pct = .
                        if abs(`att_mean') > 1e-10 {
                            local bias_pct = `bias_abs' / `att_mean' * 100
                        }
                        di as text "  Spec `s':        " ///
                            %10.6f `coef_mat'[1, `s'] ///
                            "  bias = " %8.4f `bias_abs' ///
                            " (" %6.1f `bias_pct' "%)"
                    }
                }
            }
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
    if !`_pte_compare_esample_ready' {
        local _pte_compare_esample_rc = 459
    }
    else {
        capture confirm variable `_pte_compare_esample', exact
        local _pte_compare_esample_rc = _rc
    }
    if `_pte_compare_esample_rc' {
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
        exit `_pte_compare_esample_rc'
    }

    // Method I temporarily aligns xtset to the active pte panel contract so
    // L. operators track the comparison design from the paper/DO scripts, but
    // the public compare command must leave the caller's ambient xtset state
    // exactly as it found it.
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
    
    ereturn post, esample(`_pte_compare_esample')
    
    // Scalars
    ereturn scalar att_expost_1 = `coef_mat'[1, 1]
    ereturn scalar att_expost_2 = `coef_mat'[1, 2]
    ereturn scalar att_expost_3 = `coef_mat'[1, 3]
    ereturn scalar se_expost_1  = `se_mat'[1, 1]
    ereturn scalar se_expost_2  = `se_mat'[1, 2]
    ereturn scalar se_expost_3  = `se_mat'[1, 3]
    ereturn scalar fval_expost  = `fval_expost'
    
    // Matrices
    ereturn matrix coef_expost  = `coef_mat'
    ereturn matrix se_expost    = `se_mat'
    ereturn matrix ci_expost    = `ci_mat'
    ereturn matrix r2_expost    = `r2_mat'
    ereturn matrix n_expost     = `n_mat'
    ereturn matrix beta_expost  = `beta_expost'
    
    // T5.5: compare_coef/compare_se for US-011 chart interface
    tempname compare_coef compare_se
    matrix `compare_coef' = J(1, 3, .)
    matrix `compare_se'   = J(1, 3, .)
    forvalues s = 1/3 {
        matrix `compare_coef'[1, `s'] = e(att_expost_`s')
        matrix `compare_se'[1, `s']   = e(se_expost_`s')
    }
    matrix colnames `compare_coef' = spec1 spec2 spec3
    matrix colnames `compare_se'   = spec1 spec2 spec3
    ereturn matrix compare_coef = `compare_coef'
    ereturn matrix compare_se   = `compare_se'
    
    // Strings
    ereturn local cmd "pte_compare"
    ereturn local method "expost"
    ereturn local treatment "`treatment'"
    ereturn local absorb "`absorb'"
    ereturn local specs "`specs'"
    if "`lagtreatment'" != "" ereturn local lagtreatment "lagtreatment"
    
end
