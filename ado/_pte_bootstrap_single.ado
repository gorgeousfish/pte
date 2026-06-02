*! _pte_bootstrap_single.ado
*! Single Bootstrap Iteration
*! Encapsulates one complete bootstrap iteration for parallel execution

version 14.0
capture program drop _pte_bootstrap_single
program define _pte_bootstrap_single, rclass
    version 14.0
    local _pte_cmdline `"`0'"'
    foreach _pte_input_opt in treatment depvar free state proxy id time {
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
    syntax, b(integer) ///
        treatment(varname) ///
        depvar(varname) free(varname) state(varname) proxy(varname) ///
        id(varname) time(varname) ///
        [omegapoly(integer 3) ///
         attperiods(integer 4) ///
         nsim(integer -1) ///
         eps0window(integer 0) ///
         seed(integer 1) ///
         inner_seed(integer 123456) ///
         prodfunc(string) ///
         poly(integer -1) ///
         touse(name) ///
         control(varlist) ///
         REPlicate ///
         NOTRIMeps ///
         NODIAGnose]

    local _pte_treatment_resolved = lower(`"`treatment'"')
    local _pte_depvar_resolved = lower(`"`depvar'"')
    local _pte_free_resolved = lower(`"`free'"')
    local _pte_state_resolved = lower(`"`state'"')
    local _pte_proxy_resolved = lower(`"`proxy'"')
    local _pte_id_resolved = lower(`"`id'"')
    local _pte_time_resolved = lower(`"`time'"')
    foreach _pte_input_opt in treatment depvar free state proxy id time {
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

    // Match the serial bootstrap/_pte_att omission contract: order 1 uses
    // one path, higher-order laws default to 100 counterfactual paths.
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

    // Match the serial bootstrap benchmark law: the official translog
    // order-1 replicate path switches the ATT simulation seed to 10000.
    if "`replicate'" != "" & "`prodfunc'" == "translog" & `omegapoly' == 1 {
        local inner_seed = 10000
    }
    if `inner_seed' < 1 {
        di as error "[pte] Error: inner_seed must be >= 1"
        exit 198
    }
    if `inner_seed' > 2147483647 {
        di as error "[pte] Error: inner_seed exceeds maximum value (2147483647)"
        exit 198
    }

    tempname _pte_prev_est
    local _pte_has_prev_est = 0
    capture confirm matrix e(b)
    if _rc == 0 {
        capture estimates store `_pte_prev_est', copy
        if _rc == 0 {
            local _pte_has_prev_est = 1
        }
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

    local _pte_boot_delta ""
    local _pte_boot_delta_opt ""
    capture quietly xtset
    if _rc == 0 {
        local _pte_boot_delta "`r(tdelta)'"
        if "`_pte_boot_delta'" != "" {
            local _pte_boot_delta_opt ", delta(`_pte_boot_delta')"
        }
    }

    // bootstrap_single is an internal helper, but it still runs in a live
    // caller session. The resampling workspace must not leak temporary data or
    // panel-state changes (_pte_firm_bs / xtset) after success or failure.
    local _pte_orig_rngstate = c(rngstate)
    preserve
    local _pte_bs_rc = 0
    tempname att_raw att_trim betas
    capture noisily {
        // ================================================================
        // Step 1: Set outer seed for this iteration
        // ================================================================
        local outer_seed = `seed' + `b' - 1
        set seed `outer_seed'

        // Match the serial bootstrap contract: define the resampling universe on
        // the estimation sample before constructing firm-level strata.
        quietly keep if `_pte_bs_sample'
        quietly replace `_pte_bs_sample' = 1

        // ================================================================
        // Step 2: Stratified cluster bootstrap resampling
        //   bsample, strata(treat) cluster(firm) idcluster(firm1)
        // ================================================================

        // Rebuild firm-level treatment strata from the live bootstrap sample.
        // Stale ambient caches can belong to a different treatment context.
        capture drop _pte_treat_firm
        quietly bysort `id': egen _pte_treat_firm = max(`treatment')

        capture drop _pte_firm_bs
        quietly bsample, strata(_pte_treat_firm) cluster(`id') idcluster(_pte_firm_bs)
        quietly xtset _pte_firm_bs `time'`_pte_boot_delta_opt'

        // ================================================================
        // ================================================================
        local _pf_opts "treatment(`treatment') id(_pte_firm_bs) time(`time')"
        local _pf_opts "`_pf_opts' lny(`depvar') free(`free') state(`state') proxy(`proxy')"
        local _pf_opts "`_pf_opts' pfunc(`prodfunc') poly(`poly') omegapoly(`omegapoly')"
        local _pf_opts "`_pf_opts' touse(`_pte_bs_sample')"
        if "`control'" != "" {
            local _pf_opts "`_pf_opts' control(`control')"
        }
        local _pf_opts "`_pf_opts' noreport nodiagnose"

        _pte_prodfunc, `_pf_opts'

        // Store betas
        local bs_beta_l = _b[`free']
        local bs_beta_k = _b[`state']
        local bs_beta_t = .
        local bs_n_beta_controls = 0
        local bs_beta_ctrl_names ""
        capture matrix _pte_beta_ctrl = e(beta_controls)
        if _rc == 0 {
            local bs_n_beta_controls = colsof(_pte_beta_ctrl)
            local bs_beta_ctrl_names : colnames _pte_beta_ctrl
            if `bs_n_beta_controls' == 1 {
                local bs_beta_t = _pte_beta_ctrl[1, 1]
            }
        }
        else {
            capture local bs_beta_t = _b[t]
        }
        if "`prodfunc'" == "translog" {
            local bs_beta_ll = _b[l2]
            local bs_beta_kk = _b[k2]
            local bs_beta_lk = _b[l1k1]
        }

        // ================================================================
        // ================================================================
        local _om_opts "treatment(`treatment') omegapoly(`omegapoly') nodiagnose"
        local _om_opts "`_om_opts' beta_l(`bs_beta_l') beta_k(`bs_beta_k')"
        local _om_opts "`_om_opts' eps0window(`eps0window')"
        local _om_opts "`_om_opts' touse(`_pte_bs_sample')"
        if "`prodfunc'" == "translog" {
            local _om_opts "`_om_opts' beta_ll(`bs_beta_ll') beta_kk(`bs_beta_kk') beta_lk(`bs_beta_lk')"
            local _om_opts "`_om_opts' prodfunc(translog)"
        }
        if "`notrimeps'" != "" {
            local _om_opts "`_om_opts' notrimeps"
        }

        _pte_omega, `_om_opts'

        // ================================================================
        // ================================================================
        local _att_opts "treatment(`treatment') omegapoly(`omegapoly')"
        local _att_opts "`_att_opts' attperiods(`attperiods') nsim(`nsim') seed(`inner_seed')"
        local _att_opts "`_att_opts' touse(`_pte_bs_sample')"
        local _att_opts "`_att_opts' nodiagnose nostabilitycheck"
        if "`notrimeps'" != "" {
            local _att_opts "`_att_opts' notrimeps"
        }

        _pte_att, `_att_opts'

        // ================================================================
        // Step 6: Collect and return results
        // ================================================================
        local nperiods = `attperiods' + 1
        local ncols = 1 + `nperiods'
        local overall_att = e(ATT_avg)

        // Raw track: [att_overall, att_0, ..., att_T]
        matrix `att_raw' = J(1, `ncols', .)
        matrix `att_raw'[1, 1] = e(ATT_avg_raw)
        forvalues s = 0/`attperiods' {
            local col = `s' + 2
            capture local _tmp = e(att_raw_`s')
            if _rc == 0 & !missing(`_tmp') {
                matrix `att_raw'[1, `col'] = `_tmp'
            }
        }

        // Trim track (conditional)
        local do_trim = ("`notrimeps'" == "")
        if `do_trim' {
            matrix `att_trim' = J(1, `ncols', .)
            capture local _tmp_t = e(ATT_avg_trim)
            if _rc == 0 & !missing(`_tmp_t') {
                matrix `att_trim'[1, 1] = `_tmp_t'
            }
            forvalues s = 0/`attperiods' {
                local col = `s' + 2
                capture local _tmp_t = e(att_trim_`s')
                if _rc == 0 & !missing(`_tmp_t') {
                    matrix `att_trim'[1, `col'] = `_tmp_t'
                }
            }
        }

        // Beta storage
        if "`prodfunc'" == "cd" {
            if `bs_n_beta_controls' > 1 {
                matrix `betas' = J(1, 2 + `bs_n_beta_controls', .)
                matrix colnames `betas' = beta_l beta_k `bs_beta_ctrl_names'
            }
            else {
                matrix `betas' = J(1, 3, .)
                matrix colnames `betas' = beta_l beta_k beta_t
            }
            matrix `betas'[1, 1] = `bs_beta_l'
            matrix `betas'[1, 2] = `bs_beta_k'
            if `bs_n_beta_controls' > 1 {
                forvalues j = 1/`bs_n_beta_controls' {
                    matrix `betas'[1, 2 + `j'] = _pte_beta_ctrl[1, `j']
                }
            }
            else if !missing(`bs_beta_t') {
                matrix `betas'[1, 3] = `bs_beta_t'
            }
        }
        else {
            if `bs_n_beta_controls' > 1 {
                matrix `betas' = J(1, 5 + `bs_n_beta_controls', .)
                matrix colnames `betas' = beta_l beta_k beta_ll beta_kk beta_lk `bs_beta_ctrl_names'
            }
            else {
                matrix `betas' = J(1, 6, .)
                matrix colnames `betas' = beta_l beta_k beta_ll beta_kk beta_lk beta_t
            }
            matrix `betas'[1, 1] = `bs_beta_l'
            matrix `betas'[1, 2] = `bs_beta_k'
            matrix `betas'[1, 3] = `bs_beta_ll'
            matrix `betas'[1, 4] = `bs_beta_kk'
            matrix `betas'[1, 5] = `bs_beta_lk'
            if `bs_n_beta_controls' > 1 {
                forvalues j = 1/`bs_n_beta_controls' {
                    matrix `betas'[1, 5 + `j'] = _pte_beta_ctrl[1, `j']
                }
            }
            else if !missing(`bs_beta_t') {
                matrix `betas'[1, 6] = `bs_beta_t'
            }
        }
    }
    local _pte_bs_rc = _rc
    restore
    if `_pte_bs_rc' != 0 {
        capture set rngstate `_pte_orig_rngstate'
        if `_pte_has_prev_est' {
            capture estimates restore `_pte_prev_est'
            capture estimates drop `_pte_prev_est'
        }
        else {
            capture ereturn clear
        }
        exit `_pte_bs_rc'
    }

    capture set rngstate `_pte_orig_rngstate'
    if `_pte_has_prev_est' {
        capture estimates restore `_pte_prev_est'
        capture estimates drop `_pte_prev_est'
    }
    else {
        capture ereturn clear
    }
    
    // Return
    return scalar b = `b'
    return scalar att = `overall_att'
    return matrix att_raw = `att_raw'
    if `do_trim' {
        return matrix att_trim = `att_trim'
    }
    return matrix betas = `betas'
end
