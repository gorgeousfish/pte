*! _pte_att_plus.ado
*! ATT+ Estimation Module (Non-absorbing Treatment Entry)
*!
*! Implements Proposition C.3/C.4: ATT+ for treatment entry episodes.
*! Counterfactual uses ONLY h_bar_0 (untreated evolution).
*! Symmetric with _pte_att but uses att_plus_sample/nt_plus.

version 14.0
capture program drop _pte_att_plus
program define _pte_att_plus, eclass
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

    tempname _pte_attp_rho0_in _pte_attp_rho1_in
    local _pte_attp_has_rho0 = 0
    local _pte_attp_has_rho1 = 0
    local _pte_attp_has_sigma0 = 0
    local _pte_attp_has_sigma0_trim = 0
    local _pte_attp_has_sigma0_raw = 0
    local _pte_attp_has_sigma1 = 0
    local _pte_attp_has_sigma1_trim = 0
    local _pte_attp_has_sigma1_raw = 0
    
    // ================================================================
    // Task 1: Validate prerequisites
    // ================================================================
    
    // Check att_plus_sample variable
    capture confirm variable att_plus_sample, exact
    if _rc {
        di as error "[pte] Error: att_plus_sample not found"
        di as error "[pte] Please run _pte_nonabs_sample first"
        exit 111
    }
    
    // Check nt_plus variable
    capture confirm variable nt_plus, exact
    if _rc {
        di as error "[pte] Error: nt_plus not found"
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
    
    // Check e(rho_0) matrix
    capture confirm matrix e(rho_0)
    if _rc {
        di as error "[pte] Error: e(rho_0) not found"
        di as error "[pte] Please run _pte_evolution_separate first"
        exit 111
    }
    matrix `_pte_attp_rho0_in' = e(rho_0)
    local _pte_attp_has_rho0 = 1

    capture confirm matrix e(rho_1)
    if !_rc {
        matrix `_pte_attp_rho1_in' = e(rho_1)
        local _pte_attp_has_rho1 = 1
    }
    
    // Check ATT+ innovation bridge.
    local sigma_source "sigma_eps0"
    capture scalar _pte_check_sigma = e(sigma_eps0)
    if _rc | missing(_pte_check_sigma) {
        capture scalar _pte_check_sigma = e(sigma_eps0_trim)
        if !_rc & !missing(_pte_check_sigma) {
            local sigma_source "sigma_eps0_trim"
        }
        else {
            capture scalar _pte_check_sigma = e(sigma_eps0_raw)
            if !_rc & !missing(_pte_check_sigma) {
                local sigma_source "sigma_eps0_raw"
            }
        }
    }
    if _rc | missing(_pte_check_sigma) {
        di as error "[pte] Error: ATT+ shock sigma not found in e()"
        di as error "[pte] Please run _pte_eps_bidirectional or _pte_bs_nonabs_prep first"
        exit 111
    }
    scalar drop _pte_check_sigma

    capture scalar _pte_check_sigma = e(sigma_eps0)
    if !_rc & !missing(_pte_check_sigma) {
        local _pte_attp_sigma0 = _pte_check_sigma
        local _pte_attp_has_sigma0 = 1
    }
    capture scalar _pte_check_sigma = e(sigma_eps0_trim)
    if !_rc & !missing(_pte_check_sigma) {
        local _pte_attp_sigma0_trim = _pte_check_sigma
        local _pte_attp_has_sigma0_trim = 1
    }
    capture scalar _pte_check_sigma = e(sigma_eps0_raw)
    if !_rc & !missing(_pte_check_sigma) {
        local _pte_attp_sigma0_raw = _pte_check_sigma
        local _pte_attp_has_sigma0_raw = 1
    }
    capture scalar _pte_check_sigma = e(sigma_eps1)
    if !_rc & !missing(_pte_check_sigma) {
        local _pte_attp_sigma1 = _pte_check_sigma
        local _pte_attp_has_sigma1 = 1
    }
    capture scalar _pte_check_sigma = e(sigma_eps1_trim)
    if !_rc & !missing(_pte_check_sigma) {
        local _pte_attp_sigma1_trim = _pte_check_sigma
        local _pte_attp_has_sigma1_trim = 1
    }
    capture scalar _pte_check_sigma = e(sigma_eps1_raw)
    if !_rc & !missing(_pte_check_sigma) {
        local _pte_attp_sigma1_raw = _pte_check_sigma
        local _pte_attp_has_sigma1_raw = 1
    }
    capture scalar drop _pte_check_sigma
    
    // ================================================================
    // Task 2: Extract rho coefficients from e(rho_0)
    // ================================================================
    tempname Rho_0
    matrix `Rho_0' = e(rho_0)
    
    // Validate dimension
    local ncols_rho = colsof(`Rho_0')
    if `ncols_rho' != `omegapoly' + 1 {
        di as error "[pte] Error: rho_0 has `ncols_rho' cols, expected " (`omegapoly' + 1)
        exit 198
    }
    
    // Extract coefficients to locals
    forvalues j = 0/`omegapoly' {
        local rho0_`j' = `Rho_0'[1, `j' + 1]
    }
    
    if `is_verbose' {
        di as text ""
        di as text "[pte] ATT+ rho coefficients (h_bar_0):"
        forvalues j = 0/`omegapoly' {
            di as text "  rho0_`j' = " %9.6f `rho0_`j''
        }
    }
    
    // ================================================================
    // Task 3: Validate runtime parameters
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
    // Task 4: Extract sigma_eps0
    // ================================================================
    scalar _pte_sigma_eps0 = e(`sigma_source')
    local _pte_attp_drop_sigma "capture scalar drop _pte_sigma_eps0"
    local _pte_attp_restore_rng ""
    // A singleton or perfectly concentrated shock pool implies a valid
    // degenerate innovation law with sigma = 0; only negative scales are invalid.
    if _pte_sigma_eps0 < 0 {
        di as error "[pte] Error: sigma_eps0 must be >= 0, got " _pte_sigma_eps0
        `_pte_attp_drop_sigma'
        exit 198
    }
    
    if `is_verbose' {
        di as text "[pte] sigma_eps0 = " %9.6f _pte_sigma_eps0
    }
    
    // ================================================================
    // Task 5: Numerical stability checks
    // ================================================================
    if abs(`rho0_1') > 1 {
        di as text "[pte] Warning: |rho1| = " %6.3f abs(`rho0_1') " > 1"
        di as text "  Counterfactual path may diverge"
    }
    if _pte_sigma_eps0 > 1 {
        di as text "[pte] Warning: sigma_eps0 = " %6.3f _pte_sigma_eps0 " > 1"
    }
    
    // ================================================================
    // Task 6: Sample filtering
    // ================================================================
    preserve
    
    quietly keep if att_plus_sample == 1
    quietly keep if nt_plus >= -1 & nt_plus <= `attperiods'
    
    quietly count
    local n_sample = r(N)
    
    if `n_sample' == 0 {
        di as error "[pte] Error: no observations in ATT+ sample"
        restore
        `_pte_attp_drop_sigma'
        exit 2000
    }
    
    if `is_verbose' {
        di as text "[pte] ATT+ sample: n = " %6.0f `n_sample'
    }
    
    // ================================================================
    // Task 7: Boundary check - nt=-1 existence
    // ================================================================
    quietly count if nt_plus == -1
    if r(N) == 0 {
        di as error "[pte] Error: No nt_plus=-1 observations"
        di as error "  L.omega unavailable for ATT+ simulation"
        di as error "  Cannot start counterfactual path"
        restore
        `_pte_attp_drop_sigma'
        exit 498
    }
    
    if `is_verbose' {
        di as text "[pte] nt=-1 observations: " %4.0f r(N)
    }
    
    // ================================================================
    // Task 8: Boundary check - L.omega availability
    // (Need tsset first to use L. operator)
    // ================================================================
    
    // Get panel variables
    capture _xt, trequired
    if _rc {
        di as error "[pte] Error: panel not set"
        restore
        `_pte_attp_drop_sigma'
        exit 459
    }
    local panelvar = r(ivar)
    local timevar = r(tvar)
    
    // Multi-entry firms can contribute more than one entry episode.
    // Build an episode-level panel key so nt_plus resets are legal.
    tempvar _pte_entry_episode _pte_entry_panel
    quietly sort `panelvar' `timevar'
    quietly by `panelvar' (`timevar'): gen long `_pte_entry_episode' = sum(G == 1)
    quietly replace `_pte_entry_episode' = `_pte_entry_episode' + 1 if nt_plus == -1
    quietly egen long `_pte_entry_panel' = group(`panelvar' `_pte_entry_episode')
    
    // Temporarily tsset with nt_plus for L. operator
    quietly tsset `_pte_entry_panel' nt_plus
    
    quietly count if nt_plus == 0 & missing(L.omega)
    if r(N) > 0 {
        di as error "[pte] Error: L.omega missing at nt_plus=0"
        di as error "  `r(N)' observations cannot start simulation"
        restore
        `_pte_attp_drop_sigma'
        exit 498
    }
    
    if `is_verbose' {
        di as text "[pte] L.omega check passed"
    }
    
    // ================================================================
    // Task 9: Path expansion
    // ================================================================
    if `nsim' > 1 {
        quietly expand `nsim'
        quietly bysort `_pte_entry_panel' nt_plus: gen int sim_id = _n
        quietly egen long firm_sim = group(`_pte_entry_panel' sim_id)
        quietly tsset firm_sim nt_plus
        
        // Verify expansion
        quietly count
        local n_expanded = r(N)
        local expected = `n_sample' * `nsim'
        if `n_expanded' != `expected' {
            di as error "[pte] Error: expansion failed"
            di as error "  Expected `expected', got `n_expanded'"
            restore
            `_pte_attp_drop_sigma'
            exit 498
        }
        
        if `is_verbose' {
            di as text "[pte] Expanded: " %8.0f `n_expanded' " obs (nsim=`nsim')"
        }
    }
    else {
        // nsim=1: no expansion needed, keep original tsset
        quietly tsset `_pte_entry_panel' nt_plus
        local n_expanded = `n_sample'
        
        if `is_verbose' {
            di as text "[pte] No expansion (nsim=1)"
        }
    }
    
    // ================================================================
    // Task 10: Set inner seed
    // ================================================================
    local _pte_attp_orig_rngstate = c(rngstate)
    local _pte_attp_restore_rng "capture set rngstate `_pte_attp_orig_rngstate'"
    set seed `seed'
    
    if `is_verbose' {
        di as text "[pte] Inner seed: `seed'"
    }
    
    // ================================================================
    // Task 11: Draw eps0 shock sequence
    // ================================================================
    quietly gen double eps0_sim = rnormal(0, scalar(_pte_sigma_eps0))
    
    // Verify
    quietly count if missing(eps0_sim)
    if r(N) > 0 {
        di as error "[pte] Error: eps0_sim has missing values"
        restore
        `_pte_attp_restore_rng'
        `_pte_attp_drop_sigma'
        exit 498
    }
    
    if `is_verbose' {
        quietly summarize eps0_sim
        di as text "[pte] eps0_sim: mean=" %9.6f r(mean) " sd=" %9.6f r(sd)
    }
    
    // ================================================================
    // Task 12: Initialize counterfactual variable
    // ================================================================
    quietly gen double omega_0_sim = .
    
    // High-order containers
    if `omegapoly' >= 2 {
        quietly gen double omega_0_sim2 = .
    }
    if `omegapoly' >= 3 {
        quietly gen double omega_0_sim3 = .
    }
    if `omegapoly' >= 4 {
        quietly gen double omega_0_sim4 = .
    }
    
    // ================================================================
    // Task 13: nt=0 counterfactual calculation (using observed L.omega)
    // omega_0_sim = rho0 + rho1*L.omega + rho2*(L.omega)^2 + ...
    // At nt=0, L.omega = omega at nt=-1 (observed, untreated state).
    // Proposition C.3 identifies the instantaneous switching effect from
    // h_bar_0(omega_{g-1}); the nt=0 innovation draw is consumed by later
    // recursive states through L.eps0_sim.
    // ================================================================
    
    // Build h_bar_0 formula for nt=0 (using observed values)
    // Start with constant
    local h0_obs "`rho0_0'"
    
    // Add polynomial terms
    forvalues j = 1/`omegapoly' {
        if `j' == 1 {
            local h0_obs "`h0_obs' + `rho0_1' * L.omega"
        }
        else {
            local h0_obs "`h0_obs' + `rho0_`j'' * (L.omega)^`j'"
        }
    }
    
    // Execute nt=0 calculation
    quietly replace omega_0_sim = `h0_obs' if nt_plus == 0
    
    // Verify
    quietly count if nt_plus == 0 & missing(omega_0_sim)
    if r(N) > 0 {
        di as error "[pte] Warning: " r(N) " missing omega_0_sim at nt=0"
    }
    
    if `is_debug' {
        quietly summarize omega_0_sim if nt_plus == 0
        di as text "[pte] omega_0_sim at nt=0: mean=" %9.4f r(mean) " sd=" %9.4f r(sd)
    }
    
    // ================================================================
    // Task 14-15: Recursive loop for nt=1..attperiods
    // Step A: Update high-order terms at nt=s-1
    // Step B: Build h_bar_0 formula using simulated values
    // Step C: Calculate omega_0_sim at nt=s
    // ================================================================
    
    forvalues s = 1/`attperiods' {
        
        // Step A: Update high-order terms at nt=s-1
        if `omegapoly' >= 2 {
            quietly replace omega_0_sim2 = omega_0_sim^2 if nt_plus == `s' - 1
        }
        if `omegapoly' >= 3 {
            quietly replace omega_0_sim3 = omega_0_sim^3 if nt_plus == `s' - 1
        }
        if `omegapoly' >= 4 {
            quietly replace omega_0_sim4 = omega_0_sim^4 if nt_plus == `s' - 1
        }
        
        // Step B: Build h_bar_0 formula (using simulated values)
        local h0_sim "`rho0_0' + `rho0_1' * L.omega_0_sim"
        forvalues j = 2/`omegapoly' {
            local h0_sim "`h0_sim' + `rho0_`j'' * L.omega_0_sim`j'"
        }
        
        // Step C: Calculate omega_0_sim at nt=s
        // Use L.eps0_sim (lagged shock) per reproduction code convention
        quietly replace omega_0_sim = `h0_sim' + L.eps0_sim if nt_plus == `s'
        
        if `is_debug' {
            quietly summarize omega_0_sim if nt_plus == `s'
            di as text "[pte] omega_0_sim at nt=`s': mean=" %9.4f r(mean) " sd=" %9.4f r(sd)
        }
    }
    
    // ================================================================
    // Task 16: TT+ calculation
    // TT+ = omega_obs - omega_0_sim = omega^1 - omega^0
    // ================================================================
    quietly gen double TT_plus = omega - omega_0_sim if nt_plus >= 0
    
    if `is_debug' {
        quietly summarize TT_plus if nt_plus == 0
        di as text "[pte] TT+ at nt=0: mean=" %9.4f r(mean) " sd=" %9.4f r(sd)
        quietly count if TT_plus > 0 & nt_plus >= 0
        local n_pos = r(N)
        quietly count if !missing(TT_plus) & nt_plus >= 0
        local n_total = r(N)
        di as text "[pte] TT+ positive fraction: " %5.1f 100*`n_pos'/`n_total' "%"
    }
    
    // ================================================================
    // Task 17: Cross-path mean aggregation
    // Average TT+ across nsim paths for each entry episode and nt_plus
    // ================================================================
    quietly bysort `_pte_entry_panel' nt_plus: egen double TT_plus_mean = mean(TT_plus)
    
    // Keep only nt >= 0 for aggregation
    quietly keep if nt_plus >= 0
    
    // Collapse to episode-period level before averaging across entries
    quietly duplicates drop `_pte_entry_panel' nt_plus, force

    if `is_verbose' {
        quietly count
        di as text "[pte] Episode-period observations: " %5.0f r(N)
    }
    
    // ================================================================
    // Task 18: Period-level ATT+ aggregation
    // ================================================================
    
    // Save firm-level TT for potential later use
    tempfile firm_tt_plus
    quietly save `firm_tt_plus', replace
    
    // Collapse to period level
    collapse (mean) ATT_plus = TT_plus_mean ///
             (sd) ATT_plus_sd = TT_plus_mean ///
             (count) n_plus = TT_plus_mean, by(nt_plus)
    
    // Sort by nt
    sort nt_plus
    
    // Convert to matrix
    local nrows = _N
    tempname ATT_PLUS_mat
    matrix `ATT_PLUS_mat' = J(`nrows', 4, .)
    
    forvalues i = 1/`nrows' {
        matrix `ATT_PLUS_mat'[`i', 1] = ATT_plus[`i']
        matrix `ATT_PLUS_mat'[`i', 2] = ATT_plus_sd[`i']
        matrix `ATT_PLUS_mat'[`i', 3] = n_plus[`i']
        matrix `ATT_PLUS_mat'[`i', 4] = nt_plus[`i']
    }
    
    matrix colnames `ATT_PLUS_mat' = ATT_plus SD N nt
    
    // Build row names from nt values
    local rnames ""
    forvalues i = 1/`nrows' {
        local nt_val = nt_plus[`i']
        local rnames "`rnames' nt`nt_val'"
    }
    matrix rownames `ATT_PLUS_mat' = `rnames'
    
    // Display results
    if `is_verbose' {
        di as text ""
        di as text "[pte] ATT+ Results:"
        di as text _dup(50) "-"
        di as text %6s "nt" %12s "ATT+" %12s "SD" %8s "N"
        di as text _dup(50) "-"
        forvalues i = 1/`nrows' {
            di as text %6.0f `ATT_PLUS_mat'[`i', 4] ///
                       %12.4f `ATT_PLUS_mat'[`i', 1] ///
                       %12.4f `ATT_PLUS_mat'[`i', 2] ///
                       %8.0f `ATT_PLUS_mat'[`i', 3]
        }
        di as text _dup(50) "-"
    }
    
    // Restore original data
    restore
    `_pte_attp_restore_rng'
    
    // ================================================================
    // Store results in e()
    // ================================================================
    ereturn clear
    if `_pte_attp_has_rho0' {
        ereturn matrix rho_0 = `_pte_attp_rho0_in'
    }
    if `_pte_attp_has_rho1' {
        ereturn matrix rho_1 = `_pte_attp_rho1_in'
    }
    if `_pte_attp_has_sigma0' {
        ereturn scalar sigma_eps0 = `_pte_attp_sigma0'
    }
    if `_pte_attp_has_sigma0_trim' {
        ereturn scalar sigma_eps0_trim = `_pte_attp_sigma0_trim'
    }
    if `_pte_attp_has_sigma0_raw' {
        ereturn scalar sigma_eps0_raw = `_pte_attp_sigma0_raw'
    }
    if `_pte_attp_has_sigma1' {
        ereturn scalar sigma_eps1 = `_pte_attp_sigma1'
    }
    if `_pte_attp_has_sigma1_trim' {
        ereturn scalar sigma_eps1_trim = `_pte_attp_sigma1_trim'
    }
    if `_pte_attp_has_sigma1_raw' {
        ereturn scalar sigma_eps1_raw = `_pte_attp_sigma1_raw'
    }
    ereturn matrix att_plus = `ATT_PLUS_mat'
    ereturn scalar n_att_plus_periods = `nrows'
    ereturn scalar attperiods = `attperiods'
    ereturn scalar nsim = `nsim'
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar seed = `seed'
    ereturn local cmd "_pte_att_plus"
    ereturn local title "ATT+ Estimation (Treatment Entry)"
    
    // Clean up scalars
    capture scalar drop _pte_sigma_eps0
    
    if `is_verbose' {
        di as text ""
        di as text "[pte] ATT+ estimation complete"
    }
    
end
