*! _pte_compare_clktwfe.ado
*! CLK + TWFE Implementation (Method III)
*!
*! Theory: Paper Section 5
*!
*! Key features:
*!   - Reuses the current CLK-corrected productivity object from pte
*!     when it matches the active phi/beta state, otherwise rebuilds a
*!     temporary current omega from the active pte contract
*!   - Uses package-consistent non-transition sample (_pte_mid == 0)
*!   - TWFE regression with L.treatment (lagged)
*!   - Three specs: no control (m7), AR(1) (m8), AR(3) (m9)

version 14.0
capture program drop _pte_compare_clktwfe
program define _pte_compare_clktwfe, eclass
    version 14.0
    
    syntax , treatment(varname) ///
        [SPECs(numlist integer min=1 max=3 >0 <4) ///
         ABsorb(string) VCE(string) INDustry(varname) ///
         LAGTreatment DIAGnose noREPort]
    
    // =========================================================================
    // Step 0: Validate prerequisites
    // =========================================================================
    
    // Check pte has been run
    if "`e(cmd)'" != "pte" {
        di as error "Error 301: pte has not been run."
        di as error "Please run {bf:pte} first, then call {bf:pte_compare}."
        exit 301
    }
    
    // Check the exact canonical non-transition gate. Shadow leftovers from a
    // failed rerun must not satisfy Method III through abbreviation binding.
    capture confirm variable _pte_mid, exact
    if _rc {
        di as error "Error 303: _pte_mid variable not found."
        di as error "pte must have completed successfully with transition period identification."
        di as error "Method III requires the exact canonical _pte_mid helper; shadow leftovers are not accepted."
        exit 303
    }
    
    // Check reghdfe is installed
    capture which reghdfe
    if _rc {
        di as error "Error 601: reghdfe is required but not installed."
        di as error "Please install: {stata ssc install reghdfe}"
        exit 601
    }

    // The paper/DO reference path compares the full sample and hard-coded
    // industry subsets. This worker does not implement a general industry()
    // API, so reject the option instead of silently ignoring it.
    if "`industry'" != "" {
        di as error "Error 198: industry() is not supported by _pte_compare_clktwfe."
        di as error "Method III currently supports only the overall-sample regression path."
        di as error "Subset the data before calling, or use a dedicated industry comparison workflow."
        exit 198
    }

    // =========================================================================
    // Step 1: Save pte results before they get overwritten
    // =========================================================================
    
    local pte_panelvar "`e(panelvar)'"
    local pte_timevar  "`e(timevar)'"
    local pte_treatment "`e(treatment)'"
    local pte_free    "`e(free)'"
    local pte_state   "`e(state)'"
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
    
    // Extract pte ATT mean for bias calculation
    local att_pte_mean = .
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
        local att_pte_mean = `att_sum' / `att_cnt'
    }
    
    // Default specs: all three
    if "`specs'" == "" local specs "1 2 3"
    
    // Default absorb: firm + year FE
    if "`absorb'" == "" local absorb "`pte_panelvar' `pte_timevar'"
    
    // Default VCE: reghdfe default robust
    local vce_opt ""
    if "`vce'" != "" local vce_opt "vce(`vce')"
    
    di as text ""
    di as text "{hline 70}"
    di as text "  CLK + TWFE (Method III)"
    di as text "{hline 70}"
    di as text ""
    
    // =========================================================================
    // Step 2: Resolve the current CLK omega object
    // =========================================================================
    
    di as text "  Step 1: Preparing CLK omega variables..."

    tempvar _pte_compare_omega_current _pte_compare_omega2 _pte_compare_omega3
    local omega_var "_pte_omega"
    local omega_rebuilt = 0
    local omega_mismatch = 0

    capture confirm variable phi, exact
    local has_phi = (_rc == 0)
    capture confirm variable `pte_free', exact
    local has_free = (_rc == 0)
    capture confirm variable `pte_state', exact
    local has_state = (_rc == 0)

    local has_beta_state = 1
    tempname _pte_beta_probe
    capture scalar `_pte_beta_probe' = e(beta_l)
    if _rc local has_beta_state = 0
    capture scalar `_pte_beta_probe' = e(beta_k)
    if _rc local has_beta_state = 0
    if "`pte_prodfunc'" == "translog" {
        capture scalar `_pte_beta_probe' = e(beta_ll)
        if _rc local has_beta_state = 0
        capture scalar `_pte_beta_probe' = e(beta_kk)
        if _rc local has_beta_state = 0
        capture scalar `_pte_beta_probe' = e(beta_lk)
        if _rc local has_beta_state = 0
    }

    if `has_phi' & `has_free' & `has_state' & `has_beta_state' {
        if "`pte_prodfunc'" == "translog" {
            qui gen double `_pte_compare_omega_current' = phi ///
                - e(beta_l) * `pte_free' ///
                - e(beta_k) * `pte_state' ///
                - e(beta_ll) * (`pte_free')^2 ///
                - e(beta_kk) * (`pte_state')^2 ///
                - e(beta_lk) * `pte_free' * `pte_state'
        }
        else {
            qui gen double `_pte_compare_omega_current' = phi ///
                - e(beta_l) * `pte_free' ///
                - e(beta_k) * `pte_state'
        }

        capture confirm variable _pte_omega, exact
        if _rc {
            local omega_var "`_pte_compare_omega_current'"
            local omega_rebuilt = 1
        }
        else {
            quietly count if _pte_mid == 0 ///
                & !missing(`_pte_compare_omega_current') ///
                & (missing(_pte_omega) | abs(_pte_omega - `_pte_compare_omega_current') > 1e-10)
            if r(N) > 0 {
                local omega_var "`_pte_compare_omega_current'"
                local omega_rebuilt = 1
                local omega_mismatch = r(N)
            }
        }
    }
    else {
        capture confirm variable _pte_omega, exact
        if _rc {
            di as error "Error 302: _pte_omega variable not found."
            di as error "pte_compare could not rebuild the current CLK omega from phi and stored betas."
            di as error "Re-run {bf:pte} so Method III can reuse the live omega contract."
            exit 302
        }
    }

    qui gen double `_pte_compare_omega2' = `omega_var'^2
    qui gen double `_pte_compare_omega3' = `omega_var'^3

    qui count if !missing(`omega_var') & _pte_mid == 0
    if r(N) == 0 {
        di as error "Error 304: No valid observations with _pte_mid == 0."
        di as error "All observations are in transition period."
        exit 304
    }

    if `omega_rebuilt' {
        if `omega_mismatch' > 0 {
            di as text "    Rebuilt current CLK omega from active phi/beta because `_pte_omega' was stale on " ///
                as result `omega_mismatch' as text " non-transition observations."
        }
        else {
            di as text "    Rebuilt current CLK omega from active phi/beta because `_pte_omega' was unavailable."
        }
    }
    else {
        di as text "    Using current pte CLK omega: N = " r(N) " (excluding transition period)"
    }
    
    // =========================================================================
    // Step 3: TWFE Regressions
    // =========================================================================
    
    di as text ""
    di as text "  Step 2: TWFE regressions (excluding transition period)..."
    
    // Ensure panel is set for lag operations
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
    // Official DO uses if mid!=1 after trimming the working sample.
    // In-package, _pte_transition sets sample-out observations to _pte_mid=.,
    // so the package-consistent non-transition gate is _pte_mid == 0.
    di as text "    Absorb: `absorb'"
    di as text "    Sample restriction: _pte_mid == 0 (package non-transition sample)"
    
    // Initialize result matrices
    tempname coef_mat se_mat ci_mat r2_mat n_mat
    matrix `coef_mat' = J(1, 3, .)
    matrix `se_mat'   = J(1, 3, .)
    matrix `ci_mat'   = J(3, 2, .)
    matrix `r2_mat'   = J(1, 3, .)
    matrix `n_mat'    = J(1, 3, .)
    tempvar _pte_compare_esample
    local _pte_compare_esample_ready = 0
    
    // Track errors
    local any_error = 0
    local first_error_rc = 0
    
    // Run each specification
    // m7: reghdfe omega treat_post if mid!=1, absorb(firm year)
    // m8: reghdfe omega l.omega treat_post if mid!=1, absorb(firm year)
    // m9: reghdfe omega l.omega l.omega2 l.omega3 treat_post if mid!=1, absorb(firm year)
    // Package implementation uses _pte_mid == 0 to avoid admitting _pte_mid=.
    
    foreach s of local specs {
        
        if `s' == 1 {
            // Spec 1 (m7): No controls, CLK omega, exclude transition
            capture noisily reghdfe `omega_var' `treat_var' ///
                if _pte_mid == 0, absorb(`absorb') `vce_opt'
            
            if _rc {
                di as error "    Warning: Spec 1 (m7) failed with error " _rc
                local any_error = 1
                if `first_error_rc' == 0 local first_error_rc = _rc
            }
            else {
                local coef_s1 = _b[`treat_var']
                local se_s1   = _se[`treat_var']
                matrix `coef_mat'[1, 1] = `coef_s1'
                matrix `se_mat'[1, 1]   = `se_s1'
                matrix `ci_mat'[1, 1]   = `coef_s1' - 1.96 * `se_s1'
                matrix `ci_mat'[1, 2]   = `coef_s1' + 1.96 * `se_s1'
                matrix `r2_mat'[1, 1]   = e(r2_a)
                matrix `n_mat'[1, 1]    = e(N)

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
                
                estimates store _clktwfe_m7, nocopy
                
                di as text "    Spec 1 (m7, no control): delta = " ///
                    %9.4f `coef_s1' " (SE = " %9.4f `se_s1' ")"
            }
        }
        
        if `s' == 2 {
            // Spec 2 (m8): 1st order lag control, CLK omega, exclude transition
            capture noisily reghdfe `omega_var' L.`omega_var' `treat_var' ///
                if _pte_mid == 0, absorb(`absorb') `vce_opt'
            
            if _rc {
                di as error "    Warning: Spec 2 (m8) failed with error " _rc
                local any_error = 1
                if `first_error_rc' == 0 local first_error_rc = _rc
            }
            else {
                local coef_s2 = _b[`treat_var']
                local se_s2   = _se[`treat_var']
                matrix `coef_mat'[1, 2] = `coef_s2'
                matrix `se_mat'[1, 2]   = `se_s2'
                matrix `ci_mat'[2, 1]   = `coef_s2' - 1.96 * `se_s2'
                matrix `ci_mat'[2, 2]   = `coef_s2' + 1.96 * `se_s2'
                matrix `r2_mat'[1, 2]   = e(r2_a)
                matrix `n_mat'[1, 2]    = e(N)

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
                
                estimates store _clktwfe_m8, nocopy
                
                di as text "    Spec 2 (m8, 1st order): delta = " ///
                    %9.4f `coef_s2' " (SE = " %9.4f `se_s2' ")"
            }
        }
        
        if `s' == 3 {
            // Spec 3 (m9): 3rd order polynomial control, CLK omega, exclude transition
            capture noisily reghdfe `omega_var' L.`omega_var' ///
                L.`_pte_compare_omega2' L.`_pte_compare_omega3' `treat_var' ///
                if _pte_mid == 0, absorb(`absorb') `vce_opt'
            
            if _rc {
                di as error "    Warning: Spec 3 (m9) failed with error " _rc
                local any_error = 1
                if `first_error_rc' == 0 local first_error_rc = _rc
            }
            else {
                local coef_s3 = _b[`treat_var']
                local se_s3   = _se[`treat_var']
                matrix `coef_mat'[1, 3] = `coef_s3'
                matrix `se_mat'[1, 3]   = `se_s3'
                matrix `ci_mat'[3, 1]   = `coef_s3' - 1.96 * `se_s3'
                matrix `ci_mat'[3, 2]   = `coef_s3' + 1.96 * `se_s3'
                matrix `r2_mat'[1, 3]   = e(r2_a)
                matrix `n_mat'[1, 3]    = e(N)

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
                
                estimates store _clktwfe_m9, nocopy
                
                di as text "    Spec 3 (m9, 3rd order): delta = " ///
                    %9.4f `coef_s3' " (SE = " %9.4f `se_s3' ")"
            }
        }
    }
    
    if `any_error' {
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
        di as error "Error 459: Method III failed to recover the full requested TWFE bundle."
        di as error "Requested specs must all finish successfully before pte_compare can publish a CLK+TWFE result."
        exit `first_error_rc'
    }

    // =========================================================================
    // Step 4: Results Output
    // =========================================================================
    
    if "`report'" != "noreport" {
        di as text ""
        di as text "{hline 70}"
        di as text "  CLK + TWFE Results (Method III)"
        di as text "{hline 70}"
        di as text ""
        di as text "  Production function: CLK-corrected productivity from the active pte state"
        di as text "  Absorb: `absorb'"
        di as text "  Treatment: `treatment_label'"
        di as text "  Sample: _pte_mid == 0 (package non-transition sample)"
        di as text ""
        di as text "  {hline 66}"
        di as text "                        No Control    1st Order    3rd Order"
        di as text "                           (m7)         (m8)         (m9)"
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
        di as text "  CLK correction: transition period observations excluded"
        
        // Bias analysis (vs pte ATT mean)
        if "`diagnose'" != "" {
            di as text ""
            di as text "  Bias Source Analysis (Paper Section 5):"
            di as text "  {hline 66}"
            di as text "  CLK+TWFE uses the correct CLK production function but"
            di as text "  replaces counterfactual simulation with TWFE regression."
            di as text ""
            di as text "  Problem 1 (Unobserved Heterogeneity):      YES"
            di as text "    TWFE cannot handle selection on potential outcomes."
            di as text ""
            di as text "  Problem 2 (Misleading Causal Interpretation): PARTIAL"
            di as text "    CLK correction addresses transition period, but TWFE"
            di as text "    still conflates instantaneous and dynamic effects."
            di as text ""
            di as text "  Problem 3 (Misleading ATE):                YES"
            di as text "    TWFE estimates ATE, not ATT on the treated."
            di as text "  {hline 66}"
        }
        
        // Quantitative bias vs pte ATT
        if `att_pte_mean' != . {
            di as text ""
            di as text "  Quantitative Bias (vs pte ATT mean):"
            di as text "  pte ATT mean:  " %10.6f `att_pte_mean'
            forvalues s = 1/3 {
                if `coef_mat'[1, `s'] != . {
                    local bias_abs = `coef_mat'[1, `s'] - `att_pte_mean'
                    local bias_pct = .
                    if abs(`att_pte_mean') > 1e-10 {
                        local bias_pct = `bias_abs' / `att_pte_mean' * 100
                    }
                    di as text "  Spec `s':        " ///
                        %10.6f `coef_mat'[1, `s'] ///
                        "  bias = " %8.4f `bias_abs' ///
                        " (" %6.1f `bias_pct' "%)"
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

    // Method III needs a temporary firm-year panel declaration to evaluate
    // lagged omega controls and optional lagged treatment, but compare is a public
    // postestimation surface and must restore the caller's ambient xtset
    // contract once those lags have been materialized.
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
    
    // Scalars: ATT coefficients
    ereturn scalar att_clk_twfe_1 = `coef_mat'[1, 1]
    ereturn scalar att_clk_twfe_2 = `coef_mat'[1, 2]
    ereturn scalar att_clk_twfe_3 = `coef_mat'[1, 3]
    
    // Scalars: Standard errors
    ereturn scalar se_clk_twfe_1 = `se_mat'[1, 1]
    ereturn scalar se_clk_twfe_2 = `se_mat'[1, 2]
    ereturn scalar se_clk_twfe_3 = `se_mat'[1, 3]
    
    // Scalar: Sample size (from first non-missing spec)
    local N_clk = .
    forvalues s = 1/3 {
        if `n_mat'[1, `s'] != . {
            local N_clk = `n_mat'[1, `s']
            continue, break
        }
    }
    ereturn scalar N_clk_twfe = `N_clk'
    
    // Scalar: Bias vs pte ATT mean
    if `att_pte_mean' != . {
        // Use spec 3 (m9) as primary bias reference (most controlled)
        local bias_ref = .
        if `coef_mat'[1, 3] != . {
            local bias_ref = (`coef_mat'[1, 3] - `att_pte_mean') / `att_pte_mean' * 100
        }
        else if `coef_mat'[1, 1] != . {
            local bias_ref = (`coef_mat'[1, 1] - `att_pte_mean') / `att_pte_mean' * 100
        }
        ereturn scalar bias_clk_twfe = `bias_ref'
    }
    else {
        ereturn scalar bias_clk_twfe = .
    }
    
    // Create alias copies BEFORE ereturn matrix consumes tempnames
    tempname coef_compat se_compat r2_compat n_compat
    matrix `coef_compat' = `coef_mat'
    matrix `se_compat'   = `se_mat'
    matrix `r2_compat'   = `r2_mat'
    matrix `n_compat'    = `n_mat'
    
    // compare_coef/compare_se for chart interface (1x3 matrices)
    tempname compare_coef compare_se
    matrix `compare_coef' = J(1, 3, .)
    matrix `compare_se'   = J(1, 3, .)
    forvalues s = 1/3 {
        matrix `compare_coef'[1, `s'] = `coef_mat'[1, `s']
        matrix `compare_se'[1, `s']   = `se_mat'[1, `s']
    }
    matrix colnames `compare_coef' = spec1 spec2 spec3
    matrix colnames `compare_se'   = spec1 spec2 spec3
    
    // Primary matrices (with underscore: coef_clk_twfe)
    ereturn matrix coef_clk_twfe = `coef_mat'
    ereturn matrix se_clk_twfe   = `se_mat'
    ereturn matrix ci_clk_twfe   = `ci_mat'
    ereturn matrix r2_clk_twfe   = `r2_mat'
    ereturn matrix n_clk_twfe    = `n_mat'
    
    // Alias matrices for _pte_compare_all.ado compatibility (without underscore: coef_clktwfe)
    ereturn matrix coef_clktwfe = `coef_compat'
    ereturn matrix se_clktwfe   = `se_compat'
    ereturn matrix r2_clktwfe   = `r2_compat'
    ereturn matrix n_clktwfe    = `n_compat'
    
    // Chart interface matrices
    ereturn matrix compare_coef = `compare_coef'
    ereturn matrix compare_se   = `compare_se'
    
    // Strings
    ereturn local cmd "pte_compare"
    ereturn local method "clktwfe"
    ereturn local treatment "`treatment'"
    ereturn local absorb "`absorb'"
    ereturn local specs "`specs'"
    if "`lagtreatment'" != "" ereturn local lagtreatment "lagtreatment"
    
end
