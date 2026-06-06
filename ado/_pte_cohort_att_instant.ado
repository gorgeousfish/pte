*! _pte_cohort_att_instant.ado
*! Instantaneous Cohort ATT Estimation
*! PURPOSE:
*! Estimates the instantaneous (nt=0) cohort-specific ATT for a given
*! FORMULA:
*! ATT_{g,0} = E[omega_{it} - h_bar_0(omega_{i,t-1}) | i in g, t=g]
*! where h_bar_0(.) is the control-group evolution polynomial:
*! h_bar_0(omega) = rho_0 + rho_1*omega + ... + rho_p*omega^p
*! KEY DESIGN DECISIONS:
*! - At nt=0 (treatment onset), the counterfactual is DETERMINISTIC:
*! no epsilon-zero shock is added because E[eps0|omega_{t-1}] = 0.
*! This distinguishes it from dynamic effects (nt>=1) which require
*! Monte Carlo simulation of epsilon-zero draws.
*! - This helper computes the Proposition C.1 benchmark directly.
*! The main _pte_att worker follows the official DO-style simulated
*! untreated path, which consumes the first innovation draw at nt=0.
*! - Lag omega (L.omega) is computed BEFORE any sample filtering to
*! avoid missing values from panel gaps.
*! - Only the control-group evolution function h_bar_0 is used for
*! counterfactual (not h_bar_1), since we ask "what if untreated?"
*! INPUTS:
*! cohort(integer)    - treatment year defining cohort g
*! rho(name)          - 1 x (omegapoly+1) matrix of evolution coefficients
*! omegapoly(integer) - polynomial order for omega evolution
*! panelvar(varname)  - panel identifier (default: from xtset)
*! timevar(varname)   - time variable (default: from xtset)
*! omega(varname)     - productivity variable (default: _pte_omega)
*! cohortvar(varname) - cohort identifier (default: auto-detects
*! treat_yr0, _pte_treat_year, _pte_cohort_var, treat_year)
*! RETURNS:
*! r(att_g_0)    - cohort-specific ATT at nt=0
*! r(att_g_0_se) - analytical standard error = SD(TT)/sqrt(N)
*! r(n_g)        - number of firms in cohort at nt=0
*! r(n_missing)  - count of missing TT values
*! r(cohort)     - cohort year
*! r(omegapoly)  - polynomial order used
*! REFERENCE:
*! See also: _pte_cohort_att_dynamic.ado for nt>=1 effects.

version 14.0
capture program drop _pte_cohort_att_instant
program define _pte_cohort_att_instant, rclass
    version 14.0
    local _pte_cohort_raw_opts `"`0'"'
    
    syntax , cohort(integer) rho(name) omegapoly(integer) ///
            [panelvar(varname) timevar(varname) omega(varname) ///
             cohortvar(varname) nolog]
    if "`log'" != "" {
        local nolog "nolog"
    }
    
    // ================================================================
    // Task 2: Default parameter handling
    // ================================================================
    
    if "`panelvar'" == "" | "`timevar'" == "" {
        qui xtset
        if "`panelvar'" == "" local panelvar = r(panelvar)
        if "`timevar'" == "" local timevar = r(timevar)
    }
    if "`omega'" == "" local omega "_pte_omega"
    unab _pte_cohort_allvars : _all
    if "`cohortvar'" == "" {
        // Prefer the public/DO cohort anchor before any private scratch state.
        foreach _pte_cohort_candidate in treat_yr0 _pte_treat_year _pte_cohort_var treat_year {
            local _pte_has_cohort_candidate : list posof "`_pte_cohort_candidate'" in _pte_cohort_allvars
            if `_pte_has_cohort_candidate' {
                local cohortvar "`_pte_cohort_candidate'"
                continue, break
            }
        }
        if "`cohortvar'" == "" local cohortvar "treat_year"
    }

    foreach _pte_cohort_exact in panelvar timevar omega cohortvar {
        local _pte_cohort_literal ""
        if regexm(`"`_pte_cohort_raw_opts'"', "(^|[ ,])`_pte_cohort_exact'[ ]*[(]([^)]*)[)]") {
            local _pte_cohort_literal `"`=strtrim(regexs(2))'"'
        }
        if `"`_pte_cohort_literal'"' != "" {
            local _pte_has_literal : list posof "`_pte_cohort_literal'" in _pte_cohort_allvars
            if !`_pte_has_literal' {
                di as error "{bf:pte error E-3018}: Variable `_pte_cohort_literal' not found"
                exit 3018
            }
        }
        local _pte_cohort_resolved "``_pte_cohort_exact''"
        local _pte_has_resolved : list posof "`_pte_cohort_resolved'" in _pte_cohort_allvars
        if !`_pte_has_resolved' {
            di as error "{bf:pte error E-3018}: Variable `_pte_cohort_resolved' not found"
            exit 3018
        }
    }

    // Preserve the caller's panel declaration and delta so the helper can
    // normalize event time in panel periods without leaking xtset changes.
    local pte_prev_panel ""
    local pte_prev_time ""
    local pte_had_xtset 0
    capture quietly xtset
    if _rc == 0 {
        local pte_had_xtset 1
        local pte_prev_panel "`r(panelvar)'"
        local pte_prev_time "`r(timevar)'"
        local pte_prev_delta "`r(tdelta)'"
    }
    local pte_restore_xtset `"capture quietly xtset, clear"'
    if `pte_had_xtset' {
        local pte_restore_xtset `"capture quietly xtset `pte_prev_panel' `pte_prev_time'"'
        if "`pte_prev_delta'" != "" {
            local pte_restore_xtset ///
                `"capture quietly xtset `pte_prev_panel' `pte_prev_time', delta(`pte_prev_delta')"'
        }
    }
    
    // ================================================================
    // Task 3: Parameter validation
    // ================================================================
    
    // Verify rho matrix exists
    cap confirm matrix `rho'
    if _rc != 0 {
        di as error "{bf:pte error E-3018}: Matrix `rho' not found"
        exit 3018
    }
    
    // Verify rho dimension matches omegapoly
    // rho should be 1 x (omegapoly+1): [rho_0, rho_1, ..., rho_p]
    local expected_cols = `omegapoly' + 1
    if colsof(`rho') != `expected_cols' {
        di as error "{bf:pte error E-3020}: rho dimension mismatch"
        di as error "  Expected: 1 x `expected_cols'"
        di as error "  Found: 1 x " colsof(`rho')
        exit 3020
    }
    
    // Verify omega variable is numeric after exact binding.
    cap confirm numeric variable `omega'
    if _rc != 0 {
        di as error "{bf:pte error E-3018}: Variable `omega' must be numeric"
        exit 3018
    }
    
    // ================================================================
    // Task 4: Panel setup and lag variable computation
    // CRITICAL: Compute L.omega BEFORE any sample filtering
    // ================================================================
    
    local pte_work_delta_opt ""
    if `pte_had_xtset' & ///
        "`panelvar'" == "`pte_prev_panel'" & ///
        "`timevar'" == "`pte_prev_time'" & ///
        "`pte_prev_delta'" != "" {
        local pte_work_delta_opt ", delta(`pte_prev_delta')"
    }
    qui xtset `panelvar' `timevar'`pte_work_delta_opt'
    quietly xtset
    local pte_time_delta = real("`r(tdelta)'")
    if missing(`pte_time_delta') | `pte_time_delta' <= 0 {
        local pte_time_delta = 1
    }
    
    tempvar omega_lag
    qui gen double `omega_lag' = L.`omega'
    
    // ================================================================
    // Task 5: Relative time calculation
    // ================================================================
    
    tempvar nt
    qui gen double `nt' = (`timevar' - `cohort') / `pte_time_delta'
    qui replace `nt' = round(`nt') if ///
        !missing(`nt') & abs(`nt' - round(`nt')) <= 1e-10
    
    // ================================================================
    // Task 6: nt=-1 observation validation
    // ================================================================
    
    qui count if `cohortvar' == `cohort' & `nt' == -1
    local n_lag = r(N)
    
    if `n_lag' == 0 {
        `pte_restore_xtset'
        di as error "{bf:pte error E-3019}: No nt=-1 observations for cohort `cohort'"
        exit 3019
    }
    
    qui count if `cohortvar' == `cohort' & `nt' == 0
    local n_instant = r(N)
    
    if `n_lag' < `n_instant' * 0.8 & "`nolog'" == "" {
        di as text "{bf:Warning W-3017}: Insufficient nt=-1 observations"
        di as text "  nt=-1: `n_lag', nt=0: `n_instant'"
    }
    
    // ================================================================
    // Task 7: Cohort sample filtering (keep nt=0 for treated cohort)
    // ================================================================
    
    tempvar keep_flag
    qui gen byte `keep_flag' = (`cohortvar' == `cohort' & `nt' == 0)
    
    // ================================================================
    // Task 8-12: Counterfactual omega calculation using h_bar_0
    // Dynamic polynomial: omega_cf = rho_0 + rho_1*omega_lag + ... + rho_p*omega_lag^p
    // ================================================================
    
    tempvar omega_cf
    qui gen double `omega_cf' = `rho'[1,1] if `keep_flag' == 1
    
    forvalues j = 1/`omegapoly' {
        qui replace `omega_cf' = `omega_cf' + `rho'[1,`j'+1] * `omega_lag'^`j' ///
            if `keep_flag' == 1
    }
    
    // ================================================================
    // Task 13: Instantaneous TT calculation
    // TT = omega - omega_cf (actual minus counterfactual)
    // ================================================================
    
    tempvar TT_0
    qui gen double `TT_0' = `omega' - `omega_cf' if `keep_flag' == 1
    
    // Count missing values
    qui count if missing(`TT_0') & `keep_flag' == 1
    local n_missing = r(N)
    
    // ================================================================
    // Task 14: ATT mean calculation
    // ATT_{g,0} = mean(TT) over cohort g at nt=0
    // ================================================================
    
    qui summ `TT_0' if `keep_flag' == 1
    local ATT_g_0 = r(mean)
    local N_g = r(N)
    local sd_TT = r(sd)
    
    // ================================================================
    // Task 15: Analytical standard error
    // SE = SD(TT) / sqrt(N)
    // ================================================================
    
    if `N_g' > 1 {
        local SE_g_0 = `sd_TT' / sqrt(`N_g')
    }
    else {
        local SE_g_0 = .
    }
    
    // ================================================================
    // Task 16: Return values
    // ================================================================
    
    return scalar att_g_0 = `ATT_g_0'
    return scalar att_g_0_se = `SE_g_0'
    return scalar n_g = `N_g'
    return scalar n_missing = `n_missing'
    return scalar cohort = `cohort'
    return scalar omegapoly = `omegapoly'
    
    // ================================================================
    // Task 17: Diagnostic output
    // ================================================================
    
    if "`nolog'" == "" {
        di as text ""
        di as text "Cohort `cohort' instantaneous ATT (Prop C.1):"
        di as text "  ATT_{g,0} = " %9.6f `ATT_g_0' " (SE = " %7.5f `SE_g_0' ")"
        di as text "  N = `N_g' firms, `n_missing' missing"
    }

    `pte_restore_xtset'
    
end
