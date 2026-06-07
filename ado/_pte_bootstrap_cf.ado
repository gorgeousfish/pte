*! _pte_bootstrap_cf.ado
*! Counterfactual Bootstrap Inference Module
*!
*! Extends standard ATT bootstrap to jointly compute ATT and ATE^count
*! in each bootstrap iteration, enabling difference testing.
*!
*! Two-layer seed management:
*!   - Outer seed: set seed() + b - 1 for each bootstrap iteration
*!     (with the public default seed() = 1 reducing to the official
*!      set seed b loop when seed() is omitted)
*!   - Inner seed: fixed at 123456 for ATT/ATE^count simulation on the
*!     standard serial path; benchmark translog replicate(order1) uses
*!     the official fixed inner seed 10000

version 14.0
capture program drop _pte_bootstrap_cf
program define _pte_bootstrap_cf, eclass
    version 14.0
    local _pte_cmdline `"`0'"'
    syntax, treatment(varname) ///
        depvar(varname) free(varname) state(varname) proxy(varname) ///
        id(varname) time(varname) ///
        TARGETgroup(varname) REFERENCEtime(integer) EXPANSIONtime(integer) ///
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
         level(integer 95) ///
         NOTRIMeps ///
         NOLOg ///
         NODIAGnose ///
         saving(string) ///
         REPlicate ///
         INDustry(varname) ///
         TOUSE(varname) ///
         NOPROgress]

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
    local _pte_cf_seed_offset = 7654321
    local _pte_cf_inner_seed_max = 2147483647 - `_pte_cf_seed_offset'
    local seed_source = "default"
    if regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])seed[(]") {
        local seed_source = "user"
    }
    if `eps0window' < 0 {
        di as error "[pte] Error: eps0window must be non-negative"
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
        di as error "  run {bf:xtset `id' `time'} before calling _pte_bootstrap_cf"
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
    foreach v in `depvar' `free' `state' `proxy' `treatment' `targetgroup' {
        capture confirm variable `v', exact
        if _rc != 0 {
            di as error "[pte] Error: variable '`v'' not found"
            exit 111
        }
    }

    // Replicate mode: switch inner seed for translog order 1
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
    if `inner_seed' > `_pte_cf_inner_seed_max' {
        di as error "[pte] Error: inner_seed exceeds maximum value (`_pte_cf_inner_seed_max')"
        di as error "       counterfactual bootstrap uses an internal eps0 seed offset of +`_pte_cf_seed_offset'"
        exit 198
    }

    // Determine if trim track is active
    local do_trim = ("`notrimeps'" == "")

    // Counterfactual bootstrap is a public eclass entry point. Any failure
    // after nested workers run must restore the caller's prior e() bundle,
    // matching the ordinary bootstrap rollback contract.
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
    di as text ""
    di as text "{hline 70}"
    di as text "Counterfactual Bootstrap Inference"
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
    di as text "  Target group:         " as result "`targetgroup'"
    di as text "  Reference time:       " as result "`referencetime'"
    di as text "  Expansion time:       " as result "`expansiontime'"
    di as text "{hline 70}"

    // ================================================================
    // Step 2: Restrict the workspace to the validated estimation sample
    // before constructing counterfactual bootstrap objects.
    // ================================================================
    tempfile full_data
    quietly save `full_data', replace
    quietly keep if `_pte_bs_sample'
    quietly replace `_pte_bs_sample' = 1

    // ================================================================
    // Step 3: Create firm-level treatment indicator for stratification
    // ================================================================
    capture drop _pte_treat_firm
    quietly bysort `panelvar': egen _pte_treat_firm = max(`treatment')

    // ================================================================
    // Step 4: Save original data and RNG state
    // ================================================================
    tempfile orig_data
    quietly save `orig_data', replace
    local orig_rngstate = c(rngstate)

    // ================================================================
    // Step 5: Point estimates on original data (before bootstrap)
    // ================================================================
    di as text ""
    di as text "Running point estimates on original data..."

    tempname pt_beta_controls_mat
    local has_pt_beta_controls = 0
    local pt_n_beta_controls = 0
    capture {
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

        set seed `inner_seed'
        local _att_opts "treatment(`treatment') omegapoly(`omegapoly')"
        local _att_opts "`_att_opts' attperiods(`attperiods') nsim(`nsim') seed(`inner_seed')"
        local _att_opts "`_att_opts' touse(`_pte_bs_sample')"
        local _att_opts "`_att_opts' nodiagnose"
        if "`notrimeps'" != "" {
            local _att_opts "`_att_opts' notrimeps"
        }
        quietly _pte_att, `_att_opts'

        // Store ATT point estimates
        local nperiods = `attperiods' + 1
        local ncols = `nperiods' + 1   // periods 0..L + pooled
        local pt_att_pooled = e(ATT_avg)
        forvalues s = 0/`attperiods' {
            capture local pt_att_`s' = e(att_`s')
            if _rc != 0 local pt_att_`s' = .
        }
    }
    local _pte_point_rc = _rc
    if `_pte_point_rc' != 0 {
        quietly use `full_data', clear
        quietly xtset `panelvar' `timevar'`_pte_boot_delta_opt'
        capture set rngstate `orig_rngstate'
        capture drop _pte_treat_firm
        if `_pte_has_prev_est' {
            capture estimates restore `_pte_prev_est'
            capture estimates drop `_pte_prev_est'
        }
        else {
            capture ereturn clear
        }
        exit `_pte_point_rc'
    }

    // --- Counterfactual ATE^count estimation ---
    // Call _pte_cf_divergent as default counterfactual method
    local cfmethod "divergent"
    local subcmd_cf "counterfactual_divergent"
    local _cf_opts "targetgroup(`targetgroup') referencetime(`referencetime')"
    local _cf_opts "`_cf_opts' expansiontime(`expansiontime') attperiods(`attperiods')"
    local _cf_opts "`_cf_opts' nsim(`nsim') seed(`inner_seed') quiet"
    capture noisily _pte_cf_divergent, `_cf_opts'
    local cf_rc = _rc
    local cf_ok = (`cf_rc' == 0)
    if `cf_ok' {
        capture local cfmethod "`e(cfmethod)'"
        if _rc != 0 | "`cfmethod'" == "" {
            local cfmethod "divergent"
        }
        capture local subcmd_cf "`e(subcmd_cf)'"
        if _rc != 0 | "`subcmd_cf'" == "" {
            local subcmd_cf "counterfactual_divergent"
        }
    }

    // Store ATE^count point estimates
    if `cf_ok' {
        local pt_ate_pooled = .
        forvalues s = 0/`attperiods' {
            local pt_ate_`s' = .
        }

        tempname pt_ate_mat
        capture matrix `pt_ate_mat' = e(ate_counterfactual)
        if _rc == 0 {
            local pt_ate_sum = 0
            local pt_ate_n = 0
            local pt_ate_cols = colsof(`pt_ate_mat')
            forvalues s = 0/`attperiods' {
                local col = `s' + 1
                if `pt_ate_cols' >= `col' {
                    local _pt_ate_val = `pt_ate_mat'[1, `col']
                    if !missing(`_pt_ate_val') {
                        local pt_ate_`s' = `_pt_ate_val'
                        local pt_ate_sum = `pt_ate_sum' + `_pt_ate_val'
                        local ++pt_ate_n
                    }
                }
            }
            if `pt_ate_cols' >= `ncols' {
                local _pt_ate_pooled = `pt_ate_mat'[1, `ncols']
                if !missing(`_pt_ate_pooled') {
                    local pt_ate_pooled = `_pt_ate_pooled'
                }
            }
            if missing(`pt_ate_pooled') & `pt_ate_n' > 0 {
                local pt_ate_pooled = `pt_ate_sum' / `pt_ate_n'
            }
        }
        else {
            capture local pt_ate_pooled = e(ate_count_avg)
            if _rc != 0 local pt_ate_pooled = .
            forvalues s = 0/`attperiods' {
                capture local pt_ate_`s' = e(ate_count_`s')
                if _rc != 0 local pt_ate_`s' = .
            }
        }
    }
    else {
        di as error "[pte] Error: Counterfactual estimation failed on original data"
        quietly use `full_data', clear
        quietly xtset `panelvar' `timevar'`_pte_boot_delta_opt'
        capture set rngstate `orig_rngstate'
        capture drop _pte_treat_firm
        if `_pte_has_prev_est' {
            capture estimates restore `_pte_prev_est'
            capture estimates drop `_pte_prev_est'
        }
        else {
            capture ereturn clear
        }
        exit `cf_rc'
    }

    di as text "  Point ATT (pooled)       = " as result %10.6f `pt_att_pooled'
    di as text "  Point ATE^count (pooled)  = " as result %10.6f `pt_ate_pooled'

    // ================================================================
    // Step 6: Initialize bootstrap result matrices
    // ================================================================
    // ATT_boot[B x ncols]: col 1..nperiods = att_0..att_L, col ncols = pooled
    // ATE_count_boot[B x ncols]: same layout for ATE^count
    // Delta_boot[B x ncols]: ATT - ATE^count
    tempname bs_att bs_ate bs_delta bs_betas
    matrix `bs_att' = J(`breps', `ncols', .)
    matrix `bs_ate' = J(`breps', `ncols', .)
    matrix `bs_delta' = J(`breps', `ncols', .)
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
    local n_cf_fail = 0

    // ================================================================
    // Step 7: Bootstrap outer loop
    // ================================================================
    di as text ""
    if "`noprogress'" == "" {
        di as text "Bootstrap iterations:" _continue
    }

    // Set bootstrap flag for downstream modules
    scalar _pte_in_bootstrap = 1

    forvalues b = 1/`breps' {
        // 6.1 Progress display
        if "`noprogress'" == "" {
            if mod(`b', 50) == 0 {
                di as result `b' _continue
            }
            else {
                di as text "." _continue
            }
        }

        // 6.2 Restore original data
        quietly use `orig_data', clear
        capture drop phi phi_raw omega
        capture drop _pte_phi _pte_omega _pte_eps0 _pte_eps0_trim _pte_eps0_ind
        capture drop _pte_eps0_draw _pte_eps0_trim_draw
        capture drop _pte_omega_0 _pte_omega_0_trim _pte_omega_02 _pte_omega_03 _pte_omega_04
        capture drop _pte_omega_02_trim _pte_omega_03_trim _pte_omega_04_trim
        capture drop _pte_tt _pte_tt_trim _pte_tt_raw _pte_nt _pte_treat_year treat_yr0

        // 6.3 Set outer seed
        local outer_seed = `seed' + `b' - 1
        set seed `outer_seed'

        // 6.4 Stratified cluster bootstrap resampling
        local bs_ok = 1
        capture drop _pte_firm_bs
        quietly bsample, strata(_pte_treat_firm) cluster(`panelvar') idcluster(_pte_firm_bs)
        quietly count if _pte_treat_firm == 0
        local n_control_bs = r(N)
        quietly count if _pte_treat_firm == 1
        local n_treated_bs = r(N)
        if `n_control_bs' == 0 | `n_treated_bs' == 0 {
            local bs_ok = 0
        }

        // 6.5 Re-xtset with bootstrap firm IDs
        if `bs_ok' == 1 {
            quietly xtset _pte_firm_bs `timevar'`_pte_boot_delta_opt'
        }

        // 6.6 Re-run full pipeline with error handling
        if `bs_ok' == 1 {
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
                capture confirm numeric variable omega
                if _rc != 0 {
                    local bs_ok = 0
                }
                capture confirm numeric variable _pte_eps0
                if _rc != 0 {
                    local bs_ok = 0
                }
                capture confirm numeric variable _pte_eps0_ind
                if _rc != 0 {
                    local bs_ok = 0
                }
            }
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
            if `bs_ok' == 1 {
                capture confirm numeric variable omega
                if _rc != 0 {
                    local bs_ok = 0
                }
                capture confirm numeric variable _pte_eps0
                if _rc != 0 {
                    local bs_ok = 0
                }
                capture confirm numeric variable _pte_eps0_ind
                if _rc != 0 {
                    local bs_ok = 0
                }
            }
        }

        if `bs_ok' == 1 {
            // --- Set inner seed (fixed) for simulation ---
            set seed `inner_seed'

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
            // Joint ATT/ATE^count bootstrap draws are valid only when the
            // counterfactual worker also succeeds. Keep ATT values local until
            // the full counterfactual branch confirms success.
            local _att_avg = e(ATT_avg)
            forvalues s = 0/`attperiods' {
                capture local _tmp_att_`s' = e(att_`s')
                if _rc != 0 local _tmp_att_`s' = .
            }

            // --- Counterfactual ATE^count estimation ---
            local cf_bs_ok = 1
            capture {
                local _cf_bs "targetgroup(`targetgroup') referencetime(`referencetime')"
                local _cf_bs "`_cf_bs' expansiontime(`expansiontime') attperiods(`attperiods')"
                local _cf_bs "`_cf_bs' nsim(`nsim') seed(`inner_seed') quiet"
                _pte_cf_divergent, `_cf_bs'
            }
            if _rc != 0 {
                local cf_bs_ok = 0
                local bs_ok = 0
                local ++n_cf_fail
            }

            if `cf_bs_ok' == 1 {
                // Store ATT results only for fully successful joint draws.
                if !missing(`_att_avg') {
                    matrix `bs_att'[`b', `ncols'] = `_att_avg'
                }
                forvalues s = 0/`attperiods' {
                    local col = `s' + 1
                    if !missing(`_tmp_att_`s'') {
                        matrix `bs_att'[`b', `col'] = `_tmp_att_`s''
                    }
                }

                // Store ATE^count results
                local _ate_avg = .
                tempname ate_bs_mat
                capture matrix `ate_bs_mat' = e(ate_counterfactual)
                if _rc == 0 {
                    local _ate_sum = 0
                    local _ate_n = 0
                    local _ate_cols = colsof(`ate_bs_mat')
                    forvalues s = 0/`attperiods' {
                        local col = `s' + 1
                        if `_ate_cols' >= `col' {
                            local _tmp_ate = `ate_bs_mat'[1, `col']
                            if !missing(`_tmp_ate') {
                                matrix `bs_ate'[`b', `col'] = `_tmp_ate'
                                local _ate_sum = `_ate_sum' + `_tmp_ate'
                                local ++_ate_n
                            }
                        }
                    }
                    if `_ate_cols' >= `ncols' {
                        local _ate_avg_mat = `ate_bs_mat'[1, `ncols']
                        if !missing(`_ate_avg_mat') {
                            local _ate_avg = `_ate_avg_mat'
                        }
                    }
                    if missing(`_ate_avg') & `_ate_n' > 0 {
                        local _ate_avg = `_ate_sum' / `_ate_n'
                    }
                    if !missing(`_ate_avg') {
                        matrix `bs_ate'[`b', `ncols'] = `_ate_avg'
                    }
                }
                else {
                    capture local _ate_avg = e(ate_count_avg)
                    if _rc == 0 & !missing(`_ate_avg') {
                        matrix `bs_ate'[`b', `ncols'] = `_ate_avg'
                    }
                    forvalues s = 0/`attperiods' {
                        local col = `s' + 1
                        capture local _tmp_ate = e(ate_count_`s')
                        if _rc == 0 & !missing(`_tmp_ate') {
                            matrix `bs_ate'[`b', `col'] = `_tmp_ate'
                        }
                    }
                }

                // Compute and store Delta = ATT - ATE^count
                forvalues j = 1/`ncols' {
                    local _a = `bs_att'[`b', `j']
                    local _c = `bs_ate'[`b', `j']
                    if !missing(`_a') & !missing(`_c') {
                        matrix `bs_delta'[`b', `j'] = `_a' - `_c'
                    }
                }
            }

        }
        if `bs_ok' == 1 {
            local ++n_success
        }
        else {
            // Joint bootstrap inference is defined on complete
            // ATT/ATE^count/Delta draws only. If the iteration fails after
            // any partial payload was written, clear the entire row so later
            // SE/CI calculations cannot mix successful joint draws with
            // ATT-only or beta-only fragments.
            forvalues j = 1/`ncols' {
                matrix `bs_att'[`b', `j'] = .
                matrix `bs_ate'[`b', `j'] = .
                matrix `bs_delta'[`b', `j'] = .
            }
            local _pte_beta_cols = cond("`prodfunc'" == "cd", 3, 6)
            forvalues j = 1/`_pte_beta_cols' {
                matrix `bs_betas'[`b', `j'] = .
            }
            local ++n_fail
        }
    }

    // Clear bootstrap flag
    capture scalar drop _pte_in_bootstrap

    if "`noprogress'" == "" {
        di as text _n "Done."
    }

    // Restore RNG state
    capture set rngstate `orig_rngstate'

    // ================================================================
    // Step 7: Compute bootstrap statistics (SE, CI, p-values, Wald)
    // ================================================================
    di as text ""
    di as text "Bootstrap completed: " as result `n_success' as text "/" as result `breps' as text " successful"
    if `n_fail' > 0 {
        di as text "  Failed iterations: " as result `n_fail'
    }
    if `n_cf_fail' > 0 {
        di as text "  CF-only failures:  " as result `n_cf_fail'
    }
    if `n_fail' / `breps' > 0.1 {
        di as error "Warning: >10% Bootstrap iterations failed. Results may be unreliable."
    }
    if `n_success' < 2 {
        di as error "[pte] Error: fewer than 2 successful bootstrap iterations"
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
    if `n_success' < 50 {
        di as text "{bf:Warning}: only `n_success' successful bootstrap iterations"
        di as text "  Percentile intervals and standard errors are unstable with fewer than 50 draws"
    }

    // 7.1 Compute SE, CI, p-values using temporary dataset
    local alpha = (100 - `level') / 200
    // Percentile points (in percent) for the _pctile-based CI bounds, matching
    // the official replication DOs (egen pctile(), p(.)).
    local p_lo = 100 * `alpha'
    local p_hi = 100 * (1 - `alpha')
    tempname se_att ci_lo_att ci_hi_att pval_att mean_att
    tempname se_ate ci_lo_ate ci_hi_ate pval_ate mean_ate
    tempname se_delta ci_lo_delta ci_hi_delta pval_delta mean_delta
    matrix `se_att' = J(1, `ncols', .)
    matrix `ci_lo_att' = J(1, `ncols', .)
    matrix `ci_hi_att' = J(1, `ncols', .)
    matrix `pval_att' = J(1, `ncols', .)
    matrix `mean_att' = J(1, `ncols', .)
    matrix `se_ate' = J(1, `ncols', .)
    matrix `ci_lo_ate' = J(1, `ncols', .)
    matrix `ci_hi_ate' = J(1, `ncols', .)
    matrix `pval_ate' = J(1, `ncols', .)
    matrix `mean_ate' = J(1, `ncols', .)
    matrix `se_delta' = J(1, `ncols', .)
    matrix `ci_lo_delta' = J(1, `ncols', .)
    matrix `ci_hi_delta' = J(1, `ncols', .)
    matrix `pval_delta' = J(1, `ncols', .)
    matrix `mean_delta' = J(1, `ncols', .)

    // Load bootstrap results into temporary dataset
    preserve
    clear
    quietly set obs `breps'

    // Load ATT, ATE, Delta columns
    forvalues j = 1/`ncols' {
        quietly gen double _att`j' = .
        quietly gen double _ate`j' = .
        quietly gen double _delta`j' = .
        forvalues bb = 1/`breps' {
            local va = `bs_att'[`bb', `j']
            local vc = `bs_ate'[`bb', `j']
            local vd = `bs_delta'[`bb', `j']
            if !missing(`va') {
                quietly replace _att`j' = `va' in `bb'
            }
            if !missing(`vc') {
                quietly replace _ate`j' = `vc' in `bb'
            }
            if !missing(`vd') {
                quietly replace _delta`j' = `vd' in `bb'
            }
        }
    }

    // Compute statistics for each column
    forvalues j = 1/`ncols' {
        // --- ATT ---
        quietly summarize _att`j'
        if r(N) >= 2 {
            matrix `mean_att'[1, `j'] = r(mean)
            matrix `se_att'[1, `j'] = r(sd)
            // Percentile CI: use _pctile so the bounds match the official
            // replication DOs (egen pctile(), p(.)) exactly.
            quietly count if !missing(_att`j')
            local nv = r(N)
            quietly _pctile _att`j' if !missing(_att`j'), percentiles(`p_lo' `p_hi')
            matrix `ci_lo_att'[1, `j'] = r(r1)
            matrix `ci_hi_att'[1, `j'] = r(r2)
            // Count zero mass on both tails so a degenerate null distribution
            // does not spuriously reject at p = 0.
            quietly count if _att`j' >= 0 & !missing(_att`j')
            local n_nonneg = r(N)
            quietly count if _att`j' <= 0 & !missing(_att`j')
            local n_nonpos = r(N)
            local prop_nonneg = `n_nonneg' / `nv'
            local prop_nonpos = `n_nonpos' / `nv'
            local pv = min(1, 2 * min(`prop_nonneg', `prop_nonpos'))
            matrix `pval_att'[1, `j'] = `pv'
        }

        // --- ATE^count ---
        quietly summarize _ate`j'
        if r(N) >= 2 {
            matrix `mean_ate'[1, `j'] = r(mean)
            matrix `se_ate'[1, `j'] = r(sd)
            quietly count if !missing(_ate`j')
            local nv = r(N)
            quietly _pctile _ate`j' if !missing(_ate`j'), percentiles(`p_lo' `p_hi')
            matrix `ci_lo_ate'[1, `j'] = r(r1)
            matrix `ci_hi_ate'[1, `j'] = r(r2)
            quietly count if _ate`j' >= 0 & !missing(_ate`j')
            local n_nonneg = r(N)
            quietly count if _ate`j' <= 0 & !missing(_ate`j')
            local n_nonpos = r(N)
            local prop_nonneg = `n_nonneg' / `nv'
            local prop_nonpos = `n_nonpos' / `nv'
            local pv = min(1, 2 * min(`prop_nonneg', `prop_nonpos'))
            matrix `pval_ate'[1, `j'] = `pv'
        }

        // --- Delta = ATT - ATE^count ---
        quietly summarize _delta`j'
        if r(N) >= 2 {
            matrix `mean_delta'[1, `j'] = r(mean)
            matrix `se_delta'[1, `j'] = r(sd)
            quietly count if !missing(_delta`j')
            local nv = r(N)
            quietly _pctile _delta`j' if !missing(_delta`j'), percentiles(`p_lo' `p_hi')
            matrix `ci_lo_delta'[1, `j'] = r(r1)
            matrix `ci_hi_delta'[1, `j'] = r(r2)
            quietly count if _delta`j' >= 0 & !missing(_delta`j')
            local n_nonneg = r(N)
            quietly count if _delta`j' <= 0 & !missing(_delta`j')
            local n_nonpos = r(N)
            local prop_nonneg = `n_nonneg' / `nv'
            local prop_nonpos = `n_nonpos' / `nv'
            local pv = min(1, 2 * min(`prop_nonneg', `prop_nonpos'))
            matrix `pval_delta'[1, `j'] = `pv'
        }
    }

    // 7.2 Wald joint test: H0: Delta_0 = Delta_1 = ... = Delta_L = 0
    // Wald = Delta' * V^{-1} * Delta ~ chi2(L+1)
    local wald_joint = .
    local wald_pval = .
    local wald_df = `nperiods'

    if `nperiods' >= 1 {
        // Build Delta point estimate vector (exclude pooled column)
        tempname delta_vec V_boot V_boot_inv wald_mat
        matrix `delta_vec' = J(`nperiods', 1, 0)
        forvalues i = 1/`nperiods' {
            local _att_i = `pt_att_`= `i' - 1''
            local _ate_i = `pt_ate_`= `i' - 1''
            if !missing(`_att_i') & !missing(`_ate_i') {
                matrix `delta_vec'[`i', 1] = `_att_i' - `_ate_i'
            }
        }

        // Variance-covariance matrix from bootstrap delta columns
        // Keep only period-specific delta columns (exclude pooled)
        capture {
            tempvar _pte_wald_rowmiss
            keep _delta1-_delta`nperiods'
            quietly egen `_pte_wald_rowmiss' = rowmiss(_delta1-_delta`nperiods')
            quietly count if `_pte_wald_rowmiss' == 0
            local n_wald = r(N)
            if `n_wald' >= 2 {
                quietly keep if `_pte_wald_rowmiss' == 0
                drop `_pte_wald_rowmiss'
                mat accum `V_boot' = _delta*, deviations noconstant
                mat `V_boot' = `V_boot' / (`n_wald' - 1)

                // Check invertibility
                local det_v = det(`V_boot')
                if `det_v' > 1e-10 {
                    mat `V_boot_inv' = inv(`V_boot')
                }
                else {
                    // Use Mata generalized inverse for near-singular case
                    di as text "  Note: Variance matrix near-singular, using generalized inverse"
                    mata: st_matrix("`V_boot_inv'", pinv(st_matrix("`V_boot'")))
                }

                // Wald = Delta' * V^{-1} * Delta
                mat `wald_mat' = `delta_vec'' * `V_boot_inv' * `delta_vec'
                local wald_joint = `wald_mat'[1, 1]
                local wald_pval = 1 - chi2(`wald_df', `wald_joint')
            }
        }
        if _rc != 0 {
            di as text "  Note: Wald test computation failed (rc=" _rc ")"
            local wald_joint = .
            local wald_pval = .
        }
    }

    restore

    // ================================================================
    // Step 8: Display results
    // ================================================================
    di as text ""
    di as text "{hline 70}"
    di as text "Counterfactual Bootstrap Results (`level'% CI, `n_success' reps)"
    di as text "{hline 70}"

    // --- ATT results ---
    di as text ""
    di as text "  ATT (Average Treatment Effect on the Treated):"
    di as text "  " _col(5) "ell" _col(14) "ATT" _col(26) "BS_SE" _col(38) "[`level'% CI]" _col(62) "p-val"
    di as text "  {hline 62}"
    forvalues s = 0/`attperiods' {
        local col = `s' + 1
        local att_pt = `pt_att_`s''
        local bse = `se_att'[1, `col']
        local cil = `ci_lo_att'[1, `col']
        local cih = `ci_hi_att'[1, `col']
        local pv = `pval_att'[1, `col']
        if !missing(`att_pt') & !missing(`bse') {
            di as text "  " _col(5) %3.0f `s' _col(11) as result %10.4f `att_pt' _col(23) as result %8.4f `bse' _col(33) as text "[" as result %7.4f `cil' as text "," as result %7.4f `cih' as text "]" _col(58) as result %6.4f `pv'
        }
    }
    // Pooled row
    local bse_p = `se_att'[1, `ncols']
    local cil_p = `ci_lo_att'[1, `ncols']
    local cih_p = `ci_hi_att'[1, `ncols']
    local pv_p = `pval_att'[1, `ncols']
    di as text "  {hline 62}"
    di as text "  " _col(5) "All" _col(11) as result %10.4f `pt_att_pooled' _col(23) as result %8.4f `bse_p' _col(33) as text "[" as result %7.4f `cil_p' as text "," as result %7.4f `cih_p' as text "]" _col(58) as result %6.4f `pv_p'

    // --- ATE^count results ---
    di as text ""
    di as text "  ATE^count (Counterfactual Average Treatment Effect):"
    di as text "  " _col(5) "ell" _col(14) "ATE_cf" _col(26) "BS_SE" _col(38) "[`level'% CI]" _col(62) "p-val"
    di as text "  {hline 62}"
    forvalues s = 0/`attperiods' {
        local col = `s' + 1
        local ate_pt = `pt_ate_`s''
        local bse = `se_ate'[1, `col']
        local cil = `ci_lo_ate'[1, `col']
        local cih = `ci_hi_ate'[1, `col']
        local pv = `pval_ate'[1, `col']
        if !missing(`ate_pt') & !missing(`bse') {
            di as text "  " _col(5) %3.0f `s' _col(11) as result %10.4f `ate_pt' _col(23) as result %8.4f `bse' _col(33) as text "[" as result %7.4f `cil' as text "," as result %7.4f `cih' as text "]" _col(58) as result %6.4f `pv'
        }
    }
    local bse_p = `se_ate'[1, `ncols']
    local cil_p = `ci_lo_ate'[1, `ncols']
    local cih_p = `ci_hi_ate'[1, `ncols']
    local pv_p = `pval_ate'[1, `ncols']
    di as text "  {hline 62}"
    di as text "  " _col(5) "All" _col(11) as result %10.4f `pt_ate_pooled' _col(23) as result %8.4f `bse_p' _col(33) as text "[" as result %7.4f `cil_p' as text "," as result %7.4f `cih_p' as text "]" _col(58) as result %6.4f `pv_p'

    // --- Delta = ATT - ATE^count ---
    di as text ""
    di as text "  Delta = ATT - ATE^count (Difference Test):"
    di as text "  " _col(5) "ell" _col(14) "Delta" _col(26) "BS_SE" _col(38) "[`level'% CI]" _col(62) "p-val"
    di as text "  {hline 62}"
    forvalues s = 0/`attperiods' {
        local col = `s' + 1
        local att_pt = `pt_att_`s''
        local ate_pt = `pt_ate_`s''
        local delta_pt = .
        if !missing(`att_pt') & !missing(`ate_pt') {
            local delta_pt = `att_pt' - `ate_pt'
        }
        local bse = `se_delta'[1, `col']
        local cil = `ci_lo_delta'[1, `col']
        local cih = `ci_hi_delta'[1, `col']
        local pv = `pval_delta'[1, `col']
        if !missing(`delta_pt') & !missing(`bse') {
            di as text "  " _col(5) %3.0f `s' _col(11) as result %10.4f `delta_pt' _col(23) as result %8.4f `bse' _col(33) as text "[" as result %7.4f `cil' as text "," as result %7.4f `cih' as text "]" _col(58) as result %6.4f `pv'
        }
    }
    local delta_pooled = .
    if !missing(`pt_att_pooled') & !missing(`pt_ate_pooled') {
        local delta_pooled = `pt_att_pooled' - `pt_ate_pooled'
    }
    local bse_p = `se_delta'[1, `ncols']
    local cil_p = `ci_lo_delta'[1, `ncols']
    local cih_p = `ci_hi_delta'[1, `ncols']
    local pv_p = `pval_delta'[1, `ncols']
    di as text "  {hline 62}"
    di as text "  " _col(5) "All" _col(11) as result %10.4f `delta_pooled' _col(23) as result %8.4f `bse_p' _col(33) as text "[" as result %7.4f `cil_p' as text "," as result %7.4f `cih_p' as text "]" _col(58) as result %6.4f `pv_p'

    // --- Wald joint test ---
    di as text ""
    if !missing(`wald_joint') {
        di as text "  Wald joint test: H0: Delta_0 = ... = Delta_L = 0"
        di as text "    Wald statistic = " as result %10.4f `wald_joint'
        di as text "    df             = " as result `wald_df'
        di as text "    p-value        = " as result %8.4f `wald_pval'
    }
    else {
        di as text "  Wald joint test: not computed"
    }
    di as text "{hline 70}"

    // ================================================================
    // Step 9: Restore original data
    // ================================================================
    quietly use `full_data', clear
    quietly xtset `panelvar' `timevar'`_pte_boot_delta_opt'
    capture drop _pte_treat_firm

    // ================================================================
    // Step 10: Optionally save bootstrap results
    // ================================================================
    if "`saving'" != "" {
        preserve
        clear
        quietly set obs `breps'
        quietly gen long boot_id = _n

        // ATT columns
        quietly gen double att_pooled = .
        forvalues s = 0/`attperiods' {
            quietly gen double att_`s' = .
        }
        // ATE^count columns
        quietly gen double ate_count_pooled = .
        forvalues s = 0/`attperiods' {
            quietly gen double ate_count_`s' = .
        }
        // Delta columns
        quietly gen double delta_pooled = .
        forvalues s = 0/`attperiods' {
            quietly gen double delta_`s' = .
        }

        // Fill from bootstrap matrices
        forvalues bb = 1/`breps' {
            // ATT
            local _v = `bs_att'[`bb', `ncols']
            if !missing(`_v') {
                quietly replace att_pooled = `_v' in `bb'
            }
            forvalues s = 0/`attperiods' {
                local col = `s' + 1
                local _v = `bs_att'[`bb', `col']
                if !missing(`_v') {
                    quietly replace att_`s' = `_v' in `bb'
                }
            }
            // ATE^count
            local _v = `bs_ate'[`bb', `ncols']
            if !missing(`_v') {
                quietly replace ate_count_pooled = `_v' in `bb'
            }
            forvalues s = 0/`attperiods' {
                local col = `s' + 1
                local _v = `bs_ate'[`bb', `col']
                if !missing(`_v') {
                    quietly replace ate_count_`s' = `_v' in `bb'
                }
            }
            // Delta
            local _v = `bs_delta'[`bb', `ncols']
            if !missing(`_v') {
                quietly replace delta_pooled = `_v' in `bb'
            }
            forvalues s = 0/`attperiods' {
                local col = `s' + 1
                local _v = `bs_delta'[`bb', `col']
                if !missing(`_v') {
                    quietly replace delta_`s' = `_v' in `bb'
                }
            }
        }

        quietly save "`saving'", replace
        di as text ""
        di as text "Bootstrap results saved to: " as result "`saving'"
        restore
    }

    // ================================================================
    // Step 11: Store e() return values
    // ================================================================
    if `_pte_has_prev_est' {
        capture estimates drop `_pte_prev_est'
    }
    ereturn clear

    local _pte_sparse_support_cols ""
    local _pte_sparse_support_periods ""
    forvalues s = 0/`attperiods' {
        if !missing(`pt_att_`s'') & !missing(`pt_ate_`s'') {
            local _pte_sparse_support_cols "`_pte_sparse_support_cols' `=`s' + 1'"
            local _pte_sparse_support_periods "`_pte_sparse_support_periods' `s'"
        }
    }
    local _pte_sparse_support_cols : list retokenize _pte_sparse_support_cols
    local _pte_sparse_support_periods : list retokenize _pte_sparse_support_periods
    local _pte_sparse_nperiods : word count `_pte_sparse_support_cols'
    if `_pte_sparse_nperiods' < 1 {
        di as error "[pte] Error: no common nonmissing dynamic ATT/ATE^count periods remain"
        exit 2000
    }
    local _pte_sparse_ncols = `_pte_sparse_nperiods' + 1

    tempname att_mat ate_mat
    tempname se_att_out ci_lo_att_out ci_hi_att_out pval_att_out
    tempname se_ate_out ci_lo_ate_out ci_hi_ate_out pval_ate_out
    tempname se_delta_out ci_lo_delta_out ci_hi_delta_out pval_delta_out
    tempname bs_att_out bs_ate_out bs_delta_out
    tempname attperiods_vec attperiods_mat
    matrix `att_mat' = J(1, `_pte_sparse_ncols', .)
    matrix `ate_mat' = J(1, `_pte_sparse_ncols', .)
    matrix `se_att_out' = J(1, `_pte_sparse_ncols', .)
    matrix `ci_lo_att_out' = J(1, `_pte_sparse_ncols', .)
    matrix `ci_hi_att_out' = J(1, `_pte_sparse_ncols', .)
    matrix `pval_att_out' = J(1, `_pte_sparse_ncols', .)
    matrix `se_ate_out' = J(1, `_pte_sparse_ncols', .)
    matrix `ci_lo_ate_out' = J(1, `_pte_sparse_ncols', .)
    matrix `ci_hi_ate_out' = J(1, `_pte_sparse_ncols', .)
    matrix `pval_ate_out' = J(1, `_pte_sparse_ncols', .)
    matrix `se_delta_out' = J(1, `_pte_sparse_ncols', .)
    matrix `ci_lo_delta_out' = J(1, `_pte_sparse_ncols', .)
    matrix `ci_hi_delta_out' = J(1, `_pte_sparse_ncols', .)
    matrix `pval_delta_out' = J(1, `_pte_sparse_ncols', .)
    matrix `bs_att_out' = J(`breps', `_pte_sparse_ncols', .)
    matrix `bs_ate_out' = J(`breps', `_pte_sparse_ncols', .)
    matrix `bs_delta_out' = J(`breps', `_pte_sparse_ncols', .)
    matrix `attperiods_vec' = J(1, `_pte_sparse_nperiods', .)
    local att_colnames ""
    local ate_colnames ""
    local delta_colnames ""
    local ap_colnames ""
    local _pte_store_idx = 0
    foreach s of local _pte_sparse_support_periods {
        local ++_pte_store_idx
        local col : word `_pte_store_idx' of `_pte_sparse_support_cols'
        matrix `att_mat'[1, `_pte_store_idx'] = `pt_att_`s''
        matrix `ate_mat'[1, `_pte_store_idx'] = `pt_ate_`s''
        matrix `se_att_out'[1, `_pte_store_idx'] = `se_att'[1, `col']
        matrix `ci_lo_att_out'[1, `_pte_store_idx'] = `ci_lo_att'[1, `col']
        matrix `ci_hi_att_out'[1, `_pte_store_idx'] = `ci_hi_att'[1, `col']
        matrix `pval_att_out'[1, `_pte_store_idx'] = `pval_att'[1, `col']
        matrix `se_ate_out'[1, `_pte_store_idx'] = `se_ate'[1, `col']
        matrix `ci_lo_ate_out'[1, `_pte_store_idx'] = `ci_lo_ate'[1, `col']
        matrix `ci_hi_ate_out'[1, `_pte_store_idx'] = `ci_hi_ate'[1, `col']
        matrix `pval_ate_out'[1, `_pte_store_idx'] = `pval_ate'[1, `col']
        matrix `se_delta_out'[1, `_pte_store_idx'] = `se_delta'[1, `col']
        matrix `ci_lo_delta_out'[1, `_pte_store_idx'] = `ci_lo_delta'[1, `col']
        matrix `ci_hi_delta_out'[1, `_pte_store_idx'] = `ci_hi_delta'[1, `col']
        matrix `pval_delta_out'[1, `_pte_store_idx'] = `pval_delta'[1, `col']
        forvalues _pte_b = 1/`breps' {
            matrix `bs_att_out'[`_pte_b', `_pte_store_idx'] = `bs_att'[`_pte_b', `col']
            matrix `bs_ate_out'[`_pte_b', `_pte_store_idx'] = `bs_ate'[`_pte_b', `col']
            matrix `bs_delta_out'[`_pte_b', `_pte_store_idx'] = `bs_delta'[`_pte_b', `col']
        }
        matrix `attperiods_vec'[1, `_pte_store_idx'] = `s'
        local att_colnames "`att_colnames' nt`s'"
        local ate_colnames "`ate_colnames' ate_count_`s'"
        local delta_colnames "`delta_colnames' delta_`s'"
        local ap_colnames "`ap_colnames' `s'"
    }
    matrix `att_mat'[1, `_pte_sparse_ncols'] = `pt_att_pooled'
    matrix `ate_mat'[1, `_pte_sparse_ncols'] = `pt_ate_pooled'
    matrix `se_att_out'[1, `_pte_sparse_ncols'] = `se_att'[1, `ncols']
    matrix `ci_lo_att_out'[1, `_pte_sparse_ncols'] = `ci_lo_att'[1, `ncols']
    matrix `ci_hi_att_out'[1, `_pte_sparse_ncols'] = `ci_hi_att'[1, `ncols']
    matrix `pval_att_out'[1, `_pte_sparse_ncols'] = `pval_att'[1, `ncols']
    matrix `se_ate_out'[1, `_pte_sparse_ncols'] = `se_ate'[1, `ncols']
    matrix `ci_lo_ate_out'[1, `_pte_sparse_ncols'] = `ci_lo_ate'[1, `ncols']
    matrix `ci_hi_ate_out'[1, `_pte_sparse_ncols'] = `ci_hi_ate'[1, `ncols']
    matrix `pval_ate_out'[1, `_pte_sparse_ncols'] = `pval_ate'[1, `ncols']
    matrix `se_delta_out'[1, `_pte_sparse_ncols'] = `se_delta'[1, `ncols']
    matrix `ci_lo_delta_out'[1, `_pte_sparse_ncols'] = `ci_lo_delta'[1, `ncols']
    matrix `ci_hi_delta_out'[1, `_pte_sparse_ncols'] = `ci_hi_delta'[1, `ncols']
    matrix `pval_delta_out'[1, `_pte_sparse_ncols'] = `pval_delta'[1, `ncols']
    forvalues _pte_b = 1/`breps' {
        matrix `bs_att_out'[`_pte_b', `_pte_sparse_ncols'] = `bs_att'[`_pte_b', `ncols']
        matrix `bs_ate_out'[`_pte_b', `_pte_sparse_ncols'] = `bs_ate'[`_pte_b', `ncols']
        matrix `bs_delta_out'[`_pte_b', `_pte_sparse_ncols'] = `bs_delta'[`_pte_b', `ncols']
    }
    matrix colnames `att_mat' = `att_colnames' ATT_avg
    matrix colnames `ate_mat' = `ate_colnames' ATE_count_avg
    matrix rownames `att_mat' = ATT
    matrix rownames `ate_mat' = ATE_count
    matrix colnames `se_att_out' = `att_colnames' ATT_avg
    matrix colnames `ci_lo_att_out' = `att_colnames' ATT_avg
    matrix colnames `ci_hi_att_out' = `att_colnames' ATT_avg
    matrix colnames `pval_att_out' = `att_colnames' ATT_avg
    matrix rownames `se_att_out' = ATT
    matrix rownames `ci_lo_att_out' = ATT
    matrix rownames `ci_hi_att_out' = ATT
    matrix rownames `pval_att_out' = ATT
    matrix colnames `se_ate_out' = `ate_colnames' ATE_count_avg
    matrix colnames `ci_lo_ate_out' = `ate_colnames' ATE_count_avg
    matrix colnames `ci_hi_ate_out' = `ate_colnames' ATE_count_avg
    matrix colnames `pval_ate_out' = `ate_colnames' ATE_count_avg
    matrix rownames `se_ate_out' = ATE_count
    matrix rownames `ci_lo_ate_out' = ATE_count
    matrix rownames `ci_hi_ate_out' = ATE_count
    matrix rownames `pval_ate_out' = ATE_count
    matrix colnames `se_delta_out' = `delta_colnames' delta_avg
    matrix colnames `ci_lo_delta_out' = `delta_colnames' delta_avg
    matrix colnames `ci_hi_delta_out' = `delta_colnames' delta_avg
    matrix colnames `pval_delta_out' = `delta_colnames' delta_avg
    matrix rownames `se_delta_out' = Delta
    matrix rownames `ci_lo_delta_out' = Delta
    matrix rownames `ci_hi_delta_out' = Delta
    matrix rownames `pval_delta_out' = Delta
    matrix colnames `bs_att_out' = `att_colnames' ATT_avg
    matrix colnames `bs_ate_out' = `ate_colnames' ATE_count_avg
    matrix colnames `bs_delta_out' = `delta_colnames' delta_avg
    matrix colnames `attperiods_vec' = `ap_colnames'
    matrix rownames `attperiods_vec' = "period"
    matrix `attperiods_mat' = `attperiods_vec'

    // --- Scalar returns: ATT point estimates ---
    ereturn scalar ATT_avg = `pt_att_pooled'
    foreach s of local _pte_sparse_support_periods {
        if !missing(`pt_att_`s'') {
            ereturn scalar att_`s' = `pt_att_`s''
        }
    }

    // --- Scalar returns: ATE^count point estimates ---
    // Main ATE^count contract is matrix e(ate_count); keep the pooled scalar
    // under an explicit alias to avoid scalar/matrix name collisions in Stata.
    ereturn scalar ate_count_avg = `pt_ate_pooled'
    foreach s of local _pte_sparse_support_periods {
        if !missing(`pt_ate_`s'') {
            ereturn scalar ate_count_`s' = `pt_ate_`s''
        }
    }

    // --- Scalar returns: Delta point estimates ---
    local delta_pooled_val = .
    if !missing(`pt_att_pooled') & !missing(`pt_ate_pooled') {
        local delta_pooled_val = `pt_att_pooled' - `pt_ate_pooled'
    }
    ereturn scalar delta = `delta_pooled_val'
    foreach s of local _pte_sparse_support_periods {
        local _d = .
        if !missing(`pt_att_`s'') & !missing(`pt_ate_`s'') {
            local _d = `pt_att_`s'' - `pt_ate_`s''
        }
        ereturn scalar delta_`s' = `_d'
    }

    // --- Scalar returns: Wald test ---
    ereturn scalar wald_joint = `wald_joint'
    ereturn scalar wald_pval = `wald_pval'
    ereturn scalar wald_df = `_pte_sparse_nperiods'

    // --- Scalar returns: Bootstrap diagnostics ---
    ereturn scalar n_success = `n_success'
    ereturn scalar n_fail = `n_fail'
    ereturn scalar n_cf_fail = `n_cf_fail'
    ereturn scalar bootstrap = `breps'
    ereturn scalar breps = `breps'
    ereturn scalar nboot = `breps'

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
    ereturn scalar level = `level'
    ereturn scalar poly = `poly'
    ereturn scalar referencetime = `referencetime'

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

    // --- Matrix returns: ATT point estimates ---
    ereturn matrix attperiods = `attperiods_mat'
    ereturn matrix attperiods_vec = `attperiods_vec'
    ereturn matrix att = `att_mat'
    ereturn matrix ate_count = `ate_mat'

    // --- Matrix returns: SE ---
    ereturn matrix att_se = `se_att_out'
    ereturn matrix ate_count_se = `se_ate_out'
    ereturn matrix delta_se = `se_delta_out'

    // --- Matrix returns: CI ---
    ereturn matrix att_lb = `ci_lo_att_out'
    ereturn matrix att_ub = `ci_hi_att_out'
    ereturn matrix ate_count_lb = `ci_lo_ate_out'
    ereturn matrix ate_count_ub = `ci_hi_ate_out'
    ereturn matrix delta_lb = `ci_lo_delta_out'
    ereturn matrix delta_ub = `ci_hi_delta_out'

    // --- Matrix returns: p-values ---
    ereturn matrix att_pval = `pval_att_out'
    ereturn matrix ate_count_pval = `pval_ate_out'
    ereturn matrix delta_pval = `pval_delta_out'

    // --- Matrix returns: Bootstrap samples ---
    ereturn matrix bs_att = `bs_att_out'
    ereturn matrix bs_ate = `bs_ate_out'
    ereturn matrix bs_delta = `bs_delta_out'
    if `has_pt_beta_controls' {
        ereturn matrix beta_controls = `pt_beta_controls_mat'
    }
    ereturn matrix bs_betas = `bs_betas'

    // --- Local returns ---
    ereturn local treatment "`treatment'"
    ereturn local targetgroup "`targetgroup'"
    ereturn local prodfunc "`prodfunc'"
    ereturn local depvar "`depvar'"
    ereturn local free "`free'"
    ereturn local state "`state'"
    ereturn local proxy "`proxy'"
    ereturn local cfmethod "`cfmethod'"
    ereturn local subcmd_cf "`subcmd_cf'"
    ereturn local cmd "_pte_bootstrap_cf"
    ereturn local title "PTE Counterfactual Bootstrap Inference"
    ereturn local seed_source "`seed_source'"
    ereturn local inner_seed_source "`inner_seed_source'"
    ereturn local seed_outer_strategy "start_plus_index"

end
