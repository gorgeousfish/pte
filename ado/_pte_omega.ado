*! _pte_omega.ado
*! Orchestrates the bridge from realized omega recovery through
*! untreated-shock distribution estimation for later ATT simulation.
*! The active sample inherits the live support contract unless
*! touse() overrides it, so reruns do not silently widen the estimand.

version 14.0
capture program drop _pte_omega
program define _pte_omega, eclass
    version 14.0
    preserve
    tempname _pte_prev_est
    local _pte_has_prev_est = 0
    capture estimates store `_pte_prev_est', copy
    if _rc == 0 {
        local _pte_has_prev_est = 1
    }
    local _pte_clear_eclass ///
        `"quietly _pte_omega_restore, estname(`_pte_prev_est') hasest(`_pte_has_prev_est')"'
    
    // Parse options first so every failure path can restore the caller's e().
    capture noisily syntax, treatment(name) ///
        [omegapoly(integer 3) ///
         eps0window(integer 0) ///
         NOTRIMeps ///
         NODIAGnose ///
         beta_l(real -999) beta_k(real -999) ///
         beta_ll(real 0) beta_kk(real 0) beta_lk(real 0) ///
         prodfunc(string) ///
         LEGACYPOOLEDeps0 ///
         LEGACYFLOATOMEGA ///
         TOUSE(name)]
    if _rc != 0 {
        local _pte_syntax_rc = _rc
        `_pte_clear_eclass'
        exit `_pte_syntax_rc'
    }
    
    // Validate the handoff before any helper mutates omega state.
    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "[pte] Error: omegapoly must be 1, 2, 3, or 4"
        di as error "[pte]        Specified: omegapoly(`omegapoly')"
        `_pte_clear_eclass'
        exit 198
    }
    if `eps0window' < 0 {
        di as error "[pte] Error: eps0window must be non-negative"
        di as error "[pte]        Specified: eps0window(`eps0window')"
        `_pte_clear_eclass'
        exit 198
    }
    
    capture confirm variable phi, exact
    if _rc != 0 {
        di as error "[pte] Error: variable 'phi' not found"
        di as error "[pte] Please run _pte_prodfunc first"
        `_pte_clear_eclass'
        exit 111
    }
    
    capture confirm variable _pte_mid, exact
    if _rc != 0 {
        capture confirm variable mid, exact
        if _rc != 0 {
            di as error "[pte] Error: neither '_pte_mid' nor legacy 'mid' found"
            di as error "[pte] Please run _pte_transition first"
            `_pte_clear_eclass'
            exit 111
        }
        local midvar "mid"
    }
    else {
        local midvar "_pte_mid"
    }

    capture confirm numeric variable `midvar'
    if _rc != 0 {
        di as error "[pte] Error: transition indicator '`midvar'' must be numeric"
        di as error "[pte] Please run _pte_transition again to rebuild the switch indicator"
        `_pte_clear_eclass'
        exit 111
    }
    
    // Keep the literal treatment() token until the exact-name guard runs.
    // Using syntax varname here would silently expand D -> D_shadow before
    // can verify that the requested state variable is the true D_t.
    capture confirm variable `treatment', exact
    if _rc != 0 {
        di as error "[pte] Error: treatment variable '`treatment'' not found"
        `_pte_clear_eclass'
        exit 111
    }

    tempvar _pte_sample
    local _pte_last_cmd `"`e(cmd)'"'
    local _pte_inherit_live_sample = inlist("`_pte_last_cmd'", ///
        "_pte_prodfunc", "_pte_omega_recovery", "_pte_evolution", ///
        "_pte_treatdep_evolution", "_pte_omega", "_pte_eps0_sample", ///
        "_pte_winsorize", "pte")
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
        // Live/002 reruns should preserve the current active-sample
        // boundary. Falling back to the full dataset would silently rewrite
        // omega recovery, evolution, and eps0 support on a broader estimand.
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
                // _pte_prodfunc posts e(sample) as the narrow GMM criterion
                // sample, but must bridge from the broader
                // recoverable omega support published by itself.
                // That support is the prodfunc-ready contract marker, not
                // every row with a nonmissing phi scratch value. Otherwise
                // not-ready rows can silently re-enter omega/evolution/eps0.
                if "`_pte_last_cmd'" == "_pte_prodfunc" {
                    capture confirm variable _pte_prodfunc_ready, exact
                    if _rc != 0 {
                        di as error "[pte] Error: current data are missing the readiness marker '_pte_prodfunc_ready'"
                        di as error "[pte]        Re-run _pte_prodfunc before calling _pte_omega"
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
                    quietly gen byte `_pte_sample' = ///
                        (_pte_prodfunc_ready == 1 & !missing(_pte_prodfunc_ready))
                    quietly count if `_pte_sample'
                    if r(N) == 0 {
                        di as error "[pte] Error: current data do not contain a live readiness marker on the requested sample"
                        di as error "[pte]        Re-run _pte_prodfunc before calling _pte_omega"
                        `_pte_clear_eclass'
                        exit 498
                    }
                }
                else if inlist("`_pte_last_cmd'", "_pte_winsorize", "_pte_eps0_sample", ///
                    "_pte_evolution", "_pte_treatdep_evolution", "_pte_omega", "pte") {
                    di as error "[pte] Error: current `_pte_last_cmd' state is missing '_pte_active_sample'"
                    if inlist("`_pte_last_cmd'", "_pte_winsorize", "_pte_eps0_sample") {
                        di as error "[pte]        e(sample) from `_pte_last_cmd' is the eps0 shock support,"
                    }
                    else {
                        di as error "[pte]        e(sample) from `_pte_last_cmd' is the posted estimation sample,"
                    }
                    di as error "[pte]        not the active sample required for omega/evolution reruns"
                    di as error "[pte]        Re-run _pte_omega with touse(), or rebuild '_pte_active_sample'"
                    `_pte_clear_eclass'
                    exit 498
                }
                else {
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

    // treatment() is the live D_t state variable for the entire
    // pipeline. Reject nonnumeric or non-binary inputs before omega recovery
    // so the orchestrator cannot mutate omega state and then fail later in
    // the downstream evolution/eps0 gates.
    capture confirm numeric variable `treatment'
    if _rc != 0 {
        di as error "[pte] Error: treatment variable '`treatment'' must be numeric"
        `_pte_clear_eclass'
        exit 111
    }

    capture assert inlist(`treatment', 0, 1) if `_pte_sample' & !missing(`treatment')
    if _rc {
        di as error "[pte] Error: treatment variable '`treatment'' must be binary (0/1)"
        di as error "[pte]        Found values outside {0, 1}"
        `_pte_clear_eclass'
        exit 450
    }
    
    // The mid contract depends on the declared panel spacing, not row order.
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
        touse(`_pte_sample') context("_pte_omega")
    if _rc != 0 {
        local _pte_mid_contract_rc = _rc
        `_pte_clear_eclass'
        exit `_pte_mid_contract_rc'
    }
    
    // Infer the production-function form from explicit betas only when the
    // caller did not already pin prodfunc().
    local _has_explicit_betas = (`beta_l' != -999 & `beta_k' != -999)
    local _has_higher_order = (`beta_ll' != 0 | `beta_kk' != 0 | `beta_lk' != 0)
    
    if "`prodfunc'" == "" {
        if `_has_explicit_betas' {
            if `_has_higher_order' {
                local prodfunc "translog"
            }
            else {
                local prodfunc "cd"
            }
        }
        else {
            local prodfunc `"`e(prodfunc)'"'
            if "`prodfunc'" == "" {
                local prodfunc `"`e(pfunc)'"'
            }
            if "`prodfunc'" == "" {
                local prodfunc "cd"
            }
        }
    }
    
    if "`prodfunc'" == "cd" & `_has_explicit_betas' & `_has_higher_order' {
        di as error "[pte] Error: prodfunc(cd) conflicts with nonzero beta_ll()/beta_kk()/beta_lk()"
        di as error "[pte]        Either omit prodfunc() to infer translog, or specify prodfunc(translog)"
        `_pte_clear_eclass'
        exit 198
    }
    
    // Emit the user-facing contract summary before downstream helpers post
    // their own diagnostics or eclass results.
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "{hline 70}"
        di as text "Productivity Recovery and Evolution"
        di as text "{hline 70}"
        di as text "  Production function:  " as result "`prodfunc'"
        di as text "  Polynomial order:     " as result "`omegapoly'"
        di as text "  Treatment variable:   " as result "`treatment'"
        if `eps0window' == 0 {
            di as text "  eps0 window:          " as result "all pre-treatment"
        }
        else {
            di as text "  eps0 window:          " as result "`eps0window'" as text " panel periods"
        }
        di as text "  Winsorize eps0:       " as result cond("`notrimeps'" == "", "Yes (1%-99%)", "No (notrimeps)")
        di as text "{hline 70}"
    }
    
    // Step 1 recovers realized productivity on the active sample. When the
    // caller omits explicit betas, the command trusts only live
    // readiness markers rather than any stale omega variable in memory.
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "Step 1: Productivity Recovery"
    }
    
    // Keep one master active-sample boundary for the full chain and
    // pass throwaway copies to each eclass substep. Reusing the same caller
    // tempvar across multiple ereturn-posting helpers is fragile because any
    // child may publish it as esample() and thereby consume the name before
    // later steps reuse it.
    if `_has_explicit_betas' {
        tempvar _pte_sample_recovery
        quietly gen byte `_pte_sample_recovery' = `_pte_sample'
        // Explicit betas trigger a fresh omega rebuild under the requested
        // production-function form.
        local _pte_recovery_opts "pfunc(`prodfunc') touse(`_pte_sample_recovery')"
        if "`legacyfloatomega'" != "" {
            local _pte_recovery_opts "`_pte_recovery_opts' legacyfloatomega"
        }
        capture noisily _pte_omega_recovery, ///
            beta_l(`beta_l') beta_k(`beta_k') ///
            beta_ll(`beta_ll') beta_kk(`beta_kk') beta_lk(`beta_lk') ///
            `_pte_recovery_opts' `nodiagnose'
        if _rc != 0 {
            local _pte_recovery_rc = _rc
            `_pte_clear_eclass'
            exit `_pte_recovery_rc'
        }
    }
    else {
        // Without explicit betas, omega must come from a live handoff.
        capture confirm variable _pte_prodfunc_ready, exact
        if _rc != 0 {
            capture confirm variable omega, exact
            if _rc == 0 capture drop omega
            di as error "[pte] Error: current data are missing the readiness marker '_pte_prodfunc_ready'"
            di as error "[pte]        Re-run _pte_prodfunc, or provide beta_l()/beta_k() to rebuild omega"
            `_pte_clear_eclass'
            exit 111
        }

        capture confirm numeric variable _pte_prodfunc_ready
        if _rc != 0 {
            capture confirm variable omega, exact
            if _rc == 0 capture drop omega
            di as error "[pte] Error: '_pte_prodfunc_ready' must be numeric"
            di as error "[pte]        Re-run _pte_prodfunc to rebuild the readiness marker"
            `_pte_clear_eclass'
            exit 111
        }

        quietly count if `_pte_sample' & _pte_prodfunc_ready == 1
        if r(N) == 0 {
            capture confirm variable omega, exact
            if _rc == 0 capture drop omega
            di as error "[pte] Error: current data do not contain a live readiness marker on the requested sample"
            di as error "[pte]        Re-run _pte_prodfunc, or provide beta_l()/beta_k() to rebuild omega"
            `_pte_clear_eclass'
            exit 498
        }

        capture confirm variable omega, exact
        if _rc != 0 {
            di as error "[pte] Error: variable 'omega' not found"
            di as error "[pte] Either run _pte_prodfunc first, or provide beta_l()/beta_k()"
            `_pte_clear_eclass'
            exit 111
        }

        capture confirm numeric variable omega
        if _rc != 0 {
            di as error "[pte] Error: variable 'omega' must be numeric"
            di as error "[pte] Either run _pte_prodfunc first, or provide beta_l()/beta_k()"
            `_pte_clear_eclass'
            exit 111
        }
        
        // Require nonmissing realized productivity on the requested support.
        quietly count if `_pte_sample' & !missing(omega)
        if r(N) == 0 {
            di as error "[pte] Error: variable 'omega' has no valid observations"
            `_pte_clear_eclass'
            exit 2000
        }
        
        if "`nodiagnose'" == "" {
            di as text "  Using existing omega from production function estimation (_pte_prodfunc)"
        }
    }
    
    // Cache recovery summaries before later eclass calls overwrite them.
    if `_has_explicit_betas' {
        local N_omega = e(N_omega)
        local omega_mean = e(omega_mean)
        local omega_sd = e(omega_sd)
    }
    else {
        // Existing omega still needs fresh sample-restricted summary stats.
        quietly count if `_pte_sample' & !missing(omega)
        local N_omega = r(N)
        quietly summarize omega if `_pte_sample', meanonly
        local omega_mean = r(mean)
        quietly summarize omega if `_pte_sample'
        local omega_sd = r(sd)
    }
    
    // Step 2 estimates the non-transition evolution law. Child helpers enforce
    // the paper's split between untreated h_bar_0 and treated h_bar_1 paths.
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "Step 2: Evolution Regression"
    }
    
    // Use a throwaway sample marker so child esample() posting cannot consume
    // the orchestrator's master support variable.
    tempvar _pte_sample_evolution
    quietly gen byte `_pte_sample_evolution' = `_pte_sample'
    capture noisily _pte_evolution, treatment(`treatment') omegapoly(`omegapoly') pfunc(`prodfunc') ///
        touse(`_pte_sample_evolution') `nodiagnose'
    if _rc != 0 {
        local _pte_evolution_rc = _rc
        `_pte_clear_eclass'
        exit `_pte_evolution_rc'
    }
    
    // Snapshot evolution outputs before the next helper clears e().
    local N_evo = e(N_evo)
    local N_lag_untreated = e(N_lag_untreated)
    local N_lag_treated = e(N_lag_treated)
    local lag_treated_supported = e(lag_treated_supported)
    local r2_evo = e(r2)
    local rmse_evo = e(rmse)
    
    // Scalars keep the treated-side terms optional when the sample has no
    // supported lagged treated observations.
    scalar _pte_rho0 = e(rho0)
    scalar _pte_rho1 = e(rho1)
    if `omegapoly' >= 2 scalar _pte_rho2 = e(rho2)
    if `omegapoly' >= 3 scalar _pte_rho3 = e(rho3)
    if `omegapoly' >= 4 scalar _pte_rho4 = e(rho4)

    if `lag_treated_supported' {
        scalar _pte_gamma1 = e(gamma1)
        if `omegapoly' >= 2 scalar _pte_gamma2 = e(gamma2)
        if `omegapoly' >= 3 scalar _pte_gamma3 = e(gamma3)
        if `omegapoly' >= 4 scalar _pte_gamma4 = e(gamma4)
        scalar _pte_delta = e(delta)
    }

    // Preserve coefficient vectors in tempnames for the final consolidated e().
    tempname rho_0
    matrix `rho_0' = e(rho_0)
    local has_rho_1 = 0
    tempname rho_1
    if `lag_treated_supported' {
        capture confirm matrix e(rho_1)
        if _rc == 0 {
            matrix `rho_1' = e(rho_1)
            local has_rho_1 = 1
        }
    }
    
    // Step 3 restricts eps0 support to untreated pre-treatment observations,
    // matching the control-path innovation logic used for ATT simulation.
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "Step 3: eps0 Sample Selection"
    }
    
    // eps0 support depends on treatment timing, not on the chosen polynomial
    // order, so omegapoly is intentionally omitted here.
    tempvar _pte_sample_eps0
    quietly gen byte `_pte_sample_eps0' = `_pte_sample'
    local _pte_eps0_opts "treatment(`treatment') eps0window(`eps0window')"
    local _pte_eps0_opts "`_pte_eps0_opts' touse(`_pte_sample_eps0')"
    if "`legacypooledeps0'" != "" {
        local _pte_eps0_opts "`_pte_eps0_opts' legacypooledeps0"
    }
    capture noisily _pte_eps0_sample, `_pte_eps0_opts' `nodiagnose'
    if _rc != 0 {
        local _pte_eps0_rc = _rc
        `_pte_clear_eclass'
        exit `_pte_eps0_rc'
    }
    
    // Keep only the support count here; the shock moments are finalized below.
    local N_eps0_sample = e(N_eps0)
    
    // Step 4 turns the eps0 support into the innovation law used by ATT
    // simulation. The default 1%-99% trimming matches the paper's outlier
    // guard; notrimeps leaves the raw support in place.
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "Step 4: eps0 Distribution Estimation"
    }
    
    // The winsorize helper owns the percentile cutoffs and sigma estimates.
    local _pte_win_opts "`notrimeps' `nodiagnose'"
    if "`legacypooledeps0'" != "" {
        local _pte_win_opts "`_pte_win_opts' legacywinsor2"
    }
    capture noisily _pte_winsorize, `_pte_win_opts'
    if _rc != 0 {
        local _pte_winsorize_rc = _rc
        `_pte_clear_eclass'
        exit `_pte_winsorize_rc'
    }
    
    // Cache the released innovation moments before posting top-level e().
    // _pte_winsorize owns the shock moments and overwrites e(), so the legacy
    // support flag must come from this worker's option state, not child e().
    local sigma_eps = e(sigma_eps)
    local sigma_eps_trim = e(sigma_eps_trim)
    local N_eps0 = e(N_eps0)
    local N_eps0_trim = e(N_eps0_trim)
    local legacy_pooled_eps0 = ("`legacypooledeps0'" != "")
    local eps0_p1 = e(eps0_p1)
    local eps0_p99 = e(eps0_p99)
    local trimeps = e(trimeps)
    
    // Post a coherent top-level sample contract. The orchestrator's
    // active sample is the touse()-bounded set with recoverable omega values;
    // later stage counts (evolution / eps0) are published separately below.
    tempvar _pte_omega_esample
    quietly gen byte `_pte_omega_esample' = (`_pte_sample' & !missing(omega))
    quietly count if `_pte_omega_esample'
    local N_omega_post = r(N)

    // Replace any inherited child e() result with the consolidated
    // view of the active omega support.
    ereturn clear
    ereturn post, esample(`_pte_omega_esample') obs(`N_omega_post') depname("omega")
    
    // Publish the evolution coefficients first because downstream callers
    // treat them as the public interface to h_bar_0 / h_bar_1.
    ereturn scalar rho0 = _pte_rho0
    ereturn scalar rho1 = _pte_rho1
    if `omegapoly' >= 2 ereturn scalar rho2 = _pte_rho2
    if `omegapoly' >= 3 ereturn scalar rho3 = _pte_rho3
    if `omegapoly' >= 4 ereturn scalar rho4 = _pte_rho4
    
    if `lag_treated_supported' {
        ereturn scalar gamma1 = _pte_gamma1
        if `omegapoly' >= 2 ereturn scalar gamma2 = _pte_gamma2
        if `omegapoly' >= 3 ereturn scalar gamma3 = _pte_gamma3
        if `omegapoly' >= 4 ereturn scalar gamma4 = _pte_gamma4
        ereturn scalar delta = _pte_delta
    }
    
    // Report counts for each stage separately so diagnostics can distinguish
    // omega support, evolution support, and eps0 support shrinkage.
    ereturn scalar N = `N_omega_post'
    ereturn scalar N_omega = `N_omega_post'
    ereturn scalar N_evo = `N_evo'
    ereturn scalar N_lag_untreated = `N_lag_untreated'
    ereturn scalar N_lag_treated = `N_lag_treated'
    ereturn scalar N_eps0 = `N_eps0'
    ereturn scalar N_eps0_trim = `N_eps0_trim'
    
    // These moments summarize the realized omega and eps0 objects that ATT
    // simulation reuses downstream.
    ereturn scalar omega_mean = `omega_mean'
    ereturn scalar omega_sd = `omega_sd'
    ereturn scalar r2_evo = `r2_evo'
    ereturn scalar rmse_evo = `rmse_evo'
    ereturn scalar sigma_eps = `sigma_eps'
    ereturn scalar sigma_eps_trim = `sigma_eps_trim'
    ereturn scalar eps0_p1 = `eps0_p1'
    ereturn scalar eps0_p99 = `eps0_p99'
    
    // Configuration scalars expose the exact evolution and shock settings that
    // generated the posted state.
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar eps0window = `eps0window'
    ereturn scalar legacy_pooled_eps0 = `legacy_pooled_eps0'
    ereturn scalar lag_treated_supported = `lag_treated_supported'
    ereturn scalar trimeps = `trimeps'
    
    // Keep the polynomial coefficient vectors in matrix form for Mata and
    // postestimation consumers.
    ereturn matrix rho_0 = `rho_0'
    if `has_rho_1' {
        ereturn matrix rho_1 = `rho_1'
    }

    local pte_treatsig ""
    capture quietly _pte_treatment_signature, ///
        panelvar(`panelvar') timevar(`timevar') treatment(`treatment')
    if _rc == 0 {
        local pte_treatsig `"`r(signature)'"'
    }
    
    // Preserve the public naming bridge expected by older callers.
    ereturn local treatment "`treatment'"
    ereturn local treatsig `"`pte_treatsig'"'
    ereturn local pfunc "`prodfunc'"
    ereturn local prodfunc "`prodfunc'"
    ereturn local id "`panelvar'"
    ereturn local time "`timevar'"
    ereturn local idvar "`panelvar'"
    ereturn local timevar "`timevar'"
    local xtdelta_num = real("`xtdelta'")
    if !missing(`xtdelta_num') {
        ereturn scalar xtdelta = `xtdelta_num'
    }
    ereturn local eps0_dist "normal"
    ereturn local cmd "_pte_omega"
    ereturn local title "PTE Productivity Recovery and Evolution"
    if `_pte_has_prev_est' {
        capture estimates drop `_pte_prev_est'
    }
    restore, not
    
    // The printed summary is informational only; the authoritative contract is
    // the consolidated e() state posted above.
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "{hline 70}"
        di as text " Summary"
        di as text "{hline 70}"
        di as text "  Productivity recovery:  " as result %10.0fc `N_omega' " observations"
        di as text "  Evolution regression:   " as result %10.0fc `N_evo' " observations (R² = " %5.3f `r2_evo' ")"
        di as text "  eps0 sample:            " as result %10.0fc `N_eps0' " → " %10.0fc `N_eps0_trim' " (after trim)"
        di as text "  sigma_eps (for ATT):    " as result %10.6f `sigma_eps_trim'
        di as text "{hline 70}"
        di as text ""
    }
    
    // Remove scratch scalars so later commands cannot read stale evolution
    // coefficients from the global scalar namespace.
    capture scalar drop _pte_rho0
    capture scalar drop _pte_rho1
    if `omegapoly' >= 2 {
        capture scalar drop _pte_rho2
    }
    if `omegapoly' >= 3 {
        capture scalar drop _pte_rho3
    }
    if `omegapoly' >= 4 {
        capture scalar drop _pte_rho4
    }
    if `lag_treated_supported' {
        capture scalar drop _pte_gamma1
        capture scalar drop _pte_gamma2
        capture scalar drop _pte_gamma3
        capture scalar drop _pte_gamma4
        capture scalar drop _pte_delta
    }
    // Cleanup may legitimately hit absent treated-side temp scalars on the
    // h_bar_0-only path. Do not leak those capture rc values as the command
    // status after has already succeeded and posted fresh e().
    quietly count if 0
    exit 0

end
