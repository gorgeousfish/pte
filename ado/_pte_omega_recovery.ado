*! _pte_omega_recovery.ado
*! Recover realized productivity from the stage-1 control function and
*! the production-function coefficients.
*!
*! The core identity is omega = phi - f(free, state; beta). In verify mode,
*! the program also reconstructs omega from observed output and confirms that
*! the phi-based and direct formulas agree up to tight numerical tolerances.

version 14.0
capture program drop _pte_omega_recovery
program define _pte_omega_recovery, eclass
    version 14.0
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
    // Two contracts are supported: a live bridge that reads the
    // current e(b), and a standalone path that takes beta inputs directly.
    capture noisily syntax [, free(name) state(name) pfunc(string) NODIAGnose ///
              beta_l(real -999) beta_k(real -999) ///
              beta_ll(real 0) beta_kk(real 0) beta_lk(real 0) ///
              VERIFY DEBUG depvar(name) time(name) beta_t(real -999) ///
              LEGACYFLOATOMEGA ///
              TOUSE(name)]
    if _rc != 0 {
        local _pte_syntax_rc = _rc
        `_pte_clear_eclass'
        exit `_pte_syntax_rc'
    }

    // Clear any previously published omega state before validation so a
    // failed recovery cannot leak stale productivity into downstream steps.
    // Rebuild the keep-list from exact variable names to avoid dropping
    // omega_* shadows through Stata abbreviation matching.
    capture confirm variable omega, exact
    if _rc == 0 {
        quietly ds
        local _pte_allvars `"`r(varlist)'"'
        local _pte_keepvars ""
        foreach _pte_var of local _pte_allvars {
            if "`_pte_var'" != "omega" {
                local _pte_keepvars `"`_pte_keepvars' `_pte_var'"'
            }
        }
        quietly keep `_pte_keepvars'
    }
    
    // The caller must either provide free()/state() for the live bridge or
    // beta_l()/beta_k() for standalone recovery.
    local mode_epic001 = ("`free'" != "" & "`state'" != "")
    local mode_standalone = (`beta_l' != -999 & `beta_k' != -999)
    local _has_higher_order = (`beta_ll' != 0 | `beta_kk' != 0 | `beta_lk' != 0)

    if `mode_epic001' & `mode_standalone' {
        di as error "[pte] Error: free()/state() and beta_l()/beta_k() are mutually exclusive"
        di as error "[pte]        Choose pipeline mode or standalone mode, not both"
        `_pte_clear_eclass'
        exit 198
    }
    
    // Standalone recovery can still borrow variable names from the current
    // e() context, but only if those names resolve to live numeric columns.
    if `mode_standalone' & !`mode_epic001' {
        // Try e(free) and e(state) from the current estimation context.
        // Only keep inferred names that are live numeric variables in the
        // current data; otherwise fall back to the canonical lnl/lnk defaults.
        if "`free'" == "" {
            local free `"`e(free)'"'
            if "`free'" != "" {
                capture confirm variable `free', exact
                if _rc != 0 local free ""
                else {
                    capture confirm numeric variable `free'
                    if _rc != 0 local free ""
                }
            }
        }
        if "`state'" == "" {
            local state `"`e(state)'"'
            if "`state'" != "" {
                capture confirm variable `state', exact
                if _rc != 0 local state ""
                else {
                    capture confirm numeric variable `state'
                    if _rc != 0 local state ""
                }
            }
        }
        // Fall back to the canonical log-input names used across the package.
        if "`free'" == "" {
            capture confirm variable lnl, exact
            if _rc == 0 local free "lnl"
        }
        if "`state'" == "" {
            capture confirm variable lnk, exact
            if _rc == 0 local state "lnk"
        }
        // A standalone call cannot recover omega unless both input columns exist.
        if "`free'" == "" | "`state'" == "" {
            di as error "[pte] Error: In standalone mode, free/state variables not found"
            di as error "[pte]        Provide free()/state() or ensure lnl/lnk exist in data"
            `_pte_clear_eclass'
            exit 111
        }
    }
    
    // Reject under-specified or mixed contracts before touching data state.
    if !`mode_epic001' & !`mode_standalone' {
        di as error "[pte] Error: Must specify either free()/state() or beta_l()/beta_k()"
        di as error "[pte]        Mode 1: free(name) state(name) - reads beta from e(b)"
        di as error "[pte]        Mode 2: beta_l(#) beta_k(#) - uses provided beta values"
        `_pte_clear_eclass'
        exit 198
    }
    
    // The production-function branch is part of the public bridge contract.
    if "`pfunc'" == "" {
        if `mode_epic001' {
            // live contract publishes e(prodfunc); keep e(pfunc)
            // as a fallback for older callers that may still set it.
            local pfunc `"`e(prodfunc)'"'
            if "`pfunc'" == "" {
                local pfunc `"`e(pfunc)'"'
            }
        }
        else if `mode_standalone' & `_has_higher_order' {
            local pfunc "translog"
        }
        else {
            local pfunc "cd"
        }
    }
    
    // Nonzero higher-order terms imply translog; allowing pfunc(cd) here
    // would silently drop curvature terms from the omega identity.
    if `mode_standalone' & "`pfunc'" == "cd" & `_has_higher_order' {
        di as error "[pte] Error: pfunc(cd) conflicts with nonzero beta_ll()/beta_kk()/beta_lk()"
        di as error "[pte]        Either omit pfunc() to infer translog, or specify pfunc(translog)"
        `_pte_clear_eclass'
        exit 198
    }
    
    // Keep the standalone defaults aligned with the package-wide naming convention.
    if `mode_standalone' & "`free'" == "" {
        local free "lnl"
    }
    if `mode_standalone' & "`state'" == "" {
        local state "lnk"
    }

    tempvar _pte_sample
    local _pte_sample_from_ready 0
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
        if `mode_epic001' {
            // The live bridge should stay on the readiness support produced by
            // _pte_prodfunc; reopening off-sample rows would mix incompatible phi states.
            capture confirm variable _pte_prodfunc_ready, exact
            if _rc == 0 {
                capture confirm numeric variable _pte_prodfunc_ready
                if _rc != 0 {
                    di as error "[pte] Error: '_pte_prodfunc_ready' must be numeric"
                    di as error "[pte]        Re-run _pte_prodfunc to rebuild the readiness marker"
                    `_pte_clear_eclass'
                    exit 111
                }
                quietly gen byte `_pte_sample' = (_pte_prodfunc_ready == 1 & !missing(_pte_prodfunc_ready))
                local _pte_sample_from_ready 1
            }
            else {
                quietly gen byte `_pte_sample' = 1
            }
        }
        else {
            quietly gen byte `_pte_sample' = 1
        }
    }

    quietly count if `_pte_sample'
    if r(N) == 0 & !(`mode_epic001' & `_pte_sample_from_ready') {
        di as error "[pte] Error: touse() excludes all observations"
        `_pte_clear_eclass'
        exit 2000
    }
    
    local _pte_verify_has_controls 0
    local _pte_verify_control_vars ""

    if "`verify'" != "" {
        // Verify mode reconstructs omega from observed output, so depvar()
        // must bind to the exact log-output column used in stage 1.
        if "`depvar'" == "" {
            di as error "[pte] Error: verify mode requires depvar() option"
            di as error "[pte]        depvar(name) specifies the exact dependent-variable name (log output)"
            `_pte_clear_eclass'
            exit 198
        }
        
        // Verify must consume the exact observed output column rather than
        // allowing Stata abbreviation fallback to bind depvar() to a shadow.
        capture confirm variable `depvar', exact
        if _rc != 0 {
            di as error "[pte] Error: depvar variable '`depvar'' not found"
            `_pte_clear_eclass'
            exit 111
        }
        capture confirm numeric variable `depvar'
        if _rc != 0 {
            di as error "[pte] Error: depvar variable '`depvar'' must be numeric"
            di as error "[pte]        verify reconstructs omega from observed log output"
            `_pte_clear_eclass'
            exit 111
        }
        
        if `mode_epic001' {
            capture confirm matrix e(beta_controls)
            if _rc == 0 {
                tempname _pte_verify_controls
                matrix `_pte_verify_controls' = e(beta_controls)
                local _pte_verify_control_vars : colnames `_pte_verify_controls'
                if `"`_pte_verify_control_vars'"' != "" {
                    local _pte_verify_has_controls 1
                    foreach _pte_ctrl of local _pte_verify_control_vars {
                        capture confirm variable `_pte_ctrl', exact
                        if _rc != 0 {
                            di as error "[pte] Error: verify control variable '`_pte_ctrl'' not found"
                            di as error "[pte]        Production function verify requires the original stage-1 control variables"
                            `_pte_clear_eclass'
                            exit 111
                        }
                        capture confirm numeric variable `_pte_ctrl'
                        if _rc != 0 {
                            di as error "[pte] Error: verify control variable '`_pte_ctrl'' is not numeric"
                            di as error "[pte]        Production function verify requires the original stage-1 control variables"
                            `_pte_clear_eclass'
                            exit 111
                        }
                    }
                }
            }
        }

        local _pte_require_legacy_time 0
        if !`_pte_verify_has_controls' {
            local _pte_legacy_beta_t = 0
            if `beta_t' != -999 {
                local _pte_legacy_beta_t = `beta_t'
            }
            else if `mode_epic001' {
                capture confirm scalar e(beta_t)
                if _rc == 0 {
                    local _pte_legacy_beta_t = e(beta_t)
                }
            }

            // Legacy callers may carry one scalar control coefficient instead
            // of e(beta_controls). time() matters only when that legacy term is active.
            local _pte_require_legacy_time = (abs(`_pte_legacy_beta_t') > 1e-12)
        }

        if "`time'" != "" {
            capture confirm variable `time', exact
            if _rc != 0 {
                di as error "[pte] Error: time variable '`time'' not found"
                `_pte_clear_eclass'
                exit 111
            }
            capture confirm numeric variable `time'
            if _rc != 0 {
                di as error "[pte] Error: time variable '`time'' is not numeric"
                `_pte_clear_eclass'
                exit 111
            }
        }
        else if !`_pte_verify_has_controls' & `_pte_require_legacy_time' {
            di as error "[pte] Error: verify mode requires time() when a legacy single control is active"
            di as error "[pte]        time(name) specifies the control variable used in the direct method"
            `_pte_clear_eclass'
            exit 198
        }
        
        local _pte_verify_has_legacy_time = ("`time'" != "")
        if !`_pte_verify_has_controls' {
            // Preserve the legacy single-control bridge without requiring it
            // when phi already has every control netted out.
            if `beta_t' == -999 {
                if `mode_epic001' & "`time'" != "" {
                    capture confirm scalar e(beta_t)
                    if _rc != 0 {
                        di as error "[pte] Error: e(beta_t) not found and beta_t() not specified"
                        di as error "[pte]        Production function verify now prefers e(beta_controls); otherwise beta_t() is needed"
                        `_pte_clear_eclass'
                        exit 198
                    }
                    local _pte_beta_t_val = e(beta_t)
                }
                else if `mode_epic001' {
                    capture confirm scalar e(beta_t)
                    if _rc == 0 {
                        local _pte_beta_t_val = e(beta_t)
                    }
                    else {
                        local _pte_beta_t_val = 0
                    }
                }
                else {
                    // Standalone mode without beta_t: default to 0
                    local _pte_beta_t_val = 0
                }
            }
            else {
                local _pte_beta_t_val = `beta_t'
            }
        }
    }
    
    // phi is the realized control-function object coming out of stage 1.
    capture confirm variable phi, exact
    if _rc != 0 {
        di as error "[pte] Error: variable 'phi' not found from production function estimation"
        di as error "[pte] Please run _pte_prodfunc.ado first"
        `_pte_clear_eclass'
        exit 198
    }

    capture confirm numeric variable phi
    if _rc != 0 {
        di as error "[pte] Error: variable 'phi' must be numeric"
        di as error "[pte] Please run _pte_prodfunc.ado first"
        `_pte_clear_eclass'
        exit 111
    }
    
    // A live phi column with no usable observations is equivalent to no bridge.
    quietly count if !missing(phi)
    if r(N) == 0 {
        di as error "[pte] Error: variable 'phi' has no valid observations"
        `_pte_clear_eclass'
        exit 2000
    }
    local n_phi_valid = r(N)

    // success must come from the current data/run, not from a stale
    // eclass object that survived a failed producer rerun. _pte_prodfunc
    // publishes this readiness marker only after reaching its final
    // ereturn-post boundary.
    if `mode_epic001' {
        capture confirm variable _pte_prodfunc_ready, exact
        if _rc != 0 {
            di as error "[pte] Error: current data are missing the readiness marker '_pte_prodfunc_ready'"
            di as error "[pte]        Re-run _pte_prodfunc before calling _pte_omega_recovery"
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
        quietly count if `_pte_sample' & _pte_prodfunc_ready == 1
        if r(N) == 0 {
            di as error "[pte] Error: current data do not contain a live readiness marker on the requested sample"
            di as error "[pte]        Re-run _pte_prodfunc before calling _pte_omega_recovery"
            `_pte_clear_eclass'
            exit 498
        }
    }

    // In live-bridge mode, the coefficient vector must come from the current
    // production-function result, not from an unrelated estimator.
    if `mode_epic001' {
        capture confirm matrix e(b)
        if _rc != 0 {
            di as error "[pte] Error: matrix e(b) not found from production function estimation"
            di as error "[pte] Please run _pte_prodfunc.ado first"
            `_pte_clear_eclass'
            exit 198
        }

        // Once a live result object exists, the exact input columns
        // are the next binding bridge contract. Stale layout diagnostics must
        // not mask a missing-input failure on the current dataset.
        capture confirm variable `free', exact
        if _rc != 0 {
            di as error "[pte] Error: free variable '`free'' not found"
            `_pte_clear_eclass'
            exit 111
        }
        capture confirm numeric variable `free'
        if _rc != 0 {
            di as error "[pte] Error: free variable '`free'' must be numeric"
            `_pte_clear_eclass'
            exit 111
        }
        
        capture confirm variable `state', exact
        if _rc != 0 {
            di as error "[pte] Error: state variable '`state'' not found"
            `_pte_clear_eclass'
            exit 111
        }
        capture confirm numeric variable `state'
        if _rc != 0 {
            di as error "[pte] Error: state variable '`state'' must be numeric"
            `_pte_clear_eclass'
            exit 111
        }
        
        tempname _pte_bmat
        matrix `_pte_bmat' = e(b)
        local ncols = colsof(`_pte_bmat')
        local _pte_bnames : colnames `_pte_bmat'
        local _pte_expected_bnames "`free' `state'"
        if "`pfunc'" == "translog" {
            local _pte_expected_bnames "`free' `state' l2 k2 l1k1"
        }
        
        // Only the package's supported production-function branches are valid here.
        if !inlist("`pfunc'", "cd", "translog") {
            di as error "[pte] Error: pfunc must be 'cd' or 'translog', got '`pfunc''"
            `_pte_clear_eclass'
            exit 198
        }
        
        // The expected width depends on whether omega subtracts a CD or translog frontier.
        if "`pfunc'" == "cd" & `ncols' != 2 {
            di as error "[pte] Error: e(b) has `ncols' columns, expected 2 for Cobb-Douglas"
            `_pte_clear_eclass'
            exit 198
        }
        if "`pfunc'" == "translog" & `ncols' != 5 {
            di as error "[pte] Error: e(b) has `ncols' columns, expected 5 for Translog"
            `_pte_clear_eclass'
            exit 198
        }

        // recovery must read the production-function beta vector,
        // not an unrelated live regression result that happens to have the
        // right width. The exact coefficient layout is part of the bridge
        // contract published by _pte_prodfunc.
        if `"`_pte_bnames'"' != `"`_pte_expected_bnames'"' {
            di as error "[pte] Error: current e(b) does not match the coefficient layout"
            di as error "[pte]        Found:    `_pte_bnames'"
            di as error "[pte]        Expected: `_pte_expected_bnames'"
            di as error "[pte]        Please run _pte_prodfunc.ado first"
            `_pte_clear_eclass'
            exit 198
        }

        local _pte_live_free `"`e(free)'"'
        if "`_pte_live_free'" != "" & "`_pte_live_free'" != "`free'" {
            di as error "[pte] Error: current e(free) does not match free(`free')"
            di as error "[pte]        Current e(free): `_pte_live_free'"
            di as error "[pte]        Please run _pte_prodfunc.ado with matching free()/state() first"
            `_pte_clear_eclass'
            exit 198
        }

        local _pte_live_state `"`e(state)'"'
        if "`_pte_live_state'" != "" & "`_pte_live_state'" != "`state'" {
            di as error "[pte] Error: current e(state) does not match state(`state')"
            di as error "[pte]        Current e(state): `_pte_live_state'"
            di as error "[pte]        Please run _pte_prodfunc.ado with matching free()/state() first"
            `_pte_clear_eclass'
            exit 198
        }

        local _pte_live_pfunc `"`e(prodfunc)'"'
        if "`_pte_live_pfunc'" == "" {
            local _pte_live_pfunc `"`e(pfunc)'"'
        }
        if "`_pte_live_pfunc'" != "" & "`_pte_live_pfunc'" != "`pfunc'" {
            di as error "[pte] Error: current production-function metadata does not match pfunc(`pfunc')"
            di as error "[pte]        Current live branch: `"_pte_live_pfunc'"'"
            di as error "[pte]        Please run _pte_prodfunc.ado first"
            `_pte_clear_eclass'
            exit 198
        }
    }
    else {
        // Standalone mode still enforces the same branch contract and input types.
        if !inlist("`pfunc'", "cd", "translog") {
            di as error "[pte] Error: pfunc must be 'cd' or 'translog', got '`pfunc''"
            `_pte_clear_eclass'
            exit 198
        }
        local ncols = cond("`pfunc'" == "cd", 2, 5)

        capture confirm variable `free', exact
        if _rc != 0 {
            di as error "[pte] Error: free variable '`free'' not found"
            `_pte_clear_eclass'
            exit 111
        }
        capture confirm numeric variable `free'
        if _rc != 0 {
            di as error "[pte] Error: free variable '`free'' must be numeric"
            `_pte_clear_eclass'
            exit 111
        }
        
        capture confirm variable `state', exact
        if _rc != 0 {
            di as error "[pte] Error: state variable '`state'' not found"
            `_pte_clear_eclass'
            exit 111
        }
        capture confirm numeric variable `state'
        if _rc != 0 {
            di as error "[pte] Error: state variable '`state'' must be numeric"
            `_pte_clear_eclass'
            exit 111
        }
    }
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "Production Function Interface Validation"
        di as text "{hline 60}"
        di as text "  phi:             " as result %10.0fc `n_phi_valid' as text " valid observations"
        di as text "  e(b):            " as result %10.0f `ncols' as text " parameters"
        di as text "  Production func: " as result %10s "`pfunc'"
        di as text "  Status:          " as result "PASSED"
        di as text "{hline 60}"
    }
    
    if `mode_epic001' {
        // The live bridge reads the exact coefficient layout posted by _pte_prodfunc.
        scalar _pte_beta_l = `_pte_bmat'[1,1]
        scalar _pte_beta_k = `_pte_bmat'[1,2]
        
        if "`pfunc'" == "translog" {
            scalar _pte_beta_ll = `_pte_bmat'[1,3]
            scalar _pte_beta_kk = `_pte_bmat'[1,4]
            scalar _pte_beta_lk = `_pte_bmat'[1,5]
        }
    }
    else {
        // Standalone mode treats the supplied beta values as the full production frontier.
        scalar _pte_beta_l = `beta_l'
        scalar _pte_beta_k = `beta_k'
        
        if "`pfunc'" == "translog" {
            scalar _pte_beta_ll = `beta_ll'
            scalar _pte_beta_kk = `beta_kk'
            scalar _pte_beta_lk = `beta_lk'
        }
    }
    
    // Drop only the exact omega column so omega_* simulation variables survive.
    capture confirm new variable omega
    if _rc {
        // omega exact name is taken → drop it without touching omega_* shadows
        capture confirm variable omega, exact
        if _rc == 0 {
            drop omega
        }
    }

    if "`pfunc'" == "cd" {
        // CD recovery subtracts only the linear free and state elasticities.
        if "`legacyfloatomega'" != "" {
            quietly gen float omega = phi - _pte_beta_l * `free' - _pte_beta_k * `state' if `_pte_sample'
        }
        else {
            quietly gen double omega = phi - _pte_beta_l * `free' - _pte_beta_k * `state' if `_pte_sample'
        }
    }
    else if "`pfunc'" == "translog" {
        // Translog recovery subtracts the full curvature and interaction terms
        // so omega stays comparable to the paper's realized productivity object.
        if "`legacyfloatomega'" != "" {
            quietly gen float omega = phi - _pte_beta_l * `free' - _pte_beta_k * `state' ///
                                     - _pte_beta_ll * (`free')^2 - _pte_beta_kk * (`state')^2 ///
                                     - _pte_beta_lk * `free' * `state' if `_pte_sample'
        }
        else {
            quietly gen double omega = phi - _pte_beta_l * `free' - _pte_beta_k * `state' ///
                                     - _pte_beta_ll * (`free')^2 - _pte_beta_kk * (`state')^2 ///
                                     - _pte_beta_lk * `free' * `state' if `_pte_sample'
        }
    }

    // Missing omega values should reflect missing inputs on the active sample,
    // not silent reopening of excluded rows.
    quietly count if `_pte_sample' & !missing(omega)
    local n_omega = r(N)

    if `n_omega' == 0 {
        di as error "[pte] Error: no recoverable omega values in the active sample"
        di as error "[pte]        Check phi/free/state inputs or touse() restrictions"
        capture confirm variable omega, exact
        if _rc == 0 capture drop omega
        `_pte_clear_eclass'
        exit 2000
    }
    
    quietly count if `_pte_sample' & missing(omega) & !missing(phi)
    local n_missing = r(N)
    
    if `n_missing' > 0 & "`nodiagnose'" == "" {
        di as text ""
        di as text "[pte] Note: `n_missing' obs have missing omega due to missing inputs"
    }
    
    label variable omega "Recovered productivity (log TFP)"

    // Verify mode compares the phi identity against the direct output-based
    // formula used in the ATT code path.
    local _pte_verify_corr = .
    local _pte_verify_pass = 0
    local _pte_verify_maxdiff = .
    local _pte_verify_meandiff = .
    
    if "`verify'" != "" {
        
        tempvar omega_direct

        if !`_pte_verify_has_controls' {
            scalar _pte_beta_t = `_pte_beta_t_val'
        }
        
        if "`pfunc'" == "cd" {
            // This mirrors the direct CD formula used when ATT code reconstructs omega.
            quietly gen double `omega_direct' = `depvar' ///
                - _pte_beta_l * `free' ///
                - _pte_beta_k * `state'
        }
        else if "`pfunc'" == "translog" {
            // This mirrors the direct translog formula used in the ATT simulation path.
            quietly gen double `omega_direct' = `depvar' ///
                - _pte_beta_l * `free' ///
                - _pte_beta_k * `state' ///
                - _pte_beta_ll * (`free')^2 ///
                - _pte_beta_kk * (`state')^2 ///
                - _pte_beta_lk * `free' * `state'
        }

        if `_pte_verify_has_controls' {
            local _pte_ctrl_j = 0
            foreach _pte_ctrl of local _pte_verify_control_vars {
                local ++_pte_ctrl_j
                scalar _pte_beta_ctrl = `_pte_verify_controls'[1, `_pte_ctrl_j']
                quietly replace `omega_direct' = `omega_direct' - _pte_beta_ctrl * `_pte_ctrl'
                scalar drop _pte_beta_ctrl
            }
        }
        else if `_pte_verify_has_legacy_time' {
            quietly replace `omega_direct' = `omega_direct' - _pte_beta_t * `time'
        }
        
        // The comparison uses only rows where both formulas are numerically defined.
        quietly count if !missing(omega) & !missing(`omega_direct')
        local n_valid_pair = r(N)
        
        if `n_valid_pair' == 0 {
            di as error "[pte] Error: No valid observations for equivalence check"
            capture scalar drop _pte_beta_t
            capture confirm variable omega, exact
            if _rc == 0 capture drop omega
            `_pte_clear_eclass'
            exit 2000
        }
        
        if `n_valid_pair' == 1 {
            // With one paired row, equivalence collapses to an exact numeric identity.
            tempvar _diff_single
            quietly gen double `_diff_single' = `omega_direct' - omega ///
                if !missing(omega) & !missing(`omega_direct')
            quietly summarize `_diff_single'
            if abs(r(mean)) < 1e-10 {
                di as text "[pte] Note: Single observation - skipping correlation, direct comparison passed"
                local _pte_verify_corr = .
                local _pte_verify_pass = 1
                local _pte_verify_maxdiff = abs(r(mean))
                local _pte_verify_meandiff = abs(r(mean))
            }
            else {
                di as error "[pte] Error: Single observation values differ by " %12.10f abs(r(mean))
                capture scalar drop _pte_beta_t
                capture confirm variable omega, exact
                if _rc == 0 capture drop omega
                `_pte_clear_eclass'
                exit 2001
            }
        }
        else {
            // Correlation is informative only when both series have nontrivial variation.
            quietly summarize omega if !missing(omega) & !missing(`omega_direct')
            local sd_phi = r(sd)
            quietly summarize `omega_direct' if !missing(omega) & !missing(`omega_direct')
            local sd_direct = r(sd)
            
            if `sd_phi' < 1e-10 | `sd_direct' < 1e-10 {
                // Constant series imply exact affine alignment is already pinned by the diff check below.
                di as text "[pte] Note: Near-zero variance detected, setting correlation = 1"
                local _pte_verify_corr = 1
            }
            else {
                quietly correlate omega `omega_direct' ///
                    if !missing(omega) & !missing(`omega_direct')
                local _pte_verify_corr = r(rho)
                
                // A negative correlation signals that the reconstructed frontier
                // is structurally wrong, not just numerically noisy.
                if `_pte_verify_corr' < 0 {
                    di as error "[pte] CRITICAL: Negative correlation (`_pte_verify_corr') detected"
                    di as error "[pte]          This indicates an implementation bug"
                    if "`debug'" != "" {
                        quietly summarize omega if !missing(omega) & !missing(`omega_direct')
                        di as error "[pte]   phi method mean:    " %12.6f r(mean)
                        quietly summarize `omega_direct' if !missing(omega) & !missing(`omega_direct')
                        di as error "[pte]   direct method mean: " %12.6f r(mean)
                        di as error "[pte]   Possible causes: sign error, variable mismatch, or data corruption"
                    }
                    capture scalar drop _pte_beta_t
                    capture confirm variable omega, exact
                    if _rc == 0 capture drop omega
                    `_pte_clear_eclass'
                    exit 2002
                }
            }
            
            tempvar _diff
            quietly gen double `_diff' = `omega_direct' - omega ///
                if !missing(omega) & !missing(`omega_direct')
            quietly summarize `_diff', detail
            local _pte_verify_maxdiff = max(abs(r(min)), abs(r(max)))
            local _pte_verify_meandiff = abs(r(mean))
            local _pte_verify_sddiff = r(sd)
            local _pte_verify_p1 = r(p1)
            local _pte_verify_p50 = r(p50)
            local _pte_verify_p99 = r(p99)
            
            // A high correlation alone is not sufficient because affine shifts
            // preserve corr() while violating the pointwise omega identity.
            local _pte_verify_corr_ok = (`_pte_verify_corr' > 0.9999)
            local _pte_verify_diff_ok = ///
                (`_pte_verify_maxdiff' < 1e-8 & `_pte_verify_meandiff' < 1e-10)

            if !`_pte_verify_corr_ok' | !`_pte_verify_diff_ok' {
                di as error ""
                di as error "[pte] Method equivalence FAILED"
                if !`_pte_verify_corr_ok' {
                    di as error "[pte]   Correlation = " %9.7f `_pte_verify_corr' " <= 0.9999"
                }
                if !`_pte_verify_diff_ok' {
                    if `_pte_verify_maxdiff' >= 1e-8 {
                        di as error "[pte]   Max absolute diff = " %12.10f `_pte_verify_maxdiff' " >= 1e-8"
                    }
                    if `_pte_verify_meandiff' >= 1e-10 {
                        di as error "[pte]   Mean absolute diff = " %12.10f `_pte_verify_meandiff' " >= 1e-10"
                    }
                }
                di as error "[pte]   Check production function output (phi, e(b), e(beta_controls))"
                
                if "`debug'" != "" {
                    di as text ""
                    di as text "{hline 60}"
                    di as text "Equivalence Diagnostic Report"
                    di as text "{hline 60}"
                    di as text "  Max absolute diff:  " as result %12.10f `_pte_verify_maxdiff'
                    di as text "  Mean absolute diff: " as result %12.10f `_pte_verify_meandiff'
                    di as text "  Std of diff:        " as result %12.10f `_pte_verify_sddiff'
                    di as text "  Diff percentiles:"
                    di as text "    p1:               " as result %12.10f `_pte_verify_p1'
                    di as text "    p50:              " as result %12.10f `_pte_verify_p50'
                    di as text "    p99:              " as result %12.10f `_pte_verify_p99'
                    di as text "{hline 60}"
                }
                
                capture scalar drop _pte_beta_t
                capture confirm variable omega, exact
                if _rc == 0 capture drop omega
                `_pte_clear_eclass'
                exit 2001
            }
            else {
                local _pte_verify_pass = 1
                
                if "`nodiagnose'" == "" {
                    di as text ""
                    di as text "[pte] Method equivalence verified: correlation = " ///
                        as result %9.7f `_pte_verify_corr' as text ", max diff = " ///
                        as result %12.2e `_pte_verify_maxdiff'
                }
            }
        }
        
        if "`debug'" != "" & `_pte_verify_pass' == 1 & `n_valid_pair' > 1 {
            di as text ""
            di as text "{hline 60}"
            di as text "Equivalence Diagnostic Report (debug)"
            di as text "{hline 60}"
            di as text "  Correlation:        " as result %12.10f `_pte_verify_corr'
            di as text "  Max absolute diff:  " as result %12.10f `_pte_verify_maxdiff'
            di as text "  Mean absolute diff: " as result %12.10f `_pte_verify_meandiff'
            di as text "  Std of diff:        " as result %12.10f `_pte_verify_sddiff'
            di as text "  Diff percentiles:"
            di as text "    p1:               " as result %12.10f `_pte_verify_p1'
            di as text "    p50:              " as result %12.10f `_pte_verify_p50'
            di as text "    p99:              " as result %12.10f `_pte_verify_p99'
            di as text "  Valid pairs:        " as result %12.0fc `n_valid_pair'
            di as text "{hline 60}"
        }
        
        if !`_pte_verify_has_controls' {
            capture scalar drop _pte_beta_t
        }
    }

    quietly summarize omega if `_pte_sample', detail
    local omega_mean = r(mean)
    local omega_sd = r(sd)
    local omega_min = r(min)
    local omega_max = r(max)
    local omega_p50 = r(p50)
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "Productivity Recovery Summary"
        di as text "{hline 60}"
        di as text "  Production function:         " as result %10s "`pfunc'"
        di as text "  Valid omega observations:    " as result %10.0fc `n_omega'
        di as text "  Missing (input missing):     " as result %10.0fc `n_missing'
        di as text ""
        di as text "  omega Statistics:"
        di as text "    Mean:                      " as result %10.4f `omega_mean'
        di as text "    Std. Dev.:                 " as result %10.4f `omega_sd'
        di as text "    Min:                       " as result %10.4f `omega_min'
        di as text "    Median:                    " as result %10.4f `omega_p50'
        di as text "    Max:                       " as result %10.4f `omega_max'
        di as text "{hline 60}"
        
        // Large omega magnitudes or elasticities far outside unit intervals
        // often indicate a data or staging-contract problem upstream.
        if `omega_max' > 10 | `omega_min' < -10 {
            di as text ""
            di as text "[pte] Warning: omega has extreme values (outside [-10, 10])"
            di as text "[pte]          This may indicate data issues or outlier firms"
        }
        
        if _pte_beta_l < 0 | _pte_beta_l > 1 {
            di as text "[pte] Warning: beta_l = " %6.4f _pte_beta_l " outside typical [0,1] range"
        }
        if _pte_beta_k < 0 | _pte_beta_k > 1 {
            di as text "[pte] Warning: beta_k = " %6.4f _pte_beta_k " outside typical [0,1] range"
        }
    }

    tempvar _pte_esample
    quietly gen byte `_pte_esample' = (`_pte_sample' & !missing(omega))

    // e(sample) is the omega-ready support used by downstream evolution and ATT code.
    ereturn clear
    ereturn post, esample(`_pte_esample') obs(`n_omega')
    
    ereturn scalar N = `n_omega'
    ereturn scalar N_omega = `n_omega'
    ereturn scalar n_missing = `n_missing'
    ereturn scalar omega_mean = `omega_mean'
    ereturn scalar omega_sd = `omega_sd'
    ereturn scalar omega_min = `omega_min'
    ereturn scalar omega_max = `omega_max'
    ereturn scalar omega_p50 = `omega_p50'
    
    ereturn scalar beta_l = _pte_beta_l
    ereturn scalar beta_k = _pte_beta_k
    
    if "`pfunc'" == "translog" {
        ereturn scalar beta_ll = _pte_beta_ll
        ereturn scalar beta_kk = _pte_beta_kk
        ereturn scalar beta_lk = _pte_beta_lk
    }
    
    ereturn local pfunc "`pfunc'"
    ereturn local prodfunc "`pfunc'"
    ereturn local free "`free'"
    ereturn local state "`state'"
    ereturn local cmd "_pte_omega_recovery"
    
    // The verification returns let callers assert the phi/direct identity programmatically.
    if "`verify'" != "" {
        ereturn scalar method_corr = `_pte_verify_corr'
        ereturn scalar equiv_pass = `_pte_verify_pass'
        ereturn scalar max_diff = `_pte_verify_maxdiff'
        ereturn scalar mean_diff = `_pte_verify_meandiff'
    }
    
    capture scalar drop _pte_beta_l
    capture scalar drop _pte_beta_k
    capture scalar drop _pte_beta_ll
    capture scalar drop _pte_beta_kk
    capture scalar drop _pte_beta_lk
    capture matrix drop __pte_B

    // Successful cleanup probes above can leave caller _rc at the last
    // missing-object code (for example 111). Reset it explicitly so a
    // successful recovery obeys the standard Stata rc==0 contract.
    capture confirm integer number 1
    exit 0
    
end
