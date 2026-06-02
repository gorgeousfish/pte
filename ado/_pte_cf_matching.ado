*! _pte_cf_matching.ado
*! Dynamic counterfactual ATE estimation (Stationary Distribution Matching)
*! Implements Proposition D.4: ATE_{s,ell}^{count} via matching
*! Three methods: nearest neighbor, kernel, local polynomial

version 14.0
capture program drop _pte_cf_matching
program define _pte_cf_matching, eclass
    version 14.0
    
    // ================================================================
    // Syntax parsing (Task 1-4)
    // ================================================================
    
    syntax , ///
        TARGETgroup(name)        /// 0/1 variable identifying target group G
        REFERENCEtime(integer)   /// t0: first treatment period
        EXPANSIONtime(integer)   /// t0+s: planned expansion period
        [                        ///
        MATCHmethod(string)      /// nearest (default), kernel, lpoly
        ATTperiods(integer 0)    /// max ell for dynamic ATE
        NSIM(integer 100)        /// number of simulation paths for omega0
        SEED(integer 123456)     /// inner seed for omega0 simulation
        BANDwidth(real 0)        /// kernel/lpoly bandwidth (0=auto)
        DEGree(integer 1)        /// lpoly degree
        Level(integer 95)        /// confidence level
        QUIET                    /// suppress display
        DIAGnose                 /// run D.3/D.4 assumption tests
        ALPHA(real 0.05)         /// significance level for assumption tests
        OVERLAP_threshold(real 0.8) /// overlap threshold for D.4
        OMEGA(name)              /// productivity variable (default: _pte_omega, fallback: omega)
        TREATment(name)          /// treatment status variable D_it
        ]
    
    // Default matchmethod
    if "`matchmethod'" == "" local matchmethod "nearest"
    
    if !inlist("`matchmethod'", "nearest", "kernel", "lpoly") {
        di as error "{bf:pte error 3010}: matchmethod() must be: nearest, kernel, or lpoly"
        exit 3010
    }
    
    // Validate bandwidth/degree for method
    if "`matchmethod'" != "kernel" & "`matchmethod'" != "lpoly" {
        if `bandwidth' != 0 & "`quiet'" == "" {
            di as text "  Note: bandwidth() ignored for matchmethod(`matchmethod')"
        }
    }
    if "`matchmethod'" != "lpoly" {
        if `degree' != 1 & "`quiet'" == "" {
            di as text "  Note: degree() ignored for matchmethod(`matchmethod')"
        }
    }
    if "`matchmethod'" == "lpoly" {
        if `degree' < 0 | `degree' > 3 {
            di as error "degree() must be 0, 1, 2, or 3"
            exit 198
        }
    }
    if `bandwidth' < 0 {
        di as error "{bf:pte error 3015}: bandwidth() must be non-negative"
        exit 3015
    }

    capture _xt, trequired
    if _rc != 0 {
        di as error "{bf:pte error 3016}: data must be xtset as panel"
        exit 459
    }
    local panelvar = r(ivar)
    local timevar = r(tvar)

    capture confirm variable `targetgroup', exact
    if _rc {
        di as error "{bf:pte error 3006}: targetgroup variable '`targetgroup'' not found"
        exit 111
    }

    // Resolve data-variable contracts before estimation.
    local omega_var "`omega'"
    if "`omega_var'" == "" {
        capture confirm variable _pte_omega, exact
        if !_rc {
            local omega_var "_pte_omega"
        }
        else {
            capture confirm variable omega, exact
            if !_rc {
                local omega_var "omega"
            }
        }
    }
    if "`omega_var'" == "" {
        di as error "{bf:pte error 3012}: Neither _pte_omega nor omega variable found"
        exit 111
    }
    capture confirm variable `omega_var', exact
    if _rc {
        di as error "{bf:pte error 3012}: Productivity variable '`omega_var'' not found"
        exit 111
    }

    local treatment_var "`treatment'"
    if "`treatment_var'" != "" {
        capture confirm variable `treatment_var', exact
        if _rc {
            di as error "{bf:pte error 3016}: treatment variable '`treatment_var'' not found"
            exit 111
        }
    }
    else {
        local treatment_var `"`e(treatment)'"'
        if "`treatment_var'" != "" {
            capture confirm variable `treatment_var', exact
            if _rc local treatment_var ""
        }
        if "`treatment_var'" == "" {
            capture confirm variable _pte_D, exact
            if !_rc local treatment_var "_pte_D"
        }
        if "`treatment_var'" == "" {
            capture confirm variable D, exact
            if !_rc local treatment_var "D"
        }
        if "`treatment_var'" == "" {
            capture confirm variable treat, exact
            if !_rc local treatment_var "treat"
        }
        if "`treatment_var'" == "" {
            di as error "{bf:pte error 3016}: No treatment variable found; specify treatment()"
            exit 3016
        }
    }

    tempvar _pte_cf_ever_treated
    quietly bysort `panelvar': egen byte `_pte_cf_ever_treated' = max(`treatment_var')
    
    // ================================================================
    // Optional: Run D.3/D.4 assumption tests before estimation
    // ================================================================
    
    if "`diagnose'" != "" {
        tempname _diag_h_plus _diag_rho_0 _diag_gamma _diag_delta_scalar _diag_sigma_eps_scalar _diag_sigma_eps_trim_scalar _diag_omegapoly_scalar
        local _diag_has_h_plus = 0
        local _diag_has_rho_0 = 0
        local _diag_has_gamma = 0
        local _diag_delta = .
        local _diag_sigma_eps = .
        local _diag_sigma_eps_trim = .
        local _diag_omegapoly_state = .

        capture confirm matrix e(h_plus)
        if !_rc {
            matrix `_diag_h_plus' = e(h_plus)
            local _diag_has_h_plus = 1
        }
        capture confirm matrix e(rho_0)
        if !_rc {
            matrix `_diag_rho_0' = e(rho_0)
            local _diag_has_rho_0 = 1
        }
        capture confirm matrix e(gamma)
        if !_rc {
            matrix `_diag_gamma' = e(gamma)
            local _diag_has_gamma = 1
        }
        capture scalar `_diag_delta_scalar' = e(delta)
        if !_rc local _diag_delta = scalar(`_diag_delta_scalar')
        capture scalar `_diag_sigma_eps_scalar' = e(sigma_eps)
        if !_rc local _diag_sigma_eps = scalar(`_diag_sigma_eps_scalar')
        capture scalar `_diag_sigma_eps_trim_scalar' = e(sigma_eps_trim)
        if !_rc local _diag_sigma_eps_trim = scalar(`_diag_sigma_eps_trim_scalar')
        capture scalar `_diag_omegapoly_scalar' = e(omegapoly)
        if !_rc local _diag_omegapoly_state = scalar(`_diag_omegapoly_scalar')

        // Determine panel/time/treat variables from data context
        local _diag_panelvar "`panelvar'"
        local _diag_timevar "`timevar'"
        local _diag_treatvar "`_pte_cf_ever_treated'"
        local _diag_midvar "_pte_mid"
        capture confirm variable `_diag_midvar', exact
        if _rc != 0 local _diag_midvar "mid"

        local _diag_timing_opts ""
        capture confirm variable _pte_treat_year, exact
        if _rc == 0 {
            local _diag_timing_opts "cohortvar(_pte_treat_year)"
        }
        else {
            capture confirm variable treat_year, exact
            if _rc == 0 {
                local _diag_timing_opts "cohortvar(treat_year)"
            }
            else {
                local _diag_timing_opts "statusvar(`treatment_var')"
            }
        }
        
        // Compute s from expansion - reference
        local _diag_s = `expansiontime' - `referencetime'
        
        // Determine omegapoly from e() if available
        local _diag_omegapoly = e(omegapoly)
        if `_diag_omegapoly' == . local _diag_omegapoly = 3
        
        // Determine noreport from quiet option
        local _diag_noreport ""
        if "`quiet'" != "" local _diag_noreport "noreport"
        
        capture noisily _pte_cf_assumption_tests, ///
            t0(`referencetime') s(`_diag_s') ///
            targetvar(`targetgroup') ///
            omega(`omega_var') ///
            omegapoly(`_diag_omegapoly') ///
            panelvar(`_diag_panelvar') timevar(`_diag_timevar') ///
            treatvar(`_diag_treatvar') midvar(`_diag_midvar') ///
            `_diag_timing_opts' ///
            alpha(`alpha') overlap_threshold(`overlap_threshold') ///
            `_diag_noreport'
        
        if _rc == 0 {
            // Store assumption test results for later retrieval
            local _diag_d3_pass = r(d3_pass)
            local _diag_d4_pass = r(d4_pass)
            local _diag_overlap_ok = r(overlap_ok)
            local _diag_d3_pval = r(assumption_d3_pval)
            local _diag_d4_pval = r(assumption_d4_pval)
            local _diag_overlap_ratio = r(overlap_ratio)
        }
        else {
            if "`quiet'" == "" {
                di as text "  Note: Assumption tests failed (rc=`=_rc'), continuing with estimation"
            }
            local _diag_d3_pass = .
            local _diag_d4_pass = .
            local _diag_overlap_ok = .
        }

        ereturn clear
        if `_diag_has_h_plus' {
            ereturn matrix h_plus = `_diag_h_plus'
        }
        if `_diag_has_rho_0' {
            ereturn matrix rho_0 = `_diag_rho_0'
        }
        if `_diag_has_gamma' {
            ereturn matrix gamma = `_diag_gamma'
        }
        if !missing(`_diag_delta') {
            ereturn scalar delta = `_diag_delta'
        }
        if !missing(`_diag_sigma_eps') {
            ereturn scalar sigma_eps = `_diag_sigma_eps'
        }
        if !missing(`_diag_sigma_eps_trim') {
            ereturn scalar sigma_eps_trim = `_diag_sigma_eps_trim'
        }
        if !missing(`_diag_omegapoly_state') {
            ereturn scalar omegapoly = `_diag_omegapoly_state'
        }
    }
    
    // ================================================================
    // Task 2-3: Extract evolution parameters from e()
    // ================================================================
    
    local omegapoly = e(omegapoly)
    if `omegapoly' == . {
        di as error "{bf:pte error 3014}: Missing omegapoly from prior estimation"
        exit 3014
    }
    
    // rho_0 for omega0 simulation
    capture confirm matrix e(rho_0)
    if _rc {
        di as error "{bf:pte error 3010}: Missing evolution parameters rho_0"
        exit 3010
    }
    tempname Rho_0
    matrix `Rho_0' = e(rho_0)
    
    forvalues j = 0/`omegapoly' {
        local rho_0_`j' = `Rho_0'[1, `j'+1]
    }
    
    local sigma_eps_raw = e(sigma_eps)
    if `sigma_eps_raw' == . {
        di as error "{bf:pte error 3015}: Missing sigma_eps"
        exit 3015
    }
    local sigma_eps_trim = e(sigma_eps_trim)
    // A zero trimmed sigma is a valid degenerate innovation law. Fall back
    // only when the trimmed scale is missing; negative values remain invalid.
    if !missing(`sigma_eps_trim') & `sigma_eps_trim' < 0 {
        di as error "{bf:pte error 3015}: sigma_eps_trim cannot be negative"
        exit 3015
    }
    if missing(`sigma_eps_trim') {
        local sigma_eps_trim = `sigma_eps_raw'
    }
    local sigma_eps0 = `sigma_eps_trim'
    
    // ================================================================
    // Task 5-10: Data preparation
    // ================================================================
    
    local t0 = `referencetime'
    local s_val = `expansiontime' - `referencetime'
    local target_year = `t0' + `s_val' - 1
    
    // Validate time range
    qui sum `timevar'
    if `target_year' < r(min) | `target_year' > r(max) {
        di as error "{bf:pte error 3013}: Target period `target_year' out of data range"
        exit 3013
    }
    
    // --- Task 5: Extract target group sample ---
    preserve
    
    keep if `targetgroup' == 1 & `timevar' == `target_year'
    local n_target = _N
    
    if `n_target' == 0 {
        di as error "{bf:pte error 3011}: No observations in target group at year `target_year'"
        restore
        exit 3011
    }
    
    // Verify G subset of untreated
    qui count if `treatment_var' == 1
    if r(N) > 0 {
        di as error "{bf:pte error 3011}: Target group contains `r(N)' treated firms"
        restore
        exit 3011
    }
    
    drop if missing(`omega_var')
    local n_target = _N
    if `n_target' == 0 {
        di as error "{bf:pte error 3012}: No valid omega in target group"
        restore
        exit 3012
    }
    
    // Save target omega values
    tempname omega_target_vec
    mkmat `omega_var', matrix(`omega_target_vec')
    
    // Save firm IDs if available
    capture confirm variable `panelvar'
    local has_firm = (!_rc)
    if `has_firm' {
        tempname firm_target_vec
        mkmat `panelvar', matrix(`firm_target_vec')
    }
    
    restore
    
    // --- Task 6: Extract treated group matching base ---
    // Treated firms at t0-1 (pre-treatment period)
    preserve
    
    keep if `_pte_cf_ever_treated' == 1 & `timevar' == `t0' - 1
    
    drop if missing(`omega_var')
    local n_treated = _N
    
    if `n_treated' == 0 {
        di as error "{bf:pte error 3012}: No treated observations at t0-1 = `=`t0'-1'"
        restore
        exit 3012
    }
    
    // Save treated omega base values
    tempname omega_treated_base
    mkmat `omega_var', matrix(`omega_treated_base')
    
    // Save firm IDs
    if `has_firm' {
        tempname firm_treated_vec
        mkmat `panelvar', matrix(`firm_treated_vec')
    }
    
    restore
    
    // --- Task 7: Extract treated group outcome at each ell ---
    // omega^1 = observed omega of treated firms at t0+ell
    tempname omega1_cf_firm
    matrix `omega1_cf_firm' = J(`n_target', `attperiods' + 1, .)
    
    // --- Task 8: Common support ---
    // Treated omega range
    mata: st_local("omega_tr_min", strofreal(min(st_matrix("`omega_treated_base'"))))
    mata: st_local("omega_tr_max", strofreal(max(st_matrix("`omega_treated_base'"))))
    
    // Target omega range
    mata: st_local("omega_tg_min", strofreal(min(st_matrix("`omega_target_vec'"))))
    mata: st_local("omega_tg_max", strofreal(max(st_matrix("`omega_target_vec'"))))
    
    // Count target firms in support
    mata: _pte_cfm_overlap("`omega_target_vec'", `omega_tr_min', `omega_tr_max', "n_in_support")
    local overlap_ratio = `n_in_support' / `n_target'
    
    // --- Task 10: Common support warning ---
    if `overlap_ratio' < 0.8 & "`quiet'" == "" {
        di as error "{hline 70}"
        di as error "WARNING: Low overlap ratio = " %5.3f `overlap_ratio'
        di as error "{hline 70}"
        di as text "  `=`n_target' - `n_in_support'' target firms outside support"
        di as text "  Target omega range:  [" %7.4f `omega_tg_min' ", " %7.4f `omega_tg_max' "]"
        di as text "  Treated omega range: [" %7.4f `omega_tr_min' ", " %7.4f `omega_tr_max' "]"
        di as error "{hline 70}"
    }
    
    // ================================================================
    // Task 11-23: Matching (method-specific)
    // ================================================================
    
    if "`matchmethod'" == "nearest" {
        // ============================================================
        // NEAREST NEIGHBOR MATCHING (Task 11-14)
        // ============================================================
        
        // Mata vectorized matching (with replacement)
        mata: _pte_cfm_nn("`omega_target_vec'", "`omega_treated_base'", "_pte_matched_idx", "_pte_match_dist", "match_dist_mean", "match_dist_max", "match_dist_sd")
    }
    else if "`matchmethod'" == "kernel" {
        // ============================================================
        // KERNEL MATCHING (Task 15-19)
        // ============================================================
        
        // Silverman bandwidth if not specified
        if `bandwidth' == 0 {
            mata: _pte_cfm_bw("`omega_treated_base'", "h_kernel")
        }
        else {
            local h_kernel = `bandwidth'
        }
        
        // Compute kernel weights for each target firm
        // Gaussian kernel: K(u) = (1/sqrt(2*pi)) * exp(-u^2/2)
        mata: _pte_cfm_kw("`omega_target_vec'", "`omega_treated_base'", `h_kernel', "_pte_kernel_weights")
        
        local match_dist_mean = 0
        local match_dist_max = 0
        local match_dist_sd = 0
    }
    else if "`matchmethod'" == "lpoly" {
        // ============================================================
        // LOCAL POLYNOMIAL MATCHING (Task 20-23)
        // ============================================================
        
        // Will be computed per-period below
        local match_dist_mean = 0
        local match_dist_max = 0
        local match_dist_sd = 0
    }
    
    // ================================================================
    // Extract omega^1 for each period via matching
    // ================================================================
    
    forvalues ell = 0/`attperiods' {
        local outcome_year = `t0' + `ell'
        
        // Get treated omega at t0+ell
        preserve
        keep if `_pte_cf_ever_treated' == 1 & `timevar' == `outcome_year'
        drop if missing(`omega_var')
        
        local n_treated_ell = _N
        
        if `n_treated_ell' == 0 {
            di as error "{bf:pte error 3014}: No treated observations at t0+`ell' = `outcome_year'"
            restore
            exit 3014
        }
        
        // Need to align treated firms with matching base
        // Merge by firm to get outcome for matched firms
        tempname omega_outcome_ell
        
        if "`matchmethod'" == "nearest" {
            // For nearest: extract omega of matched firms
            // matched_idx maps target -> treated base index
            // We need treated firm's omega at t0+ell
            
            // Get omega for all treated firms at this period
            if `has_firm' {
                mkmat `panelvar' `omega_var', matrix(`omega_outcome_ell')
            }
            else {
                mkmat `omega_var', matrix(`omega_outcome_ell')
            }
            
            restore
            
            // Map matched firms to their outcomes
            mata: _pte_cfm_nn_out("_pte_matched_idx", "`firm_treated_vec'", "`omega_outcome_ell'", "`omega1_cf_firm'", `ell')
        }
        else if "`matchmethod'" == "kernel" {
            // For kernel: weighted average of all treated outcomes
            mkmat `omega_var', matrix(`omega_outcome_ell')
            
            restore
            
            mata: _pte_cfm_kout("_pte_kernel_weights", "`omega_outcome_ell'", "`omega1_cf_firm'", `ell')
        }
        else if "`matchmethod'" == "lpoly" {
            // For lpoly: local polynomial regression prediction
            // Regress omega_outcome on omega_base for treated, predict at target points
            
            // Need treated base omega aligned with outcome
            // Simple approach: merge by firm
            if `has_firm' {
                mkmat `panelvar' `omega_var', matrix(`omega_outcome_ell')
            }
            else {
                mkmat `omega_var', matrix(`omega_outcome_ell')
            }
            
            restore
            
            // Use Stata's lpoly for prediction
            preserve
            clear
            
            // Create treated dataset: omega_base -> omega_outcome
            local n_out = rowsof(`omega_outcome_ell')
            qui set obs `n_out'
            
            if `has_firm' {
                mata: st_store(., st_addvar("double", "omega_outcome"), ///
                    st_matrix("`omega_outcome_ell'")[., 2])
                mata: st_store(., st_addvar("double", "firm_id"), ///
                    st_matrix("`omega_outcome_ell'")[., 1])
                
                // Merge with base omega
                mata: _pte_cfm_lbase("`firm_treated_vec'", "`omega_treated_base'")
                drop if missing(omega_base)
            }
            else {
                // Without firm IDs, assume same order
                mata: st_store(., st_addvar("double", "omega_outcome"), ///
                    st_matrix("`omega_outcome_ell'"))
                mata: st_store(., st_addvar("double", "omega_base"), ///
                    st_matrix("`omega_treated_base'")[1..`n_out', 1])
            }
            
            // Add target points for prediction
            local n_base = _N
            local n_total = `n_base' + `n_target'
            qui set obs `n_total'
            
            mata: _pte_cfm_ltarget(`n_base', `n_total', "`omega_target_vec'")
            
            // Run lpoly
            local bw_opt ""
            if `bandwidth' > 0 {
                local bw_opt "bwidth(`bandwidth')"
            }
            
            qui lpoly omega_outcome omega_base, ///
                degree(`degree') `bw_opt' ///
                generate(_pte_lpoly_pred) at(omega_base) nograph
            
            // Extract predictions for target firms
            mata: _pte_cfm_lpred("`omega1_cf_firm'", `n_base', `n_total', `ell')
            
            restore
        }
    }
    
    // ================================================================
    // Task 24-26: omega^0 simulation (shared with divergent method)
    // ================================================================

    // As a reusable worker, cf_matching must keep its internal simulation
    // seed local to this call and leave the caller RNG state unchanged.
    local _pte_cf_orig_rngstate `"`c(rngstate)'"'
    local _pte_cf_restore_rng `"capture set rngstate `_pte_cf_orig_rngstate'"'
    local _pte_cf_exec_rc = 0
    
    // Simulate omega0 for each target firm using h_bar_0
    capture noisily {
        preserve
    
    // Reconstruct target group data
    keep if `targetgroup' == 1 & `timevar' == `target_year'
    drop if missing(`omega_var')
    
    // Expand for nsim paths
    qui expand `nsim'
    capture confirm variable `panelvar'
    if !_rc {
        qui bys `panelvar': gen int _pte_path_id = _n
    }
    else {
        qui gen int _pte_path_id = mod(_n - 1, `nsim') + 1
    }
    
    // Expand for time periods
    local n_periods = `attperiods' + 2
    qui expand `n_periods'
    capture confirm variable `panelvar'
    if !_rc {
        qui bys `panelvar' _pte_path_id: gen int _pte_nt = _n - 2
        qui egen long _pte_firm_path = group(`panelvar' _pte_path_id)
    }
    else {
        qui gen long _pte_obs_id = ceil(_n / `n_periods')
        qui gen int _pte_nt = mod(_n - 1, `n_periods') - 1
        qui gen long _pte_firm_path = _pte_obs_id
    }
    
    qui tsset _pte_firm_path _pte_nt
    
    // Store starting omega at nt=-1
    qui gen double _pte_omega_base = `omega_var' if _pte_nt == -1
    qui bys _pte_firm_path: egen double _pte_omega_start = max(_pte_omega_base)
    drop _pte_omega_base
    
    // Set inner seed
    set seed `seed'
    
    // Draw eps0 shocks
    qui gen double _pte_eps0_sim = rnormal(0, `sigma_eps0')
    
    // omega0 recursive simulation using h_bar_0
    qui gen double _pte_omega0 = .
    qui replace _pte_omega0 = _pte_omega_start if _pte_nt == -1
    
    // nt=0
    local h0_formula "`rho_0_0'"
    forvalues j = 1/`omegapoly' {
        local h0_formula "`h0_formula' + `rho_0_`j'' * (L._pte_omega0)^`j'"
    }
    qui replace _pte_omega0 = `h0_formula' + _pte_eps0_sim if _pte_nt == 0
    
    // nt>=1 recursive
    if `omegapoly' >= 2 {
        qui gen double _pte_omega0_2 = .
    }
    if `omegapoly' >= 3 {
        qui gen double _pte_omega0_3 = .
    }
    if `omegapoly' >= 4 {
        qui gen double _pte_omega0_4 = .
    }
    
    forvalues ell = 1/`attperiods' {
        if `omegapoly' >= 2 {
            qui replace _pte_omega0_2 = _pte_omega0^2 if _pte_nt == `ell' - 1
        }
        if `omegapoly' >= 3 {
            qui replace _pte_omega0_3 = _pte_omega0^3 if _pte_nt == `ell' - 1
        }
        if `omegapoly' >= 4 {
            qui replace _pte_omega0_4 = _pte_omega0^4 if _pte_nt == `ell' - 1
        }
        
        local h0_sim "`rho_0_0' + `rho_0_1' * L._pte_omega0"
        if `omegapoly' >= 2 {
            local h0_sim "`h0_sim' + `rho_0_2' * L._pte_omega0_2"
        }
        if `omegapoly' >= 3 {
            local h0_sim "`h0_sim' + `rho_0_3' * L._pte_omega0_3"
        }
        if `omegapoly' >= 4 {
            local h0_sim "`h0_sim' + `rho_0_4' * L._pte_omega0_4"
        }
        
        qui replace _pte_omega0 = `h0_sim' + _pte_eps0_sim if _pte_nt == `ell'
    }
    
    // Aggregate omega0: mean across paths for each firm-period
    capture confirm variable `panelvar'
    if !_rc {
        qui bys `panelvar' _pte_nt: egen double _pte_omega0_mean = mean(_pte_omega0)
        qui duplicates drop `panelvar' _pte_nt, force
    }
    else {
        qui gen long _pte_orig_id = ceil(_pte_firm_path / `nsim')
        qui bys _pte_orig_id _pte_nt: egen double _pte_omega0_mean = mean(_pte_omega0)
        qui duplicates drop _pte_orig_id _pte_nt, force
    }
    
    // Extract omega0 mean per firm per period into matrix
    tempname omega0_mean_firm
    matrix `omega0_mean_firm' = J(`n_target', `attperiods' + 1, .)
    
    forvalues ell = 0/`attperiods' {
        // Get omega0 means for this period, sorted by firm
        qui sort `panelvar' _pte_nt
        mata: _pte_cfm_fill_om0("_pte_omega0_mean", "_pte_nt", "`omega0_mean_firm'", `ell')
    }
    
    restore
    
    // ================================================================
    // Task 27: Compute ATE^count = omega1 - omega0
    // ================================================================
    
    tempname tt_count_firm ATE_count ATE_count_se
    matrix `tt_count_firm' = J(`n_target', `attperiods' + 1, .)
    matrix `ATE_count' = J(1, `attperiods' + 1, .)
    matrix `ATE_count_se' = J(1, `attperiods' + 1, .)
    
    mata: _pte_cfm_agg("`omega1_cf_firm'", "`omega0_mean_firm'", "`tt_count_firm'", "`ATE_count'", "`ATE_count_se'")
    
    // Column names
    local colnames ""
    forvalues ell = 0/`attperiods' {
        local colnames "`colnames' ell_`ell'"
    }
    matrix colnames `ATE_count' = `colnames'
    matrix colnames `ATE_count_se' = `colnames'
    
    // ================================================================
    // Task 28: Display results and store e() returns
    // ================================================================
    
    if "`quiet'" == "" {
        di as text ""
        di as text "{hline 70}"
        di as text "Dynamic Counterfactual Treatment Effect (Proposition D.4)"
        di as text "Method: Stationary Distribution Matching"
        di as text "Match Method: `matchmethod'"
        di as text "{hline 70}"
        di as text ""
        di as text "  Reference time (t0):     " as result %4.0f `t0'
        di as text "  Expansion time (t0+s):   " as result %4.0f `expansiontime'
        di as text "  Delay (s):               " as result %4.0f `s_val'
        di as text "  Target group N:          " as result %9.0f `n_target'
        di as text "  Treated group N:         " as result %9.0f `n_treated'
        di as text "  Simulation paths (nsim): " as result %9.0f `nsim'
        di as text "  Overlap ratio:           " as result %9.4f `overlap_ratio'
        
        if "`matchmethod'" == "nearest" {
            di as text "  Mean match distance:     " as result %12.6f `match_dist_mean'
            di as text "  Max match distance:      " as result %12.6f `match_dist_max'
        }
        else if "`matchmethod'" == "kernel" {
            di as text "  Bandwidth:               " as result %12.6f `h_kernel'
        }
        else if "`matchmethod'" == "lpoly" {
            di as text "  Polynomial degree:       " as result %4.0f `degree'
        }
        
        di as text ""
        di as text "{hline 70}"
        di as text %20s "Period (ell)" %15s "ATE_count" %15s "Std. Err."
        di as text "{hline 70}"
        
        forvalues ell = 0/`attperiods' {
            local ate_val = `ATE_count'[1, `ell' + 1]
            local se_val = `ATE_count_se'[1, `ell' + 1]
            if `se_val' < . {
                di as text %20.0f `ell' as result %15.6f `ate_val' %15.6f `se_val'
            }
            else {
                di as text %20.0f `ell' as result %15.6f `ate_val' %15s "N/A"
            }
        }
        
        di as text "{hline 70}"
        di as text ""
        di as text "  omega1: from matched treated firms (method: `matchmethod')"
        di as text "  omega0: simulated via h_bar_0 (control evolution, rho only)"
        di as text "{hline 70}"
    }
    
    // Store e() returns
    ereturn matrix ate_counterfactual = `ATE_count'
    ereturn matrix ate_counterfactual_se = `ATE_count_se'
    
    ereturn scalar n_target_group = `n_target'
    ereturn scalar n_reference = `n_treated'
    ereturn scalar overlap_ratio = `overlap_ratio'
    ereturn scalar t0 = `t0'
    ereturn scalar expansion_time = `expansiontime'
    ereturn scalar s = `s_val'
    ereturn scalar attperiods = `attperiods'
    ereturn scalar nsim = `nsim'
    ereturn scalar seed = `seed'
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar sigma_eps = `sigma_eps_raw'
    ereturn scalar sigma_eps_trim = `sigma_eps0'
    
    if "`matchmethod'" == "nearest" {
        ereturn scalar match_distance_mean = `match_dist_mean'
        ereturn scalar match_distance_max = `match_dist_max'
        ereturn scalar match_distance_sd = `match_dist_sd'
    }
    else if "`matchmethod'" == "kernel" {
        ereturn scalar bandwidth = `h_kernel'
    }
    else if "`matchmethod'" == "lpoly" {
        ereturn scalar lpoly_degree = `degree'
    }
    
    ereturn local cfmethod "matching"
    ereturn local matchmethod "`matchmethod'"
    ereturn local subcmd_cf "counterfactual_matching"
    
    // Store parameter vectors
    tempname rho_0_store
    matrix `rho_0_store' = `Rho_0'
    ereturn matrix rho_0_used = `rho_0_store'
    
    // Clean up Mata matrices
    cap matrix drop _pte_matched_idx
    cap matrix drop _pte_match_dist
    cap matrix drop _pte_kernel_weights
    
        // Store assumption test results if diagnose was run
        if "`diagnose'" != "" {
            ereturn scalar assumption_d3_pval = `_diag_d3_pval'
            ereturn scalar assumption_d4_pval = `_diag_d4_pval'
            ereturn scalar assumption_d3_pass = `_diag_d3_pass'
            ereturn scalar assumption_d4_pass = `_diag_d4_pass'
            ereturn scalar assumption_overlap_ok = `_diag_overlap_ok'
            ereturn scalar assumption_overlap_ratio = `_diag_overlap_ratio'
        }
    }
    local _pte_cf_exec_rc = _rc
    if `_pte_cf_exec_rc' != 0 {
        capture restore
    }
    `_pte_cf_restore_rng'
    if `_pte_cf_exec_rc' != 0 {
        exit `_pte_cf_exec_rc'
    }
    
end

// ================================================================
// Mata helpers for _pte_cf_matching
// ================================================================

capture mata: mata drop _pte_cfm_overlap()
capture mata: mata drop _pte_cfm_nn()
capture mata: mata drop _pte_cfm_nn_out()
capture mata: mata drop _pte_cfm_fill_om0()
capture mata: mata drop _pte_cfm_agg()
capture mata: mata drop _pte_cfm_bw()
capture mata: mata drop _pte_cfm_kw()
capture mata: mata drop _pte_cfm_kout()
capture mata: mata drop _pte_cfm_lbase()
capture mata: mata drop _pte_cfm_ltarget()
capture mata: mata drop _pte_cfm_lpred()

mata:

void _pte_cfm_overlap(
    string scalar target_mat_name,
    real scalar omega_tr_min,
    real scalar omega_tr_max,
    string scalar local_name)
{
    real colvector omega_target
    real scalar n_in

    omega_target = st_matrix(target_mat_name)
    n_in = sum((omega_target :>= omega_tr_min) :& (omega_target :<= omega_tr_max))
    st_local(local_name, strofreal(n_in))
}

void _pte_cfm_nn(
    string scalar target_mat_name,
    string scalar treated_mat_name,
    string scalar idx_name,
    string scalar dist_name,
    string scalar mean_local,
    string scalar max_local,
    string scalar sd_local)
{
    real colvector omega_t, omega_tr, matched_idx, match_dist, dists
    real rowvector idx, w
    real scalar n_t, i

    omega_t = st_matrix(target_mat_name)
    omega_tr = st_matrix(treated_mat_name)
    n_t = rows(omega_t)
    matched_idx = J(n_t, 1, .)
    match_dist = J(n_t, 1, .)

    for (i = 1; i <= n_t; i++) {
        dists = abs(omega_tr :- omega_t[i])
        minindex(dists, 1, idx, w)
        matched_idx[i] = idx[1]
        match_dist[i] = dists[idx[1]]
    }

    st_matrix(idx_name, matched_idx)
    st_matrix(dist_name, match_dist)
    st_local(mean_local, strofreal(mean(match_dist)))
    st_local(max_local, strofreal(max(match_dist)))
    if (rows(match_dist) > 1) {
        st_local(sd_local, strofreal(sqrt(variance(match_dist))))
    }
    else {
        st_local(sd_local, "0")
    }
}

void _pte_cfm_bw(
    string scalar treated_mat_name,
    string scalar local_name)
{
    real colvector omega_tr
    real scalar sd_omega, n_tr, h

    omega_tr = st_matrix(treated_mat_name)
    sd_omega = sqrt(variance(omega_tr))
    n_tr = rows(omega_tr)
    h = 1.06 * sd_omega * n_tr^(-0.2)
    st_local(local_name, strofreal(h))
}

void _pte_cfm_kw(
    string scalar target_mat_name,
    string scalar treated_mat_name,
    real scalar h,
    string scalar w_name)
{
    real colvector omega_t, omega_tr, u, K
    real matrix W_kernel
    real scalar n_t, n_tr, i, K_sum

    omega_t = st_matrix(target_mat_name)
    omega_tr = st_matrix(treated_mat_name)
    n_t = rows(omega_t)
    n_tr = rows(omega_tr)
    W_kernel = J(n_t, n_tr, .)

    for (i = 1; i <= n_t; i++) {
        u = (omega_tr :- omega_t[i]) / h
        K = exp(-0.5 * u:^2) / sqrt(2 * pi())
        K_sum = sum(K)
        if (K_sum > 0) {
            W_kernel[i, .] = (K / K_sum)'
        }
        else {
            W_kernel[i, .] = J(1, n_tr, 1 / n_tr)
        }
    }

    st_matrix(w_name, W_kernel)
}

void _pte_cfm_nn_out(
    string scalar idx_name,
    string scalar firm_tr_name,
    string scalar outcome_name,
    string scalar om1_name,
    real scalar ell)
{
    real colvector midx, firm_tr, outcome_firms, outcome_omega, omega1_ell
    real matrix outcome_data, om1
    real scalar n_t, i, j, ate_col, idx_found, matched_firm_id

    midx = st_matrix(idx_name)
    n_t = rows(midx)
    firm_tr = st_matrix(firm_tr_name)
    outcome_data = st_matrix(outcome_name)
    outcome_firms = outcome_data[., 1]
    outcome_omega = outcome_data[., cols(outcome_data)]

    omega1_ell = J(n_t, 1, .)
    for (i = 1; i <= n_t; i++) {
        matched_firm_id = firm_tr[midx[i]]
        idx_found = .
        for (j = 1; j <= rows(outcome_firms); j++) {
            if (outcome_firms[j] == matched_firm_id) {
                idx_found = j
                break
            }
        }
        if (idx_found != .) {
            omega1_ell[i] = outcome_omega[idx_found]
        }
    }

    ate_col = ell + 1
    om1 = st_matrix(om1_name)
    om1[., ate_col] = omega1_ell
    st_matrix(om1_name, om1)
}

void _pte_cfm_kout(
    string scalar w_name,
    string scalar outcome_name,
    string scalar om1_name,
    real scalar ell)
{
    real matrix W, om1
    real colvector outcome_omega, omega1_ell
    real scalar n_t, n_out, n_tr, ate_col

    W = st_matrix(w_name)
    outcome_omega = st_matrix(outcome_name)
    n_t = rows(W)
    n_out = rows(outcome_omega)
    n_tr = cols(W)

    if (n_out == n_tr) {
        omega1_ell = W * outcome_omega
    }
    else {
        omega1_ell = J(n_t, 1, mean(outcome_omega))
    }

    ate_col = ell + 1
    om1 = st_matrix(om1_name)
    om1[., ate_col] = omega1_ell
    st_matrix(om1_name, om1)
}

void _pte_cfm_fill_om0(
    string scalar omega0_mean_var,
    string scalar nt_var,
    string scalar om0_name,
    real scalar ell)
{
    real colvector omega0_view, nt_view, vals
    real matrix om0
    real scalar n, i, ate_col, n_fill

    omega0_view = st_data(., omega0_mean_var)
    nt_view = st_data(., nt_var)
    n = rows(omega0_view)
    vals = J(0, 1, .)

    for (i = 1; i <= n; i++) {
        if (nt_view[i] == ell) {
            vals = vals \ omega0_view[i]
        }
    }

    om0 = st_matrix(om0_name)
    ate_col = ell + 1
    n_fill = rows(vals)
    if (rows(om0) < n_fill) {
        n_fill = rows(om0)
    }
    if (n_fill > 0) {
        om0[1..n_fill, ate_col] = vals[1..n_fill]
    }
    st_matrix(om0_name, om0)
}

void _pte_cfm_lbase(
    string scalar firm_tr_name,
    string scalar omega_base_name)
{
    real colvector firm_tr, omega_base, firm_out, base_vals
    real scalar i, j

    firm_tr = st_matrix(firm_tr_name)
    omega_base = st_matrix(omega_base_name)
    firm_out = st_data(., "firm_id")
    base_vals = J(rows(firm_out), 1, .)

    for (i = 1; i <= rows(firm_out); i++) {
        for (j = 1; j <= rows(firm_tr); j++) {
            if (firm_out[i] == firm_tr[j]) {
                base_vals[i] = omega_base[j]
                break
            }
        }
    }

    st_store(., st_addvar("double", "omega_base"), base_vals)
}

void _pte_cfm_ltarget(
    real scalar n_base,
    real scalar n_total,
    string scalar target_mat_name)
{
    real colvector omega_t

    omega_t = st_matrix(target_mat_name)
    st_store((n_base + 1, n_total), "omega_base", omega_t)
}

void _pte_cfm_lpred(
    string scalar om1_name,
    real scalar n_base,
    real scalar n_total,
    real scalar ell)
{
    real colvector pred
    real matrix om1
    real scalar ate_col

    pred = st_data((n_base + 1, n_total), "_pte_lpoly_pred")
    ate_col = ell + 1
    om1 = st_matrix(om1_name)
    om1[., ate_col] = pred
    st_matrix(om1_name, om1)
}

void _pte_cfm_agg(
    string scalar om1_name,
    string scalar om0_name,
    string scalar tt_name,
    string scalar ate_name,
    string scalar se_name)
{
    real matrix om1, om0, tt, ate, ate_se
    real colvector col, valid
    real scalar n_p, c

    om1 = st_matrix(om1_name)
    om0 = st_matrix(om0_name)
    tt = om1 - om0
    n_p = cols(tt)

    ate = J(1, n_p, .)
    ate_se = J(1, n_p, .)

    for (c = 1; c <= n_p; c++) {
        col = tt[., c]
        valid = select(col, col :< .)
        if (rows(valid) > 0) {
            ate[1, c] = mean(valid)
            if (rows(valid) > 1) {
                ate_se[1, c] = sqrt(variance(valid)) / sqrt(rows(valid))
            }
        }
    }

    st_matrix(tt_name, tt)
    st_matrix(ate_name, ate)
    st_matrix(se_name, ate_se)
}

end
