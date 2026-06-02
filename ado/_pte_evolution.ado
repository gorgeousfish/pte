*! _pte_evolution.ado
*! Internal evolution-law estimator for realized productivity paths.

version 14.0
capture program drop _pte_evolution
program define _pte_evolution, eclass
    version 14.0
    
    // Preserve the caller's e() state and any live omega variable so this
    // helper can fail closed without corrupting the surrounding pipeline.
    tempname _pte_prev_est
    tempvar _pte_prev_omega
    local _pte_has_prev_est = 0
    local _pte_has_prev_omega = 0
    capture estimates store `_pte_prev_est', copy
    if _rc == 0 {
        local _pte_has_prev_est = 1
    }
    capture confirm variable omega, exact
    if _rc == 0 {
        quietly clonevar `_pte_prev_omega' = omega
        local _pte_has_prev_omega = 1
    }
    local _pte_clear_eclass ///
        "quietly _pte_restore_prev_est, estname(`_pte_prev_est') hasest(`_pte_has_prev_est') omegabackup(`_pte_prev_omega') hasomega(`_pte_has_prev_omega')"
    local _pte_clear_outputs "capture drop _pte_omega_hat"
    capture noisily syntax, treatment(name) [omegapoly(integer 3) pfunc(string) NODIAGnose TOUSE(name)]
    if _rc != 0 {
        local _pte_syntax_rc = _rc
        `_pte_clear_outputs'
        `_pte_clear_eclass'
        exit `_pte_syntax_rc'
    }
    // _pte_omega_hat is a live output of the current evolution fit. Clear any
    // stale copy before validation so failed reruns cannot leave an old hat
    // behind while e() has already been invalidated.
    `_pte_clear_outputs'
    
    // The package only advertises polynomial orders that the ATT simulators
    // and eps0 recovery layer know how to consume.
    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "[pte] Error: omegapoly must be 1, 2, 3, or 4"
        di as error "[pte]        Specified: omegapoly(`omegapoly')"
        `_pte_clear_eclass'
        exit 198
    }
    
    // Exact-name confirmation prevents Stata from abbreviating omega to one
    // of the temporary omega_* regressors created later in this routine.
    capture confirm variable omega, exact
    if _rc != 0 {
        di as error "[pte] Error: variable 'omega' not found or not numeric"
        di as error "[pte] Please run _pte_omega_recovery first"
        `_pte_clear_eclass'
        exit 111
    }

    capture confirm numeric variable omega
    if _rc != 0 {
        di as error "[pte] Error: variable 'omega' not found or not numeric"
        di as error "[pte] Please run _pte_omega_recovery first"
        `_pte_clear_eclass'
        exit 111
    }
    
    // Preserve the literal treatment() token until the exact-name check.
    capture confirm variable `treatment', exact
    if _rc != 0 {
        di as error "[pte] Error: treatment variable '`treatment'' not found"
        `_pte_clear_eclass'
        exit 111
    }
    capture confirm numeric variable `treatment'
    if _rc != 0 {
        di as error "[pte] Error: treatment variable '`treatment'' must be numeric"
        `_pte_clear_eclass'
        exit 111
    }

    tempvar _pte_sample
    local _pte_last_cmd `"`e(cmd)'"'
    local _pte_inherit_live_sample = inlist("`_pte_last_cmd'", ///
        "_pte_prodfunc", "_pte_omega_recovery", ///
        "_pte_evolution", "_pte_treatdep_evolution", ///
        "_pte_omega", "_pte_eps0_sample", "_pte_winsorize", "pte")
    if "`touse'" != "" {
        capture confirm variable `touse', exact
        if _rc != 0 {
            di as error "[pte] Error: touse variable '`touse'' not found"
            `_pte_clear_eclass'
            exit 111
        }
        capture confirm numeric variable `touse'
        if _rc != 0 {
            di as error "[pte] Error: touse variable '`touse'' must be numeric"
            `_pte_clear_eclass'
            exit 111
        }
        quietly gen byte `_pte_sample' = (`touse' != 0 & !missing(`touse'))
    }
    else {
        // Live reruns must inherit the previously posted active sample.
        // Falling back to the full dataset would change h_bar_0 and the
        // untreated shock support used later for counterfactual simulation.
        if `_pte_inherit_live_sample' {
            capture confirm variable _pte_active_sample, exact
            if _rc == 0 {
                capture confirm numeric variable _pte_active_sample
                if _rc != 0 {
                    di as error "[pte] Error: persisted active sample '_pte_active_sample' must be numeric"
                    di as error "[pte]        Re-run _pte_evolution or _pte_omega to rebuild the bridge state"
                    `_pte_clear_eclass'
                    exit 111
                }
                quietly gen byte `_pte_sample' = (_pte_active_sample != 0 & !missing(_pte_active_sample))
            }
            else {
                if "`_pte_last_cmd'" == "_pte_prodfunc" {
                    capture confirm variable phi, exact
                    if _rc != 0 {
                        di as error "[pte] Error: direct _pte_prodfunc bridge requires variable 'phi'"
                        di as error "[pte]        active sample must inherit the recoverable phi support"
                        di as error "[pte]        Re-run _pte_prodfunc, or call _pte_evolution with touse()"
                        `_pte_clear_eclass'
                        exit 111
                    }
                    capture confirm numeric variable phi
                    if _rc != 0 {
                        di as error "[pte] Error: direct _pte_prodfunc bridge requires numeric variable 'phi'"
                        di as error "[pte]        active sample must inherit the recoverable phi support"
                        `_pte_clear_eclass'
                        exit 111
                    }
                    capture confirm variable _pte_prodfunc_ready, exact
                    if _rc != 0 {
                        di as error "[pte] Error: current data are missing the readiness marker '_pte_prodfunc_ready'"
                        di as error "[pte]        Re-run _pte_prodfunc before calling _pte_evolution"
                        `_pte_clear_eclass'
                        exit 111
                    }
                    capture confirm numeric variable _pte_prodfunc_ready
                    if _rc != 0 {
                        di as error "[pte] Error: '_pte_prodfunc_ready' must be numeric"
                        di as error "[pte]        Re-run _pte_prodfunc to rebuild the readiness marker"
                        `_pte_clear_eclass'
                        exit 111
                    }
                    // _pte_prodfunc posts the narrow stable GMM sample in
                    // e(sample), but evolution needs the broader support on
                    // which omega can be recovered. Restricting by the
                    // readiness marker keeps that bridge explicit.
                    quietly gen byte `_pte_sample' = ///
                        (_pte_prodfunc_ready == 1 & !missing(_pte_prodfunc_ready))
                    quietly count if `_pte_sample' & _pte_prodfunc_ready == 1
                    if r(N) == 0 {
                        di as error "[pte] Error: current data do not contain a live readiness marker on the requested sample"
                        di as error "[pte]        Re-run _pte_prodfunc before calling _pte_evolution"
                        `_pte_clear_eclass'
                        exit 498
                    }
                }
                else {
                if inlist("`_pte_last_cmd'", "_pte_winsorize", "_pte_eps0_sample", ///
                    "_pte_evolution", "_pte_treatdep_evolution", "_pte_omega", "pte") {
                    di as error "[pte] Error: current `_pte_last_cmd' state is missing '_pte_active_sample'"
                    if inlist("`_pte_last_cmd'", "_pte_winsorize", "_pte_eps0_sample") {
                        di as error "[pte]        e(sample) from `_pte_last_cmd' is the eps0 shock support,"
                    }
                    else {
                        di as error "[pte]        e(sample) from `_pte_last_cmd' is the posted estimation sample,"
                    }
                    di as error "[pte]        not the active sample required for evolution reruns"
                    di as error "[pte]        Re-run _pte_omega/_pte_evolution with touse(), or rebuild '_pte_active_sample'"
                    `_pte_clear_eclass'
                    exit 498
                }
                quietly gen byte `_pte_sample' = e(sample)
                }
            }
        }
        else {
            quietly gen byte `_pte_sample' = 1
        }
    }

    quietly count if `_pte_sample'
    if r(N) == 0 {
        di as error "[pte] Error: touse() excludes all observations"
        `_pte_clear_eclass'
        exit 2000
    }
    
    // Binary treatment is required only on the live working sample. Values
    // outside touse() must not veto an otherwise valid rerun.
    capture assert inlist(`treatment', 0, 1) if `_pte_sample' & !missing(`treatment')
    if _rc {
        di as error "[pte] Error: treatment variable '`treatment'' must be binary (0/1)"
        di as error "[pte]        Found values outside {0, 1}"
        `_pte_clear_eclass'
        exit 450
    }
    
    local midvar "_pte_mid"
    capture confirm variable `midvar', exact
    if _rc != 0 {
        local midvar "mid"
        capture confirm variable `midvar', exact
        if _rc != 0 {
            di as error "[pte] Error: neither '_pte_mid' nor legacy 'mid' found from production function estimation"
            `_pte_clear_eclass'
            exit 111
        }
    }

    capture confirm numeric variable `midvar'
    if _rc != 0 {
        di as error "[pte] Error: transition indicator '`midvar'' must be numeric"
        di as error "[pte] Please run _pte_transition again to rebuild the switch indicator"
        `_pte_clear_eclass'
        exit 111
    }
    
    capture _xt, trequired
    if _rc != 0 {
        di as error "[pte] Error: data must be xtset as panel"
        `_pte_clear_eclass'
        exit 459
    }
    local panelvar = r(ivar)
    local timevar = r(tvar)
    local xtdelta = "`r(tdelta)'"

    capture noisily _pte_validate_mid_contract, midvar(`midvar') ///
        treatment(`treatment') panelvar(`panelvar') timevar(`timevar') ///
        touse(`_pte_sample') context("_pte_evolution")
    if _rc != 0 {
        local _pte_mid_contract_rc = _rc
        `_pte_clear_eclass'
        exit `_pte_mid_contract_rc'
    }
    
    // The evolution law is shared by both production-function branches, but
    // downstream helpers still rely on the branch tag stored in e().
    if "`pfunc'" == "" {
        // The evolution equation is numerically independent of the
        // production-function branch, but downstream workers consume the
        // live branch metadata from e(). Preserve that state when available.
        local pfunc `"`e(prodfunc)'"'
        if "`pfunc'" == "" {
            local pfunc `"`e(pfunc)'"'
        }
        if "`pfunc'" == "" {
            local pfunc "cd"
        }
    }
    
    if !inlist("`pfunc'", "cd", "translog") {
        di as error "[pte] Error: pfunc must be 'cd' or 'translog'"
        di as error "[pte]        Specified: pfunc(`pfunc')"
        `_pte_clear_eclass'
        exit 198
    }
    
    // Theorem 3.1 is implemented on non-transition rows only. Lagged terms
    // must also stay inside the active sample so current rows cannot borrow
    // L.omega or L.D from observations outside the live contract.
    tempvar _pte_evo_regsample
    quietly gen byte `_pte_evo_regsample' = ///
        (`_pte_sample' & `midvar' == 0 & L.`_pte_sample' == 1)
    quietly count if `_pte_evo_regsample' & !missing(omega, `treatment') ///
        & !missing(L.omega, L.`treatment')
    if r(N) == 0 {
        di as error "[pte] Error: no valid observations after excluding transition periods"
        `_pte_clear_eclass'
        exit 2001
    }
    local n_valid = r(N)
    quietly count if `_pte_evo_regsample' & !missing(omega, `treatment') ///
        & !missing(L.omega, L.`treatment') & L.`treatment' == 0
    local n_lag_untreated = r(N)
    quietly count if `_pte_evo_regsample' & !missing(omega, `treatment') ///
        & !missing(L.omega, L.`treatment') & L.`treatment' == 1
    local n_lag_treated = r(N)
    if `n_lag_untreated' == 0 {
        di as error "[pte] Error: evolution regression requires untreated lag support"
        di as error "[pte]        Lag untreated support (D_{t-1}=0): `n_lag_untreated'"
        di as error "[pte]        Lag treated support (D_{t-1}=1):   `n_lag_treated'"
        di as error "[pte]        h_bar_0 is not identified without non-transition untreated lags"
        di as error "[pte]        Check touse(), panel lags, or missing values in omega/treatment"
        `_pte_clear_eclass'
        exit 498
    }

    local lag_treated_supported = (`n_lag_treated' > 0)
    if !`lag_treated_supported' & "`nodiagnose'" == "" {
        di as text "{bf:Warning}: evolution regression has no non-transition treated lag support"
        di as text "          Assumption 3.3 / Theorem 3.1 do not identify h_bar_1 on this sample."
        di as text "          The pooled OLS fit continues so h_bar_0 can still be used for eps0 recovery"
        di as text "          and Proposition 4.3 counterfactual simulation; treated-law returns are omitted."
    }
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "Evolution Regression"
        di as text "{hline 60}"
        di as text "  Polynomial order:    " as result %10.0f `omegapoly'
        di as text "  Treatment variable:  " as result %10s "`treatment'"
    }
    
    local omega2_var "_pte_omega2"
    local omega3_var "_pte_omega3"
    local omega4_var "_pte_omega4"
    local omega_tp_var "_pte_omega_tp"
    local omega2_tp_var "_pte_omega2_tp"
    local omega3_tp_var "_pte_omega3_tp"
    local omega4_tp_var "_pte_omega4_tp"

    // Temporary regressors carry a private prefix so they cannot collide
    // with user variables or helper output from adjacent stages.
    if `omegapoly' >= 2 {
        capture drop `omega2_var'
        quietly gen double `omega2_var' = omega^2
        label variable `omega2_var' "omega squared"
    }
    
    if `omegapoly' >= 3 {
        capture drop `omega3_var'
        quietly gen double `omega3_var' = omega^3
        label variable `omega3_var' "omega cubed"
    }
    
    if `omegapoly' >= 4 {
        capture drop `omega4_var'
        quietly gen double `omega4_var' = omega^4
        label variable `omega4_var' "omega to the fourth"
    }
    
    // Interaction regressors parameterize the treated law h_bar_1 relative
    // to the untreated law h_bar_0 through lagged treatment status.
    capture drop `omega_tp_var'
    quietly gen double `omega_tp_var' = omega * `treatment'
    label variable `omega_tp_var' "omega × treatment"
    
    if `omegapoly' >= 2 {
        capture drop `omega2_tp_var'
        quietly gen double `omega2_tp_var' = `omega2_var' * `treatment'
        label variable `omega2_tp_var' "omega2 × treatment"
    }
    
    if `omegapoly' >= 3 {
        capture drop `omega3_tp_var'
        quietly gen double `omega3_tp_var' = `omega3_var' * `treatment'
        label variable `omega3_tp_var' "omega3 × treatment"
    }
    
    if `omegapoly' >= 4 {
        capture drop `omega4_tp_var'
        quietly gen double `omega4_tp_var' = `omega4_var' * `treatment'
        label variable `omega4_tp_var' "omega4 × treatment"
    }
    
    // Column order is preserved so downstream coefficient extraction can map
    // main terms to rho and interaction terms to gamma without ambiguity.
    local main_vars "L.omega"
    local int_vars "L.`omega_tp_var'"
    
    if `omegapoly' >= 2 {
        local main_vars "`main_vars' L.`omega2_var'"
        local int_vars "`int_vars' L.`omega2_tp_var'"
    }
    
    if `omegapoly' >= 3 {
        local main_vars "`main_vars' L.`omega3_var'"
        local int_vars "`int_vars' L.`omega3_tp_var'"
    }
    
    if `omegapoly' >= 4 {
        local main_vars "`main_vars' L.`omega4_var'"
        local int_vars "`int_vars' L.`omega4_tp_var'"
    }
    
    local varlist "`main_vars' `int_vars' L.`treatment'"
    
    // reg omega ... if mid!=1 in the DOs assumes a pre-trimmed dataset.
    // In the package, only `midvar' == 0 is admissible because `midvar' == .
    // denotes observations outside the active estimation sample, and lagged
    // regressors must also come from rows with touse()==1.
    capture quietly reg omega `varlist' if `_pte_evo_regsample'
    if _rc != 0 {
        di as error "[pte] Error: evolution regression failed (rc = " _rc ")"
        `_pte_clear_eclass'
        exit _rc
    }

    local lag_treated_supported_raw = (`n_lag_treated' > 0)
    local lag_treated_effective = `lag_treated_supported_raw'
    local ebnames : colnames e(b)

    // Requested untreated polynomial terms define h_bar_0 itself. If Stata
    // omits one of them, the advertised omegapoly() contract is no longer
    // the law used for eps0 recovery or ATT simulation.
    local untreated_terms_omitted 0
    local untreated_omitted_terms ""
    local omitted_L_omega 0
    local omitted_L_omega2 0
    local omitted_L_omega3 0
    local omitted_L_omega4 0
    local omitted_L_omega_tp 0
    local omitted_L_omega2_tp 0
    local omitted_L_omega3_tp 0
    local omitted_L_omega4_tp 0
    local omitted_L_treat 0
    foreach nm of local ebnames {
        if "`nm'" == "oL.omega" {
            local omitted_L_omega 1
        }
        if `omegapoly' >= 2 & "`nm'" == "oL.`omega2_var'" {
            local omitted_L_omega2 1
        }
        if `omegapoly' >= 3 & "`nm'" == "oL.`omega3_var'" {
            local omitted_L_omega3 1
        }
        if `omegapoly' >= 4 & "`nm'" == "oL.`omega4_var'" {
            local omitted_L_omega4 1
        }
        if "`nm'" == "oL.`omega_tp_var'" {
            local omitted_L_omega_tp 1
        }
        if `omegapoly' >= 2 & "`nm'" == "oL.`omega2_tp_var'" {
            local omitted_L_omega2_tp 1
        }
        if `omegapoly' >= 3 & "`nm'" == "oL.`omega3_tp_var'" {
            local omitted_L_omega3_tp 1
        }
        if `omegapoly' >= 4 & "`nm'" == "oL.`omega4_tp_var'" {
            local omitted_L_omega4_tp 1
        }
        if "`nm'" == "oL.`treatment'" {
            local omitted_L_treat 1
        }
    }
    if `omitted_L_omega' {
        local untreated_terms_omitted 1
        local untreated_omitted_terms "`untreated_omitted_terms' L.omega"
    }
    if `omitted_L_omega2' {
        local untreated_terms_omitted 1
        local untreated_omitted_terms "`untreated_omitted_terms' L.omega2"
    }
    if `omitted_L_omega3' {
        local untreated_terms_omitted 1
        local untreated_omitted_terms "`untreated_omitted_terms' L.omega3"
    }
    if `omitted_L_omega4' {
        local untreated_terms_omitted 1
        local untreated_omitted_terms "`untreated_omitted_terms' L.omega4"
    }
    if `untreated_terms_omitted' {
        di as error "[pte] Error: requested untreated evolution terms were omitted in the live OLS fit"
        di as error "[pte]        Omitted h_bar_0 terms:`untreated_omitted_terms'"
        di as error "[pte]        Requested omegapoly(`omegapoly') is not identified on the current sample"
        di as error "[pte]        Rebuild omega on a sample with richer untreated support or lower omegapoly()"
        `_pte_clear_eclass'
        exit 498
    }

    if `lag_treated_supported_raw' {
        local treated_terms_omitted = 0
        if `omitted_L_omega_tp' {
            local treated_terms_omitted = 1
        }
        if `omitted_L_omega2_tp' {
            local treated_terms_omitted = 1
        }
        if `omitted_L_omega3_tp' {
            local treated_terms_omitted = 1
        }
        if `omitted_L_omega4_tp' {
            local treated_terms_omitted = 1
        }
        if `omitted_L_treat' {
            local treated_terms_omitted = 1
        }
        if `treated_terms_omitted' {
            local lag_treated_effective = 0
        }
    }
    local lag_treated_supported = `lag_treated_effective'
    if `lag_treated_supported_raw' & !`lag_treated_effective' & "`nodiagnose'" == "" {
        di as text "{bf:Warning}: treated-side regressors were omitted in the pooled OLS fit"
        di as text "          h_bar_0 remains estimable, but the treated evolution law is not identified."
        di as text "          e(rho_1), e(gamma#), and e(delta) will not be posted."
    }
    
    local N_evo = e(N)
    local r2 = e(r2)
    local rmse = e(rmse)
    
    // The fitted realized law is persisted because eps0 is defined as the
    // realized residual from this regression on the admissible sample.
    capture drop _pte_omega_hat
    quietly predict double _pte_omega_hat if e(sample), xb
    label variable _pte_omega_hat "Evolution regression predicted omega"

    // Publish the active-sample marker only after the current rerun has
    // passed every identification gate. Failed reruns must not overwrite
    // the last successful bridge that later stages rely on.
    capture drop _pte_active_sample
    quietly gen byte _pte_active_sample = `_pte_sample'
    label variable _pte_active_sample "omega recovery active sample indicator"
    
    // rho_j parameterize h_bar_0; gamma_j and delta tilt that law into
    // h_bar_1 when treated-lag support is actually identified.
    scalar _pte_rho0 = _b[_cons]
    scalar _pte_rho1 = _b[L.omega]
    
    if `omegapoly' >= 2 {
        scalar _pte_rho2 = _b[L.`omega2_var']
    }
    
    if `omegapoly' >= 3 {
        scalar _pte_rho3 = _b[L.`omega3_var']
    }
    
    if `omegapoly' >= 4 {
        scalar _pte_rho4 = _b[L.`omega4_var']
    }
    
    // Leave treated-side parameters missing when h_bar_1 is not identified.
    // Posting stale or partial treated coefficients would mislead ATT code
    // about what can be simulated from the current sample.
    if `lag_treated_supported' {
        scalar _pte_gamma1 = _b[L.`omega_tp_var']
        
        if `omegapoly' >= 2 {
            scalar _pte_gamma2 = _b[L.`omega2_tp_var']
        }
        
        if `omegapoly' >= 3 {
            scalar _pte_gamma3 = _b[L.`omega3_tp_var']
        }
        
        if `omegapoly' >= 4 {
            scalar _pte_gamma4 = _b[L.`omega4_tp_var']
        }
        
        scalar _pte_delta = _b[L.`treatment']
    }
    else {
        scalar _pte_gamma1 = .
        if `omegapoly' >= 2 {
            scalar _pte_gamma2 = .
        }
        if `omegapoly' >= 3 {
            scalar _pte_gamma3 = .
        }
        if `omegapoly' >= 4 {
            scalar _pte_gamma4 = .
        }
        scalar _pte_delta = .
    }
    
    // rho_0 and rho_1 store the untreated and treated transition laws in the
    // exact shape expected by downstream simulation code.
    if `omegapoly' == 1 {
        matrix _pte_rho_0 = (_pte_rho0, _pte_rho1)
        matrix colnames _pte_rho_0 = rho0 rho1
        if `lag_treated_supported' {
            matrix _pte_rho_1 = (_pte_rho0 + _pte_delta, _pte_rho1 + _pte_gamma1)
            matrix colnames _pte_rho_1 = rho0_d rho1_g1
        }
    }
    else if `omegapoly' == 2 {
        matrix _pte_rho_0 = (_pte_rho0, _pte_rho1, _pte_rho2)
        matrix colnames _pte_rho_0 = rho0 rho1 rho2
        if `lag_treated_supported' {
            matrix _pte_rho_1 = (_pte_rho0 + _pte_delta, _pte_rho1 + _pte_gamma1, _pte_rho2 + _pte_gamma2)
            matrix colnames _pte_rho_1 = rho0_d rho1_g1 rho2_g2
        }
    }
    else if `omegapoly' == 3 {
        matrix _pte_rho_0 = (_pte_rho0, _pte_rho1, _pte_rho2, _pte_rho3)
        matrix colnames _pte_rho_0 = rho0 rho1 rho2 rho3
        if `lag_treated_supported' {
            matrix _pte_rho_1 = (_pte_rho0 + _pte_delta, _pte_rho1 + _pte_gamma1, _pte_rho2 + _pte_gamma2, _pte_rho3 + _pte_gamma3)
            matrix colnames _pte_rho_1 = rho0_d rho1_g1 rho2_g2 rho3_g3
        }
    }
    else if `omegapoly' == 4 {
        matrix _pte_rho_0 = (_pte_rho0, _pte_rho1, _pte_rho2, _pte_rho3, _pte_rho4)
        matrix colnames _pte_rho_0 = rho0 rho1 rho2 rho3 rho4
        if `lag_treated_supported' {
            matrix _pte_rho_1 = (_pte_rho0 + _pte_delta, _pte_rho1 + _pte_gamma1, _pte_rho2 + _pte_gamma2, _pte_rho3 + _pte_gamma3, _pte_rho4 + _pte_gamma4)
            matrix colnames _pte_rho_1 = rho0_d rho1_g1 rho2_g2 rho3_g3 rho4_g4
        }
    }
    
    // Normalize temporary column names before reposting so public e(b) and
    // e(V) expose stable names instead of private _pte_* scratch variables.
    tempname b V
    tempvar touse
    matrix `b' = e(b)
    matrix `V' = e(V)
    local _pte_b_names : colnames `b'
    local _pte_b_names = subinstr(`"`_pte_b_names'"', "_pte_omega2", "omega2", .)
    local _pte_b_names = subinstr(`"`_pte_b_names'"', "_pte_omega3", "omega3", .)
    local _pte_b_names = subinstr(`"`_pte_b_names'"', "_pte_omega4", "omega4", .)
    local _pte_b_names = subinstr(`"`_pte_b_names'"', "_pte_omega_tp", "omega_tp", .)
    local _pte_b_names = subinstr(`"`_pte_b_names'"', "_pte_omega2_tp", "omega2_tp", .)
    local _pte_b_names = subinstr(`"`_pte_b_names'"', "_pte_omega3_tp", "omega3_tp", .)
    local _pte_b_names = subinstr(`"`_pte_b_names'"', "_pte_omega4_tp", "omega4_tp", .)
    matrix colnames `b' = `_pte_b_names'
    matrix colnames `V' = `_pte_b_names'
    matrix rownames `V' = `_pte_b_names'
    quietly gen byte `touse' = e(sample)
    
    ereturn post `b' `V', esample(`touse')
    
    // Scalar returns mirror the public contract consumed by omega, eps0, and
    // ATT helpers, even though the underlying regression used tempvar names.
    ereturn scalar rho0 = _pte_rho0
    ereturn scalar rho1 = _pte_rho1
    if `omegapoly' >= 2 {
        ereturn scalar rho2 = _pte_rho2
    }
    if `omegapoly' >= 3 {
        ereturn scalar rho3 = _pte_rho3
    }
    if `omegapoly' >= 4 {
        ereturn scalar rho4 = _pte_rho4
    }
    
    if `lag_treated_supported' {
        ereturn scalar gamma1 = _pte_gamma1
        if `omegapoly' >= 2 {
            ereturn scalar gamma2 = _pte_gamma2
        }
        if `omegapoly' >= 3 {
            ereturn scalar gamma3 = _pte_gamma3
        }
        if `omegapoly' >= 4 {
            ereturn scalar gamma4 = _pte_gamma4
        }
        
        ereturn scalar delta = _pte_delta
    }
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar N_evo = `N_evo'
    ereturn scalar N = `N_evo'
    ereturn scalar r2 = `r2'
    ereturn scalar rmse = `rmse'
    ereturn scalar N_lag_untreated = `n_lag_untreated'
    ereturn scalar N_lag_treated = `n_lag_treated'
    ereturn scalar lag_treated_supported = `lag_treated_supported'
    
    ereturn matrix rho_0 = _pte_rho_0
    if `lag_treated_supported' {
        ereturn matrix rho_1 = _pte_rho_1
    }

    local pte_treatsig ""
    capture quietly _pte_treatment_signature, ///
        panelvar(`panelvar') timevar(`timevar') treatment(`treatment')
    if _rc == 0 {
        local pte_treatsig `"`r(signature)'"'
    }
    
    ereturn local treatment = "`treatment'"
    ereturn local treatsig `"`pte_treatsig'"'
    ereturn local pfunc = "`pfunc'"
    ereturn local prodfunc = "`pfunc'"
    ereturn local predict "_pte_evolution_p"
    ereturn local id = "`panelvar'"
    ereturn local time = "`timevar'"
    ereturn local idvar = "`panelvar'"
    ereturn local timevar = "`timevar'"
    local xtdelta_num = real("`xtdelta'")
    if !missing(`xtdelta_num') {
        ereturn scalar xtdelta = `xtdelta_num'
    }
    ereturn local cmd = "_pte_evolution"
    ereturn local title = "PTE Evolution Regression"
    if `_pte_has_prev_est' {
        capture estimates drop `_pte_prev_est'
    }
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "  Evolution Regression Results:"
        di as text "  {hline 50}"
        di as text "  Observations:        " as result %10.0fc `N_evo'
        di as text "  R-squared:           " as result %10.4f `r2'
        di as text "  RMSE:                " as result %10.4f `rmse'
        di as text "  Lag untreated rows:  " as result %10.0fc `n_lag_untreated'
        di as text "  Lag treated rows:    " as result %10.0fc `n_lag_treated'
        di as text ""
        di as text "  Main Effect Coefficients (h̄₀):"
        di as text "    rho0 (constant):   " as result %10.6f _pte_rho0
        di as text "    rho1 (omega):      " as result %10.6f _pte_rho1
        if `omegapoly' >= 2 {
            di as text "    rho2 (omega²):     " as result %10.6f _pte_rho2
        }
        if `omegapoly' >= 3 {
            di as text "    rho3 (omega³):     " as result %10.6f _pte_rho3
        }
        if `omegapoly' >= 4 {
            di as text "    rho4 (omega⁴):     " as result %10.6f _pte_rho4
        }
        di as text ""
        if `lag_treated_supported' {
            di as text "  Interaction Coefficients (h̄₁ - h̄₀):"
            di as text "    gamma1:            " as result %10.6f _pte_gamma1
            if `omegapoly' >= 2 {
                di as text "    gamma2:            " as result %10.6f _pte_gamma2
            }
            if `omegapoly' >= 3 {
                di as text "    gamma3:            " as result %10.6f _pte_gamma3
            }
            if `omegapoly' >= 4 {
                di as text "    gamma4:            " as result %10.6f _pte_gamma4
            }
            di as text ""
            di as text "  Treatment Direct Effect:"
            di as text "    delta:             " as result %10.6f _pte_delta
        }
        else {
            if `lag_treated_supported_raw' {
                di as text "  Treated-lag support present, but treated-side regressors were omitted: h̄₁ not posted"
            }
            else {
                di as text "  Treated-lag support absent: h̄₁ not posted"
            }
        }
        di as text "{hline 60}"
    }
    
    // Clean scratch scalars so a later partial rerun cannot read stale
    // coefficient objects from the current Stata session.
    capture scalar drop _pte_rho0
    capture scalar drop _pte_rho1
    capture scalar drop _pte_rho2
    capture scalar drop _pte_rho3
    capture scalar drop _pte_rho4
    capture scalar drop _pte_gamma1
    capture scalar drop _pte_gamma2
    capture scalar drop _pte_gamma3
    capture scalar drop _pte_gamma4
    capture scalar drop _pte_delta
    
end


// Build polynomial-treatment interaction variables using the public naming
// convention expected by diagnostics and legacy compatibility checks.

capture program drop _pte_interaction_gen
program define _pte_interaction_gen
    version 14.0
    
    syntax, omegapoly(integer) [treatment(name) pfunc(string)]
    
    // Exact omega is required because these generated names are later read
    // through lag operators and public diagnostics.
    capture confirm numeric variable omega
    if _rc {
        di as error "[pte] Error: variable 'omega' not found or not numeric"
        di as error "[pte] Please run _pte_omega_recovery first"
        exit 111
    }
    
    // Default to treat_post to mirror the DO naming convention used by the
    // replication scripts and the lag-equivalence verifier below.
    if "`treatment'" == "" {
        capture confirm variable treat_post, exact
        if _rc {
            di as error "[pte] Error: treatment variable 'treat_post' not found or not numeric"
            exit 111
        }
        local treatment "treat_post"
    }
    else {
        capture confirm variable `treatment', exact
        if _rc {
            di as error "[pte] Error: treatment variable '`treatment'' not found or not numeric"
            exit 111
        }
    }
    
    capture confirm numeric variable `treatment'
    if _rc {
        di as error "[pte] Error: treatment variable '`treatment'' not found or not numeric"
        exit 111
    }
    
    // The generated interaction terms are only meaningful for binary
    // treatment histories.
    capture assert inlist(`treatment', 0, 1) if !missing(`treatment')
    if _rc {
        di as error "[pte] Error: treatment variable '`treatment'' must be binary (0/1)"
        di as error "[pte]        Found values outside {0, 1}"
        exit 450
    }
    
    if !inlist(`omegapoly', 1, 2, 3, 4) {
        di as error "[pte] Error: omegapoly must be 1, 2, 3, or 4"
        di as error "[pte]        Specified: omegapoly(`omegapoly')"
        exit 198
    }
    
    // The naming helper accepts both production-function branches because the
    // evolution polynomial order is orthogonal to CD versus translog.
    if "`pfunc'" == "" {
        local pfunc "cd"
    }
    
    if !inlist("`pfunc'", "cd", "translog") {
        di as error "[pte] Error: pfunc must be 'cd' or 'translog'"
        di as error "[pte]        Specified: pfunc(`pfunc')"
        exit 198
    }
    
    // Order 1 keeps the historical omega/omega_tp names; higher orders use
    // numeric suffixes so downstream lookup is deterministic.
    capture drop omega_tp
    quietly gen double omega_tp = omega * `treatment'
    label variable omega_tp "omega x treatment (j=1)"
    
    if `omegapoly' >= 2 {
        capture drop omega2
        quietly gen double omega2 = omega^2
        label variable omega2 "omega squared"
        
        capture drop omega2_tp
        quietly gen double omega2_tp = omega2 * `treatment'
        label variable omega2_tp "omega2 x treatment (j=2)"
    }
    
    if `omegapoly' >= 3 {
        capture drop omega3
        quietly gen double omega3 = omega^3
        label variable omega3 "omega cubed"
        
        capture drop omega3_tp
        quietly gen double omega3_tp = omega3 * `treatment'
        label variable omega3_tp "omega3 x treatment (j=3)"
    }
    
    if `omegapoly' >= 4 {
        capture drop omega4
        quietly gen double omega4 = omega^4
        label variable omega4 "omega to the fourth"
        
        capture drop omega4_tp
        quietly gen double omega4_tp = omega4 * `treatment'
        label variable omega4_tp "omega4 x treatment (j=4)"
    }
    
end


// Verify that the generated interaction variables commute with the lag
// operator on an xtset panel, which is the identity used by the OLS law.

capture program drop _pte_verify_interaction_lag
program define _pte_verify_interaction_lag, rclass
    version 14.0
    
    syntax, omegapoly(integer) [treatment(name) TOLerance(real 1e-10)]
    
    // Keep the verifier aligned with the legacy treat_post default so its
    // output can be compared directly against the replication scripts.
    if "`treatment'" == "" {
        capture confirm variable treat_post, exact
        if _rc {
            di as error "[pte] Error: treatment variable 'treat_post' not found"
            exit 111
        }
        local treatment "treat_post"
    }
    else {
        capture confirm variable `treatment', exact
        if _rc {
            di as error "[pte] Error: treatment variable '`treatment'' not found"
            exit 111
        }
    }
    
    capture _xt, trequired
    if _rc {
        di as error "[pte] Error: data must be xtset as panel"
        exit 459
    }
    
    local total_errors = 0
    local total_checks = 0
    
    di as text ""
    di as text "{hline 60}"
    di as text "Interaction Lag Equivalence Verification"
    di as text "{hline 60}"
    di as text "  Tolerance: " as result %12.2e `tolerance'
    di as text "  omegapoly: " as result `omegapoly'
    di as text ""
    
    // Order 1 is always part of the contract because every admissible law
    // includes L.omega and L.omega_tp.
    tempvar manual_lag1 diff1
    quietly gen double `manual_lag1' = L.omega * L.`treatment'
    quietly gen double `diff1' = abs(L.omega_tp - `manual_lag1')
    quietly count if `diff1' > `tolerance' & !missing(`diff1')
    local err1 = r(N)
    quietly count if !missing(`diff1')
    local n1 = r(N)
    local total_errors = `total_errors' + `err1'
    local total_checks = `total_checks' + 1
    
    if `err1' == 0 {
        di as text "  [PASS] Order 1: L.omega_tp == L.omega * L.`treatment'" ///
           as text "  (N=" as result `n1' as text ")"
    }
    else {
        di as error "  [FAIL] Order 1: " `err1' " obs exceed tolerance"
        quietly summarize `diff1', meanonly
        di as error "         Max deviation: " %12.4e r(max)
    }
    
    // Higher-order checks are only meaningful when that polynomial order was
    // requested and the corresponding variables exist.
    if `omegapoly' >= 2 {
        tempvar manual_lag2 diff2
        quietly gen double `manual_lag2' = L.omega2 * L.`treatment'
        quietly gen double `diff2' = abs(L.omega2_tp - `manual_lag2')
        quietly count if `diff2' > `tolerance' & !missing(`diff2')
        local err2 = r(N)
        quietly count if !missing(`diff2')
        local n2 = r(N)
        local total_errors = `total_errors' + `err2'
        local total_checks = `total_checks' + 1
        
        if `err2' == 0 {
            di as text "  [PASS] Order 2: L.omega2_tp == L.omega2 * L.`treatment'" ///
               as text "  (N=" as result `n2' as text ")"
        }
        else {
            di as error "  [FAIL] Order 2: " `err2' " obs exceed tolerance"
            quietly summarize `diff2', meanonly
            di as error "         Max deviation: " %12.4e r(max)
        }
    }
    
    if `omegapoly' >= 3 {
        tempvar manual_lag3 diff3
        quietly gen double `manual_lag3' = L.omega3 * L.`treatment'
        quietly gen double `diff3' = abs(L.omega3_tp - `manual_lag3')
        quietly count if `diff3' > `tolerance' & !missing(`diff3')
        local err3 = r(N)
        quietly count if !missing(`diff3')
        local n3 = r(N)
        local total_errors = `total_errors' + `err3'
        local total_checks = `total_checks' + 1
        
        if `err3' == 0 {
            di as text "  [PASS] Order 3: L.omega3_tp == L.omega3 * L.`treatment'" ///
               as text "  (N=" as result `n3' as text ")"
        }
        else {
            di as error "  [FAIL] Order 3: " `err3' " obs exceed tolerance"
            quietly summarize `diff3', meanonly
            di as error "         Max deviation: " %12.4e r(max)
        }
    }
    
    if `omegapoly' >= 4 {
        tempvar manual_lag4 diff4
        quietly gen double `manual_lag4' = L.omega4 * L.`treatment'
        quietly gen double `diff4' = abs(L.omega4_tp - `manual_lag4')
        quietly count if `diff4' > `tolerance' & !missing(`diff4')
        local err4 = r(N)
        quietly count if !missing(`diff4')
        local n4 = r(N)
        local total_errors = `total_errors' + `err4'
        local total_checks = `total_checks' + 1
        
        if `err4' == 0 {
            di as text "  [PASS] Order 4: L.omega4_tp == L.omega4 * L.`treatment'" ///
               as text "  (N=" as result `n4' as text ")"
        }
        else {
            di as error "  [FAIL] Order 4: " `err4' " obs exceed tolerance"
            quietly summarize `diff4', meanonly
            di as error "         Max deviation: " %12.4e r(max)
        }
    }
    
    di as text ""
    local validation_passed = (`total_errors' == 0)
    if `validation_passed' {
        di as text "  Result: " as result "ALL PASSED" ///
           as text " (" as result `total_checks' as text " checks)"
    }
    else {
        di as error "  Result: FAILED (" `total_errors' " errors in " `total_checks' " checks)"
    }
    di as text "{hline 60}"
    
    // Return counts so callers can fail fast without scraping the display.
    return scalar error_count = `total_errors'
    return scalar validation_passed = `validation_passed'
    return scalar total_checks = `total_checks'
    
end
