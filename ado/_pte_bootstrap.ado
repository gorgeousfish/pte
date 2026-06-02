*! _pte_bootstrap.ado
*! Bootstrap Inference Module
*!
*! Implements bootstrap inference for ATT estimation:
*!   Outer loop: b = 1..B, set outer_seed = seed + b - 1
*!     (default seed = 1, so omitted seed() matches official set seed b)
*!   Inner: stratified cluster resampling -> re-run full pipeline
*!   Inner seed for ATT simulation defaults to 123456
*!   except benchmark replicate translog order 1, which uses 10000
*!
*! Two-layer seed management:
*!   - Outer seed: set seed() + b - 1 for each bootstrap iteration
*!     with seed() defaulting to 1 on the public serial contract
*!   - Inner seed: usually fixed at 123456 for ATT counterfactual simulation
*!     but benchmark replicate translog order 1 follows the official 10000 rule
*!
*! Dual-track: stores both raw ATT and trim ATT per bootstrap iteration
*!   Bootstrap SE computed for both tracks

version 14.0
capture program drop _pte_bootstrap
program define _pte_bootstrap, eclass
    version 14.0

    // Preserve the raw option string so exact-name validation can reject
    // Stata's silent abbreviation resolution for core bootstrap variables.
    local _pte_cmdline `"`0'"'
    foreach _pte_input_opt in treatment depvar free state proxy id time touse targetgroup {
        local _pte_`_pte_input_opt'_literal ""
        if regexm(lower(`"`_pte_cmdline'"'), ///
            "(^|[ ,])`_pte_input_opt'[(]([^)]*)[)]") {
            local _pte_`_pte_input_opt'_literal `"`=regexs(2)'"'
            local _pte_`_pte_input_opt'_literal = ///
                lower(strtrim(`"`_pte_`_pte_input_opt'_literal'"'))
        }
    }
    local _pte_control_literal ""
    if regexm(lower(`"`_pte_cmdline'"'), ///
        "(^|[ ,])(control|contro|contr|cont)[ ]*[(]([^)]*)[)]") {
        local _pte_control_literal `"`=regexs(3)'"'
        local _pte_control_literal = ///
            lower(strtrim(`"`_pte_control_literal'"'))
    }

    syntax, treatment(varname) ///
        depvar(varname) free(varname) state(varname) proxy(varname) ///
        id(varname) time(varname) ///
        [omegapoly(integer 3) ///
         attperiods(integer 4) ///
         nsim(integer -1) ///
         breps(integer 100) ///
         seed(integer 1) ///
         inner_seed(integer 123456) ///
         eps0window(integer 0) ///
         prodfunc(string) ///
         poly(integer -1) ///
         control(varlist) ///
         level(cilevel) ///
         NOTRIMeps ///
         NOLOg ///
         NODIAGnose ///
         saving(string) ///
         REPlicate ///
         COUNTERfactual ///
         TARGETgroup(varname) ///
         REFERENCEtime(integer 0) ///
         EXPANSIONtime(integer -2147483647) ///
         TOUSE(name)]

    local _pte_treatment_resolved = lower(`"`treatment'"')
    local _pte_depvar_resolved = lower(`"`depvar'"')
    local _pte_free_resolved = lower(`"`free'"')
    local _pte_state_resolved = lower(`"`state'"')
    local _pte_proxy_resolved = lower(`"`proxy'"')
    local _pte_id_resolved = lower(`"`id'"')
    local _pte_time_resolved = lower(`"`time'"')
    local _pte_touse_resolved = lower(`"`touse'"')
    local _pte_targetgroup_resolved = lower(`"`targetgroup'"')
    foreach _pte_input_opt in treatment depvar free state proxy id time touse targetgroup {
        if `"`_pte_`_pte_input_opt'_literal'"' != "" & ///
            `"`_pte_`_pte_input_opt'_literal'"' != `"`_pte_`_pte_input_opt'_resolved'"' {
            di as error "[pte] Error: variable '`_pte_`_pte_input_opt'_literal'' not found"
            exit 111
        }
    }
    if `"`_pte_control_literal'"' != "" & "`control'" != "" {
        local _pte_control_literal = lower(itrim(strtrim(`"`_pte_control_literal'"')))
        local _pte_control_resolved = lower(itrim(strtrim(`"`control'"')))
        if `"`_pte_control_literal'"' != `"`_pte_control_resolved'"' {
            di as error "[pte] Error: control() variables must be specified with exact existing variable names"
            exit 111
        }
    }

    // ================================================================
    // Step 0: Input validation
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
    if `seed' < 1 {
        di as error "[pte] Error: seed must be >= 1"
        exit 198
    }
    if `seed' > 2147483647 {
        di as error "[pte] Error: seed exceeds maximum value (2147483647)"
        exit 198
    }
    if `seed' > 2147483647 - `breps' + 1 {
        di as error "[pte] Error: seed() is too large for breps(`breps')"
        exit 198
    }
    local seed_source = "default"
    if regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])seed[(]") {
        local seed_source = "user"
    }
    if `eps0window' < 0 {
        di as error "[pte] Error: eps0window must be non-negative"
        exit 198
    }
    local _pte_inner_seed_validate = `inner_seed'
    local _pte_cf_seed_offset = 7654321
    local _pte_cf_inner_seed_max = 2147483647 - `_pte_cf_seed_offset'
    if "`replicate'" != "" & "`prodfunc'" == "translog" & `omegapoly' == 1 {
        local _pte_inner_seed_validate = 10000
    }
    if `_pte_inner_seed_validate' < 1 {
        di as error "[pte] Error: inner_seed must be >= 1"
        exit 198
    }
    if `_pte_inner_seed_validate' > 2147483647 {
        di as error "[pte] Error: inner_seed exceeds maximum value (2147483647)"
        exit 198
    }
    if "`counterfactual'" != "" & `_pte_inner_seed_validate' > `_pte_cf_inner_seed_max' {
        di as error "[pte] Error: inner_seed exceeds maximum value (`_pte_cf_inner_seed_max')"
        di as error "       counterfactual bootstrap uses an internal eps0 seed offset of +`_pte_cf_seed_offset'"
        exit 198
    }
    capture _xt, trequired
    if _rc != 0 {
        di as error "[pte] Error: data must be xtset as panel"
        exit 459
    }
    local panelvar = r(ivar)
    local timevar = r(tvar)
    if "`panelvar'" != "`id'" | "`timevar'" != "`time'" {
        di as error "[pte] xtset must match id() and time()"
        di as error "  current xtset: `panelvar' `timevar'"
        di as error "  requested:     `id' `time'"
        di as error "  run {bf:xtset `id' `time'} before calling _pte_bootstrap"
        exit 459
    }
    quietly xtset
    local _pte_boot_delta "`r(tdelta)'"
    local _pte_boot_delta_opt ""
    if "`_pte_boot_delta'" != "" {
        local _pte_boot_delta_opt ", delta(`_pte_boot_delta')"
    }
    tempvar _pte_bs_sample
    if "`touse'" != "" {
        capture confirm variable `touse', exact
        if _rc != 0 {
            di as error "[pte] Error: touse variable '`touse'' not found"
            exit 111
        }
        capture confirm numeric variable `touse'
        if _rc != 0 {
            di as error "[pte] Error: touse variable '`touse'' must be numeric"
            exit 111
        }
        quietly gen byte `_pte_bs_sample' = (`touse' != 0 & !missing(`touse'))
    }
    else {
        quietly gen byte `_pte_bs_sample' = 1
    }
    quietly count if `_pte_bs_sample'
    if r(N) == 0 {
        di as error "[pte] Error: touse() excludes all observations"
        exit 2000
    }
    foreach v in `depvar' `free' `state' `proxy' `treatment' {
        capture confirm variable `v', exact
        if _rc != 0 {
            di as error "[pte] Error: variable '`v'' not found"
            exit 111
        }
    }
    capture confirm numeric variable `treatment'
    if _rc != 0 {
        di as error "[pte] Error: treatment() variable '`treatment'' must be numeric"
        exit 111
    }
    capture assert inlist(`treatment', 0, 1) if `_pte_bs_sample' & !missing(`treatment')
    if _rc {
        di as error "[pte] Error: treatment() variable '`treatment'' must be binary (0/1)"
        di as error "[pte]        Found values outside {0, 1}"
        exit 450
    }
    // ================================================================
    // Step 0b: Counterfactual mode dispatch
    // ================================================================
    if "`counterfactual'" != "" {
        // Validate counterfactual-specific parameters
        if "`targetgroup'" == "" {
            di as error "[pte] Error: targetgroup() required with counterfactual option"
            exit 198
        }
        if `expansiontime' == -2147483647 {
            di as error "[pte] Error: expansiontime() required with counterfactual option"
            exit 198
        }
        
        // Build options for _pte_bootstrap_cf
        local _cf_opts "treatment(`treatment')"
        local _cf_opts "`_cf_opts' depvar(`depvar') free(`free') state(`state') proxy(`proxy')"
        local _cf_opts "`_cf_opts' id(`id') time(`time')"
        local _cf_opts "`_cf_opts' omegapoly(`omegapoly') attperiods(`attperiods')"
        local _cf_opts "`_cf_opts' nsim(`nsim') breps(`breps') seed(`seed') inner_seed(`inner_seed') eps0window(`eps0window')"
        local _cf_opts "`_cf_opts' prodfunc(`prodfunc') poly(`poly')"
        local _cf_opts "`_cf_opts' level(`level')"
        local _cf_opts "`_cf_opts' targetgroup(`targetgroup') referencetime(`referencetime') expansiontime(`expansiontime')"
        if "`control'" != "" {
            local _cf_opts "`_cf_opts' control(`control')"
        }
        if "`notrimeps'" != "" {
            local _cf_opts "`_cf_opts' notrimeps"
        }
        if "`nolog'" != "" {
            local _cf_opts "`_cf_opts' nolog"
        }
        if "`nodiagnose'" != "" {
            local _cf_opts "`_cf_opts' nodiagnose"
        }
        if "`saving'" != "" {
            local _cf_opts "`_cf_opts' saving(`saving')"
        }
        if "`replicate'" != "" {
            local _cf_opts "`_cf_opts' replicate"
        }
        if "`touse'" != "" {
            local _cf_opts "`_cf_opts' touse(`touse')"
        }
        
        // Dispatch to counterfactual bootstrap module
        _pte_bootstrap_cf, `_cf_opts'
        
        // Forward e() results
        // _pte_bootstrap_cf sets its own e() returns
        exit
    }

    // Official translog order-1 bootstrap DOs switch the ATT simulation seed
    // to 10000 under benchmark replicate mode; higher orders stay at 123456.
    if "`replicate'" != "" & "`prodfunc'" == "translog" & `omegapoly' == 1 {
        local inner_seed = 10000
        local inner_seed_source "replicate"
    }
    else {
        local inner_seed_source = cond(`inner_seed' == 123456, "default", "user")
    }
    if `inner_seed' < 1 {
        di as error "[pte] Error: inner_seed must be >= 1"
        exit 198
    }
    if `inner_seed' > 2147483647 {
        di as error "[pte] Error: inner_seed exceeds maximum value (2147483647)"
        exit 198
    }

    // Determine if trim track is active
    local do_trim = ("`notrimeps'" == "")
    local show_diagnostics = ("`nodiagnose'" == "")

    // Late bootstrap failures happen after nested/002/003 calls have
    // overwritten e(). Save the caller estimate so failure exits can roll back
    // to the pre-entry state instead of leaking internal worker context.
    tempname _pte_prev_est
    local _pte_has_prev_est = 0
    capture local _pte_prev_cmd `"`e(cmd)'"'
    if _rc == 0 {
        capture estimates store `_pte_prev_est', copy
        if _rc == 0 {
            local _pte_has_prev_est = 1
        }
    }
    // ================================================================
    // Step 1: Display header
    // ================================================================
    if `show_diagnostics' {
        di as text ""
        di as text "{hline 70}"
        di as text "Bootstrap Inference"
        di as text "{hline 70}"
        di as text "  Production function:  " as result "`prodfunc'"
        di as text "  Polynomial order:     " as result "`omegapoly'"
        di as text "  ATT periods:          " as result "0 to `attperiods'"
        di as text "  Bootstrap reps:       " as result "`breps'"
        di as text "  Outer seed start:     " as result "`seed'"
        di as text "  Inner seed:           " as result "`inner_seed'"
        if `eps0window' == 0 {
            di as text "  eps0 window:          " as result "all pre-treatment"
        }
        else {
            di as text "  eps0 window:          " as result "`eps0window'" as text " panel periods"
        }
        di as text "  nsim:                 " as result "`nsim'"
        di as text "  Trim eps0:            " as result cond(`do_trim', "Yes (1%-99%)", "No")
        di as text "  Confidence level:     " as result "`level'%"
        di as text "{hline 70}"
    }
    // ================================================================
    // Step 2: Save the full caller dataset, then restrict the bootstrap
    // workspace to the validated estimation sample.
    // ================================================================
    tempfile full_data pte_boot_point_outputs
    quietly save `full_data', replace
    quietly keep if `_pte_bs_sample'
    quietly replace `_pte_bs_sample' = 1
    // ================================================================
    // Step 3: Create firm-level treatment indicator for stratification on the
    // estimation sample and save the bootstrap workspace.
    // ================================================================
    capture drop _pte_treat_firm
    quietly bysort `panelvar': egen _pte_treat_firm = max(`treatment')
    tempfile orig_data
    quietly save `orig_data', replace
    
    // ================================================================
    // Step 3b: Save RNG state ( Task 4)
    // ================================================================
    local orig_rngstate = c(rngstate)
    // ================================================================
    // Step 4: Run point estimate on original data
    // ================================================================
    if `show_diagnostics' {
        di as text ""
        di as text "Running point estimate on original data..."
    }
    tempname pt_beta_controls_mat
    local has_pt_beta_controls = 0
    local pt_n_beta_controls = 0
    capture {
        // Build _pte_prodfunc options
        local _pf_opts "treatment(`treatment') id(`id') time(`time')"
        local _pf_opts "`_pf_opts' lny(`depvar') free(`free') state(`state') proxy(`proxy')"
        local _pf_opts "`_pf_opts' pfunc(`prodfunc') poly(`poly') omegapoly(`omegapoly')"
        local _pf_opts "`_pf_opts' touse(`_pte_bs_sample')"
        if "`control'" != "" {
            local _pf_opts "`_pf_opts' control(`control')"
        }
        local _pf_opts "`_pf_opts' noreport nodiagnose"
        quietly _pte_prodfunc, `_pf_opts'
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
        local _om_opts "treatment(`treatment') omegapoly(`omegapoly') nodiagnose"
        local _om_opts "`_om_opts' beta_l(`pt_beta_l') beta_k(`pt_beta_k') eps0window(`eps0window')"
        local _om_opts "`_om_opts' touse(`_pte_bs_sample')"
        if "`prodfunc'" == "translog" {
            local _om_opts "`_om_opts' beta_ll(`pt_beta_ll') beta_kk(`pt_beta_kk') beta_lk(`pt_beta_lk')"
            local _om_opts "`_om_opts' prodfunc(translog)"
        }
        if "`notrimeps'" != "" {
            local _om_opts "`_om_opts' notrimeps"
        }
        quietly _pte_omega, `_om_opts'
        local _att_opts "treatment(`treatment') omegapoly(`omegapoly')"
        local _att_opts "`_att_opts' attperiods(`attperiods') nsim(`nsim') seed(`inner_seed')"
        local _att_opts "`_att_opts' touse(`_pte_bs_sample')"
        local _att_opts "`_att_opts' nodiagnose nostabilitycheck"
        if "`notrimeps'" != "" {
            local _att_opts "`_att_opts' notrimeps"
        }
        quietly _pte_att, `_att_opts'
        // Store point estimates (canonical paper track + explicit raw aliases)
        local nperiods = `attperiods' + 1
        tempname n_by_period_mat point_attperiods_mat
        matrix `n_by_period_mat' = e(N_by_period)
        local _pte_point_exact_support = 0
        capture matrix `point_attperiods_mat' = e(attperiods)
        if _rc == 0 {
            if rowsof(`point_attperiods_mat') == 1 & ///
                colsof(`point_attperiods_mat') == colsof(`n_by_period_mat') {
                local _pte_point_exact_support = 1
            }
        }
        local pt_att = e(ATT_avg)
        local pt_att_raw = e(ATT_avg_raw)
        forvalues s = 0/`attperiods' {
            capture local pt_att_`s' = e(att_`s')
            if _rc != 0 local pt_att_`s' = .
            capture local pt_att_raw_`s' = e(att_raw_`s')
            if _rc != 0 local pt_att_raw_`s' = .
        }
        // Store point estimates (trim aliases)
        if `do_trim' {
            local pt_att_trim = e(ATT_avg_trim)
            forvalues s = 0/`attperiods' {
                capture local pt_att_trim_`s' = e(att_trim_`s')
                if _rc != 0 local pt_att_trim_`s' = .
            }
        }
        preserve
        local _pte_point_keep "`id' `time'"
        foreach _v in _pte_nt _pte_tt _pte_tt_trim _pte_tt_raw {
            capture confirm variable `_v'
            if _rc == 0 {
                local _pte_point_keep "`_pte_point_keep' `_v'"
            }
        }
        quietly keep `_pte_point_keep'
        quietly save `pte_boot_point_outputs', replace
        restore
    }
    local _pte_point_rc = _rc
    if `_pte_point_rc' != 0 {
        quietly use `full_data', clear
        quietly xtset `panelvar' `timevar'`_pte_boot_delta_opt'
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
    if `show_diagnostics' {
        di as text "  Point estimate ATT (canonical) = " as result %10.6f `pt_att'
        di as text "  Point estimate ATT (raw)       = " as result %10.6f `pt_att_raw'
        if `do_trim' {
            di as text "  Point estimate ATT (trim)      = " as result %10.6f `pt_att_trim'
        }
    }
    // ================================================================
    // Step 5: Initialize bootstrap results storage
    // ================================================================
    // Raw track: breps x (1 + nperiods) = [att_overall, att_0, ..., att_T]
    local ncols = 1 + `nperiods'
    tempname bs_raw bs_trim bs_betas
    matrix `bs_raw' = J(`breps', `ncols', .)
    if `do_trim' {
        matrix `bs_trim' = J(`breps', `ncols', .)
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
    // Track success/failure
    local n_success = 0
    local n_fail = 0
    // ================================================================
    // Step 6: Bootstrap outer loop
    //   forv b = 1(1)$bN {
    //     use est_temp2, clear
    //     set seed `b'   // official DO reference
    //     bsample, strata(treat) cluster(firm) idcluster(firm1)
    //     ... re-run full pipeline ...
    //   }
    // ================================================================
    if `show_diagnostics' {
        di as text ""
        di as text "Bootstrap iterations:"
    }
    
    // Set bootstrap flag for downstream modules ( IMPL-010)
    scalar _pte_in_bootstrap = 1
    
    forvalues b = 1/`breps' {
        // 6.1 Progress display
        if `show_diagnostics' & (mod(`b', 10) == 0 | `b' == 1 | `b' == `breps') {
            di as text "  b = " %4.0f `b' "/" %4.0f `breps' _continue
        }
        // 6.2 Restore original data
        quietly use `orig_data', clear
        // 6.3 Set outer seed
        local outer_seed = `seed' + `b' - 1
        set seed `outer_seed'
        // Task 6c/8: Debug mode seed log (when nolog is not specified)
        if `show_diagnostics' & "`nolog'" == "" {
            di as text "    [seed] b=`b': outer_seed=`outer_seed', inner_seed=`inner_seed' (`inner_seed_source')"
        }
        // Task 6d/9: Seed checksum for deterministic verification (debug mode)
        if `show_diagnostics' & "`nolog'" == "" & `b' <= 3 {
            // Generate checksum from first random draw after set seed
            // Same seed must produce same checksum — verifies seed was set correctly
            tempvar _ck_tmp
            quietly gen double `_ck_tmp' = runiform() in 1
            local _ck_val = `_ck_tmp'[1]
            drop `_ck_tmp'
            di as text "      checksum = " %12.10f `_ck_val'
            // Reset seed after checksum (consumed one draw)
            set seed `outer_seed'
        }
        // 6.4 Stratified cluster bootstrap resampling
        capture drop _pte_firm_bs
        quietly bsample, strata(_pte_treat_firm) cluster(`panelvar') idcluster(_pte_firm_bs)
        // 6.5 Re-xtset with bootstrap firm IDs
        quietly xtset _pte_firm_bs `timevar'`_pte_boot_delta_opt'
        // 6.6 Re-run full pipeline with error handling
        local bs_ok = 1
        capture {
            local _pf_bs "treatment(`treatment') id(_pte_firm_bs) time(`timevar')"
            local _pf_bs "`_pf_bs' lny(`depvar') free(`free') state(`state') proxy(`proxy')"
            local _pf_bs "`_pf_bs' pfunc(`prodfunc') poly(`poly') omegapoly(`omegapoly')"
            local _pf_bs "`_pf_bs' touse(`_pte_bs_sample')"
            if "`control'" != "" {
                local _pf_bs "`_pf_bs' control(`control')"
            }
            local _pf_bs "`_pf_bs' noreport nodiagnose"
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
            capture matrix _pte_beta_ctrl = e(beta_controls)
            if _rc == 0 {
                local bs_n_beta_controls = colsof(_pte_beta_ctrl)
                if `bs_n_beta_controls' == 1 {
                    local bs_beta_t = _pte_beta_ctrl[1, 1]
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
                        matrix `bs_betas'[`b', `bs_pf_cols' + `j'] = _pte_beta_ctrl[1, `j']
                    }
                }
            }
            else if !missing(`bs_beta_t') {
                if "`prodfunc'" == "cd" {
                    matrix `bs_betas'[`b', 3] = `bs_beta_t'
                }
                else {
                    matrix `bs_betas'[`b', 6] = `bs_beta_t'
                }
            }
            capture {
                local _om_bs "treatment(`treatment') omegapoly(`omegapoly') nodiagnose"
                local _om_bs "`_om_bs' beta_l(`bs_beta_l') beta_k(`bs_beta_k') eps0window(`eps0window')"
                local _om_bs "`_om_bs' touse(`_pte_bs_sample')"
                if "`prodfunc'" == "translog" {
                    local _om_bs "`_om_bs' beta_ll(`bs_beta_ll') beta_kk(`bs_beta_kk') beta_lk(`bs_beta_lk')"
                    local _om_bs "`_om_bs' prodfunc(translog)"
                }
                if "`notrimeps'" != "" {
                    local _om_bs "`_om_bs' notrimeps"
                }
                _pte_omega, `_om_bs'
            }
            if _rc != 0 {
                local bs_ok = 0
            }
        }
        if `bs_ok' == 1 {
            // Task 13: Inner seed consistency verification (debug mode)
            if `show_diagnostics' & "`nolog'" == "" & `b' == 1 {
                di as text "      inner_seed = `inner_seed' (fixed across all iterations)"
            }
            capture {
                local _att_bs "treatment(`treatment') omegapoly(`omegapoly')"
                local _att_bs "`_att_bs' attperiods(`attperiods') nsim(`nsim') seed(`inner_seed')"
                local _att_bs "`_att_bs' touse(`_pte_bs_sample')"
                local _att_bs "`_att_bs' nodiagnose nostabilitycheck"
                if "`notrimeps'" != "" {
                    local _att_bs "`_att_bs' notrimeps"
                }
                _pte_att, `_att_bs'
            }
            if _rc != 0 {
                local bs_ok = 0
            }
        }
        if `bs_ok' == 1 {
            // A successful bootstrap draw must carry pooled payload anchors.
            // Late-horizon support loss is allowed, but overall + nt=0 effects
            // are mandatory for valid pooled inference accounting.
            local _pte_payload_ok = 1
            capture local _pte_att_raw_overall = e(ATT_avg_raw)
            if _rc != 0 | missing(`_pte_att_raw_overall') {
                local _pte_payload_ok = 0
            }
            capture local _pte_att_raw_0 = e(att_raw_0)
            if _rc != 0 | missing(`_pte_att_raw_0') {
                local _pte_payload_ok = 0
            }
            if `do_trim' {
                capture local _pte_att_trim_overall = e(ATT_avg)
                if _rc != 0 | missing(`_pte_att_trim_overall') {
                    local _pte_payload_ok = 0
                }
                capture local _pte_att_trim_0 = e(att_0)
                if _rc != 0 | missing(`_pte_att_trim_0') {
                    local _pte_payload_ok = 0
                }
            }
            if `show_diagnostics' & "`nolog'" == "" & `_pte_payload_ok' == 0 {
                di as error " [FAILED: missing pooled ATT payload]"
            }
            if `_pte_payload_ok' == 0 {
                local bs_ok = 0
            }
        }
        // 6.7 Store results
        if `bs_ok' == 1 {
            // Raw track
            matrix `bs_raw'[`b', 1] = e(ATT_avg_raw)
            forvalues s = 0/`attperiods' {
                local col = `s' + 2
                capture local _tmp = e(att_raw_`s')
                if _rc == 0 {
                    if !missing(`_tmp') {
                        matrix `bs_raw'[`b', `col'] = `_tmp'
                    }
                }
            }
            // Trim track
            if `do_trim' {
                matrix `bs_trim'[`b', 1] = e(ATT_avg)
                forvalues s = 0/`attperiods' {
                    local col = `s' + 2
                    capture local _tmp_t = e(att_`s')
                    if _rc == 0 {
                        if !missing(`_tmp_t') {
                            matrix `bs_trim'[`b', `col'] = `_tmp_t'
                        }
                    }
                }
            }
            local ++n_success
            if `show_diagnostics' & (mod(`b', 10) == 0 | `b' == 1 | `b' == `breps') {
                di as result " ATT=" %8.4f e(ATT_avg) " [OK]"
            }
        }
        else {
            local ++n_fail
            if `show_diagnostics' & (mod(`b', 10) == 0 | `b' == 1 | `b' == `breps') {
                di as error " [FAILED]"
            }
        }
    }
    
    // Clear bootstrap flag ( IMPL-010)
    capture scalar drop _pte_in_bootstrap
    
    // ================================================================
    // Step 6b: Restore RNG state ( Task 5)
    // ================================================================
    capture set rngstate `orig_rngstate'
    if _rc {
        di as text "{bf:Warning}: Failed to restore random number state"
    }
    
    // ================================================================
    // Step 7: Compute bootstrap statistics
    // ================================================================
    if `show_diagnostics' {
        di as text ""
        di as text "Bootstrap completed: " as result `n_success' as text "/" as result `breps' as text " successful"
        if `n_fail' > 0 {
            di as text "  Failed iterations: " as result `n_fail'
        }
    }
    if `n_success' < 2 {
        di as error "[pte] Error: fewer than 2 successful bootstrap iterations"
        di as error "[pte] Cannot compute standard errors"
        quietly use `full_data', clear
        quietly xtset `panelvar' `timevar'`_pte_boot_delta_opt'
        if `_pte_has_prev_est' {
            capture estimates restore `_pte_prev_est'
            capture estimates drop `_pte_prev_est'
        }
        else {
            capture ereturn clear
        }
        exit 2000
    }
    // 7.1 Compute SE, CI for raw track
    local alpha = (100 - `level') / 200
    tempname se_raw ci_lo_raw ci_hi_raw mean_raw
    matrix `se_raw' = J(1, `ncols', .)
    matrix `ci_lo_raw' = J(1, `ncols', .)
    matrix `ci_hi_raw' = J(1, `ncols', .)
    matrix `mean_raw' = J(1, `ncols', .)
    // Trim track vectors (conditional)
    if `do_trim' {
        tempname se_trim ci_lo_trim ci_hi_trim mean_trim
        matrix `se_trim' = J(1, `ncols', .)
        matrix `ci_lo_trim' = J(1, `ncols', .)
        matrix `ci_hi_trim' = J(1, `ncols', .)
        matrix `mean_trim' = J(1, `ncols', .)
    }
    // Use temporary dataset to compute column statistics
    preserve
    clear
    quietly set obs `breps'
    // Load raw track results
    forvalues j = 1/`ncols' {
        quietly gen double _raw`j' = .
        forvalues bb = 1/`breps' {
            local val = `bs_raw'[`bb', `j']
            if !missing(`val') {
                quietly replace _raw`j' = `val' in `bb'
            }
        }
    }
    // Load trim track results
    if `do_trim' {
        forvalues j = 1/`ncols' {
            quietly gen double _trim`j' = .
            forvalues bb = 1/`breps' {
                local val = `bs_trim'[`bb', `j']
                if !missing(`val') {
                    quietly replace _trim`j' = `val' in `bb'
                }
            }
        }
    }
    // Compute statistics for each column
    forvalues j = 1/`ncols' {
        // --- Raw track ---
        quietly summarize _raw`j'
        if r(N) >= 2 {
            matrix `mean_raw'[1, `j'] = r(mean)
            matrix `se_raw'[1, `j'] = r(sd)
            // Percentile CI
            sort _raw`j'
            quietly count if !missing(_raw`j')
            local nv = r(N)
            local lo_idx = max(1, ceil(`nv' * `alpha'))
            local hi_idx = min(`nv', floor(`nv' * (1 - `alpha')) + 1)
            matrix `ci_lo_raw'[1, `j'] = _raw`j'[`lo_idx']
            matrix `ci_hi_raw'[1, `j'] = _raw`j'[`hi_idx']
        }
        // --- Trim track ---
        if `do_trim' {
            quietly summarize _trim`j'
            if r(N) >= 2 {
                matrix `mean_trim'[1, `j'] = r(mean)
                matrix `se_trim'[1, `j'] = r(sd)
                sort _trim`j'
                quietly count if !missing(_trim`j')
                local nv = r(N)
                local lo_idx = max(1, ceil(`nv' * `alpha'))
                local hi_idx = min(`nv', floor(`nv' * (1 - `alpha')) + 1)
                matrix `ci_lo_trim'[1, `j'] = _trim`j'[`lo_idx']
                matrix `ci_hi_trim'[1, `j'] = _trim`j'[`hi_idx']
            }
        }
    }
    restore
    // ================================================================
    // Step 8: Display results
    // ================================================================
    if `show_diagnostics' {
        di as text ""
        di as text "{hline 70}"
        di as text "Bootstrap ATT Results (`level'% CI, `n_success' replications)"
        di as text "{hline 70}"
    }
    // --- Raw track table ---
    if `show_diagnostics' {
        di as text ""
        di as text "  Raw Track (non-parametric eps0):"
        di as text "  " _col(5) "nt" _col(15) "ATT" _col(27) "BS_SE" _col(39) "[`level'% CI]" _col(63) "N_bs"
        di as text "  {hline 62}"
    }
    // Build result table matrix: [nt, ATT, SE, CI_lo, CI_hi, BS_mean, N_valid]
    tempname rtab_raw
    local nrows_tab = `nperiods' + 1
    matrix `rtab_raw' = J(`nrows_tab', 7, .)
    matrix colnames `rtab_raw' = nt ATT BS_SE CI_lo CI_hi BS_mean N_valid
    forvalues s = 0/`attperiods' {
        local row = `s' + 1
        local col = `s' + 2
        local att_pt = `pt_att_raw_`s''
        local bse = `se_raw'[1, `col']
        local cil = `ci_lo_raw'[1, `col']
        local cih = `ci_hi_raw'[1, `col']
        local bsm = `mean_raw'[1, `col']
        // Count valid bootstrap estimates
        local nv_s = 0
        forvalues bb = 1/`breps' {
            if !missing(`bs_raw'[`bb', `col']) {
                local ++nv_s
            }
        }
        matrix `rtab_raw'[`row', 1] = `s'
        matrix `rtab_raw'[`row', 2] = `att_pt'
        matrix `rtab_raw'[`row', 3] = `bse'
        matrix `rtab_raw'[`row', 4] = `cil'
        matrix `rtab_raw'[`row', 5] = `cih'
        matrix `rtab_raw'[`row', 6] = `bsm'
        matrix `rtab_raw'[`row', 7] = `nv_s'
        if `show_diagnostics' & !missing(`att_pt') & !missing(`bse') {
            di as text "  " _col(5) %3.0f `s' _col(12) as result %10.4f `att_pt' _col(24) as result %10.4f `bse' _col(36) as text "[" as result %8.4f `cil' as text ", " as result %8.4f `cih' as text "]" _col(60) as result %5.0f `nv_s'
        }
    }
    // Overall ATT row
    local row_all = `nperiods' + 1
    local bse_all = `se_raw'[1, 1]
    local cil_all = `ci_lo_raw'[1, 1]
    local cih_all = `ci_hi_raw'[1, 1]
    local bsm_all = `mean_raw'[1, 1]
    matrix `rtab_raw'[`row_all', 1] = -1
    matrix `rtab_raw'[`row_all', 2] = `pt_att_raw'
    matrix `rtab_raw'[`row_all', 3] = `bse_all'
    matrix `rtab_raw'[`row_all', 4] = `cil_all'
    matrix `rtab_raw'[`row_all', 5] = `cih_all'
    matrix `rtab_raw'[`row_all', 6] = `bsm_all'
    matrix `rtab_raw'[`row_all', 7] = `n_success'
    if `show_diagnostics' {
        di as text "  {hline 62}"
        di as text "  " _col(5) "All" _col(12) as result %10.4f `pt_att_raw' _col(24) as result %10.4f `bse_all' _col(36) as text "[" as result %8.4f `cil_all' as text ", " as result %8.4f `cih_all' as text "]" _col(60) as result %5.0f `n_success'
    }
    // --- Trim track table (conditional) ---
    if `do_trim' {
        tempname rtab_trim
        matrix `rtab_trim' = J(`nrows_tab', 7, .)
        matrix colnames `rtab_trim' = nt ATT_trim BS_SE_trim CI_lo_trim CI_hi_trim BS_mean_trim N_valid
        if `show_diagnostics' {
            di as text ""
            di as text "  Trim Track (parametric eps0, winsorized 1-99%):"
            di as text "  " _col(5) "nt" _col(15) "ATT_trim" _col(27) "BS_SE" _col(39) "[`level'% CI]" _col(63) "N_bs"
            di as text "  {hline 62}"
        }
        forvalues s = 0/`attperiods' {
            local row = `s' + 1
            local col = `s' + 2
            local att_pt_t = `pt_att_trim_`s''
            local bse_t = `se_trim'[1, `col']
            local cil_t = `ci_lo_trim'[1, `col']
            local cih_t = `ci_hi_trim'[1, `col']
            local bsm_t = `mean_trim'[1, `col']
            local nv_s_t = 0
            forvalues bb = 1/`breps' {
                if !missing(`bs_trim'[`bb', `col']) {
                    local ++nv_s_t
                }
            }
            matrix `rtab_trim'[`row', 1] = `s'
            matrix `rtab_trim'[`row', 2] = `att_pt_t'
            matrix `rtab_trim'[`row', 3] = `bse_t'
            matrix `rtab_trim'[`row', 4] = `cil_t'
            matrix `rtab_trim'[`row', 5] = `cih_t'
            matrix `rtab_trim'[`row', 6] = `bsm_t'
            matrix `rtab_trim'[`row', 7] = `nv_s_t'
            if `show_diagnostics' & !missing(`att_pt_t') & !missing(`bse_t') {
                di as text "  " _col(5) %3.0f `s' _col(12) as result %10.4f `att_pt_t' _col(24) as result %10.4f `bse_t' _col(36) as text "[" as result %8.4f `cil_t' as text ", " as result %8.4f `cih_t' as text "]" _col(60) as result %5.0f `nv_s_t'
            }
        }
        // Overall trim ATT
        local bse_all_t = `se_trim'[1, 1]
        local cil_all_t = `ci_lo_trim'[1, 1]
        local cih_all_t = `ci_hi_trim'[1, 1]
        local bsm_all_t = `mean_trim'[1, 1]
        matrix `rtab_trim'[`row_all', 1] = -1
        matrix `rtab_trim'[`row_all', 2] = `pt_att_trim'
        matrix `rtab_trim'[`row_all', 3] = `bse_all_t'
        matrix `rtab_trim'[`row_all', 4] = `cil_all_t'
        matrix `rtab_trim'[`row_all', 5] = `cih_all_t'
        matrix `rtab_trim'[`row_all', 6] = `bsm_all_t'
        matrix `rtab_trim'[`row_all', 7] = `n_success'
        if `show_diagnostics' {
            di as text "  {hline 62}"
            di as text "  " _col(5) "All" _col(12) as result %10.4f `pt_att_trim' _col(24) as result %10.4f `bse_all_t' _col(36) as text "[" as result %8.4f `cil_all_t' as text ", " as result %8.4f `cih_all_t' as text "]" _col(60) as result %5.0f `n_success'
        }
    }
    if `show_diagnostics' {
        di as text "{hline 70}"
    }
    // ================================================================
    // Step 9: Restore original data
    // ================================================================
    quietly use `full_data', clear
    foreach _v in _pte_nt _pte_tt _pte_tt_trim _pte_tt_raw {
        capture drop `_v'
    }
    quietly merge 1:1 `id' `time' using `pte_boot_point_outputs', nogen
    quietly xtset `panelvar' `timevar'`_pte_boot_delta_opt'
    capture drop _pte_treat_firm
    // ================================================================
    // Step 10: Optionally save bootstrap results
    // ================================================================
    if "`saving'" != "" {
        local _pte_save_rc = 0
        preserve
        capture noisily {
            clear
            quietly set obs `breps'
            quietly gen long boot_id = _n
            quietly gen double att_raw = .
            if `do_trim' {
                quietly gen double att_trim = .
            }
            forvalues s = 0/`attperiods' {
                quietly gen double att_raw_`s' = .
                if `do_trim' {
                    quietly gen double att_trim_`s' = .
                }
            }
            forvalues bb = 1/`breps' {
                quietly replace att_raw = `bs_raw'[`bb', 1] in `bb'
                forvalues s = 0/`attperiods' {
                    local col = `s' + 2
                    quietly replace att_raw_`s' = `bs_raw'[`bb', `col'] in `bb'
                }
                if `do_trim' {
                    quietly replace att_trim = `bs_trim'[`bb', 1] in `bb'
                    forvalues s = 0/`attperiods' {
                        local col = `s' + 2
                        quietly replace att_trim_`s' = `bs_trim'[`bb', `col'] in `bb'
                    }
                }
            }
            quietly save "`saving'", replace
        }
        local _pte_save_rc = _rc
        restore
        if `_pte_save_rc' != 0 {
            quietly use `full_data', clear
            quietly xtset `panelvar' `timevar'`_pte_boot_delta_opt'
            capture set rngstate `orig_rngstate'
            if `_pte_has_prev_est' {
                capture estimates restore `_pte_prev_est'
                capture estimates drop `_pte_prev_est'
            }
            else {
                capture ereturn clear
            }
            exit `_pte_save_rc'
        }
        if `show_diagnostics' {
            di as text ""
            di as text "Bootstrap results saved to: " as result "`saving'"
        }
    }
    // ================================================================
    // Step 11: Store e() return values
    // ================================================================
    if `_pte_has_prev_est' {
        capture estimates drop `_pte_prev_est'
    }
    ereturn clear
    // --- Scalar returns: Canonical paper-track point estimates ---
    ereturn scalar ATT_avg = `pt_att'
    forvalues s = 0/`attperiods' {
        if !missing(`pt_att_`s'') {
            ereturn scalar att_`s' = `pt_att_`s''
        }
    }
    // --- Scalar returns: Explicit raw aliases ---
    ereturn scalar ATT_avg_raw = `pt_att_raw'
    forvalues s = 0/`attperiods' {
        if !missing(`pt_att_raw_`s'') {
            ereturn scalar att_raw_`s' = `pt_att_raw_`s''
        }
    }
    // --- Scalar returns: Canonical bootstrap SE/CI ---
    if `do_trim' {
        ereturn scalar bs_se = `bse_all_t'
        ereturn scalar ci_lo = `cil_all_t'
        ereturn scalar ci_hi = `cih_all_t'
    }
    else {
        ereturn scalar bs_se = `bse_all'
        ereturn scalar ci_lo = `cil_all'
        ereturn scalar ci_hi = `cih_all'
    }
    forvalues s = 0/`attperiods' {
        local col = `s' + 2
        if `do_trim' local se_s = `se_trim'[1, `col']
        else local se_s = `se_raw'[1, `col']
        if !missing(`se_s') {
            ereturn scalar bs_se_`s' = `se_s'
        }
    }
    forvalues s = 0/`attperiods' {
        local col = `s' + 2
        if `do_trim' {
            local lo_s = `ci_lo_trim'[1, `col']
            local hi_s = `ci_hi_trim'[1, `col']
        }
        else {
            local lo_s = `ci_lo_raw'[1, `col']
            local hi_s = `ci_hi_raw'[1, `col']
        }
        if !missing(`lo_s') {
            ereturn scalar ci_lo_`s' = `lo_s'
            ereturn scalar ci_hi_`s' = `hi_s'
        }
    }
    // --- Scalar returns: Trim aliases ---
    if `do_trim' local pt_att_trim_alias = `pt_att_trim'
    else local pt_att_trim_alias = `pt_att'
    ereturn scalar ATT_avg_trim = `pt_att_trim_alias'
    forvalues s = 0/`attperiods' {
        if `do_trim' local pt_att_trim_s = `pt_att_trim_`s''
        else local pt_att_trim_s = `pt_att_`s''
        if !missing(`pt_att_trim_s') {
            ereturn scalar att_trim_`s' = `pt_att_trim_s'
        }
    }
    if `do_trim' {
        ereturn scalar bs_se_trim = `bse_all_t'
        ereturn scalar ci_lo_trim = `cil_all_t'
        ereturn scalar ci_hi_trim = `cih_all_t'
    }
    else {
        ereturn scalar bs_se_trim = `bse_all'
        ereturn scalar ci_lo_trim = `cil_all'
        ereturn scalar ci_hi_trim = `cih_all'
    }
    forvalues s = 0/`attperiods' {
        local col = `s' + 2
        if `do_trim' {
            local se_s_t = `se_trim'[1, `col']
            local lo_s_t = `ci_lo_trim'[1, `col']
            local hi_s_t = `ci_hi_trim'[1, `col']
        }
        else {
            local se_s_t = `se_raw'[1, `col']
            local lo_s_t = `ci_lo_raw'[1, `col']
            local hi_s_t = `ci_hi_raw'[1, `col']
        }
        if !missing(`se_s_t') {
            ereturn scalar bs_se_trim_`s' = `se_s_t'
        }
        if !missing(`lo_s_t') {
            ereturn scalar ci_lo_trim_`s' = `lo_s_t'
            ereturn scalar ci_hi_trim_`s' = `hi_s_t'
        }
    }
    // --- Scalar returns: Raw bootstrap SE/CI aliases ---
    ereturn scalar bs_se_raw = `bse_all'
    ereturn scalar ci_lo_raw = `cil_all'
    ereturn scalar ci_hi_raw = `cih_all'
    forvalues s = 0/`attperiods' {
        local col = `s' + 2
        local se_s_raw = `se_raw'[1, `col']
        local lo_s_raw = `ci_lo_raw'[1, `col']
        local hi_s_raw = `ci_hi_raw'[1, `col']
        if !missing(`se_s_raw') {
            ereturn scalar bs_se_raw_`s' = `se_s_raw'
        }
        if !missing(`lo_s_raw') {
            ereturn scalar ci_lo_raw_`s' = `lo_s_raw'
            ereturn scalar ci_hi_raw_`s' = `hi_s_raw'
        }
    }
    // --- Scalar returns: Bootstrap diagnostics ---
    ereturn scalar n_success = `n_success'
    ereturn scalar n_fail = `n_fail'
    ereturn scalar bootstrap = `breps'
    ereturn scalar breps = `breps'
    ereturn scalar rngstate_saved = 1
    // --- Scalar returns: Configuration ---
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar attperiods_max = `attperiods'
    ereturn scalar nsim = `nsim'
    ereturn scalar seed = `seed'
    ereturn scalar seed_outer = `seed'
    ereturn scalar inner_seed = `inner_seed'
    ereturn scalar seed_inner = `inner_seed'
    ereturn scalar point_seed = `inner_seed'
    ereturn scalar eps0window = `eps0window'
    ereturn local seed_source "`seed_source'"
    ereturn local inner_seed_source "`inner_seed_source'"
    ereturn scalar level = `level'
    ereturn scalar poly = `poly'
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
    // --- Matrix returns ---
    if `has_pt_beta_controls' {
        ereturn matrix beta_controls = `pt_beta_controls_mat'
    }
    ereturn matrix bs_raw = `bs_raw'
    ereturn matrix bs_betas = `bs_betas'
    ereturn matrix result_table_raw = `rtab_raw'
    ereturn matrix N_by_period = `n_by_period_mat'
    if `do_trim' {
        ereturn matrix bs_trim = `bs_trim'
        ereturn matrix result_table_trim = `rtab_trim'
    }
    // --- Matrix returns: att_se, att_ci_lower, att_ci_upper ---
    // Rearrange from [overall, period0..periodL] to [period0..periodL, overall]
    // to match _pte_compare_se / _pte_graph_att_dynamic consumer contract
    // ncols = 1 + nperiods, where nperiods = attperiods + 1
    tempname att_mat att_trim_mat att_se_mat att_ci_lo_mat att_ci_hi_mat att_raw_mat ///
        attperiods_mat
    local _pte_post_nperiods = `nperiods'
    local _pte_post_support ""
    if `_pte_point_exact_support' {
        local _pte_post_nperiods = colsof(`point_attperiods_mat')
        forvalues _pte_j = 1/`_pte_post_nperiods' {
            local _pte_s = `point_attperiods_mat'[1, `_pte_j']
            local _pte_s_int = round(`_pte_s')
            if missing(`_pte_s') | abs(`_pte_s' - `_pte_s_int') > 1e-10 | ///
                `_pte_s_int' < 0 | `_pte_s_int' > `attperiods' {
                di as error "[pte] Internal error: point ATT support contains invalid event time " ///
                    "`_pte_s'"
                quietly use `full_data', clear
                quietly xtset `panelvar' `timevar'`_pte_boot_delta_opt'
                if `_pte_has_prev_est' {
                    capture estimates restore `_pte_prev_est'
                    capture estimates drop `_pte_prev_est'
                }
                else {
                    capture ereturn clear
                }
                exit 498
            }
            local _pte_post_support "`_pte_post_support' `_pte_s_int'"
        }
    }
    else {
        forvalues s = 0/`attperiods' {
            local _pte_post_support "`_pte_post_support' `s'"
        }
    }
    local _pte_post_support : list retokenize _pte_post_support
    local _pte_post_ncols = `_pte_post_nperiods' + 1
    matrix `att_mat' = J(1, `_pte_post_ncols', .)
    matrix `att_trim_mat' = J(1, `_pte_post_ncols', .)
    matrix `att_se_mat' = J(1, `_pte_post_ncols', .)
    matrix `att_ci_lo_mat' = J(1, `_pte_post_ncols', .)
    matrix `att_ci_hi_mat' = J(1, `_pte_post_ncols', .)
    matrix `att_raw_mat' = J(1, `_pte_post_ncols', .)
    matrix `attperiods_mat' = J(1, `_pte_post_nperiods', .)
    local _se_colnames ""
    local _pte_dst_col = 0
    foreach s of local _pte_post_support {
        local ++_pte_dst_col
        local src_col = `s' + 2
        local dst_col = `_pte_dst_col'
        if `do_trim' {
            if !missing(`pt_att_trim_`s'') {
                matrix `att_mat'[1, `dst_col'] = `pt_att_trim_`s''
                matrix `att_trim_mat'[1, `dst_col'] = `pt_att_trim_`s''
            }
        }
        else {
            if !missing(`pt_att_`s'') {
                matrix `att_mat'[1, `dst_col'] = `pt_att_`s''
                matrix `att_trim_mat'[1, `dst_col'] = `pt_att_`s''
            }
        }
        if `do_trim' {
            matrix `att_se_mat'[1, `dst_col'] = `se_trim'[1, `src_col']
            matrix `att_ci_lo_mat'[1, `dst_col'] = `ci_lo_trim'[1, `src_col']
            matrix `att_ci_hi_mat'[1, `dst_col'] = `ci_hi_trim'[1, `src_col']
        }
        else {
            matrix `att_se_mat'[1, `dst_col'] = `se_raw'[1, `src_col']
            matrix `att_ci_lo_mat'[1, `dst_col'] = `ci_lo_raw'[1, `src_col']
            matrix `att_ci_hi_mat'[1, `dst_col'] = `ci_hi_raw'[1, `src_col']
        }
        if !missing(`pt_att_raw_`s'') {
            matrix `att_raw_mat'[1, `dst_col'] = `pt_att_raw_`s''
        }
        matrix `attperiods_mat'[1, `dst_col'] = `s'
        local _se_colnames "`_se_colnames' nt`s'"
    }
    // Fill overall (avg) as last column
    if `do_trim' {
        matrix `att_mat'[1, `_pte_post_ncols'] = `pt_att_trim'
        matrix `att_trim_mat'[1, `_pte_post_ncols'] = `pt_att_trim'
        matrix `att_se_mat'[1, `_pte_post_ncols'] = `se_trim'[1, 1]
        matrix `att_ci_lo_mat'[1, `_pte_post_ncols'] = `ci_lo_trim'[1, 1]
        matrix `att_ci_hi_mat'[1, `_pte_post_ncols'] = `ci_hi_trim'[1, 1]
    }
    else {
        matrix `att_mat'[1, `_pte_post_ncols'] = `pt_att'
        matrix `att_trim_mat'[1, `_pte_post_ncols'] = `pt_att_trim_alias'
        matrix `att_se_mat'[1, `_pte_post_ncols'] = `se_raw'[1, 1]
        matrix `att_ci_lo_mat'[1, `_pte_post_ncols'] = `ci_lo_raw'[1, 1]
        matrix `att_ci_hi_mat'[1, `_pte_post_ncols'] = `ci_hi_raw'[1, 1]
    }
    matrix `att_raw_mat'[1, `_pte_post_ncols'] = `pt_att_raw'
    local _se_colnames "`_se_colnames' ATT_avg"
    matrix colnames `att_mat' = `_se_colnames'
    matrix colnames `att_trim_mat' = `_se_colnames'
    matrix colnames `att_se_mat' = `_se_colnames'
    matrix colnames `att_ci_lo_mat' = `_se_colnames'
    matrix colnames `att_ci_hi_mat' = `_se_colnames'
    matrix colnames `att_raw_mat' = `_se_colnames'
    local _attperiods_colnames : subinstr local _se_colnames " ATT_avg" "", all
    matrix colnames `attperiods_mat' = `_attperiods_colnames'
    matrix rownames `attperiods_mat' = period
    ereturn matrix att = `att_mat'
    ereturn matrix att_trim = `att_trim_mat'
    ereturn matrix att_se = `att_se_mat'
    ereturn matrix att_ci_lower = `att_ci_lo_mat'
    ereturn matrix att_ci_upper = `att_ci_hi_mat'
    ereturn matrix att_raw = `att_raw_mat'
    ereturn matrix attperiods = `attperiods_mat'
    // --- Local returns ---
    ereturn local treatment "`treatment'"
    ereturn local prodfunc "`prodfunc'"
    ereturn local depvar "`depvar'"
    ereturn local free "`free'"
    ereturn local state "`state'"
    ereturn local proxy "`proxy'"
    ereturn local cmd "_pte_bootstrap"
    ereturn local title "PTE Bootstrap Inference"
    ereturn local seed_outer_strategy "start_plus_index"
end
