*! _pte_call_endopoly_standard.ado
*! Standard (non-treatdependent) endopolyprodest engine for pte
*! Faithful to paper DO: digitalization_att_estimation_main_new.do line 377
*! version 1.0.0  2026-06-09

version 14.0
capture program drop _pte_call_endopoly_standard
program define _pte_call_endopoly_standard, eclass
    version 14.0
    
    // ═══════════════════════════════════════════════════════════════════════
    // Syntax parsing
    // ═══════════════════════════════════════════════════════════════════════
    syntax, DEPVAR(varname) FREE(varname) STATE(varname) PROXY(varname) ///
        ENDO(varname) ///
        [CONTROL(varlist) PFUNC(string) OMEGAPOLY(integer 3) ///
         MID(varname) TOUSE(varname) VERBOSE]
    
    // ═══════════════════════════════════════════════════════════════════════
    // Defaults and validation
    // ═══════════════════════════════════════════════════════════════════════
    if "`pfunc'" == "" local pfunc "translog"
    if "`mid'" == "" local mid "_pte_mid"
    
    // Validate mid variable
    capture confirm variable `mid', exact
    if _rc {
        di as error "[pte engine(endopoly)] Transition variable `mid' not found"
        exit 111
    }
    
    // Validate endopolyprodest availability
    capture which endopolyprodest
    if _rc {
        di as error "[pte engine(endopoly)] endopolyprodest not installed"
        di as error "      Install with: ssc install endopolyprodest"
        exit 601
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Construct command (faithful to paper DO line 377)
    // DO: endopolyprodest lny if indid_adj==`i'&mid!=1, method(lp)
    //     free(lnl) proxy(lnm) state(lnk) control(t) endo(treat_post)
    //     translog valueadded acf reps(5) prodpoly(3)
    // ═══════════════════════════════════════════════════════════════════════
    
    // Build sample condition
    local _sample_cond "`mid' == 0"
    if "`touse'" != "" {
        local _sample_cond "`touse' & `_sample_cond'"
    }
    
    // Count estimation sample
    quietly count if `_sample_cond'
    local N_est = r(N)
    if `N_est' == 0 {
        di as error "[pte engine(endopoly)] No available observations after excluding transitions"
        exit 2000
    }
    
    // Count excluded transitions
    if "`touse'" != "" {
        quietly count if `touse' & `mid' == 1
    }
    else {
        quietly count if `mid' == 1
    }
    local N_excluded = r(N)
    
    // Base command
    local cmd "endopolyprodest `depvar' if `_sample_cond'"
    
    // Required parameters (order matches paper DO)
    local cmd "`cmd', method(lp)"
    local cmd "`cmd' free(`free')"
    local cmd "`cmd' proxy(`proxy')"
    local cmd "`cmd' state(`state')"
    
    // Control variables
    if "`control'" != "" {
        local cmd "`cmd' control(`control')"
    }
    
    // Endogenous treatment variable
    local cmd "`cmd' endo(`endo')"
    
    // Production function type
    if "`pfunc'" == "translog" {
        local cmd "`cmd' translog"
    }
    
    // Fixed options matching paper DO
    local cmd "`cmd' valueadded acf"
    
    // Numeric parameters: reps(5) matches DO industry estimation
    local cmd "`cmd' reps(5) prodpoly(`omegapoly')"
    
    // ═══════════════════════════════════════════════════════════════════════
    // Display and execute
    // ═══════════════════════════════════════════════════════════════════════
    if "`verbose'" != "" {
        di as text ""
        di as text "{hline 70}"
        di as text "engine(endopoly) standard estimation"
        di as text "{hline 70}"
        di as text "  Dependent:  `depvar'"
        di as text "  Free:       `free'"
        di as text "  State:      `state'"
        di as text "  Proxy:      `proxy'"
        di as text "  Control:    `control'"
        di as text "  Endo:       `endo'"
        di as text "  Pfunc:      `pfunc'"
        di as text "  Omegapoly:  `omegapoly'"
        di as text "  Est. obs:   `N_est'"
        di as text "  Excluded:   `N_excluded' (transition periods)"
        di as text ""
        di as text "Command:"
        di as input "  `cmd'"
        di as text "{hline 70}"
    }
    
    // Execute endopolyprodest
    capture noisily `cmd'
    local rc = _rc
    
    if `rc' {
        di as error "[pte engine(endopoly)] endopolyprodest failed (rc = `rc')"
        di as error "  Command: `cmd'"
        exit `rc'
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Extract coefficients and generate phi/omega
    // ═══════════════════════════════════════════════════════════════════════
    // Paper DO omega formula (translog):
    //   omega = lny - _b[lnl]*lnl - _b[lnk]*lnk
    //         - _b[var_1_1]*lnl^2 - _b[var_1_2]*lnl*lnk - _b[var_2_2]*lnk^2
    //         - _b[t]*t
    // Paper DO omega formula (cd):
    //   omega = lny - _b[lnl]*lnl - _b[lnk]*lnk - _b[t]*t
    
    // Extract beta coefficients from endopolyprodest
    local beta_l = _b[`free']
    local beta_k = _b[`state']
    
    // Extract control coefficients
    local beta_controls_sum ""
    if "`control'" != "" {
        foreach cv of local control {
            capture local _bc_`cv' = _b[`cv']
            if _rc == 0 {
                local beta_controls_sum "`beta_controls_sum' - (`_bc_`cv'') * `cv'"
            }
        }
    }
    
    // Build phi and omega
    // phi = lny minus control effects (matching baseline _pte_prodfunc convention)
    // omega = phi - f(inputs; beta)
    
    if "`pfunc'" == "translog" {
        // Translog: extract quadratic coefficients
        // endopolyprodest names: var_1_1 (l^2), var_1_2 (l*k), var_2_2 (k^2)
        local beta_ll = _b[var_1_1]
        local beta_kk = _b[var_2_2]
        local beta_lk = _b[var_1_2]
        
        // Generate phi = lny - controls (paper convention)
        capture drop phi
        quietly gen double phi = `depvar' `beta_controls_sum'
        label variable phi "First-stage fitted value (endopoly engine, phi=y-controls)"
        
        // Generate omega = phi - f(inputs; beta)
        capture drop omega
        quietly gen double omega = phi ///
            - (`beta_l') * `free' ///
            - (`beta_k') * `state' ///
            - (`beta_ll') * `free'^2 ///
            - (`beta_lk') * `free' * `state' ///
            - (`beta_kk') * `state'^2
        label variable omega "Implied productivity (endopoly engine)"
    }
    else {
        // CD: simple linear
        // Generate phi = lny - controls
        capture drop phi
        quietly gen double phi = `depvar' `beta_controls_sum'
        label variable phi "First-stage fitted value (endopoly engine, phi=y-controls)"
        
        // Generate omega = phi - beta_l*l - beta_k*k
        capture drop omega
        quietly gen double omega = phi ///
            - (`beta_l') * `free' ///
            - (`beta_k') * `state'
        label variable omega "Implied productivity (endopoly engine)"
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Post e() results matching _pte_prodfunc contract
    // ═══════════════════════════════════════════════════════════════════════
    
    // Build beta matrix compatible with downstream pte pipeline
    tempname b_post V_post beta_ctrl
    if "`pfunc'" == "translog" {
        matrix `b_post' = (`beta_l', `beta_k', `beta_ll', `beta_kk', `beta_lk')
        matrix colnames `b_post' = `free' `state' l2 k2 l1k1
    }
    else {
        matrix `b_post' = (`beta_l', `beta_k')
        matrix colnames `b_post' = `free' `state'
    }
    matrix `V_post' = J(colsof(`b_post'), colsof(`b_post'), 0)
    matrix colnames `V_post' = `: colnames `b_post''
    matrix rownames `V_post' = `: colnames `b_post''
    
    // Build beta_controls matrix for downstream compatibility
    if "`control'" != "" {
        local n_ctrl : word count `control'
        matrix `beta_ctrl' = J(1, `n_ctrl', 0)
        local _ci = 0
        foreach cv of local control {
            local _ci = `_ci' + 1
            capture local _bval = _b[`cv']
            if _rc == 0 {
                matrix `beta_ctrl'[1, `_ci'] = `_bval'
            }
        }
        matrix colnames `beta_ctrl' = `control'
    }
    else {
        matrix `beta_ctrl' = J(1, 1, 0)
        matrix colnames `beta_ctrl' = _cons
    }
    
    // Post estimation results
    // Generate esample marker
    tempvar _ep_esample
    quietly gen byte `_ep_esample' = (`_sample_cond')
    
    ereturn post `b_post' `V_post', esample(`_ep_esample') obs(`N_est')
    
    // Store metadata
    ereturn scalar N_excluded = `N_excluded'
    ereturn scalar omegapoly = `omegapoly'
    ereturn local  pfunc "`pfunc'"
    ereturn local  prodfunc "`pfunc'"
    ereturn local  engine "endopoly"
    ereturn local  engine_cmd "`cmd'"
    ereturn local  cmd "_pte_prodfunc"
    ereturn matrix beta_controls = `beta_ctrl'
    
    // Store beta_t scalar for single-control compatibility
    if "`control'" != "" {
        local n_ctrl : word count `control'
        if `n_ctrl' == 1 {
            capture local _bt = _b[`control']
            if _rc == 0 {
                // Retrieve from stored matrix since ereturn post cleared _b
                ereturn scalar beta_t = `beta_ctrl'[1, 1]
            }
        }
    }
    
    if "`verbose'" != "" {
        di as text ""
        di as text "[pte engine(endopoly)] Estimation complete"
        di as text "  beta_`free' = " %9.6f `beta_l'
        di as text "  beta_`state' = " %9.6f `beta_k'
        if "`pfunc'" == "translog" {
            di as text "  beta_ll = " %9.6f `beta_ll'
            di as text "  beta_kk = " %9.6f `beta_kk'
            di as text "  beta_lk = " %9.6f `beta_lk'
        }
        quietly summarize omega, detail
        di as text "  omega: mean=" %8.4f r(mean) " sd=" %8.4f r(sd)
        di as text ""
    }
    
end
