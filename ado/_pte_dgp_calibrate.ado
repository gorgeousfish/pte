*! _pte_dgp_calibrate.ado
*! DGP parameter calibration from real data
*! Calibrates BETA, RHO, OMEGA from empirical data for Monte Carlo DGP.

version 14.0
// =========================================================================
// _pte_dgp_calibrate: Calibrate DGP parameters from real data
// =========================================================================
// TASK-001.1: Estimate BETA from production function
// TASK-001.2: Estimate RHO from productivity evolution regression
// TASK-001.3: Estimate OMEGA (mu, sigma) from untreated observations
// TASK-001.4: Parameter validation and boundary checks
// TASK-001.5: Parameter storage and interface (r() returns)
// =========================================================================

program define _pte_dgp_calibrate, rclass
    version 14.0
    
    // -----------------------------------------------------------------
    // Syntax parsing
    // -----------------------------------------------------------------
    syntax using/, [PFunc(string) Order(integer 1)]
    
    // Default production function type
    if "`pfunc'" == "" {
        local pfunc "translog"
    }
    
    // Validate pfunc
    if !inlist("`pfunc'", "translog", "cd") {
        di as error "pfunc() must be 'translog' or 'cd'"
        exit 198
    }
    
    // Validate order
    if !inlist(`order', 1, 2, 3) {
        di as error "order() must be 1, 2, or 3"
        exit 198
    }
    
    // -----------------------------------------------------------------
    // Save e(b) before loading data (use clears e() results)
    // -----------------------------------------------------------------
    tempname _saved_eb
    capture matrix `_saved_eb' = e(b)
    local _has_eb = (_rc == 0)
    
    // -----------------------------------------------------------------
    // Load data
    // -----------------------------------------------------------------
    use `"`using'"', clear
    
    // Verify panel structure
    qui xtset
    local panelvar = r(panelvar)
    local timevar  = r(timevar)
    
    // Verify required variables exist
    foreach v in lny lnl lnm lnk treat_post treat_yr0 {
        capture confirm variable `v'
        if _rc {
            di as error "Variable `v' not found in dataset"
            exit 111
        }
    }
    
    // Store observation count before any filtering
    local n_obs_total = _N
    
    // =================================================================
    // TASK-001.1: Estimate BETA from production function
    // =================================================================
    // Delegates to _pte_calibrate_beta.ado ( TASK-013.004~007)
    // which calls _pte_prodfunc ( CLK estimation framework).
    //
    // -----------------------------------------------------------------
    
    di as text ""
    di as text "{hline 60}"
    di as text "DGP Parameter Calibration"
    di as text "{hline 60}"
    di as text ""
    di as text "Production function: " as result "`pfunc'"
    di as text "Evolution order:     " as result "`order'"
    di as text ""
    
    tempname BETA
    
    // Try calling _pte_calibrate_beta (modular approach)
    // Falls back to extracting from saved e(b) if module unavailable
    capture {
        _pte_calibrate_beta, lny(lny) free(lnl) state(lnk) proxy(lnm) ///
            treatment(treat_post) id(`panelvar') time(`timevar') ///
            pfunc(`pfunc') order(`order') noreport
        matrix `BETA' = r(BETA)
    }
    
    if _rc {
        // Fallback: extract from saved e() results (pre-existing behavior)
        di as text "Note: _pte_calibrate_beta not available, using saved e(b)"
        if `_has_eb' {
            matrix `BETA' = `_saved_eb'
        }
        else {
            capture matrix `BETA' = e(b)
            if _rc {
                di as error "No estimation results found. Run pte command first,"
                di as error "or ensure e(b) contains production function estimates."
                exit 301
            }
        }
        
        // Set column names based on pfunc
        local beta_cols = colsof(`BETA')
        if "`pfunc'" == "translog" & `beta_cols' == 11 {
            matrix colnames `BETA' = bt1 bt2 bt3 bt4 bt5 bt6 bl bk bll bkk blk
        }
        else if "`pfunc'" == "cd" & `beta_cols' == 3 {
            matrix colnames `BETA' = bt bl bk
        }
    }
    
    local beta_cols = colsof(`BETA')
    di as text "BETA estimated: " as result "`beta_cols'" as text " parameters (`pfunc')"
    
    // =================================================================
    // TASK-001.2: Estimate RHO from productivity evolution regression
    // =================================================================
    //   g omega_tp = omega*treat_post
    //   qui reg omega l.omega l.omega_tp l.treat_post if mid!=1
    //   matrix RHO[i,1] = e(b)
    //
    // Key: transition period (mid != 1) must be excluded from regression.
    // mid = 1 when D_t != D_{t-1} (treatment status changed).
    // -----------------------------------------------------------------
    
    // Verify omega variable exists (should be generated by pte estimation)
    capture confirm variable omega
    if _rc {
        di as error "Variable 'omega' not found. It should be generated by pte estimation."
        exit 111
    }
    
    // Verify D variable exists for transition period identification
    // D is the treatment indicator at time t (same as treat_post in most cases)
    // IMPORTANT: must check for numeric D, not string (raw data may have
    // string variable 'D' e.g. Dlstdt abbreviated to D)
    capture confirm numeric variable D
    if _rc {
        // Fall back to treat_post if numeric D not available
        capture confirm numeric variable treat_post
        if _rc {
            di as error "Neither numeric 'D' nor 'treat_post' found for transition period identification"
            exit 111
        }
        local D_var "treat_post"
    }
    else {
        local D_var "D"
    }
    
    // Generate auxiliary variables for evolution regression
    // omega_tp: interaction of omega with treatment status
    capture drop _pte_omega_tp
    qui gen double _pte_omega_tp = omega * treat_post
    
    // mid: transition period indicator (D_t != D_{t-1})
    capture drop _pte_mid
    qui gen byte _pte_mid = (`D_var' != L.`D_var')
    // First period (no lag available) is NOT a transition period
    qui replace _pte_mid = 0 if missing(L.`D_var')
    
    // Count excluded transition observations
    qui count if _pte_mid == 1
    local n_transition = r(N)
    di as text "Transition period observations excluded: " as result "`n_transition'"
    
    tempname RHO
    
    if `order' == 1 {
        // Order 1: linear evolution
        // omega_t = rho0 + rho1 * omega_{t-1} + controls + eps
        qui reg omega l.omega l._pte_omega_tp l.treat_post if _pte_mid != 1
        matrix `RHO' = (_b[_cons], _b[L.omega])
        matrix colnames `RHO' = rho0 rho1
    }
    else if `order' == 2 {
        // Order 2: quadratic evolution
        capture drop _pte_omega2
        qui gen double _pte_omega2 = omega^2
        capture drop _pte_omega2_tp
        qui gen double _pte_omega2_tp = _pte_omega2 * treat_post
        
        qui reg omega l.omega l._pte_omega2 ///
            l._pte_omega_tp l._pte_omega2_tp l.treat_post ///
            if _pte_mid != 1
        matrix `RHO' = (_b[_cons], _b[L.omega], _b[L._pte_omega2])
        matrix colnames `RHO' = rho0 rho1 rho2
    }
    else if `order' == 3 {
        // Order 3: cubic evolution
        capture drop _pte_omega2
        qui gen double _pte_omega2 = omega^2
        capture drop _pte_omega3
        qui gen double _pte_omega3 = omega^3
        capture drop _pte_omega2_tp
        qui gen double _pte_omega2_tp = _pte_omega2 * treat_post
        capture drop _pte_omega3_tp
        qui gen double _pte_omega3_tp = _pte_omega3 * treat_post
        
        qui reg omega l.omega l._pte_omega2 l._pte_omega3 ///
            l._pte_omega_tp l._pte_omega2_tp l._pte_omega3_tp ///
            l.treat_post if _pte_mid != 1
        matrix `RHO' = (_b[_cons], _b[L.omega], _b[L._pte_omega2], _b[L._pte_omega3])
        matrix colnames `RHO' = rho0 rho1 rho2 rho3
    }
    
    local rho_cols = colsof(`RHO')
    di as text "RHO estimated:  " as result "`rho_cols'" as text " parameters (order=`order')"
    
    // =================================================================
    // TASK-001.3: Estimate OMEGA (initial distribution parameters)
    // =================================================================
    //   qui sum omega if year == treat_yr0 - 1
    //   matrix OMG[i, 1] = (r(mean), r(sd))
    //
    // The Monte Carlo DGP consumes OMEGA as the pre-adoption productivity
    // support used to initialize omega1 at e-1 and omega0 at the first
    // sample period. Align calibration with the official DO contract by
    // using the realized productivity observed at year == treat_yr0 - 1.
    // -----------------------------------------------------------------
    
    tempname OMEGA
    
    preserve
    qui keep if !missing(treat_yr0) & year == treat_yr0 - 1
    
    local n_omega = _N
    if `n_omega' == 0 {
        di as error "No observations found on the year == treat_yr0 - 1 support"
        di as error "OMEGA calibration requires pre-adoption productivity for treated firms"
        restore
        exit 2000
    }
    if `n_omega' < 100 {
        di as text "Warning: only `n_omega' observations with year == treat_yr0 - 1"
    }
    
    qui sum omega
    local mu_omega  = r(mean)
    local sd_omega  = r(sd)
    local n_omega_obs = r(N)
    
    matrix `OMEGA' = (`mu_omega', `sd_omega')
    matrix colnames `OMEGA' = mu_omega sigma_omega
    
    restore
    
    di as text "OMEGA estimated: mu=" as result %9.4f `mu_omega' ///
        as text ", sigma=" as result %9.4f `sd_omega' ///
        as text " (N=" as result "`n_omega_obs'" as text ")"
    
    // =================================================================
    // TASK-001.4: Parameter validation and boundary checks
    // =================================================================
    // Validate BETA: no missing values
    // Validate RHO: rho1 in (0, 1) for stationarity
    // Validate OMEGA: sigma > 0
    // -----------------------------------------------------------------
    
    local validation_ok = 1
    
    // --- BETA validation: check for missing values ---
    local beta_ncols = colsof(`BETA')
    forvalues j = 1/`beta_ncols' {
        if missing(`BETA'[1, `j']) {
            di as error "Validation FAILED: BETA[1,`j'] is missing"
            local validation_ok = 0
        }
    }
    if `validation_ok' == 1 {
        di as text "  BETA validation: " as result "PASSED" as text " (no missing values)"
    }
    
    // --- RHO validation: rho1 stationarity check ---
    local rho1_val = `RHO'[1, 2]
    if `rho1_val' <= 0 | `rho1_val' >= 1 {
        di as error "Validation FAILED: rho1 = `rho1_val' not in (0, 1)"
        di as error "  Productivity evolution may be non-stationary"
        local validation_ok = 0
    }
    else {
        di as text "  RHO validation:  " as result "PASSED" ///
            as text " (rho1=" as result %7.4f `rho1_val' as text ")"
    }
    
    // --- RHO boundary warning ---
    if `rho1_val' > 0.95 & `rho1_val' < 1 {
        di as text "  {it:Warning: rho1 > 0.95, evolution is highly persistent}"
    }
    
    // --- OMEGA validation: sigma > 0 ---
    if `sd_omega' <= 0 {
        di as error "Validation FAILED: sigma_omega = `sd_omega' <= 0"
        local validation_ok = 0
    }
    else {
        di as text "  OMEGA validation: " as result "PASSED" ///
            as text " (sigma=" as result %7.4f `sd_omega' as text ")"
    }
    
    if `validation_ok' == 0 {
        di as error ""
        di as error "Parameter validation failed. Results may be unreliable."
    }
    
    // =================================================================
    // TASK-001.5: Parameter storage and interface (r() returns)
    // =================================================================
    // Return matrices: BETA, RHO, OMEGA
    // Return scalars: order, n_obs
    // Display calibration summary
    // -----------------------------------------------------------------
    
    // --- Clean up temporary variables ---
    capture drop _pte_omega_tp
    capture drop _pte_mid
    capture drop _pte_omega2
    capture drop _pte_omega3
    capture drop _pte_omega2_tp
    capture drop _pte_omega3_tp
    
    // --- Return matrices ---
    return matrix BETA = `BETA'
    return matrix RHO  = `RHO'
    return matrix OMEGA = `OMEGA'
    
    // --- Return scalars ---
    return scalar order = `order'
    return scalar n_obs = `n_obs_total'
    
    // --- Display calibration summary ---
    di as text ""
    di as text "{hline 60}"
    di as text "Calibration Summary"
    di as text "{hline 60}"
    di as text "  Production function: " as result "`pfunc'"
    di as text "  Evolution order:     " as result "`order'"
    di as text "  Total observations:  " as result "`n_obs_total'"
    di as text "  BETA parameters:     " as result "`beta_cols'"
    di as text "  RHO parameters:      " as result "`rho_cols'"
    di as text "  mu(omega):           " as result %9.6f `mu_omega'
    di as text "  sigma(omega):        " as result %9.6f `sd_omega'
    di as text "{hline 60}"
    
end
