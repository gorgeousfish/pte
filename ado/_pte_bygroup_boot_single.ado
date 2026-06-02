*! _pte_bygroup_boot_single.ado
*! Encapsulates one complete bootstrap iteration for a single group:
*! 1. Stratified cluster resampling (bsample)
*! 2. Production function re-estimation (_pte_prodfunc)
*! 3. Productivity recovery (_pte_omega)
*! 4. ATT estimation (_pte_att)
*! 5. Return ATT results
*! Key difference from _pte_bootstrap_single:
*! - Does NOT set outer seed (caller manages group seed)
*! - Inner seed for ATT is optional (replication code does not reset)
*! - Data is already filtered to a single group

version 14.0
capture program drop _pte_bygroup_boot_single
program define _pte_bygroup_boot_single, rclass
    version 14.0
    local _pte_cmdline `"`0'"'
    syntax, ///
        treatment(varname) ///
        depvar(varname) free(varname) state(varname) proxy(varname) ///
        id(varname) time(varname) ///
        [omegapoly(integer 3) ///
         attperiods(integer 4) ///
         nsim(integer -1) ///
         eps0window(integer 0) ///
         inner_seed(integer -1) ///
         prodfunc(string) ///
         poly(integer -1) ///
         control(varlist) ///
         NOTRIMeps]
    
    if "`prodfunc'" == "" {
        local prodfunc "cd"
    }
    local _pte_has_poly = regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])poly[(]")
    local _pte_has_omegapoly = regexm(lower(`"`_pte_cmdline'"'), "(^|[ ,])omegapoly[(]")
    if `_pte_has_poly' {
        if `_pte_has_omegapoly' & `poly' != `omegapoly' {
            di as error "[pte] _pte_bygroup_boot_single: cannot specify both poly(`poly') and omegapoly(`omegapoly')"
            exit 198
        }
        local omegapoly = `poly'
    }
    local poly = `omegapoly'

    // Match the serial/bootstrap public omission contract: order 1 uses one
    // path, while higher-order evolution laws default to 100 paths.
    if `nsim' == -1 {
        if `omegapoly' == 1 {
            local nsim = 1
        }
        else {
            local nsim = 100
        }
    }
    if `nsim' < 1 {
        di as error "[pte] _pte_bygroup_boot_single: nsim must be >= 1"
        exit 198
    }

    local use_inner_seed = (`inner_seed' != -1)
    if `use_inner_seed' {
        if `inner_seed' < 1 {
            di as error "[pte] _pte_bygroup_boot_single: inner_seed must be >= 1 when specified"
            exit 198
        }
        if `inner_seed' > 2147483647 {
            di as error "[pte] _pte_bygroup_boot_single: inner_seed exceeds maximum value (2147483647)"
            exit 198
        }
    }
    local _pte_n_controls : word count `control'
    tempname _pte_prev_est
    local _pte_has_prev_est = 0
    capture confirm matrix e(b)
    if _rc == 0 {
        capture estimates store `_pte_prev_est', copy
        if _rc == 0 {
            local _pte_has_prev_est = 1
        }
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
    
    // This helper returns only r() payloads. The grouped bootstrap workspace
    // must not leak resampled data, rewritten xtset metadata, or nested
    // _pte_prodfunc/_pte_omega/_pte_att eclasses back to the caller session.
    local _pte_orig_rngstate = c(rngstate)
    local _pte_bgbs_rc = 0
    local do_trim = ("`notrimeps'" == "")
    local overall_att = .
    tempname att_raw att_trim betas
    preserve
    capture noisily {
        // ================================================================
        // Step 1: Stratified cluster bootstrap resampling
        //   bsample, strata(treat) cluster(firm) idcluster(firm1)
        // ================================================================
        
        // Rebuild firm-level treatment strata from the live grouped sample.
        // Stale ambient caches can belong to a different treatment context.
        capture drop _pte_treat_firm
        quietly bysort `id': egen _pte_treat_firm = max(`treatment')
        
        capture drop _pte_firm_bs
        quietly bsample, strata(_pte_treat_firm) cluster(`id') idcluster(_pte_firm_bs)
        quietly xtset _pte_firm_bs `time'`_pte_boot_delta_opt'
        
        // ================================================================
        // Step 2: Production function re-estimation
        // ================================================================
        local _pf_opts "treatment(`treatment') id(_pte_firm_bs) time(`time')"
        local _pf_opts "`_pf_opts' lny(`depvar') free(`free') state(`state') proxy(`proxy')"
        local _pf_opts "`_pf_opts' pfunc(`prodfunc') poly(`poly') omegapoly(`omegapoly')"
        if "`control'" != "" {
            local _pf_opts "`_pf_opts' control(`control')"
        }
        local _pf_opts "`_pf_opts' noreport nodiagnose"
        
        _pte_prodfunc, `_pf_opts'
        
        // Store betas. Grouped bootstrap must preserve the same industry-contract
        // beta_t column used by grouped point estimation and the official DO files.
        local bs_beta_l = _b[`free']
        local bs_beta_k = _b[`state']
        local bs_beta_t = .
        local _pte_beta_payload_ctrl_ready = 1
        capture matrix _pte_beta_ctrl = e(beta_controls)
        if _rc == 0 {
            local _pte_beta_ctrl_names : colnames _pte_beta_ctrl
            if `_pte_n_controls' > 1 {
                foreach _ctrl of local control {
                    local _ctrl_pos : list posof "`_ctrl'" in _pte_beta_ctrl_names
                    if `_ctrl_pos' < 1 {
                        local _pte_beta_payload_ctrl_ready = 0
                    }
                }
            }
            else if "`control'" != "" {
                local _only_ctrl : word 1 of `control'
                local _ctrl_pos : list posof "`_only_ctrl'" in _pte_beta_ctrl_names
                if `_ctrl_pos' < 1 {
                    local _pte_beta_payload_ctrl_ready = 0
                }
                else {
                    local bs_beta_t = _pte_beta_ctrl[1, `_ctrl_pos']
                }
            }
            else if colsof(_pte_beta_ctrl) >= 1 {
                local bs_beta_t = _pte_beta_ctrl[1, 1]
            }
        }
        else {
            capture local bs_beta_t = _b[t]
            if `_pte_n_controls' > 1 {
                local _pte_beta_payload_ctrl_ready = 0
            }
        }
        if "`prodfunc'" == "translog" {
            local bs_beta_ll = _b[l2]
            local bs_beta_kk = _b[k2]
            local bs_beta_lk = _b[l1k1]
        }
        
        // ================================================================
        // Step 3: Productivity recovery and evolution
        // ================================================================
        local _om_opts "treatment(`treatment') omegapoly(`omegapoly') nodiagnose"
        local _om_opts "`_om_opts' beta_l(`bs_beta_l') beta_k(`bs_beta_k')"
        local _om_opts "`_om_opts' eps0window(`eps0window')"
        if "`prodfunc'" == "translog" {
            local _om_opts "`_om_opts' beta_ll(`bs_beta_ll') beta_kk(`bs_beta_kk') beta_lk(`bs_beta_lk')"
            local _om_opts "`_om_opts' prodfunc(translog)"
        }
        if "`notrimeps'" != "" {
            local _om_opts "`_om_opts' notrimeps"
        }
        
        _pte_omega, `_om_opts'
        
        // ================================================================
        // Step 4: ATT estimation
        // Note: In replication code, NO inner seed reset for industry bootstrap
        // ================================================================
        local _att_opts "treatment(`treatment') omegapoly(`omegapoly')"
        local _att_opts "`_att_opts' attperiods(`attperiods') nsim(`nsim')"
        if `use_inner_seed' {
            local _att_opts "`_att_opts' seed(`inner_seed')"
        }
        else {
            local _att_opts "`_att_opts' preserverng"
        }
        local _att_opts "`_att_opts' nodiagnose nostabilitycheck"
        if "`notrimeps'" != "" {
            local _att_opts "`_att_opts' notrimeps"
        }
        
        _pte_att, `_att_opts'
        
        // ================================================================
        // Step 5: Collect and return results
        // ================================================================
        local nperiods = `attperiods' + 1
        local ncols = 1 + `nperiods'
        local att_colnames ""
        forvalues s = 0/`attperiods' {
            local att_colnames "`att_colnames' ATT`s'"
        }
        local att_colnames "`att_colnames' ATT"
        local overall_att = e(ATT_avg)
        
        // Raw track: [att_overall_raw, att_raw_0, ..., att_raw_T]
        matrix `att_raw' = J(1, `ncols', .)
        matrix colnames `att_raw' = `att_colnames'
        forvalues s = 0/`attperiods' {
            local col = `s' + 1
            capture local _tmp = e(att_raw_`s')
            if _rc == 0 & !missing(`_tmp') {
                matrix `att_raw'[1, `col'] = `_tmp'
            }
        }
        matrix `att_raw'[1, `ncols'] = e(ATT_avg_raw)
        
        // Trim track
        if `do_trim' {
            matrix `att_trim' = J(1, `ncols', .)
            matrix colnames `att_trim' = `att_colnames'
            forvalues s = 0/`attperiods' {
                local col = `s' + 1
                capture local _tmp_t = e(att_trim_`s')
                if _rc == 0 & !missing(`_tmp_t') {
                    matrix `att_trim'[1, `col'] = `_tmp_t'
                }
            }
            matrix `att_trim'[1, `ncols'] = e(ATT_avg_trim)
        }
        
        // Beta storage
        if "`prodfunc'" == "cd" {
            if `_pte_n_controls' > 1 {
                matrix `betas' = J(1, 2 + `_pte_n_controls', .)
                matrix colnames `betas' = beta_l beta_k `control'
            }
            else {
                matrix `betas' = J(1, 3, .)
                matrix colnames `betas' = beta_l beta_k beta_t
            }
            matrix `betas'[1, 1] = `bs_beta_l'
            matrix `betas'[1, 2] = `bs_beta_k'
            if `_pte_n_controls' > 1 {
                if `_pte_beta_payload_ctrl_ready' == 0 {
                    error 503
                }
                foreach _ctrl of local control {
                    local _ctrl_j = `: list posof "`_ctrl'" in control'
                    local _ctrl_pos : list posof "`_ctrl'" in _pte_beta_ctrl_names
                    matrix `betas'[1, 2 + `_ctrl_j'] = _pte_beta_ctrl[1, `_ctrl_pos']
                }
            }
            else if !missing(`bs_beta_t') {
                matrix `betas'[1, 3] = `bs_beta_t'
            }
        }
        else {
            if `_pte_n_controls' > 1 {
                matrix `betas' = J(1, 5 + `_pte_n_controls', .)
                matrix colnames `betas' = beta_l beta_k beta_l2 beta_k2 beta_lk `control'
            }
            else {
                matrix `betas' = J(1, 6, .)
                matrix colnames `betas' = beta_l beta_k beta_l2 beta_k2 beta_lk beta_t
            }
            matrix `betas'[1, 1] = `bs_beta_l'
            matrix `betas'[1, 2] = `bs_beta_k'
            matrix `betas'[1, 3] = `bs_beta_ll'
            matrix `betas'[1, 4] = `bs_beta_kk'
            matrix `betas'[1, 5] = `bs_beta_lk'
            if `_pte_n_controls' > 1 {
                if `_pte_beta_payload_ctrl_ready' == 0 {
                    error 503
                }
                foreach _ctrl of local control {
                    local _ctrl_j = `: list posof "`_ctrl'" in control'
                    local _ctrl_pos : list posof "`_ctrl'" in _pte_beta_ctrl_names
                    matrix `betas'[1, 5 + `_ctrl_j'] = _pte_beta_ctrl[1, `_ctrl_pos']
                }
            }
            else capture {
                matrix `betas'[1, 6] = `bs_beta_t'
            }
        }
    }
    local _pte_bgbs_rc = _rc
    restore

    capture set rngstate `_pte_orig_rngstate'
    if `_pte_has_prev_est' {
        capture estimates restore `_pte_prev_est'
        capture estimates drop `_pte_prev_est'
    }
    else {
        capture ereturn clear
    }
    if `_pte_bgbs_rc' != 0 {
        exit `_pte_bgbs_rc'
    }
    
    // Return
    return matrix att_raw = `att_raw'
    if `do_trim' {
        return matrix att_trim = `att_trim'
    }
    return matrix betas = `betas'
    return scalar att = `overall_att'
end
