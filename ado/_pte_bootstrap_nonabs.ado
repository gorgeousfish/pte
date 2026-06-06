*! _pte_bootstrap_nonabs.ado
*! Non-absorbing Bootstrap Inference Module
*!
*! Implements bootstrap inference for non-absorbing treatment:
*!   - Four-class stratification (strata_na): never-switch, entry-only, exit-only, both
*!   - Dual ATT estimation: ATT+ (entry) and ATT- (exit)
*!   - Independent failure handling: ATT+/ATT- can fail independently
*!   - Automatic degradation to absorbing bootstrap when no exit events
*!   - Two-layer seed management: outer=b, inner=123456
*!     except benchmark translog replicate(order1), which uses 10000

version 14.0
capture program drop _pte_bootstrap_nonabs
program define _pte_bootstrap_nonabs, eclass
    version 14.0
    local _pte_cmdline `"`0'"'
    syntax, treatment(varname) ///
        depvar(varname) free(varname) state(varname) proxy(varname) ///
        id(varname) time(varname) ///
        [omegapoly(integer 3) ///
         attperiods(integer 4) ///
         persistperiods(integer 0) ///
         nsim(integer -1) ///
         breps(integer 100) ///
         inner_seed(integer 123456) ///
         prodfunc(string) ///
         poly(integer -1) ///
         control(varlist) ///
         level(integer 95) ///
         NOTRIMeps ///
         NOLOg ///
         NODIAGnose ///
         saving(string) ///
         REPlicate ///
         VERBOSE]

    // ================================================================
    // Step 0: Input validation (Task 97 partial)
    // ================================================================
    if `breps' < 2 {
        di as error "[pte] Error: breps must be >= 2"
        exit 198
    }
    if `level' < 10 | `level' > 99 {
        di as error "[pte] Error: level must be between 10 and 99"
        exit 198
    }
    if "`prodfunc'" == "" {
        local prodfunc "cd"
    }
    local _pte_has_poly = regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])poly[(]")
    local _pte_has_omegapoly = regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])omegapoly[(]")
    if `_pte_has_poly' {
        if `_pte_has_omegapoly' & `poly' != `omegapoly' {
            di as error "[pte] Error: cannot specify both poly(`poly') and omegapoly(`omegapoly')"
            exit 198
        }
        local omegapoly = `poly'
    }
    local poly = `omegapoly'
    if "`prodfunc'" != "cd" & "`prodfunc'" != "translog" {
        di as error "[pte] Error: prodfunc must be 'cd' or 'translog'"
        exit 198
    }
    if `nsim' == -1 {
        if `omegapoly' == 1 {
            local nsim = 1
        }
        else {
            local nsim = 100
        }
    }
    if `nsim' < 1 {
        di as error "[pte] Error: nsim must be >= 1"
        exit 198
    }
    
    // Verify panel structure. Non-absorbing bootstrap uses the live panel axis
    // immediately for L.D, firm-level strata, and cluster resampling, so the
    // ambient xtset must match the requested id()/time() contract exactly.
    capture _xt, trequired
    if _rc != 0 {
        di as error "[pte] Error: data must be xtset as panel"
        exit 459
    }
    quietly xtset
    local panelvar "`r(panelvar)'"
    local timevar "`r(timevar)'"
    local _pte_boot_delta "`r(tdelta)'"
    local _pte_boot_delta_opt ""
    if "`_pte_boot_delta'" != "" {
        local _pte_boot_delta_opt ", delta(`_pte_boot_delta')"
    }
    if "`panelvar'" != "`id'" | "`timevar'" != "`time'" {
        di as error "[pte] xtset must match id() and time()"
        di as error "  current xtset: `panelvar' `timevar'"
        di as error "  requested:     `id' `time'"
        di as error "  run {bf:xtset `id' `time'} before calling _pte_bootstrap_nonabs"
        exit 459
    }
    
    // Verify required variables
    foreach v in `depvar' `free' `state' `proxy' `treatment' {
        capture confirm variable `v', exact
        if _rc != 0 {
            di as error "[pte] Error: variable '`v'' not found"
            exit 111
        }
    }
    
    local is_verbose = ("`verbose'" != "")
    local do_trim = ("`notrimeps'" == "")
    if "`replicate'" != "" & "`prodfunc'" == "translog" & `omegapoly' == 1 {
        local inner_seed = 10000
        local inner_seed_source "replicate"
    }
    else {
        local inner_seed_source = cond(`inner_seed' == 123456, "default", "user")
    }
    local _pte_nonabs_generated_scratch ""
    local _pte_nonabs_scratch "_pte_has_entry _pte_has_exit _pte_strata_na _pte_firm_bs att_plus_sample att_minus_sample nt_plus nt_minus"
    local _pte_nonabs_created_scratch ""
    foreach _pte_var of local _pte_nonabs_scratch {
        capture confirm variable `_pte_var', exact
        if _rc != 0 {
            local _pte_nonabs_created_scratch "`_pte_nonabs_created_scratch' `_pte_var'"
        }
    }
    
    // Like the absorbing bootstrap helper, the non-absorbing wrapper runs a
    // full point-estimate pipeline before it posts its own e() bundle. If a
    // point-estimate worker fails, the caller must not be left in the last
    // internal worker's e()/data/RNG state.
    tempname _pte_prev_est
    local _pte_has_prev_est = 0
    capture local _pte_prev_cmd `"`e(cmd)'"'
    if _rc == 0 {
        capture estimates store `_pte_prev_est', copy
        if _rc == 0 {
            local _pte_has_prev_est = 1
        }
    }

    // Snapshot caller data/RNG before any exact-name nonabsorbing scratch is
    // written. The wrapper must restore the caller's certified namespace on
    // success and on every fail-close path.
    tempfile orig_data
    qui save `orig_data', replace
    local orig_rngstate = c(rngstate)

    // ================================================================
    // Step 1: Non-absorbing detection (Task 7, 105)
    // Detect entry/exit events and determine degrade_mode
    // ================================================================
    
    // Verify G variable exists
    capture confirm variable G, exact
    if _rc != 0 {
        // Try to generate G from D
        capture confirm variable `treatment', exact
        if _rc != 0 {
            di as error "[pte] Error: treatment variable '`treatment'' not found"
            exit 111
        }
        qui gen G = sign(`treatment' - L.`treatment')
        local _pte_nonabs_generated_scratch "G"
        if `is_verbose' {
            di as text "[pte] Generated G = sign(D - L.D)"
        }
    }
    
    // Count entry and exit events
    qui count if G == 1
    local n_entry = r(N)
    qui count if G == -1
    local n_exit = r(N)
    
    // Determine degrade_mode (Task 7)
    // mode=0: full non-absorbing (entry>0 & exit>0)
    // mode=1: absorbing degradation (entry>0 & exit=0)
    // mode=2: exit-only (entry=0 & exit>0)
    // mode=3: error - no switching events
    local degrade_mode = 3
    if `n_entry' > 0 & `n_exit' > 0 {
        local degrade_mode = 0
    }
    else if `n_entry' > 0 & `n_exit' == 0 {
        local degrade_mode = 1
    }
    else if `n_entry' == 0 & `n_exit' > 0 {
        local degrade_mode = 2
    }
    
    // Task 105: No switching events error
    if `degrade_mode' == 3 {
        di as error "[pte] Error: no treatment switching events detected in data"
        di as error "[pte] n_entry = `n_entry', n_exit = `n_exit'"
        foreach _pte_var of local _pte_nonabs_generated_scratch {
            capture drop `_pte_var'
        }
        exit 198
    }
    
    // Task 8: Absorbing degradation
    if `degrade_mode' == 1 {
        if `persistperiods' > 0 {
            di as error "[pte] Error: persistperiods() cannot be honored when non-absorbing bootstrap degrades to the absorbing helper"
            di as error "[pte] No exit events were detected, so the absorbing bootstrap route would ignore the persistent-switch filter"
            di as error "[pte] Use persistperiods(0), or call the dedicated non-absorbing helper workflow on data with entry and exit events"
            qui use `orig_data', clear
            qui xtset `panelvar' `timevar'`_pte_boot_delta_opt'
            foreach _pte_var of local _pte_nonabs_generated_scratch {
                capture drop `_pte_var'
            }
            foreach _pte_var of local _pte_nonabs_created_scratch {
                capture drop `_pte_var'
            }
            capture set rngstate `orig_rngstate'
            if `_pte_has_prev_est' {
                capture estimates restore `_pte_prev_est'
                capture estimates drop `_pte_prev_est'
            }
            else {
                capture ereturn clear
            }
            exit 198
        }
        di as text ""
        di as text "[pte] Note: no exit events detected, degrading to absorbing Bootstrap"
        di as text "[pte] Calling standard _pte_bootstrap..."
        
        // Build options for standard bootstrap
        local _bs_opts "treatment(`treatment') depvar(`depvar') free(`free')"
        local _bs_opts "`_bs_opts' state(`state') proxy(`proxy') id(`id') time(`time')"
        local _bs_opts "`_bs_opts' omegapoly(`omegapoly') attperiods(`attperiods')"
        local _bs_opts "`_bs_opts' nsim(`nsim') breps(`breps') inner_seed(`inner_seed')"
        local _bs_opts "`_bs_opts' prodfunc(`prodfunc') poly(`poly') level(`level')"
        if "`control'" != "" local _bs_opts "`_bs_opts' control(`control')"
        if "`notrimeps'" != "" local _bs_opts "`_bs_opts' notrimeps"
        if "`nolog'" != "" local _bs_opts "`_bs_opts' nolog"
        if "`nodiagnose'" != "" local _bs_opts "`_bs_opts' nodiagnose"
        if "`saving'" != "" local _bs_opts "`_bs_opts' saving(`saving')"
        if "`replicate'" != "" local _bs_opts "`_bs_opts' replicate"
        foreach _pte_var of local _pte_nonabs_generated_scratch {
            capture drop `_pte_var'
        }
        _pte_bootstrap, `_bs_opts'
        exit
    }
    
    // Determine ATT directions to estimate
    local do_att_plus = (`n_entry' > 0)
    local do_att_minus = (`n_exit' > 0)
    
    if `is_verbose' {
        di as text "[pte] Non-absorbing detection:"
        di as text "  degrade_mode = `degrade_mode'"
        di as text "  n_entry = `n_entry', n_exit = `n_exit'"
        di as text "  do_att_plus = `do_att_plus', do_att_minus = `do_att_minus'"
    }

    // ================================================================
    // Step 2: Four-class stratification (Task 1-6)
    // strata_na: 1=never-switch, 2=entry-only, 3=exit-only, 4=both
    // ================================================================
    
    // Task 1: Validate G variable
    qui count if !inlist(G, -1, 0, 1) & !missing(G)
    if r(N) > 0 {
        di as error "[pte] Error: G contains values outside {-1, 0, 1}"
        exit 198
    }
    
    // Task 2: Firm-level switching history
    capture drop _pte_has_entry _pte_has_exit
    qui bys `panelvar': egen byte _pte_has_entry = max(G == 1)
    qui bys `panelvar': egen byte _pte_has_exit  = max(G == -1)
    
    // Task 3: Four-class stratification variable
    capture drop _pte_strata_na
    qui gen byte _pte_strata_na = 1 if _pte_has_entry == 0 & _pte_has_exit == 0
    qui replace  _pte_strata_na = 2 if _pte_has_entry == 1 & _pte_has_exit == 0
    qui replace  _pte_strata_na = 3 if _pte_has_entry == 0 & _pte_has_exit == 1
    qui replace  _pte_strata_na = 4 if _pte_has_entry == 1 & _pte_has_exit == 1
    
    // Task 4: Labels
    label define _pte_strata_na_lbl 1 "Never switch" 2 "Entry only" ///
                                    3 "Exit only" 4 "Both directions", replace
    label values _pte_strata_na _pte_strata_na_lbl
    label variable _pte_strata_na "Non-absorbing Bootstrap strata"
    
    // Task 5: Completeness validation
    qui count if missing(_pte_strata_na)
    if r(N) > 0 {
        di as error "[pte] Warning: strata_na has `r(N)' missing values"
    }
    
    // Task 6: Balance warning (firm-level check)
    preserve
    qui duplicates drop `panelvar', force
    forvalues k = 1/4 {
        qui count if _pte_strata_na == `k'
        local n_strata_`k' = r(N)
        if r(N) > 0 & r(N) < 30 {
            local lbl : label _pte_strata_na_lbl `k'
            di as text "[pte] Warning: '`lbl'' firms = `r(N)' < 30"
        }
    }
    restore

    // ================================================================
    // Step 3: Display header
    // ================================================================
    di as text ""
    di as text "{hline 70}"
    di as text "Non-absorbing Bootstrap Inference"
    di as text "{hline 70}"
    di as text "  Production function:  " as result "`prodfunc'"
    di as text "  Polynomial order:     " as result "`omegapoly'"
    di as text "  ATT periods:          " as result "0 to `attperiods'"
    di as text "  Bootstrap reps:       " as result "`breps'"
    di as text "  Inner seed:           " as result "`inner_seed'"
    di as text "  nsim:                 " as result "`nsim'"
    di as text "  Trim eps0:            " as result cond(`do_trim', "Yes (1%-99%)", "No")
    di as text "  Confidence level:     " as result "`level'%"
    di as text "  Degrade mode:         " as result "`degrade_mode'"
    di as text "  ATT+ (entry):         " as result cond(`do_att_plus', "Yes", "No")
    di as text "  ATT- (exit):          " as result cond(`do_att_minus', "Yes", "No")
    di as text "  Strata distribution:"
    forvalues k = 1/4 {
        local lbl : label _pte_strata_na_lbl `k'
        di as text "    `k'. `lbl': " as result "`n_strata_`k'' firms"
    }
    di as text "{hline 70}"
    
    // Internal worker resets need the fully prepared non-absorbing scratch
    // state, while public restore paths must recover the pristine caller
    // dataset from orig_data.
    tempfile work_data
    qui save `work_data', replace

    // ================================================================
    // Step 4: Run point estimate on original data
    // ================================================================
    di as text ""
    di as text "Running point estimate on original data..."
    tempname pt_beta_controls_mat
    local has_pt_beta_controls = 0
    local pt_n_beta_controls = 0
    capture {
        local _pf_opts "treatment(`treatment') id(`id') time(`time')"
        local _pf_opts "`_pf_opts' lny(`depvar') free(`free') state(`state') proxy(`proxy')"
        local _pf_opts "`_pf_opts' pfunc(`prodfunc') poly(`poly') omegapoly(`omegapoly')"
        local _pf_opts "`_pf_opts' noreport nodiagnose"
        if "`control'" != "" {
            local _pf_opts "`_pf_opts' control(`control')"
        }
        qui _pte_prodfunc, `_pf_opts'
        
        // Store point estimate betas
        local pt_beta_l = _b[`free']
        local pt_beta_k = _b[`state']
        local pt_beta_t = .
        capture matrix `pt_beta_controls_mat' = e(beta_controls)
        if _rc == 0 {
            local has_pt_beta_controls = 1
            local pt_n_beta_controls = colsof(`pt_beta_controls_mat')
            if `pt_n_beta_controls' == 1 {
                local pt_beta_t = `pt_beta_controls_mat'[1, 1]
            }
        }
        else {
            capture local pt_beta_t = _b[t]
        }
        if "`prodfunc'" == "translog" {
            local pt_beta_ll = _b[l2]
            local pt_beta_kk = _b[k2]
            local pt_beta_lk = _b[l1k1]
        }
        
        local _om_opts "treatment(`treatment') id(`id') time(`time')"
        local _om_opts "`_om_opts' omegapoly(`omegapoly') attperiods(`attperiods')"
        if `persistperiods' > 0 {
            local _om_opts "`_om_opts' persistperiods(`persistperiods')"
        }
        if "`notrimeps'" != "" {
            local _om_opts "`_om_opts' notrimeps"
        }
        if "`nolog'" != "" {
            local _om_opts "`_om_opts' nolog"
        }
        qui _pte_bs_nonabs_prep, `_om_opts'
        
        // --- ATT+ point estimate ---
        local nperiods = `attperiods' + 1
        
        if `do_att_plus' {
            local _att_p_opts "omegapoly(`omegapoly') attperiods(`attperiods')"
            local _att_p_opts "`_att_p_opts' nsim(`nsim') seed(`inner_seed')"
            qui _pte_att_plus, `_att_p_opts'
            
            // Store point ATT+ matrix
            tempname pt_att_plus_mat
            matrix `pt_att_plus_mat' = e(att_plus)
            local pt_n_att_plus_periods = e(n_att_plus_periods)
            
            di as text "  Point estimate ATT+ (nt=0) = " as result %10.6f `pt_att_plus_mat'[1, 1]
        }
        
        // Reload data (ATT+ may have modified it via preserve/restore but e() is cleared)
        qui use `work_data', clear
        qui xtset `panelvar' `timevar'`_pte_boot_delta_opt'
        
        // Re-run prodfunc + evolution to restore e() for ATT-
        qui _pte_prodfunc, `_pf_opts'
        local pt_beta_l = _b[`free']
        local pt_beta_k = _b[`state']
        local pt_beta_t = .
        capture matrix `pt_beta_controls_mat' = e(beta_controls)
        if _rc == 0 {
            local has_pt_beta_controls = 1
            local pt_n_beta_controls = colsof(`pt_beta_controls_mat')
            if `pt_n_beta_controls' == 1 {
                local pt_beta_t = `pt_beta_controls_mat'[1, 1]
            }
        }
        else {
            capture local pt_beta_t = _b[t]
        }
        if "`prodfunc'" == "translog" {
            local pt_beta_ll = _b[l2]
            local pt_beta_kk = _b[k2]
            local pt_beta_lk = _b[l1k1]
        }
        
        local _om_opts "treatment(`treatment') id(`id') time(`time')"
        local _om_opts "`_om_opts' omegapoly(`omegapoly') attperiods(`attperiods')"
        if `persistperiods' > 0 {
            local _om_opts "`_om_opts' persistperiods(`persistperiods')"
        }
        if "`notrimeps'" != "" {
            local _om_opts "`_om_opts' notrimeps"
        }
        if "`nolog'" != "" {
            local _om_opts "`_om_opts' nolog"
        }
        qui _pte_bs_nonabs_prep, `_om_opts'
        
        // --- ATT- point estimate ---
        if `do_att_minus' {
            local _att_m_opts "omegapoly(`omegapoly') attperiods(`attperiods')"
            local _att_m_opts "`_att_m_opts' nsim(`nsim') seed(`inner_seed')"
            qui _pte_att_minus, `_att_m_opts'
            
            tempname pt_att_minus_mat
            matrix `pt_att_minus_mat' = e(att_minus)
            local pt_n_att_minus_periods = e(n_att_minus_periods)
            
            di as text "  Point estimate ATT- (nt=0) = " as result %10.6f `pt_att_minus_mat'[1, 1]
        }
    }
    local _pte_point_rc = _rc
    if `_pte_point_rc' != 0 {
        qui use `orig_data', clear
        qui xtset `panelvar' `timevar'`_pte_boot_delta_opt'
        foreach _pte_var of local _pte_nonabs_generated_scratch {
            capture drop `_pte_var'
        }
        foreach _pte_var of local _pte_nonabs_created_scratch {
            capture drop `_pte_var'
        }
        capture set rngstate `orig_rngstate'
        if `_pte_has_prev_est' {
            capture estimates restore `_pte_prev_est'
            capture estimates drop `_pte_prev_est'
        }
        else {
            capture ereturn clear
        }
        exit `_pte_point_rc'
    }

    // ================================================================
    // Step 5: Initialize bootstrap results storage
    // ================================================================
    
    tempname bs_att_plus bs_att_minus bs_betas
    tempname bs_beta_ctrl
    if `do_att_plus' {
        local ncols_att_plus = rowsof(`pt_att_plus_mat')
        local att_plus_rnames : rownames `pt_att_plus_mat'
        matrix `bs_att_plus' = J(`breps', `ncols_att_plus', .)
        if `"`att_plus_rnames'"' != "" {
            matrix colnames `bs_att_plus' = `att_plus_rnames'
        }
    }
    if `do_att_minus' {
        local ncols_att_minus = rowsof(`pt_att_minus_mat')
        local att_minus_rnames : rownames `pt_att_minus_mat'
        matrix `bs_att_minus' = J(`breps', `ncols_att_minus', .)
        if `"`att_minus_rnames'"' != "" {
            matrix colnames `bs_att_minus' = `att_minus_rnames'
        }
    }
    local bs_pf_cols = cond("`prodfunc'" == "cd", 2, 5)
    local bs_beta_cols = cond("`prodfunc'" == "cd", 3, 6)
    local bs_beta_colnames = cond("`prodfunc'" == "cd", ///
        "beta_l beta_k beta_t", ///
        "beta_l beta_k beta_ll beta_kk beta_lk beta_t")
    if `has_pt_beta_controls' & `pt_n_beta_controls' > 1 {
        local pt_beta_ctrl_names : colnames `pt_beta_controls_mat'
        local bs_beta_cols = `bs_pf_cols' + `pt_n_beta_controls'
        local bs_beta_colnames = cond("`prodfunc'" == "cd", ///
            "beta_l beta_k `pt_beta_ctrl_names'", ///
            "beta_l beta_k beta_ll beta_kk beta_lk `pt_beta_ctrl_names'")
    }
    
    // Beta storage for diagnostics
    matrix `bs_betas' = J(`breps', `bs_beta_cols', .)
    matrix colnames `bs_betas' = `bs_beta_colnames'
    
    // Track success/failure (Task 23, 99)
    local n_success = 0
    local n_fail = 0
    local n_plus_ok = 0
    local n_minus_ok = 0
    local n_plus_fail = 0
    local n_minus_fail = 0
    
    // Set bootstrap flag for downstream modules
    scalar _pte_in_bootstrap = 1

    // ================================================================
    // Step 6: Bootstrap outer loop (Task 14-24, 97, 99, 101, 106)
    // ================================================================
    di as text ""
    di as text "Bootstrap iterations:"
    
    forvalues b = 1/`breps' {
        
        // ---- 7.1 Progress display (Task 22, 101) ----
        if mod(`b', 10) == 0 | `b' == 1 | `b' == `breps' {
            di as text "  b = " %4.0f `b' "/" %4.0f `breps' _continue
        }
        
        // ---- 7.2 Restore original data ----
        qui use `work_data', clear
        
        // ---- 7.3 Set outer seed (Task 14, 106) ----
        set seed `b'
        
        // ---- 7.4 Stratified cluster resampling (Task 10-13) ----
        capture drop _pte_firm_bs
        qui bsample, strata(_pte_strata_na) cluster(`panelvar') idcluster(_pte_firm_bs)
        
        // Task 11: Re-xtset with bootstrap firm IDs
        qui xtset _pte_firm_bs `timevar'`_pte_boot_delta_opt'
        
        // Task 97: Minimum sample check after resampling
        qui count if `treatment' == 1
        local n_treated_bs = r(N)
        qui count if `treatment' == 0
        local n_control_bs = r(N)
        
        if `n_treated_bs' < 10 | `n_control_bs' < 10 {
            local ++n_fail
            if mod(`b', 10) == 0 | `b' == 1 | `b' == `breps' {
                di as error " x" _continue
            }
            continue
        }
        
        // ---- 7.5 Re-run full pipeline ----
        local bs_ok = 1
        local att_plus_ok_b = 0
        local att_minus_ok_b = 0
        
        capture {
            local _pf_bs "treatment(`treatment') id(_pte_firm_bs) time(`timevar')"
            local _pf_bs "`_pf_bs' lny(`depvar') free(`free') state(`state') proxy(`proxy')"
            local _pf_bs "`_pf_bs' pfunc(`prodfunc') poly(`poly') omegapoly(`omegapoly')"
            local _pf_bs "`_pf_bs' noreport nodiagnose"
            if "`control'" != "" {
                local _pf_bs "`_pf_bs' control(`control')"
            }
            _pte_prodfunc, `_pf_bs'
        }
        if _rc != 0 {
            local bs_ok = 0
        }
        
        if `bs_ok' == 1 {
            // Store bootstrap betas
            local bs_beta_l = _b[`free']
            local bs_beta_k = _b[`state']
            local bs_beta_t = .
            local bs_n_beta_controls = 0
            capture matrix `bs_beta_ctrl' = e(beta_controls)
            if _rc == 0 {
                local bs_n_beta_controls = colsof(`bs_beta_ctrl')
                if `bs_n_beta_controls' == 1 {
                    local bs_beta_t = `bs_beta_ctrl'[1, 1]
                }
            }
            else {
                capture local bs_beta_t = _b[t]
            }
            matrix `bs_betas'[`b', 1] = `bs_beta_l'
            matrix `bs_betas'[`b', 2] = `bs_beta_k'
            if "`prodfunc'" == "translog" {
                local bs_beta_ll = _b[l2]
                local bs_beta_kk = _b[k2]
                local bs_beta_lk = _b[l1k1]
                matrix `bs_betas'[`b', 3] = `bs_beta_ll'
                matrix `bs_betas'[`b', 4] = `bs_beta_kk'
                matrix `bs_betas'[`b', 5] = `bs_beta_lk'
            }
            if `has_pt_beta_controls' & `pt_n_beta_controls' > 1 {
                if _rc == 0 & `bs_n_beta_controls' == `pt_n_beta_controls' {
                    forvalues j = 1/`pt_n_beta_controls' {
                        matrix `bs_betas'[`b', `bs_pf_cols' + `j'] = `bs_beta_ctrl'[1, `j']
                    }
                }
            }
            else if "`prodfunc'" == "translog" {
                matrix `bs_betas'[`b', 6] = `bs_beta_t'
            }
            else {
                matrix `bs_betas'[`b', 3] = `bs_beta_t'
            }
            
            // --- Non-absorbing evolution estimation (Task 16) ---
            capture {
                local _om_bs "treatment(`treatment') id(_pte_firm_bs) time(`timevar')"
                local _om_bs "`_om_bs' omegapoly(`omegapoly') attperiods(`attperiods')"
                if `persistperiods' > 0 {
                    local _om_bs "`_om_bs' persistperiods(`persistperiods')"
                }
                if "`notrimeps'" != "" {
                    local _om_bs "`_om_bs' notrimeps"
                }
                if "`nolog'" != "" {
                    local _om_bs "`_om_bs' nolog"
                }
                _pte_bs_nonabs_prep, `_om_bs'
            }
            if _rc != 0 {
                local bs_ok = 0
            }
        }

        // --- ATT+ estimation (Task 17, 99, 106) ---
        // Independent capture: ATT+ failure does not affect ATT-
        if `bs_ok' == 1 & `do_att_plus' {
            capture {
                local _att_p_bs "omegapoly(`omegapoly') attperiods(`attperiods')"
                local _att_p_bs "`_att_p_bs' nsim(`nsim') seed(`inner_seed')"
                _pte_att_plus, `_att_p_bs'
            }
            if _rc == 0 {
                local att_plus_ok_b = 1
                // Store ATT+ results on the point-estimate nt support.
                tempname _att_p_tmp
                matrix `_att_p_tmp' = e(att_plus)
                local nr_p = rowsof(`_att_p_tmp')
                forvalues s = 1/`nr_p' {
                    local nt_att_p = `_att_p_tmp'[`s', 4]
                    forvalues j = 1/`ncols_att_plus' {
                        if `pt_att_plus_mat'[`j', 4] == `nt_att_p' {
                            matrix `bs_att_plus'[`b', `j'] = `_att_p_tmp'[`s', 1]
                            continue, break
                        }
                    }
                }
            }
            else {
                local att_plus_ok_b = 0
            }
            
            // Reload data and re-run pipeline for ATT-
            // (ATT+ uses preserve/restore internally but clears e())
            qui use `work_data', clear
            set seed `b'
            capture drop _pte_firm_bs
            qui bsample, strata(_pte_strata_na) cluster(`panelvar') idcluster(_pte_firm_bs)
            qui xtset _pte_firm_bs `timevar'`_pte_boot_delta_opt'
            
            // Re-run prodfunc + evolution for ATT-
            capture {
                local _pf_bs2 "treatment(`treatment') id(_pte_firm_bs) time(`timevar')"
                local _pf_bs2 "`_pf_bs2' lny(`depvar') free(`free') state(`state') proxy(`proxy')"
                local _pf_bs2 "`_pf_bs2' pfunc(`prodfunc') poly(`poly') omegapoly(`omegapoly')"
                local _pf_bs2 "`_pf_bs2' noreport nodiagnose"
                if "`control'" != "" {
                    local _pf_bs2 "`_pf_bs2' control(`control')"
                }
                _pte_prodfunc, `_pf_bs2'
                
                local _om_bs2 "treatment(`treatment') id(_pte_firm_bs) time(`timevar')"
                local _om_bs2 "`_om_bs2' omegapoly(`omegapoly') attperiods(`attperiods')"
                if `persistperiods' > 0 {
                    local _om_bs2 "`_om_bs2' persistperiods(`persistperiods')"
                }
                if "`notrimeps'" != "" {
                    local _om_bs2 "`_om_bs2' notrimeps"
                }
                if "`nolog'" != "" {
                    local _om_bs2 "`_om_bs2' nolog"
                }
                _pte_bs_nonabs_prep, `_om_bs2'
            }
            if _rc != 0 {
                // If re-run fails, ATT- also fails
                local bs_ok = 0
            }
        }
        
        // --- ATT- estimation (Task 18, 99, 106) ---
        // Independent capture: ATT- failure does not affect ATT+
        if `bs_ok' == 1 & `do_att_minus' {
            capture {
                local _att_m_bs "omegapoly(`omegapoly') attperiods(`attperiods')"
                local _att_m_bs "`_att_m_bs' nsim(`nsim') seed(`inner_seed')"
                _pte_att_minus, `_att_m_bs'
            }
            if _rc == 0 {
                local att_minus_ok_b = 1
                // Store ATT- results on the point-estimate nt support.
                tempname _att_m_tmp
                matrix `_att_m_tmp' = e(att_minus)
                local nr_m = rowsof(`_att_m_tmp')
                forvalues s = 1/`nr_m' {
                    local nt_att_m = `_att_m_tmp'[`s', 4]
                    forvalues j = 1/`ncols_att_minus' {
                        if `pt_att_minus_mat'[`j', 4] == `nt_att_m' {
                            matrix `bs_att_minus'[`b', `j'] = `_att_m_tmp'[`s', 1]
                            continue, break
                        }
                    }
                }
            }
            else {
                local att_minus_ok_b = 0
            }
        }

        // ---- 7.6 Track success/failure (Task 19, 23, 99) ----
        if `bs_ok' == 0 {
            local ++n_fail
        }
        else {
            local ++n_success
        }
        if `att_plus_ok_b' == 1 {
            local ++n_plus_ok
        }
        else if `do_att_plus' {
            local ++n_plus_fail
        }
        if `att_minus_ok_b' == 1 {
            local ++n_minus_ok
        }
        else if `do_att_minus' {
            local ++n_minus_fail
        }
        
        // ---- 7.7 Progress symbol (Task 101) ----
        // . = full success, + = plus only, - = minus only, o = both ATT fail, x = pipeline fail
        if mod(`b', 10) == 0 | `b' == 1 | `b' == `breps' {
            if `bs_ok' == 0 {
                di as error " x" _continue
            }
            else if `att_plus_ok_b' & `att_minus_ok_b' {
                di as result " ." _continue
            }
            else if `att_plus_ok_b' & !`att_minus_ok_b' {
                di as text " +" _continue
            }
            else if !`att_plus_ok_b' & `att_minus_ok_b' {
                di as text " -" _continue
            }
            else {
                di as text " o" _continue
            }
        }
        
        // Newline every 100 iterations
        if mod(`b', 100) == 0 {
            di ""
        }
        
    } // end forvalues b
    
    // Final newline
    di ""
    
    // Clear bootstrap flag
    capture scalar drop _pte_in_bootstrap
    
    // Restore RNG state
    capture set rngstate `orig_rngstate'

    // ================================================================
    // Step 7: Failure rate check (Task 24)
    // ================================================================
    di as text ""
    di as text "Bootstrap completed:"
    di as text "  Total:       " as result `breps'
    di as text "  Successful:  " as result `n_success'
    di as text "  Failed:      " as result `n_fail'
    if `do_att_plus' {
        di as text "  ATT+ OK:     " as result `n_plus_ok'
        di as text "  ATT+ fail:   " as result `n_plus_fail'
    }
    if `do_att_minus' {
        di as text "  ATT- OK:     " as result `n_minus_ok'
        di as text "  ATT- fail:   " as result `n_minus_fail'
    }
    
    // Failure rate warning
    if `n_fail' > 0 {
        local fail_rate = 100 * `n_fail' / `breps'
        if `fail_rate' > 5 {
            di as error "[pte] Warning: failure rate = " %5.1f `fail_rate' "% > 5%"
            di as error "[pte] Bootstrap SE may be unreliable"
        }
    }
    
    if `n_success' < 2 {
        di as error "[pte] Error: fewer than 2 successful bootstrap iterations"
        di as error "[pte] Cannot compute standard errors"
        qui use `orig_data', clear
        qui xtset `panelvar' `timevar'`_pte_boot_delta_opt'
        foreach _pte_var of local _pte_nonabs_generated_scratch {
            capture drop `_pte_var'
        }
        foreach _pte_var of local _pte_nonabs_created_scratch {
            capture drop `_pte_var'
        }
        if `_pte_has_prev_est' {
            capture estimates restore `_pte_prev_est'
            capture estimates drop `_pte_prev_est'
        }
        else {
            capture ereturn clear
        }
        exit 2000
    }

    // ================================================================
    // Step 8: SE and CI calculation (Task 25-27)
    // Uses temporary dataset approach (same as _pte_bootstrap.ado)
    // with missing-row filtering for independent failure handling
    // ================================================================
    local alpha = (100 - `level') / 200
    // Percentile points (in percent) for the _pctile-based CI bounds, matching
    // the official replication DOs (egen pctile(), p(.)).
    local p_lo = 100 * `alpha'
    local p_hi = 100 * (1 - `alpha')

    // ATT+ SE/CI
    if `do_att_plus' {
        tempname se_plus ci_lo_plus ci_hi_plus mean_plus n_valid_plus
        matrix `se_plus' = J(1, `ncols_att_plus', .)
        matrix `ci_lo_plus' = J(1, `ncols_att_plus', .)
        matrix `ci_hi_plus' = J(1, `ncols_att_plus', .)
        matrix `mean_plus' = J(1, `ncols_att_plus', .)
        matrix `n_valid_plus' = J(1, `ncols_att_plus', 0)
        if `"`att_plus_rnames'"' != "" {
            matrix colnames `se_plus' = `att_plus_rnames'
            matrix colnames `ci_lo_plus' = `att_plus_rnames'
            matrix colnames `ci_hi_plus' = `att_plus_rnames'
            matrix colnames `mean_plus' = `att_plus_rnames'
            matrix colnames `n_valid_plus' = `att_plus_rnames'
        }
    }
    
    // ATT- SE/CI
    if `do_att_minus' {
        tempname se_minus ci_lo_minus ci_hi_minus mean_minus n_valid_minus
        matrix `se_minus' = J(1, `ncols_att_minus', .)
        matrix `ci_lo_minus' = J(1, `ncols_att_minus', .)
        matrix `ci_hi_minus' = J(1, `ncols_att_minus', .)
        matrix `mean_minus' = J(1, `ncols_att_minus', .)
        matrix `n_valid_minus' = J(1, `ncols_att_minus', 0)
        if `"`att_minus_rnames'"' != "" {
            matrix colnames `se_minus' = `att_minus_rnames'
            matrix colnames `ci_lo_minus' = `att_minus_rnames'
            matrix colnames `ci_hi_minus' = `att_minus_rnames'
            matrix colnames `mean_minus' = `att_minus_rnames'
            matrix colnames `n_valid_minus' = `att_minus_rnames'
        }
    }
    
    // Use temporary dataset to compute column statistics
    preserve
    clear
    qui set obs `breps'
    
    // Load ATT+ bootstrap results
    if `do_att_plus' {
        forvalues j = 1/`ncols_att_plus' {
            qui gen double _plus`j' = .
            forvalues bb = 1/`breps' {
                local val = `bs_att_plus'[`bb', `j']
                if !missing(`val') {
                    qui replace _plus`j' = `val' in `bb'
                }
            }
        }
    }
    
    // Load ATT- bootstrap results
    if `do_att_minus' {
        forvalues j = 1/`ncols_att_minus' {
            qui gen double _minus`j' = .
            forvalues bb = 1/`breps' {
                local val = `bs_att_minus'[`bb', `j']
                if !missing(`val') {
                    qui replace _minus`j' = `val' in `bb'
                }
            }
        }
    }
    
    // Compute statistics for each column (Task 25: missing-row filtering)
    // ATT+ statistics
    if `do_att_plus' {
        local nboot_valid_plus = 0
        forvalues j = 1/`ncols_att_plus' {
            qui summarize _plus`j'
            matrix `n_valid_plus'[1, `j'] = r(N)
            if r(N) >= 2 {
                matrix `mean_plus'[1, `j'] = r(mean)
                matrix `se_plus'[1, `j'] = r(sd)
                if `j' == 1 {
                    local nboot_valid_plus = r(N)
                }
                // Percentile CI (Task 26): use _pctile so the bounds match the
                // official replication DOs (egen pctile(), p(.)) exactly.
                qui _pctile _plus`j' if !missing(_plus`j'), percentiles(`p_lo' `p_hi')
                matrix `ci_lo_plus'[1, `j'] = r(r1)
                matrix `ci_hi_plus'[1, `j'] = r(r2)
            }
        }
    }
    
    // ATT- statistics
    if `do_att_minus' {
        local nboot_valid_minus = 0
        forvalues j = 1/`ncols_att_minus' {
            qui summarize _minus`j'
            matrix `n_valid_minus'[1, `j'] = r(N)
            if r(N) >= 2 {
                matrix `mean_minus'[1, `j'] = r(mean)
                matrix `se_minus'[1, `j'] = r(sd)
                if `j' == 1 {
                    local nboot_valid_minus = r(N)
                }
                // Percentile CI: use _pctile so the bounds match the official
                // replication DOs (egen pctile(), p(.)) exactly.
                qui _pctile _minus`j' if !missing(_minus`j'), percentiles(`p_lo' `p_hi')
                matrix `ci_lo_minus'[1, `j'] = r(r1)
                matrix `ci_hi_minus'[1, `j'] = r(r2)
            }
        }
    }
    
    restore

    // ================================================================
    // Step 9: Display results
    // ================================================================
    di as text ""
    di as text "{hline 70}"
    di as text "Non-absorbing Bootstrap ATT Results (`level'% CI)"
    di as text "{hline 70}"
    
    // --- ATT+ table ---
    if `do_att_plus' {
        di as text ""
        di as text "  ATT+ (Treatment Entry):"
        di as text "  " _col(5) "nt" _col(15) "ATT+" _col(27) "BS_SE" _col(39) "[`level'% CI]" _col(63) "N_bs"
        di as text "  {hline 62}"
        forvalues col = 1/`ncols_att_plus' {
            local nt_att_plus = `pt_att_plus_mat'[`col', 4]
            local att_pt = `pt_att_plus_mat'[`col', 1]
            local bse = `se_plus'[1, `col']
            local cil = `ci_lo_plus'[1, `col']
            local cih = `ci_hi_plus'[1, `col']
            local nbs = `n_valid_plus'[1, `col']
            if !missing(`att_pt') & !missing(`bse') {
                di as text "  " _col(5) %3.0f `nt_att_plus' ///
                    _col(12) as result %10.4f `att_pt' ///
                    _col(24) as result %10.4f `bse' ///
                    _col(36) as text "[" as result %8.4f `cil' ///
                    as text ", " as result %8.4f `cih' as text "]" ///
                    _col(60) as result %5.0f `nbs'
            }
        }
        di as text "  {hline 62}"
        di as text "  Valid bootstrap iterations (ATT+): " as result `nboot_valid_plus'
    }
    
    // --- ATT- table ---
    if `do_att_minus' {
        di as text ""
        di as text "  ATT- (Treatment Exit):"
        di as text "  " _col(5) "nt" _col(15) "ATT-" _col(27) "BS_SE" _col(39) "[`level'% CI]" _col(63) "N_bs"
        di as text "  {hline 62}"
        forvalues col = 1/`ncols_att_minus' {
            local nt_att_minus = `pt_att_minus_mat'[`col', 4]
            local att_pt = `pt_att_minus_mat'[`col', 1]
            local bse = `se_minus'[1, `col']
            local cil = `ci_lo_minus'[1, `col']
            local cih = `ci_hi_minus'[1, `col']
            local nbs = `n_valid_minus'[1, `col']
            if !missing(`att_pt') & !missing(`bse') {
                di as text "  " _col(5) %3.0f `nt_att_minus' ///
                    _col(12) as result %10.4f `att_pt' ///
                    _col(24) as result %10.4f `bse' ///
                    _col(36) as text "[" as result %8.4f `cil' ///
                    as text ", " as result %8.4f `cih' as text "]" ///
                    _col(60) as result %5.0f `nbs'
            }
        }
        di as text "  {hline 62}"
        di as text "  Valid bootstrap iterations (ATT-): " as result `nboot_valid_minus'
    }
    
    di as text "{hline 70}"

    // ================================================================
    // Step 10: Restore original data
    // ================================================================
    qui use `orig_data', clear
    qui xtset `panelvar' `timevar'`_pte_boot_delta_opt'
    foreach _pte_var of local _pte_nonabs_generated_scratch {
        capture drop `_pte_var'
    }
    foreach _pte_var of local _pte_nonabs_created_scratch {
        capture drop `_pte_var'
    }
    
    // ================================================================
    // Step 11: Store e() return values (Task 28)
    // ================================================================
    ereturn clear
    
    // --- ATT+ point estimates and bootstrap results ---
    if `do_att_plus' {
        ereturn matrix att_plus = `pt_att_plus_mat'
        ereturn matrix att_plus_boot = `bs_att_plus'
        ereturn matrix att_plus_se = `se_plus'
        ereturn matrix att_plus_ci_lower = `ci_lo_plus'
        ereturn matrix att_plus_ci_upper = `ci_hi_plus'
        ereturn matrix att_plus_mean = `mean_plus'
        ereturn scalar nboot_valid_plus = `nboot_valid_plus'
    }
    
    // --- ATT- point estimates and bootstrap results ---
    if `do_att_minus' {
        ereturn matrix att_minus = `pt_att_minus_mat'
        ereturn matrix att_minus_boot = `bs_att_minus'
        ereturn matrix att_minus_se = `se_minus'
        ereturn matrix att_minus_ci_lower = `ci_lo_minus'
        ereturn matrix att_minus_ci_upper = `ci_hi_minus'
        ereturn matrix att_minus_mean = `mean_minus'
        ereturn scalar nboot_valid_minus = `nboot_valid_minus'
    }
    
    // --- Beta bootstrap results ---
    ereturn matrix bs_betas = `bs_betas'
    
    // --- Scalar returns: Bootstrap diagnostics ---
    ereturn scalar n_success = `n_success'
    ereturn scalar n_fail = `n_fail'
    ereturn scalar n_plus_ok = `n_plus_ok'
    ereturn scalar n_minus_ok = `n_minus_ok'
    ereturn scalar n_plus_fail = `n_plus_fail'
    ereturn scalar n_minus_fail = `n_minus_fail'
    ereturn scalar breps = `breps'
    ereturn scalar degrade_mode = `degrade_mode'
    
    // --- Scalar returns: Configuration ---
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar attperiods = `attperiods'
    ereturn scalar persistperiods = `persistperiods'
    ereturn scalar nsim = `nsim'
    ereturn scalar seed_outer = 1
    ereturn scalar inner_seed = `inner_seed'
    ereturn scalar seed_inner = `inner_seed'
    ereturn scalar point_seed = `inner_seed'
    ereturn scalar level = `level'
    ereturn scalar poly = `poly'
    ereturn scalar do_att_plus = `do_att_plus'
    ereturn scalar do_att_minus = `do_att_minus'
    
    // --- Scalar returns: Point estimate betas ---
    ereturn scalar pt_beta_l = `pt_beta_l'
    ereturn scalar pt_beta_k = `pt_beta_k'
    if !missing(`pt_beta_t') {
        ereturn scalar pt_beta_t = `pt_beta_t'
    }
    if "`prodfunc'" == "translog" {
        ereturn scalar pt_beta_ll = `pt_beta_ll'
        ereturn scalar pt_beta_kk = `pt_beta_kk'
        ereturn scalar pt_beta_lk = `pt_beta_lk'
    }
    
    // --- Local returns ---
    ereturn local treatment "`treatment'"
    ereturn local prodfunc "`prodfunc'"
    ereturn local depvar "`depvar'"
    if `has_pt_beta_controls' {
        ereturn matrix beta_controls = `pt_beta_controls_mat'
    }
    ereturn local free "`free'"
    ereturn local state "`state'"
    ereturn local proxy "`proxy'"
    ereturn local cmd "_pte_bootstrap_nonabs"
    ereturn local title "PTE Non-absorbing Bootstrap Inference"
    ereturn local inner_seed_source "`inner_seed_source'"
    ereturn local seed_outer_strategy "iteration"
    
end

capture program drop _pte_bs_nonabs_prep
program define _pte_bs_nonabs_prep, eclass
    version 14.0

    syntax, TREATment(varname) ID(varname) Time(varname) ///
        OMEGApoly(integer) ATTperiods(integer) ///
        [PERSISTperiods(integer 0) NOTRIMeps NOLOG]

    quietly _pte_evolution_separate omega, ///
        treatment(`treatment') omegapoly(`omegapoly') nowarn
    capture matrix drop _pte_bs_rho0
    capture matrix drop _pte_bs_rho1
    matrix _pte_bs_rho0 = e(rho_0)
    matrix _pte_bs_rho1 = e(rho_1)

    capture noisily {
        local _sample_opts "treatment(`treatment') id(`id') time(`time')"
        local _sample_opts "`_sample_opts' attperiods(`attperiods') replace noreport"
        if `persistperiods' > 0 {
            local _sample_opts "`_sample_opts' persistperiods(`persistperiods')"
        }
        quietly _pte_nonabs_sample, `_sample_opts'

        local _eps_opts "omega(omega) treatment(`treatment')"
        local _eps_opts "`_eps_opts' rho_0(_pte_bs_rho0) rho_1(_pte_bs_rho1)"
        local _eps_opts "`_eps_opts' omegapoly(`omegapoly') attperiods(`attperiods')"
        if "`notrimeps'" != "" {
            local _eps_opts "`_eps_opts' notrimeps"
        }
        if "`nolog'" != "" {
            local _eps_opts "`_eps_opts' nolog"
        }
        quietly _pte_eps_bidirectional, `_eps_opts'

        local sigma_eps0 = cond("`notrimeps'" != "", e(sigma_eps0_raw), e(sigma_eps0_trim))
        local sigma_eps1 = cond("`notrimeps'" != "", e(sigma_eps1_raw), e(sigma_eps1_trim))
    }
    local _pte_bs_nonabs_prep_rc = _rc
    if `_pte_bs_nonabs_prep_rc' != 0 {
        capture matrix drop _pte_bs_rho0
        capture matrix drop _pte_bs_rho1
        capture ereturn clear
        exit `_pte_bs_nonabs_prep_rc'
    }

    ereturn clear
    ereturn matrix rho_0 = _pte_bs_rho0
    ereturn matrix rho_1 = _pte_bs_rho1
    ereturn scalar sigma_eps0 = `sigma_eps0'
    if !missing(`sigma_eps1') {
        ereturn scalar sigma_eps1 = `sigma_eps1'
    }
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar attperiods = `attperiods'
    ereturn scalar persistperiods = `persistperiods'
    ereturn local cmd "_pte_bs_nonabs_prep"
    capture matrix drop _pte_bs_rho0
    capture matrix drop _pte_bs_rho1
end
