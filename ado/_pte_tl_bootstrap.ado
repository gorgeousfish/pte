*! _pte_tl_bootstrap.ado
*! Bootstrap Variance Estimation for Translog Production Function
*!
*! Implements block bootstrap variance-covariance estimation for
*! Translog production function parameters (beta_l, beta_k, beta_ll,
*! beta_kk, beta_lk) while also publishing the stage-1 time-trend
*! payload beta_t through the bootstrap draw contract.
*!
*! Algorithm:
*!   For b = 1, ..., B:
*!     1. set seed b (outer-layer seed)
*!     2. bsample, strata(treat) cluster(firm) idcluster(firm1)
*!     3. xtset firm1 year
*!     4. _pte_transition (regenerate mid)
*!     5. _pte_tl_estimate (re-estimate production function)
*!     6. Collect beta_b = (beta_l, beta_k, beta_ll, beta_kk, beta_lk)
*!        and bridge beta_t from the stage-1 control payload
*!   V = Var(beta_1, ..., beta_B)  [5x5 matrix]

version 14.0
capture program drop _pte_tl_bootstrap
program define _pte_tl_bootstrap, eclass
    version 14.0

    // ================================================================
    // Syntax parsing
    // ================================================================
    syntax, free(varname) state(varname) proxy(varname) ///
        depvar(varname) treatment(varname) ///
        [CONTROLvars(varlist) omegapoly(integer 3) ///
         reps(integer 500) pooled noreport NOLOg]

    // ================================================================
    // Step 0: Retrieve panel variables from xtset
    // ================================================================
    capture _xt, trequired
    if _rc {
        di as error "{bf:_pte_tl_bootstrap}: data not xtset"
        exit 459
    }
    local panelvar "`r(ivar)'"
    local timevar  "`r(tvar)'"

    // ================================================================
    // Step 1: Generate treat stratification variable
    // ================================================================
    tempvar treat_strata
    qui bysort `panelvar': egen byte `treat_strata' = max(`treatment')
    label variable `treat_strata' "Bootstrap stratification (ever-treated)"

    // ================================================================
    // Step 2: Save original data to tempfile
    // ================================================================
    tempfile orig_data
    qui save `orig_data', replace

    // ================================================================
    // Step 3: Bootstrap loop header
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "Translog Bootstrap Variance Estimation (TASK-007.34)"
        di as text "{hline 60}"
        di as text _col(3) "Bootstrap replications:" _col(40) as result `reps'
        di as text _col(3) "Resampling:" _col(40) as result "cluster (by firm)"
        di as text _col(3) "Stratification:" _col(40) as result "ever-treated"
        di as text _col(3) "Parameters:" _col(40) as result "5 GMM + beta_t payload"
        di as text "{hline 60}"
        di as text ""
    }

    // ================================================================
    // Step 4: Initialize Mata matrix to collect bootstrap betas
    // ================================================================
    tempname beta_boot_mat bs_betas
    mata: _pte_beta_boot = J(`reps', 5, .)
    matrix `bs_betas' = J(`reps', 6, .)
    matrix colnames `bs_betas' = beta_l beta_k beta_ll beta_kk beta_lk beta_t

    local n_success = 0
    local n_fail = 0

    // Build control option string once (used in all iterations)
    local _ctrl_opt ""
    if "`controlvars'" != "" {
        local _ctrl_opt "control(`controlvars')"
    }

    // ================================================================
    // Step 5: Bootstrap loop
    // ================================================================
    // Iteration-scoped helpers (safe temporary variable names).
    // Note: tempvar names survive `use ..., clear` across iterations as locals,
    // but the variables themselves are regenerated each iteration.
    tempvar _pte_bs_id _pte_treat_strata_b

    forvalues b = 1/`reps' {

        // Progress display every 10 iterations
        if "`nolog'" == "" {
            if mod(`b', 10) == 0 | `b' == 1 | `b' == `reps' {
                di as text "  Bootstrap iteration `b'/`reps'" ///
                    " (success: `n_success', fail: `n_fail')"
            }
        }

        // 5a: Restore original data
        qui use `orig_data', clear

        // 5b: Set outer-layer seed = b
        set seed `b'

        // 5c: Block bootstrap resample
        // Stratify by ever-treated, cluster by firm, create new firm ID
        qui bysort `panelvar': egen byte `_pte_treat_strata_b' = max(`treatment')

        capture quietly bsample, strata(`_pte_treat_strata_b') cluster(`panelvar') idcluster(`_pte_bs_id')
        local rc_bsample = _rc
        if `rc_bsample' {
            local n_fail = `n_fail' + 1
            if "`nolog'" == "" {
                di as text "  Warning: iteration `b' failed in bsample (rc=`rc_bsample')"
            }
            capture drop `_pte_treat_strata_b'
            capture drop `_pte_bs_id'
            continue
        }

        // 5d: Set panel structure with new firm ID
        capture quietly xtset `_pte_bs_id' `timevar'
        local rc_xtset = _rc
        if `rc_xtset' {
            local n_fail = `n_fail' + 1
            if "`nolog'" == "" {
                di as text "  Warning: iteration `b' failed in xtset (rc=`rc_xtset')"
            }
            capture drop `_pte_treat_strata_b'
            capture drop `_pte_bs_id'
            continue
        }

        // 5e: Regenerate transition period indicator (mid)
        capture drop mid
        capture drop G
        capture drop mid_lag
        capture quietly _pte_transition, treatment(`treatment') id(`_pte_bs_id') time(`timevar') ///
            replace noreport
        local rc_transition = _rc
        if `rc_transition' {
            local n_fail = `n_fail' + 1
            if "`nolog'" == "" {
                di as text "  Warning: iteration `b' failed in _pte_transition (rc=`rc_transition')"
            }
            capture drop `_pte_treat_strata_b'
            capture drop `_pte_bs_id'
            continue
        }

        // 5f: Re-estimate Translog production function
        capture {
            if "`pooled'" != "" {
                qui _pte_tl_estimate, depvar(`depvar') free(`free') ///
                    state(`state') proxy(`proxy') treatment(`treatment') ///
                    `_ctrl_opt' omegapoly(`omegapoly') pooled nolog
            }
            else {
                qui _pte_tl_estimate, depvar(`depvar') free(`free') ///
                    state(`state') proxy(`proxy') treatment(`treatment') ///
                    `_ctrl_opt' omegapoly(`omegapoly') nolog
            }
        }

        // 5g: Collect beta if estimation succeeded
        if _rc == 0 & !missing(e(beta_l)) {
            local n_success = `n_success' + 1
            local bs_beta_l = e(beta_l)
            local bs_beta_k = e(beta_k)
            local bs_beta_ll = e(beta_ll)
            local bs_beta_kk = e(beta_kk)
            local bs_beta_lk = e(beta_lk)
            local bs_beta_t = e(beta_t)
            mata: _pte_beta_boot[`b', 1] = `bs_beta_l'
            mata: _pte_beta_boot[`b', 2] = `bs_beta_k'
            mata: _pte_beta_boot[`b', 3] = `bs_beta_ll'
            mata: _pte_beta_boot[`b', 4] = `bs_beta_kk'
            mata: _pte_beta_boot[`b', 5] = `bs_beta_lk'
            matrix `bs_betas'[`b', 1] = `bs_beta_l'
            matrix `bs_betas'[`b', 2] = `bs_beta_k'
            matrix `bs_betas'[`b', 3] = `bs_beta_ll'
            matrix `bs_betas'[`b', 4] = `bs_beta_kk'
            matrix `bs_betas'[`b', 5] = `bs_beta_lk'
            matrix `bs_betas'[`b', 6] = `bs_beta_t'
        }
        else {
            local n_fail = `n_fail' + 1
            if "`nolog'" == "" {
                di as text "  Warning: iteration `b' failed (rc=`=_rc')"
            }
        }

        // Clean up temporary variables
        capture drop `_pte_treat_strata_b'
        capture drop `_pte_bs_id'
    }

    // ================================================================
    // Step 6: Restore original data
    // ================================================================
    qui use `orig_data', clear

    // ================================================================
    // Step 7: Compute bootstrap variance-covariance matrix in Mata
    // V = Var(beta_1, ..., beta_B) [5x5]
    // Only use successful iterations (non-missing rows)
    // ================================================================
    if `n_success' < 2 {
        di as error "{bf:_pte_tl_bootstrap}: insufficient successful bootstrap iterations"
        di as error "  Successful: `n_success' out of `reps'"
        di as error "  Need at least 2 successful iterations"
        mata: mata drop _pte_beta_boot
        exit 430
    }

    mata: st_local("n_success_check", strofreal(sum(rowmissing(_pte_beta_boot) :== 0)))

    tempname V_boot b_mean
    mata: _pte_valid = select(_pte_beta_boot, rowmissing(_pte_beta_boot) :== 0)
    mata: _pte_n_valid = rows(_pte_valid)
    mata: _pte_V = variance(_pte_valid)
    mata: _pte_b_mean = mean(_pte_valid)
    mata: st_matrix("`V_boot'", _pte_V)
    mata: st_matrix("`b_mean'", _pte_b_mean)
    mata: mata drop _pte_beta_boot _pte_valid _pte_V _pte_b_mean _pte_n_valid

    // ================================================================
    // Step 8: Label V matrix rows/columns
    // ================================================================
    matrix colnames `V_boot' = `free' `state' `free'_sq `state'_sq `free'_`state'
    matrix rownames `V_boot' = `free' `state' `free'_sq `state'_sq `free'_`state'
    matrix colnames `b_mean' = `free' `state' `free'_sq `state'_sq `free'_`state'

    // ================================================================
    // Step 9: Re-run point estimation on original data to get e(b)
    // Then overwrite e(V) with bootstrap V
    // ================================================================

    // Regenerate mid on original data if needed
    capture confirm variable mid
    if _rc {
        qui _pte_transition, treatment(`treatment') id(`panelvar') ///
            time(`timevar') replace noreport
    }

    // Re-estimate on original data for point estimates
    if "`pooled'" != "" {
        qui _pte_tl_estimate, depvar(`depvar') free(`free') ///
            state(`state') proxy(`proxy') treatment(`treatment') ///
            `_ctrl_opt' omegapoly(`omegapoly') pooled nolog
    }
    else {
        qui _pte_tl_estimate, depvar(`depvar') free(`free') ///
            state(`state') proxy(`proxy') treatment(`treatment') ///
            `_ctrl_opt' omegapoly(`omegapoly') nolog
    }
    local pt_beta_t = e(beta_t)

    tempname b_post beta_gmm_post
    tempvar _pte_tl_bs_esample
    matrix `b_post' = e(b)
    local b_colnames : colnames `b_post'
    matrix `beta_gmm_post' = e(beta_gmm)
    qui gen byte `_pte_tl_bs_esample' = e(sample)
    local N_est = e(N)
    local converged_est = e(converged)
    local fval_est = e(fval)
    local criterion_est = e(criterion)
    local iterations_est = e(iterations)
    local r2_stage1_est = e(r2_stage1)
    local n_stage1_est = e(n_stage1)
    local rts_est = e(rts)
    local beta_l_est = e(beta_l)
    local beta_k_est = e(beta_k)
    local beta_ll_est = e(beta_ll)
    local beta_kk_est = e(beta_kk)
    local beta_lk_est = e(beta_lk)
    local beta_t_est = e(beta_t)
    local omegapoly_est = e(omegapoly)
    local cols_X_est = e(cols_X)
    local cols_Z_est = e(cols_Z)
    local cols_OLP_est = e(cols_OLP)
    local cond_ZZ_est = e(cond_ZZ)
    local cmd_est "`e(cmd)'"
    local subcmd_est "`e(subcmd)'"
    local pfunc_est "`e(pfunc)'"
    local depvar_est "`e(depvar)'"
    local free_est "`e(free)'"
    local state_est "`e(state)'"
    local proxy_est "`e(proxy)'"
    local treatment_est "`e(treatment)'"
    local panelvar_est "`e(panelvar)'"
    local timevar_est "`e(timevar)'"
    local mode_est "`e(mode)'"
    local byvar_est "`e(byvar)'"
    matrix colnames `V_boot' = `b_colnames'
    matrix rownames `V_boot' = `b_colnames'
    matrix colnames `b_mean' = `b_colnames'

    // ================================================================
    // Step 10: Overwrite e(V) with bootstrap variance-covariance
    // ================================================================
    ereturn clear
    ereturn post `b_post' `V_boot', esample(`_pte_tl_bs_esample') obs(`N_est')
    ereturn scalar N = `N_est'
    ereturn scalar converged = `converged_est'
    ereturn scalar fval = `fval_est'
    ereturn scalar criterion = `criterion_est'
    ereturn scalar iterations = `iterations_est'
    ereturn scalar r2_stage1 = `r2_stage1_est'
    ereturn scalar n_stage1 = `n_stage1_est'
    ereturn scalar rts = `rts_est'
    ereturn scalar beta_l = `beta_l_est'
    ereturn scalar beta_k = `beta_k_est'
    ereturn scalar beta_ll = `beta_ll_est'
    ereturn scalar beta_kk = `beta_kk_est'
    ereturn scalar beta_lk = `beta_lk_est'
    ereturn scalar beta_t = `beta_t_est'
    ereturn scalar omegapoly = `omegapoly_est'
    ereturn scalar cols_X = `cols_X_est'
    ereturn scalar cols_Z = `cols_Z_est'
    ereturn scalar cols_OLP = `cols_OLP_est'
    ereturn scalar cond_ZZ = `cond_ZZ_est'
    ereturn local cmd "`cmd_est'"
    ereturn local subcmd "`subcmd_est'"
    ereturn local pfunc "`pfunc_est'"
    ereturn local depvar "`depvar_est'"
    ereturn local free "`free_est'"
    ereturn local state "`state_est'"
    ereturn local proxy "`proxy_est'"
    ereturn local treatment "`treatment_est'"
    ereturn local panelvar "`panelvar_est'"
    ereturn local timevar "`timevar_est'"
    ereturn local mode "`mode_est'"
    if "`byvar_est'" != "" {
        ereturn local byvar "`byvar_est'"
    }
    ereturn matrix beta_gmm = `beta_gmm_post'

    // Store bootstrap-specific results
    ereturn scalar bootstrap_reps = `reps'
    ereturn scalar bootstrap_success = `n_success'
    ereturn scalar bootstrap_fail = `n_fail'
    ereturn scalar pt_beta_t = `pt_beta_t'
    ereturn local vce "bootstrap"
    ereturn local vcetype "Bootstrap"
    ereturn matrix bs_betas = `bs_betas'

    // ================================================================
    // Step 11: Results display
    // ================================================================
    if "`nolog'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "Bootstrap Variance Estimation Results"
        di as text "{hline 60}"
        di as text _col(3) "Replications:" _col(40) as result `reps'
        di as text _col(3) "Successful:" _col(40) as result `n_success'
        di as text _col(3) "Failed:" _col(40) as result `n_fail'
        di as text ""
        di as text _col(3) "Bootstrap Standard Errors:"
        tempname V_disp
        matrix `V_disp' = e(V)
        di as text _col(5) "SE(beta_l):  " as result %10.6f sqrt(`V_disp'[1,1])
        di as text _col(5) "SE(beta_k):  " as result %10.6f sqrt(`V_disp'[2,2])
        di as text _col(5) "SE(beta_ll): " as result %10.6f sqrt(`V_disp'[3,3])
        di as text _col(5) "SE(beta_kk): " as result %10.6f sqrt(`V_disp'[4,4])
        di as text _col(5) "SE(beta_lk): " as result %10.6f sqrt(`V_disp'[5,5])
        if !missing(`pt_beta_t') {
            di as text _col(5) "Point beta_t: " as result %10.6f `pt_beta_t'
        }
        di as text ""
        di as text "{hline 60}"
    }

end
