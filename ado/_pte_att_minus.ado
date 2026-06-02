*! _pte_att_minus.ado
*! ATT- Estimation Module (Non-absorbing Treatment Exit)
*!
*! Implements Proposition C.3/C.4: ATT- for treatment exit episodes.
*! Counterfactual uses ONLY h_bar_1 (treated evolution).
*! Symmetric with _pte_att_plus but for exit (D=1 -> D=0).
*!
*! TT- = omega_1_sim - omega = omega^1 - omega^0
*!   omega_1_sim: counterfactual (what if stayed treated)
*!   omega: observed (actually untreated after exit)

version 14.0
capture program drop _pte_att_minus
program define _pte_att_minus, eclass
    version 14.0
    
    // ================================================================
    // Syntax parsing
    // ================================================================
    syntax, OMEGApoly(integer) ///
        ATTperiods(integer) ///
        NSIM(integer) ///
        [SEED(integer 123456) ///
         VERBOSE ///
         DEBUG]
    
    local is_verbose = ("`verbose'" != "")
    local is_debug   = ("`debug'" != "")

    tempname _pte_attm_rho0_in _pte_attm_rho1_in
    local _pte_attm_has_rho0 = 0
    local _pte_attm_has_rho1 = 0
    local _pte_attm_has_sigma0 = 0
    local _pte_attm_has_sigma0_trim = 0
    local _pte_attm_has_sigma0_raw = 0
    local _pte_attm_has_sigma1 = 0
    local _pte_attm_has_sigma1_trim = 0
    local _pte_attm_has_sigma1_raw = 0
    
    // ================================================================
    // Validate prerequisites (input validation)
    // ================================================================
    
    // Check att_minus_sample variable
    capture confirm variable att_minus_sample, exact
    if _rc {
        di as error "[pte] Error: att_minus_sample not found"
        di as error "[pte] Please run _pte_nonabs_sample first"
        exit 111
    }
    
    // Check nt_minus variable
    capture confirm variable nt_minus, exact
    if _rc {
        di as error "[pte] Error: nt_minus not found"
        di as error "[pte] Please run _pte_nonabs_sample first"
        exit 111
    }
    
    // Check omega variable
    capture confirm variable omega, exact
    if _rc {
        di as error "[pte] Error: omega not found"
        di as error "[pte] Please run _pte_omega first"
        exit 111
    }
    
    // Check e(rho_1) matrix (h_bar_1 from separate evolution)
    capture confirm matrix e(rho_1)
    if _rc {
        di as error "[pte] Error: e(rho_1) not found"
        di as error "[pte] Please run _pte_evolution_separate first"
        exit 111
    }
    matrix `_pte_attm_rho1_in' = e(rho_1)
    local _pte_attm_has_rho1 = 1

    capture confirm matrix e(rho_0)
    if !_rc {
        matrix `_pte_attm_rho0_in' = e(rho_0)
        local _pte_attm_has_rho0 = 1
    }
    
    // Check ATT- innovation bridge.
    local sigma_source "sigma_eps1"
    capture scalar _pte_check_sigma1 = e(sigma_eps1)
    if _rc | missing(_pte_check_sigma1) {
        capture scalar _pte_check_sigma1 = e(sigma_eps1_trim)
        if !_rc & !missing(_pte_check_sigma1) {
            local sigma_source "sigma_eps1_trim"
        }
        else {
            capture scalar _pte_check_sigma1 = e(sigma_eps1_raw)
            if !_rc & !missing(_pte_check_sigma1) {
                local sigma_source "sigma_eps1_raw"
            }
        }
    }
    if _rc | missing(_pte_check_sigma1) {
        di as error "[pte] Error: ATT- shock sigma not found in e()"
        di as error "[pte] Please run _pte_eps_bidirectional or _pte_bs_nonabs_prep first"
        exit 111
    }
    scalar drop _pte_check_sigma1

    capture scalar _pte_check_sigma1 = e(sigma_eps1)
    if !_rc & !missing(_pte_check_sigma1) {
        local _pte_attm_sigma1 = _pte_check_sigma1
        local _pte_attm_has_sigma1 = 1
    }
    capture scalar _pte_check_sigma1 = e(sigma_eps1_trim)
    if !_rc & !missing(_pte_check_sigma1) {
        local _pte_attm_sigma1_trim = _pte_check_sigma1
        local _pte_attm_has_sigma1_trim = 1
    }
    capture scalar _pte_check_sigma1 = e(sigma_eps1_raw)
    if !_rc & !missing(_pte_check_sigma1) {
        local _pte_attm_sigma1_raw = _pte_check_sigma1
        local _pte_attm_has_sigma1_raw = 1
    }
    capture scalar _pte_check_sigma1 = e(sigma_eps0)
    if !_rc & !missing(_pte_check_sigma1) {
        local _pte_attm_sigma0 = _pte_check_sigma1
        local _pte_attm_has_sigma0 = 1
    }
    capture scalar _pte_check_sigma1 = e(sigma_eps0_trim)
    if !_rc & !missing(_pte_check_sigma1) {
        local _pte_attm_sigma0_trim = _pte_check_sigma1
        local _pte_attm_has_sigma0_trim = 1
    }
    capture scalar _pte_check_sigma1 = e(sigma_eps0_raw)
    if !_rc & !missing(_pte_check_sigma1) {
        local _pte_attm_sigma0_raw = _pte_check_sigma1
        local _pte_attm_has_sigma0_raw = 1
    }
    capture scalar drop _pte_check_sigma1
    
    // Check for exit events (G == -1)
    capture confirm variable G, exact
    if !_rc {
        quietly count if G == -1
        if r(N) == 0 {
            di as error "[pte] Error: No exit events found (G=-1)"
            di as error "  Treatment appears to be absorbing"
            di as error "  Use standard pte without nonabsorbing option"
            exit 3001
        }
    }
    
    // ================================================================
    // Extract rho coefficients from e(rho_1) [h_bar_1]
    // ================================================================
    tempname Rho_1
    matrix `Rho_1' = e(rho_1)
    
    // Validate dimension
    local ncols_rho = colsof(`Rho_1')
    if `ncols_rho' != `omegapoly' + 1 {
        di as error "[pte] Error: rho_1 has `ncols_rho' cols, expected " (`omegapoly' + 1)
        exit 198
    }
    
    // Extract coefficients to locals
    forvalues j = 0/`omegapoly' {
        local rho1_`j' = `Rho_1'[1, `j' + 1]
    }
    
    if `is_verbose' {
        di as text ""
        di as text "[pte] ATT- rho coefficients (h_bar_1):"
        forvalues j = 0/`omegapoly' {
            di as text "  rho1_`j' = " %9.6f `rho1_`j''
        }
    }
    
    // ================================================================
    // Validate runtime parameters
    // ================================================================
    if `attperiods' < 0 {
        di as error "[pte] Error: attperiods must be >= 0"
        exit 198
    }
    if `nsim' < 1 {
        di as error "[pte] Error: nsim must be >= 1"
        exit 198
    }
    if `nsim' > 1000 {
        di as error "[pte] Error: nsim must be <= 1000"
        exit 198
    }
    
    // ================================================================
    // Extract sigma_eps1
    // ================================================================
    scalar _pte_sigma_eps1 = e(`sigma_source')
    local _pte_attm_drop_sigma "capture scalar drop _pte_sigma_eps1"
    local _pte_attm_restore_rng ""
    // A singleton or perfectly concentrated shock pool implies a valid
    // degenerate innovation law with sigma = 0; only negative scales are invalid.
    if _pte_sigma_eps1 < 0 {
        di as error "[pte] Error: sigma_eps1 must be >= 0, got " _pte_sigma_eps1
        `_pte_attm_drop_sigma'
        exit 198
    }
    
    if `is_verbose' {
        di as text "[pte] sigma_eps1 = " %9.6f _pte_sigma_eps1
    }
    
    // Numerical stability checks
    if abs(`rho1_1') > 1 {
        di as text "[pte] Warning: |rho1_1| = " %6.3f abs(`rho1_1') " > 1"
        di as text "  Counterfactual path may diverge"
    }
    if _pte_sigma_eps1 > 1 {
        di as text "[pte] Warning: sigma_eps1 = " %6.3f _pte_sigma_eps1 " > 1"
    }
    
    // ================================================================
    // Sample filtering (exit sample)
    // ================================================================
    preserve
    
    quietly keep if att_minus_sample == 1
    quietly keep if nt_minus >= -1 & nt_minus <= `attperiods'
    
    quietly count
    local n_sample = r(N)
    
    if `n_sample' == 0 {
        di as error "[pte] Error: no observations in ATT- sample"
        restore
        `_pte_attm_drop_sigma'
        exit 2000
    }
    
    if `is_verbose' {
        di as text "[pte] ATT- sample: n = " %6.0f `n_sample'
    }
    
    // ================================================================
    // Boundary check - nt_minus=-1 existence
    // ================================================================
    quietly count if nt_minus == -1
    if r(N) == 0 {
        di as error "[pte] Error: No nt_minus=-1 observations"
        di as error "  L.omega unavailable for ATT- simulation"
        di as error "  Cannot start counterfactual path"
        restore
        `_pte_attm_drop_sigma'
        exit 498
    }
    
    if `is_verbose' {
        di as text "[pte] nt=-1 observations: " %4.0f r(N)
    }
    
    // ================================================================
    // Boundary check - L.omega availability (need tsset first)
    // ================================================================
    
    // Get panel variables
    capture _xt, trequired
    if _rc {
        di as error "[pte] Error: panel not set"
        restore
        `_pte_attm_drop_sigma'
        exit 459
    }
    local panelvar = r(ivar)
    local timevar = r(tvar)
    
    // Multi-exit firms can contribute more than one exit episode.
    // Build an episode-level panel key so nt_minus resets are legal.
    tempvar _pte_exit_episode _pte_exit_panel
    quietly sort `panelvar' `timevar'
    quietly by `panelvar' (`timevar'): gen long `_pte_exit_episode' = sum(G == -1)
    quietly replace `_pte_exit_episode' = `_pte_exit_episode' + 1 if nt_minus == -1
    quietly egen long `_pte_exit_panel' = group(`panelvar' `_pte_exit_episode')
    
    // Temporarily tsset with nt_minus for L. operator
    quietly tsset `_pte_exit_panel' nt_minus
    
    quietly count if nt_minus == 0 & missing(L.omega)
    if r(N) > 0 {
        di as error "[pte] Error: L.omega missing at nt_minus=0"
        di as error "  `r(N)' observations cannot start simulation"
        restore
        `_pte_attm_drop_sigma'
        exit 498
    }
    
    if `is_verbose' {
        di as text "[pte] L.omega check passed"
    }
    
    // ================================================================
    // Path expansion
    // ================================================================
    if `nsim' > 1 {
        quietly expand `nsim'
        quietly bysort `_pte_exit_panel' nt_minus: gen int sim_id = _n
        quietly egen long firm_sim = group(`_pte_exit_panel' sim_id)
        quietly tsset firm_sim nt_minus
        
        // Verify expansion
        quietly count
        local n_expanded = r(N)
        local expected = `n_sample' * `nsim'
        if `n_expanded' != `expected' {
            di as error "[pte] Error: expansion failed"
            di as error "  Expected `expected', got `n_expanded'"
            restore
            `_pte_attm_drop_sigma'
            exit 498
        }
        
        if `is_verbose' {
            di as text "[pte] Expanded: " %8.0f `n_expanded' " obs (nsim=`nsim')"
        }
    }
    else {
        // nsim=1: no expansion needed
        quietly tsset `_pte_exit_panel' nt_minus
        local n_expanded = `n_sample'
        
        if `is_verbose' {
            di as text "[pte] No expansion (nsim=1)"
        }
    }
    
    // ================================================================
    // Set inner seed
    // ================================================================
    local _pte_attm_orig_rngstate = c(rngstate)
    local _pte_attm_restore_rng "capture set rngstate `_pte_attm_orig_rngstate'"
    set seed `seed'
    
    if `is_verbose' {
        di as text "[pte] Inner seed: `seed'"
    }
    
    // ================================================================
    // Draw eps1 shock sequence
    // ================================================================
    quietly gen double eps1_sim = rnormal(0, scalar(_pte_sigma_eps1))
    
    // Verify
    quietly count if missing(eps1_sim)
    if r(N) > 0 {
        di as error "[pte] Error: eps1_sim has missing values"
        restore
        `_pte_attm_restore_rng'
        `_pte_attm_drop_sigma'
        exit 498
    }
    
    if `is_verbose' {
        quietly summarize eps1_sim
        di as text "[pte] eps1_sim: mean=" %9.6f r(mean) " sd=" %9.6f r(sd)
    }
    
    // ================================================================
    // Initialize counterfactual variable and high-order containers
    // ================================================================
    quietly gen double omega_1_sim = .
    
    // High-order containers
    if `omegapoly' >= 2 {
        quietly gen double omega_1_sim2 = .
    }
    if `omegapoly' >= 3 {
        quietly gen double omega_1_sim3 = .
    }
    if `omegapoly' >= 4 {
        quietly gen double omega_1_sim4 = .
    }
    
    // ================================================================
    // nt=0 counterfactual calculation (using observed L.omega)
    // omega_1_sim = rho1_0 + rho1_1*L.omega + rho1_2*(L.omega)^2 + ... + L.eps1_sim
    // At nt_minus=0, L.omega = omega at nt_minus=-1 (observed, treated state D=1)
    // ================================================================
    
    // Build h_bar_1 formula for nt=0 (using observed values)
    local h1_obs "`rho1_0'"
    
    forvalues j = 1/`omegapoly' {
        if `j' == 1 {
            local h1_obs "`h1_obs' + `rho1_1' * L.omega"
        }
        else {
            local h1_obs "`h1_obs' + `rho1_`j'' * (L.omega)^`j'"
        }
    }
    
    // Execute nt=0 calculation using the lagged innovation row, matching
    // the main ATT recursion contract with the retained nt=-1 anchor row.
    quietly replace omega_1_sim = `h1_obs' + L.eps1_sim if nt_minus == 0
    
    // Verify
    quietly count if nt_minus == 0 & missing(omega_1_sim)
    if r(N) > 0 {
        di as error "[pte] Warning: " r(N) " missing omega_1_sim at nt=0"
    }
    
    if `is_debug' {
        quietly summarize omega_1_sim if nt_minus == 0
        di as text "[pte] omega_1_sim at nt=0: mean=" %9.4f r(mean) " sd=" %9.4f r(sd)
    }
    
    // ================================================================
    // Recursive loop for nt=1..attperiods
    // Step A: Update high-order terms at nt=s-1
    // Step B: Build h_bar_1 formula using simulated values
    // Step C: Calculate omega_1_sim at nt=s
    // ================================================================
    
    forvalues s = 1/`attperiods' {
        
        // Step A: Update high-order terms at nt=s-1
        if `omegapoly' >= 2 {
            quietly replace omega_1_sim2 = omega_1_sim^2 if nt_minus == `s' - 1
        }
        if `omegapoly' >= 3 {
            quietly replace omega_1_sim3 = omega_1_sim^3 if nt_minus == `s' - 1
        }
        if `omegapoly' >= 4 {
            quietly replace omega_1_sim4 = omega_1_sim^4 if nt_minus == `s' - 1
        }
        
        // Step B: Build h_bar_1 formula (using simulated values)
        local h1_sim "`rho1_0' + `rho1_1' * L.omega_1_sim"
        forvalues j = 2/`omegapoly' {
            local h1_sim "`h1_sim' + `rho1_`j'' * L.omega_1_sim`j'"
        }
        
        // Step C: Calculate omega_1_sim at nt=s using the lagged innovation
        // carried on the previous event-time row.
        quietly replace omega_1_sim = `h1_sim' + L.eps1_sim if nt_minus == `s'
        
        if `is_debug' {
            quietly summarize omega_1_sim if nt_minus == `s'
            di as text "[pte] omega_1_sim at nt=`s': mean=" %9.4f r(mean) " sd=" %9.4f r(sd)
        }
    }
    
    // ================================================================
    // TT- calculation
    // TT- = omega_1_sim - omega = omega^1 - omega^0
    //   omega_1_sim: counterfactual (what if stayed treated, h_bar_1)
    //   omega: observed (actually untreated after exit)
    // ================================================================
    quietly gen double TT_minus = omega_1_sim - omega if nt_minus >= 0
    
    if `is_debug' {
        quietly summarize TT_minus if nt_minus == 0
        di as text "[pte] TT- at nt=0: mean=" %9.4f r(mean) " sd=" %9.4f r(sd)
        quietly count if TT_minus > 0 & nt_minus >= 0
        local n_pos = r(N)
        quietly count if !missing(TT_minus) & nt_minus >= 0
        local n_total = r(N)
        di as text "[pte] TT- positive fraction: " %5.1f 100*`n_pos'/`n_total' "%"
    }
    
    // ================================================================
    // Cross-path mean aggregation
    // Average TT- across nsim paths for each (firm, nt_minus)
    // ================================================================
    quietly bysort `_pte_exit_panel' nt_minus: egen double TT_minus_mean = mean(TT_minus)
    
    // Keep only nt >= 0 for aggregation (exclude nt=-1)
    quietly keep if nt_minus >= 0
    
    // Collapse to episode-period level before averaging across exits
    quietly duplicates drop `_pte_exit_panel' nt_minus, force
    
    if `is_verbose' {
        quietly count
        di as text "[pte] Firm-period observations: " %5.0f r(N)
    }
    
    // ================================================================
    // Period-level ATT- aggregation and matrix construction
    // ================================================================
    
    // Save firm-level TT for potential later use
    tempfile firm_tt_minus
    quietly save `firm_tt_minus', replace
    
    // Collapse to period level
    collapse (mean) ATT_minus = TT_minus_mean ///
             (sd) ATT_minus_sd = TT_minus_mean ///
             (count) n_minus = TT_minus_mean, by(nt_minus)
    
    // Sort by nt
    sort nt_minus
    
    // Convert to matrix
    local nrows = _N
    tempname ATT_MINUS_mat
    matrix `ATT_MINUS_mat' = J(`nrows', 4, .)
    
    forvalues i = 1/`nrows' {
        matrix `ATT_MINUS_mat'[`i', 1] = ATT_minus[`i']
        matrix `ATT_MINUS_mat'[`i', 2] = ATT_minus_sd[`i']
        matrix `ATT_MINUS_mat'[`i', 3] = n_minus[`i']
        matrix `ATT_MINUS_mat'[`i', 4] = nt_minus[`i']
    }
    
    matrix colnames `ATT_MINUS_mat' = ATT_minus SD N nt
    
    // Build row names from nt values
    local rnames ""
    forvalues i = 1/`nrows' {
        local nt_val = nt_minus[`i']
        local rnames "`rnames' nt`nt_val'"
    }
    matrix rownames `ATT_MINUS_mat' = `rnames'
    
    // Display results
    if `is_verbose' {
        di as text ""
        di as text "[pte] ATT- Results:"
        di as text _dup(50) "-"
        di as text %6s "nt" %12s "ATT-" %12s "SD" %8s "N"
        di as text _dup(50) "-"
        forvalues i = 1/`nrows' {
            di as text %6.0f `ATT_MINUS_mat'[`i', 4] ///
                       %12.4f `ATT_MINUS_mat'[`i', 1] ///
                       %12.4f `ATT_MINUS_mat'[`i', 2] ///
                       %8.0f `ATT_MINUS_mat'[`i', 3]
        }
        di as text _dup(50) "-"
    }
    
    // Restore original data
    restore
    `_pte_attm_restore_rng'
    
    // ================================================================
    // Store results in e()
    // ================================================================
    ereturn clear
    if `_pte_attm_has_rho0' {
        ereturn matrix rho_0 = `_pte_attm_rho0_in'
    }
    if `_pte_attm_has_rho1' {
        ereturn matrix rho_1 = `_pte_attm_rho1_in'
    }
    if `_pte_attm_has_sigma0' {
        ereturn scalar sigma_eps0 = `_pte_attm_sigma0'
    }
    if `_pte_attm_has_sigma0_trim' {
        ereturn scalar sigma_eps0_trim = `_pte_attm_sigma0_trim'
    }
    if `_pte_attm_has_sigma0_raw' {
        ereturn scalar sigma_eps0_raw = `_pte_attm_sigma0_raw'
    }
    if `_pte_attm_has_sigma1' {
        ereturn scalar sigma_eps1 = `_pte_attm_sigma1'
    }
    if `_pte_attm_has_sigma1_trim' {
        ereturn scalar sigma_eps1_trim = `_pte_attm_sigma1_trim'
    }
    if `_pte_attm_has_sigma1_raw' {
        ereturn scalar sigma_eps1_raw = `_pte_attm_sigma1_raw'
    }
    ereturn matrix att_minus = `ATT_MINUS_mat'
    ereturn scalar n_att_minus_periods = `nrows'
    ereturn scalar attperiods = `attperiods'
    ereturn scalar nsim = `nsim'
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar seed = `seed'
    ereturn local cmd "_pte_att_minus"
    ereturn local title "ATT- Estimation (Treatment Exit)"
    
    // Clean up scalars
    capture scalar drop _pte_sigma_eps1
    
    if `is_verbose' {
        di as text ""
        di as text "[pte] ATT- estimation complete"
    }
    
end
