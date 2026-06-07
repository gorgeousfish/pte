*! _pte_calibrate_beta.ado
*! BETA calibration module for MC DGP parameter estimation
*! Estimates production function coefficients (BETA) from empirical data
*! 1. Generate polynomial variables (l2, k2, l1k1, t1-t6)
*! 2. First-stage OLS → phi (subtract controls)
*! 3. GMM optimization → beta (production function coefficients)
*! 4. Recover omega = phi - X*beta
*! 5. Construct BETA matrix = (bt1..bt6, bl, bk, bll, bkk, blk)

version 14.0
capture program drop _pte_calibrate_beta
program define _pte_calibrate_beta, rclass
    version 14.0
    
    // -----------------------------------------------------------------
    // Syntax parsing (TASK-013.004.2)
    // -----------------------------------------------------------------
    syntax, LNY(varname numeric) FREE(varname numeric) ///
        STATE(varname numeric) PROXY(varname numeric) ///
        TREATment(varname numeric) ID(varname) Time(varname numeric) ///
        [PFunc(string) Order(integer 3) OMEGApoly(integer 3) ///
         INDustry(varname) BYINDustry POLY(integer 3) ///
         MULTISTART noREPORT TOUSE(varname)]
    
    // Default production function type
    if "`pfunc'" == "" {
        local pfunc "translog"
    }
    
    // Validate pfunc (TASK-013.004.3)
    if !inlist("`pfunc'", "translog", "cd") {
        di as error "[_pte_calibrate_beta] pfunc() must be 'translog' or 'cd'"
        exit 198
    }
    
    // Validate required variables exist
    foreach v in `lny' `free' `state' `proxy' `treatment' {
        capture confirm numeric variable `v'
        if _rc {
            di as error "[_pte_calibrate_beta] Variable `v' not found or not numeric"
            exit 111
        }
    }
    
    // -----------------------------------------------------------------
    // Call _pte_prodfunc for CLK estimation (TASK-013.006)
    // -----------------------------------------------------------------
    //   Step 1: reghdfe lny lnl lnk l2 k2 l1k1 t1-t6 → phi
    //   Step 2: CLK Mata GMM → beta
    //   Step 3: omega = phi - X*beta
    //
    // _pte_prodfunc handles all of this internally:
    //   - _pte_transition: identify mid (transition periods)
    //   - _pte_polyvar: generate l2, k2, l1k1, t1-t6
    //   - _pte_stage1: first-stage OLS → phi (subtract controls)
    //   - _pte_gmm_matrices: construct Z, X, X_lag
    //   - _pte_gmm_wrapper: Nelder-Mead GMM → beta
    //   - omega recovery: omega = phi - X*beta
    
    // Build _pte_prodfunc options
    local _pf_opts "treatment(`treatment') id(`id') time(`time')"
    local _pf_opts "`_pf_opts' lny(`lny') free(`free') state(`state') proxy(`proxy')"
    local _pf_opts "`_pf_opts' pfunc(`pfunc') poly(`poly') omegapoly(`omegapoly')"
    
    if "`industry'" != "" {
        local _pf_opts "`_pf_opts' industry(`industry')"
    }
    if "`byindustry'" != "" {
        local _pf_opts "`_pf_opts' byindustry"
    }
    if "`multistart'" != "" {
        local _pf_opts "`_pf_opts' multistart"
    }
    if "`report'" != "" {
        local _pf_opts "`_pf_opts' noreport"
    }
    if "`touse'" != "" {
        local _pf_opts "`_pf_opts' touse(`touse')"
    }
    
    // Execute production function estimation
    // TASK-013.006.3: mid exclusion is handled internally by _pte_prodfunc
    // TASK-013.006.4: GMM estimation via _pte_gmm_wrapper
    _pte_prodfunc, `_pf_opts'
    
    // -----------------------------------------------------------------
    // Extract results (TASK-013.006.5, TASK-013.007)
    // -----------------------------------------------------------------
    
    // Verify estimation succeeded
    if e(converged) != 1 {
        di as text "[_pte_calibrate_beta] Warning: GMM did not converge (fval = " ///
            as result %12.6f e(fval) as text ")"
    }
    
    // Extract production function coefficients from e(b)
    // e(b) structure:
    //   CD:       (bl, bk)           — 2 columns
    //   Translog: (bl, bk, bll, bkk, blk) — 5 columns
    tempname beta_pf
    matrix `beta_pf' = e(b)
    local beta_pf_cols = colsof(`beta_pf')
    
    // Extract control variable coefficients (time trends)
    // e(beta_controls) from _pte_stage1: (bt1, bt2, ..., btN)
    tempname beta_ctrl
    capture matrix `beta_ctrl' = e(beta_controls)
    local has_controls = (_rc == 0)
    
    if `has_controls' {
        local n_controls = colsof(`beta_ctrl')
    }
    else {
        local n_controls = 0
        di as text "[_pte_calibrate_beta] No control variable coefficients found"
    }
    
    // Save other estimation results before constructing BETA
    local _fval      = e(fval)
    local _converged = e(converged)
    local _omegapoly = e(omegapoly)
    local _prodfunc  "`e(prodfunc)'"
    local _N_gmm     = e(N_gmm)
    
    // -----------------------------------------------------------------
    // Construct BETA matrix (TASK-013.007)
    // -----------------------------------------------------------------
    //   matrix BETA = (beta_t1, ..., beta_t6, beta_l, beta_k, beta_ll, beta_kk, beta_lk)
    //
    // Format: (control_coefficients, production_function_coefficients)
    //   Translog: (bt1..btN, bl, bk, bll, bkk, blk) — N+5 columns
    //   CD:       (bt1..btN, bl, bk)                 — N+2 columns
    
    tempname BETA
    local total_cols = `n_controls' + `beta_pf_cols'
    matrix `BETA' = J(1, `total_cols', .)
    
    // Fill control coefficients (bt1, bt2, ..., btN)
    if `has_controls' {
        forvalues j = 1/`n_controls' {
            matrix `BETA'[1, `j'] = `beta_ctrl'[1, `j']
        }
    }
    
    // Fill production function coefficients
    forvalues j = 1/`beta_pf_cols' {
        local col = `n_controls' + `j'
        matrix `BETA'[1, `col'] = `beta_pf'[1, `j']
    }
    
    // Set column names (TASK-013.007.3)
    if "`pfunc'" == "translog" {
        if `n_controls' == 6 {
            // Standard 6-industry time trends
            matrix colnames `BETA' = bt1 bt2 bt3 bt4 bt5 bt6 bl bk bll bkk blk
        }
        else if `n_controls' > 0 {
            // Generic control names + production function params
            local _colnames ""
            forvalues j = 1/`n_controls' {
                local _colnames "`_colnames' bt`j'"
            }
            local _colnames "`_colnames' bl bk bll bkk blk"
            matrix colnames `BETA' = `_colnames'
        }
        else {
            // No controls, only production function params
            matrix colnames `BETA' = bl bk bll bkk blk
        }
    }
    else {
        // CD production function
        if `n_controls' > 0 {
            local _colnames ""
            forvalues j = 1/`n_controls' {
                local _colnames "`_colnames' bt`j'"
            }
            local _colnames "`_colnames' bl bk"
            matrix colnames `BETA' = `_colnames'
        }
        else {
            matrix colnames `BETA' = bl bk
        }
    }
    
    // -----------------------------------------------------------------
    // Validation (TASK-013.007.4)
    // -----------------------------------------------------------------
    
    // Check for missing values in BETA
    local beta_ok = 1
    forvalues j = 1/`total_cols' {
        if missing(`BETA'[1, `j']) {
            local beta_ok = 0
        }
    }
    
    if `beta_ok' == 0 {
        di as error "[_pte_calibrate_beta] BETA contains missing values"
    }
    
    // Validate production function coefficients are in reasonable range
    // bl (labor elasticity) typically in [0.1, 0.9]
    // bk (capital elasticity) typically in [0.05, 0.6]
    local _bl = `BETA'[1, `n_controls' + 1]
    local _bk = `BETA'[1, `n_controls' + 2]
    
    if `_bl' < 0 | `_bl' > 1.5 {
        di as text "[_pte_calibrate_beta] Warning: bl = " %7.4f `_bl' ///
            " outside typical range [0, 1.5]"
    }
    if `_bk' < 0 | `_bk' > 1.0 {
        di as text "[_pte_calibrate_beta] Warning: bk = " %7.4f `_bk' ///
            " outside typical range [0, 1.0]"
    }
    
    // Verify omega variable was generated
    capture confirm variable omega
    if _rc {
        di as error "[_pte_calibrate_beta] omega variable not generated by _pte_prodfunc"
        exit 111
    }
    
    // -----------------------------------------------------------------
    // Display summary
    // -----------------------------------------------------------------
    if "`report'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "BETA Calibration Results"
        di as text "{hline 60}"
        di as text "  Production function: " as result "`pfunc'"
        di as text "  GMM converged:       " as result cond(`_converged'==1, "Yes", "No")
        di as text "  GMM fval:            " as result %12.8f `_fval'
        di as text "  GMM sample size:     " as result `_N_gmm'
        di as text "  BETA dimensions:     " as result "1 x `total_cols'"
        di as text ""
        di as text "  Production function coefficients:"
        di as text "    bl (labor):    " as result %9.6f `_bl'
        di as text "    bk (capital):  " as result %9.6f `_bk'
        if "`pfunc'" == "translog" {
            local _bll = `BETA'[1, `n_controls' + 3]
            local _bkk = `BETA'[1, `n_controls' + 4]
            local _blk = `BETA'[1, `n_controls' + 5]
            di as text "    bll (l^2):     " as result %9.6f `_bll'
            di as text "    bkk (k^2):     " as result %9.6f `_bkk'
            di as text "    blk (l*k):     " as result %9.6f `_blk'
        }
        if `n_controls' > 0 {
            di as text "  Control coefficients: " as result "`n_controls'" as text " time trends"
        }
        di as text "{hline 60}"
    }
    
    // -----------------------------------------------------------------
    // Return values (TASK-013.007.4)
    // -----------------------------------------------------------------
    return matrix BETA = `BETA'
    return scalar n_controls = `n_controls'
    return scalar n_beta_pf  = `beta_pf_cols'
    return scalar fval       = `_fval'
    return scalar converged  = `_converged'
    return scalar omegapoly  = `_omegapoly'
    return scalar N_gmm      = `_N_gmm'
    return local  pfunc       "`pfunc'"
    
end
