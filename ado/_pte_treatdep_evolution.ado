*! _pte_treatdep_evolution.ado
*! Estimates evolution function with treatment interaction terms

version 14.0
capture program drop _pte_treatdep_evolution
program define _pte_treatdep_evolution, eclass
    version 14.0
    local _pte_clear_eclass "capture ereturn clear"
    capture noisily syntax , treatment(name) [omegapoly(integer 3) nodiagnose TOUSE(name)]
    if _rc != 0 {
        local _pte_syntax_rc = _rc
        `_pte_clear_eclass'
        exit `_pte_syntax_rc'
    }
    
    // ================================================================
    // Step 1: Input validation
    // ================================================================
    
    // Validate omegapoly range (1-4)
    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "Error: omegapoly must be 1, 2, 3, or 4"
        di as error "  Specified: omegapoly(`omegapoly')"
        `_pte_clear_eclass'
        exit 198
    }
    
    // Validate required state variables using exact names. The
    // treatment-dependent evolution law still conditions on the structural
    // D_t / omega_t objects from the paper and DOs; shadow-prefix fallback
    // would silently redefine the state path that identifies h_bar_0/h_bar_1.
    capture confirm variable omega, exact
    if _rc != 0 {
        di as error "Error: variable 'omega' not found"
        `_pte_clear_eclass'
        exit 111
    }
    capture confirm numeric variable omega
    if _rc != 0 {
        di as error "Error: variable 'omega' must be numeric"
        `_pte_clear_eclass'
        exit 111
    }

    capture confirm variable `treatment', exact
    if _rc != 0 {
        di as error "Error: treatment variable '`treatment'' not found"
        `_pte_clear_eclass'
        exit 111
    }
    capture confirm numeric variable `treatment'
    if _rc != 0 {
        di as error "Error: treatment variable '`treatment'' must be numeric"
        `_pte_clear_eclass'
        exit 111
    }

    local midvar "_pte_mid"
    capture confirm variable `midvar', exact
    if _rc != 0 {
        local midvar "mid"
        capture confirm variable `midvar', exact
        if _rc != 0 {
            di as error "Error: neither '_pte_mid' nor legacy 'mid' found"
            `_pte_clear_eclass'
            exit 111
        }
    }

    tempvar _pte_sample
    local _pte_last_cmd `"`e(cmd)'"'
    local _pte_inherit_live_sample = inlist("`_pte_last_cmd'", ///
        "_pte_prodfunc", "_pte_omega_recovery", ///
        "_pte_evolution", "_pte_treatdep_evolution", ///
        "_pte_omega", "_pte_eps0_sample", ///
        "_pte_winsorize", "pte")
    if "`touse'" != "" {
        capture confirm variable `touse', exact
        if _rc != 0 {
            di as error "Error: touse variable '`touse'' not found"
            `_pte_clear_eclass'
            exit 111
        }
        capture confirm numeric variable `touse'
        if _rc != 0 {
            di as error "Error: touse variable '`touse'' must be numeric"
            `_pte_clear_eclass'
            exit 111
        }
        qui gen byte `_pte_sample' = (`touse' != 0 & !missing(`touse'))
    }
    else {
        // Live treatdependent reruns must preserve the broader
        // active-sample bridge rather than silently expanding back to the
        // full dataset. Falling back to the narrower e(sample) remains a
        // secondary compatibility path when the persisted bridge variable is
        // unavailable.
        if `_pte_inherit_live_sample' {
            capture confirm variable _pte_active_sample, exact
            if _rc == 0 {
                capture confirm numeric variable _pte_active_sample
                if _rc != 0 {
                    di as error "Error: persisted active sample '_pte_active_sample' must be numeric"
                    `_pte_clear_eclass'
                    exit 111
                }
                qui gen byte `_pte_sample' = (_pte_active_sample != 0 & !missing(_pte_active_sample))
            }
            else {
                if "`_pte_last_cmd'" == "_pte_prodfunc" {
                    // The treatdependent evolution worker has no legitimate
                    // direct e(sample) bridge from. The only valid
                    // producer-side bridge is the exact readiness marker
                    // posted by a fresh _pte_prodfunc run.
                    capture confirm variable _pte_prodfunc_ready, exact
                    if _rc != 0 {
                        di as error "Error: current data are missing the readiness marker '_pte_prodfunc_ready'"
                        di as error "  Re-run _pte_prodfunc before calling _pte_treatdep_evolution"
                        `_pte_clear_eclass'
                        exit 111
                    }
                    capture confirm numeric variable _pte_prodfunc_ready
                    if _rc != 0 {
                        di as error "Error: '_pte_prodfunc_ready' must be numeric"
                        di as error "  Re-run _pte_prodfunc to rebuild the readiness marker"
                        `_pte_clear_eclass'
                        exit 111
                    }
                    qui gen byte `_pte_sample' = (_pte_prodfunc_ready == 1)
                    quietly count if `_pte_sample'
                    if r(N) == 0 {
                        di as error "Error: current data do not contain a live readiness marker on the requested sample"
                        di as error "  Re-run _pte_prodfunc before calling _pte_treatdep_evolution"
                        `_pte_clear_eclass'
                        exit 498
                    }
                }
                else {
                if inlist("`_pte_last_cmd'", "_pte_winsorize", "_pte_eps0_sample", ///
                    "_pte_evolution", "_pte_treatdep_evolution", "_pte_omega", "pte") {
                    di as error "Error: current `_pte_last_cmd' state is missing '_pte_active_sample'"
                    if inlist("`_pte_last_cmd'", "_pte_winsorize", "_pte_eps0_sample") {
                        di as error "  e(sample) from `_pte_last_cmd' is the eps0 shock support,"
                    }
                    else {
                        di as error "  e(sample) from `_pte_last_cmd' is the posted estimation sample,"
                    }
                    di as error "  not the active sample required for treat-dependent evolution reruns"
                    di as error "  Re-run _pte_treatdep_evolution/_pte_omega with touse(), or rebuild '_pte_active_sample'"
                    `_pte_clear_eclass'
                    exit 498
                }
                qui gen byte `_pte_sample' = e(sample)
                }
            }
        }
        else {
            qui gen byte `_pte_sample' = 1
        }
    }

    capture assert inlist(`treatment', 0, 1) if `_pte_sample' & !missing(`treatment')
    if _rc {
        di as error "Error: treatment variable '`treatment'' must be binary (0/1)"
        `_pte_clear_eclass'
        exit 450
    }
    
    // Validate panel structure
    capture noisily _xt, trequired
    if _rc {
        `_pte_clear_eclass'
        exit _rc
    }
    local panelvar = r(ivar)
    local timevar = r(tvar)
    local xtdelta = "`r(tdelta)'"

    capture noisily _pte_validate_mid_contract, midvar(`midvar') ///
        treatment(`treatment') panelvar(`panelvar') timevar(`timevar') ///
        touse(`_pte_sample') context("_pte_treatdep_evolution")
    if _rc != 0 {
        local _pte_mid_contract_rc = _rc
        `_pte_clear_eclass'
        exit `_pte_mid_contract_rc'
    }

    // Preserve the live production-function branch metadata before OLS
    // overwrites e(). Treatdependent evolution is still part of the same
    // production-function pipeline, and downstream eps0 / ATT workers rely
    // on e(pfunc)/e(prodfunc) to keep CD vs translog behavior aligned.
    local pte_prodfunc `"`e(prodfunc)'"'
    local pte_pfunc `"`e(pfunc)'"'
    if `"`pte_prodfunc'"' == "" {
        local pte_prodfunc `"`pte_pfunc'"'
    }
    if `"`pte_pfunc'"' == "" {
        local pte_pfunc `"`pte_prodfunc'"'
    }
    
    tempvar _pte_evo_regsample
    qui gen byte `_pte_evo_regsample' = ///
        (`_pte_sample' & `midvar' == 0 & L.`_pte_sample' == 1)

    // Validate valid observations exist (excluding transition periods)
    // Package contract: mid==0 is in-sample, non-transition; mid==1 is transition; mid==. is out-of-sample/undefined.
    qui count if `_pte_evo_regsample' & !missing(omega, `treatment', L.omega, L.`treatment')
    if r(N) == 0 {
        di as error "Error: no valid observations after excluding transition periods"
        `_pte_clear_eclass'
        exit 2001
    }

    qui count if `_pte_evo_regsample' & !missing(omega, `treatment', L.omega, L.`treatment') & L.`treatment' == 0
    local N_lag_untreated = r(N)
    qui count if `_pte_evo_regsample' & !missing(omega, `treatment', L.omega, L.`treatment') & L.`treatment' == 1
    local N_lag_treated = r(N)
    local lag_treated_supported = (`N_lag_treated' > 0)

    // Proposition 4.3 only needs the untreated evolution law h_bar_0.
    // Lack of treated stayer support should not block the h_bar_0-only
    // fallback, but lack of untreated lag support makes h_bar_0 unidentified.
    if `N_lag_untreated' == 0 {
        di as error "Error: untreated lag support is required to identify h_bar_0"
        di as error "  Non-transition untreated lag rows: `N_lag_untreated'"
        di as error "  Non-transition treated lag rows:   `N_lag_treated'"
        `_pte_clear_eclass'
        exit 498
    }
    
    // ================================================================
    // Step 2: Clean existing variables (each separately to avoid
    //         partial failure when some don't exist)
    // ================================================================
    cap drop omega2
    cap drop omega3
    cap drop omega4
    cap drop omega_tp
    cap drop omega2_tp
    cap drop omega3_tp
    cap drop omega4_tp
    
    // ================================================================
    // Step 3: Generate high-order terms (ref: L25-26)
    // ================================================================
    if `omegapoly' >= 2 {
        qui gen double omega2 = omega^2
        label var omega2 "omega squared"
    }
    if `omegapoly' >= 3 {
        qui gen double omega3 = omega^3
        label var omega3 "omega cubed"
    }
    if `omegapoly' >= 4 {
        qui gen double omega4 = omega^4
        label var omega4 "omega to the fourth"
    }
    
    // ================================================================
    // Step 4: Generate interaction terms (ref: L27-29)
    // Current-period definition: omega_tp = omega * treatment
    // In regression, L.omega_tp = omega_{t-1} * D_{t-1}
    // ================================================================
    qui gen double omega_tp = omega * `treatment'
    label var omega_tp "omega x treatment"
    
    if `omegapoly' >= 2 {
        qui gen double omega2_tp = omega2 * `treatment'
        label var omega2_tp "omega2 x treatment"
    }
    if `omegapoly' >= 3 {
        qui gen double omega3_tp = omega3 * `treatment'
        label var omega3_tp "omega3 x treatment"
    }
    if `omegapoly' >= 4 {
        qui gen double omega4_tp = omega4 * `treatment'
        label var omega4_tp "omega4 x treatment"
    }
    
    // ================================================================
    // Step 5: Build regression variable list (ref: L30)
    // Order: main effects -> interaction terms -> treatment indicator
    // ================================================================
    local main_vars "L.omega"
    if `omegapoly' >= 2 local main_vars "`main_vars' L.omega2"
    if `omegapoly' >= 3 local main_vars "`main_vars' L.omega3"
    if `omegapoly' >= 4 local main_vars "`main_vars' L.omega4"
    
    local int_vars "L.omega_tp"
    if `omegapoly' >= 2 local int_vars "`int_vars' L.omega2_tp"
    if `omegapoly' >= 3 local int_vars "`int_vars' L.omega3_tp"
    if `omegapoly' >= 4 local int_vars "`int_vars' L.omega4_tp"
    
    local varlist "`main_vars' `int_vars' L.`treatment'"
    
    // ================================================================
    // Step 6: Execute evolution regression (ref: L30)
    // CRITICAL: exclude transition periods (package contract: mid == 0)
    // ================================================================
    capture qui reg omega `varlist' if `_pte_evo_regsample'
    if _rc {
        if _rc == 503 {
            di as error "Error: evolution regression failed due to collinearity"
            di as error "  Check for perfect collinearity between variables"
        }
        else {
            di as error "Error: evolution regression failed (error code " _rc ")"
        }
        `_pte_clear_eclass'
        exit _rc
    }

    local lag_treated_supported_raw = `lag_treated_supported'
    local ebnames : colnames e(b)
    if `lag_treated_supported_raw' {
        local treated_terms_omitted = 0
        if strpos("`ebnames'", "oL.omega_tp") > 0 {
            local treated_terms_omitted = 1
        }
        if `omegapoly' >= 2 & strpos("`ebnames'", "oL.omega2_tp") > 0 {
            local treated_terms_omitted = 1
        }
        if `omegapoly' >= 3 & strpos("`ebnames'", "oL.omega3_tp") > 0 {
            local treated_terms_omitted = 1
        }
        if `omegapoly' >= 4 & strpos("`ebnames'", "oL.omega4_tp") > 0 {
            local treated_terms_omitted = 1
        }
        if strpos("`ebnames'", "oL.`treatment'") > 0 {
            local treated_terms_omitted = 1
        }
        if `treated_terms_omitted' {
            local lag_treated_supported = 0
        }
    }

    if `lag_treated_supported_raw' & !`lag_treated_supported' & "`nodiagnose'" == "" {
        di as text "{bf:Warning}: treated-side regressors were omitted in the pooled OLS fit"
        di as text "          h_bar_0 remains estimable, but the treated evolution law is not identified."
        di as text "          e(rho_1), e(gamma#), e(delta), and e(rho) will not be posted."
    }
    
    local N_evo = e(N)
    local r2 = e(r2)
    local rmse = e(rmse)

    // Persist the broader active-sample boundary for downstream
    // bridge workers. Using only e(sample) would force _pte_eps0_sample to
    // reapply the lag gate to the already-trimmed regression sample and drop
    // admissible untreated pre-treatment rows from the eps0 pool.
    capture drop _pte_active_sample
    qui gen byte _pte_active_sample = `_pte_sample'
    label var _pte_active_sample "omega recovery active sample indicator"
    
    // ================================================================
    // Step 7: Extract coefficients (ref: L31-38)
    // ================================================================
    tempname rho0 rho1 rho2 rho3 rho4
    tempname gamma1 gamma2 gamma3 gamma4 delta
    
    // Intercept
    scalar `rho0' = _b[_cons]
    
    // Main effect coefficients
    scalar `rho1' = _b[L.omega]
    if `omegapoly' >= 2 scalar `rho2' = _b[L.omega2]
    if `omegapoly' >= 3 scalar `rho3' = _b[L.omega3]
    if `omegapoly' >= 4 scalar `rho4' = _b[L.omega4]
    
    // Interaction coefficients are only meaningful when the treated-side
    // regressors survived the live OLS fit. If Stata omits any treated-side
    // term, h_bar_1 is not identified and must not be published downstream.
    if `lag_treated_supported' {
        scalar `gamma1' = _b[L.omega_tp]
        if `omegapoly' >= 2 scalar `gamma2' = _b[L.omega2_tp]
        if `omegapoly' >= 3 scalar `gamma3' = _b[L.omega3_tp]
        if `omegapoly' >= 4 scalar `gamma4' = _b[L.omega4_tp]
        scalar `delta' = _b[L.`treatment']
    }
    else {
        scalar `gamma1' = .
        if `omegapoly' >= 2 scalar `gamma2' = .
        if `omegapoly' >= 3 scalar `gamma3' = .
        if `omegapoly' >= 4 scalar `gamma4' = .
        scalar `delta' = .
    }
    
    // ================================================================
    // Step 8: Construct e(rho_0) matrix - ONLY rho parameters
    // This is the KEY interface for counterfactual simulation
    // e(rho_0) contains ONLY the untreated evolution h_bar_0
    // ================================================================
    tempname rho_0 rho_1 rho_full
    
    if `omegapoly' == 1 {
        matrix `rho_0' = (`rho0', `rho1')
        matrix colnames `rho_0' = _cons omega
        
        if `lag_treated_supported' {
            matrix `rho_1' = (`rho0'+`delta', `rho1'+`gamma1')
            matrix colnames `rho_1' = _cons omega
            matrix `rho_full' = (`rho0', `rho1', `gamma1', `delta')
            matrix colnames `rho_full' = rho0 rho1 gamma1 delta
        }
    }
    else if `omegapoly' == 2 {
        matrix `rho_0' = (`rho0', `rho1', `rho2')
        matrix colnames `rho_0' = _cons omega omega2
        
        if `lag_treated_supported' {
            matrix `rho_1' = (`rho0'+`delta', `rho1'+`gamma1', `rho2'+`gamma2')
            matrix colnames `rho_1' = _cons omega omega2
            matrix `rho_full' = (`rho0', `rho1', `rho2', `gamma1', `gamma2', `delta')
            matrix colnames `rho_full' = rho0 rho1 rho2 gamma1 gamma2 delta
        }
    }
    else if `omegapoly' == 3 {
        matrix `rho_0' = (`rho0', `rho1', `rho2', `rho3')
        matrix colnames `rho_0' = _cons omega omega2 omega3
        
        if `lag_treated_supported' {
            matrix `rho_1' = (`rho0'+`delta', `rho1'+`gamma1', `rho2'+`gamma2', `rho3'+`gamma3')
            matrix colnames `rho_1' = _cons omega omega2 omega3
            matrix `rho_full' = (`rho0', `rho1', `rho2', `rho3', `gamma1', `gamma2', `gamma3', `delta')
            matrix colnames `rho_full' = rho0 rho1 rho2 rho3 gamma1 gamma2 gamma3 delta
        }
    }
    else if `omegapoly' == 4 {
        matrix `rho_0' = (`rho0', `rho1', `rho2', `rho3', `rho4')
        matrix colnames `rho_0' = _cons omega omega2 omega3 omega4
        
        if `lag_treated_supported' {
            matrix `rho_1' = (`rho0'+`delta', `rho1'+`gamma1', `rho2'+`gamma2', `rho3'+`gamma3', `rho4'+`gamma4')
            matrix colnames `rho_1' = _cons omega omega2 omega3 omega4
            matrix `rho_full' = (`rho0', `rho1', `rho2', `rho3', `rho4', `gamma1', `gamma2', `gamma3', `gamma4', `delta')
            matrix colnames `rho_full' = rho0 rho1 rho2 rho3 rho4 gamma1 gamma2 gamma3 gamma4 delta
        }
    }
    
    // ================================================================
    // Step 9: Set ereturn values
    // Rebuild e() from the live OLS payload so unsupported paths cannot leak
    // stale treated-side objects from a prior successful run.
    // ================================================================

    tempname b V
    tempvar esample
    matrix `b' = e(b)
    matrix `V' = e(V)
    qui gen byte `esample' = e(sample)
    ereturn post `b' `V', esample(`esample')
    
    // Scalar returns - main effect coefficients
    ereturn scalar rho0 = `rho0'
    ereturn scalar rho1 = `rho1'
    if `omegapoly' >= 2 ereturn scalar rho2 = `rho2'
    if `omegapoly' >= 3 ereturn scalar rho3 = `rho3'
    if `omegapoly' >= 4 ereturn scalar rho4 = `rho4'
    
    // Scalar returns - interaction coefficients
    if `lag_treated_supported' {
        ereturn scalar gamma1 = `gamma1'
        if `omegapoly' >= 2 ereturn scalar gamma2 = `gamma2'
        if `omegapoly' >= 3 ereturn scalar gamma3 = `gamma3'
        if `omegapoly' >= 4 ereturn scalar gamma4 = `gamma4'
        ereturn scalar delta = `delta'
    }
    
    // Scalar returns - treatment effect and metadata
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar N_evo = `N_evo'
    ereturn scalar N_lag_untreated = `N_lag_untreated'
    ereturn scalar N_lag_treated = `N_lag_treated'
    ereturn scalar lag_treated_supported = `lag_treated_supported'
    ereturn scalar r2 = `r2'
    ereturn scalar rmse = `rmse'
    
    // Matrix returns
    ereturn matrix rho_0 = `rho_0'
    if `lag_treated_supported' {
        ereturn matrix rho_1 = `rho_1'
        ereturn matrix rho = `rho_full'
    }

    local pte_treatsig ""
    capture quietly _pte_treatment_signature, ///
        panelvar(`panelvar') timevar(`timevar') treatment(`treatment')
    if _rc == 0 {
        local pte_treatsig `"`r(signature)'"'
    }
    
    // Mode identifier
    ereturn local treatdependent "1"
    ereturn local treatment "`treatment'"
    ereturn local treatsig `"`pte_treatsig'"'
    ereturn local pfunc `"`pte_pfunc'"'
    ereturn local prodfunc `"`pte_prodfunc'"'
    ereturn local id "`panelvar'"
    ereturn local time "`timevar'"
    ereturn local idvar "`panelvar'"
    ereturn local timevar "`timevar'"
    local xtdelta_num = real("`xtdelta'")
    if !missing(`xtdelta_num') {
        ereturn scalar xtdelta = `xtdelta_num'
    }
    ereturn local cmd "_pte_treatdep_evolution"
    ereturn local title "Treatment-dependent evolution regression"
    
    // ================================================================
    // Step 10: Display results (unless nodiagnose)
    // ================================================================
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "Treatment-dependent evolution regression (omegapoly = `omegapoly'):"
        di as text "  N (excluding transitions) = " as result `N_evo'
        di as text ""
        di as text "  Untreated evolution (h_bar_0) coefficients:"
        di as text "    rho0 (intercept) = " as result %9.6f `rho0'
        di as text "    rho1 (linear)    = " as result %9.6f `rho1'
        if `omegapoly' >= 2 di as text "    rho2 (quadratic) = " as result %9.6f `rho2'
        if `omegapoly' >= 3 di as text "    rho3 (cubic)     = " as result %9.6f `rho3'
        if `omegapoly' >= 4 di as text "    rho4 (quartic)   = " as result %9.6f `rho4'
        di as text ""
        if `lag_treated_supported' {
            di as text "  Treatment interaction coefficients:"
            di as text "    gamma1 = " as result %9.6f `gamma1'
            if `omegapoly' >= 2 di as text "    gamma2 = " as result %9.6f `gamma2'
            if `omegapoly' >= 3 di as text "    gamma3 = " as result %9.6f `gamma3'
            if `omegapoly' >= 4 di as text "    gamma4 = " as result %9.6f `gamma4'
            di as text ""
            di as text "  Treatment effect (delta) = " as result %9.6f `delta'
        }
        else {
            di as text "  Treated evolution law:   not identified (treated-side regressor omitted)"
            di as text "  Published state:         h_bar_0 only; no e(rho_1)/e(gamma#)/e(delta)"
        }
        di as text ""
        di as text "  Note: e(rho_0) contains ONLY rho0~rho`omegapoly' for counterfactual simulation"
    }
    
end
