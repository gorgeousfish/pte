*! _pte_att_filter_sample.ado
*! Treated Sample Selection Filter
*!
*! This module implements the treated sample filtering pipeline:
*!   Precheck: Validate panel structure, required variables, parameters
*!   Step 1: Provide nt working alias (clonevar from _pte_nt)
*!   Step 2: Exclude pure control group (drop missing(nt))
*!   Step 3: Retain analysis window (nt in [-1, attperiods_max])
*!   Step 4: Compute and return filtering statistics
*!
*! Key invariants:
*!   - nt == _pte_nt for all non-missing observations
*!   - Lower bound fixed at -1 (for L.omega at nt=0)
*!   - omega values unchanged on retained rows

version 14.0
capture program drop _pte_att_filter_sample
program define _pte_att_filter_sample, rclass
    version 14.0
    syntax, attperiods_max(integer) [verbose replace]
    
    // ================================================================
    // PRECHECK: Validate preconditions (TASK-E3-001-01)
    // All required inputs must exist and be valid
    // ================================================================
    
    // 1. Check panel structure
    capture _xt, trequired
    if _rc != 0 {
        di as error "[pte] Error: Panel not properly set"
        di as error "[pte] Hint: Run 'xtset panelvar timevar' first"
        exit 459
    }
    local panelvar = r(ivar)
    local timevar = r(tvar)
    quietly xtset
    local panel_delta "`r(tdelta)'"
    local _pte_restore_delta_opt ""
    if "`panel_delta'" != "" {
        local _pte_restore_delta_opt ", delta(`panel_delta')"
    }
    
    // 2. Check _pte_nt variable (from pte_setup)
    // Core ATT event-time state must bind to the exact _pte_nt column rather
    // than a unique abbreviation such as _pte_nt_shadow.
    capture confirm variable _pte_nt, exact
    if _rc {
        di as error "[pte] Error: _pte_nt variable not found or not numeric"
        di as error "[pte] Hint: Run pte_setup first to generate core variables"
        exit 111
    }
    capture confirm numeric variable _pte_nt
    if _rc {
        di as error "[pte] Error: _pte_nt variable not found or not numeric"
        di as error "[pte] Hint: Run pte_setup first to generate core variables"
        exit 111
    }

    // Event time indexes the discrete ATT horizons l = 0, 1, ... in
    // Proposition 4.3 / the reference DOs. Fractional relative periods do
    // not map to any valid simulation horizon and must be rejected before
    // the helper mutates the caller's dataset.
    quietly count if !missing(_pte_nt) & abs(_pte_nt - round(_pte_nt)) > 1e-10
    if r(N) > 0 {
        di as error "[pte] Error: _pte_nt must contain integer event-time periods"
        di as error "[pte] Hint: Rebuild _pte_nt from the treatment timing so nt = t - e_i on the event-time grid"
        exit 198
    }
    
    // 3. Check omega variable (from)
    // The ATT bridge must consume the realized productivity variable omega,
    // not a silently abbreviated shadow column.
    capture confirm variable omega, exact
    if _rc {
        di as error "[pte] Error: omega variable not found"
        di as error "[pte] Hint: Run _pte_omega first"
        exit 111
    }
    capture confirm numeric variable omega
    if _rc {
        di as error "[pte] Error: omega variable not found"
        di as error "[pte] Hint: Run _pte_omega first"
        exit 111
    }
    
    // 4. Check dataset is not empty
    quietly count
    if r(N) == 0 {
        di as error "[pte] Error: Dataset is empty"
        exit 2000
    }
    
    // 5. Check treated firms exist (not all missing _pte_nt)
    quietly count if !missing(_pte_nt)
    if r(N) == 0 {
        di as error "[pte] Error: No treated firms found (all _pte_nt missing)"
        di as error "[pte] Hint: Check data or pte_setup configuration"
        exit 459
    }
    
    // 6. Validate attperiods_max (upstream validated by)
    if `attperiods_max' < 0 {
        di as error "[pte] Error: attperiods_max must be >= 0 (got `attperiods_max')"
        exit 198
    }
    
    if "`verbose'" != "" {
        di as text "[pte] All preconditions verified"
    }
    
    // ================================================================
    // STEP 1: Provide nt working alias
    // clonevar nt = _pte_nt
    // ================================================================
    
    // Record original observation count (TASK-E3-001-06)
    quietly count
    local N_original = r(N)
    
    local _pte_ntvar "nt"

    // Handle nt already exists scenario
    capture confirm variable nt, exact
    if _rc == 0 {
        // nt already exists
        if "`replace'" != "" {
            // replace means the legacy nt alias must be refreshed from _pte_nt.
            quietly drop nt
        }
        else {
            di as error "[pte] Error: variable 'nt' already exists"
            di as error "[pte] Hint: Use 'replace' option to overwrite, or drop nt first"
            exit 110
        }
    }

    if "`_pte_ntvar'" == "nt" {
        // Create the legacy nt alias only when the caller does not already own it.
        clonevar nt = _pte_nt
    }

    // Verify consistency invariant: working event time == _pte_nt for non-missing rows
    capture assert `_pte_ntvar' == _pte_nt if !missing(_pte_nt)
    if _rc {
        di as error "[pte] Internal error: working event time != _pte_nt after setup"
        exit 9
    }
    
    // ================================================================
    // STEP 2: Exclude pure control group
    // drop if missing(nt)
    // Rationale: ATT definition requires e_i < infinity (Eq.10)
    // ================================================================
    
    quietly count if missing(`_pte_ntvar')
    local N_control_obs = r(N)
    local N_control = 0

    if `N_control_obs' > 0 {
        tempvar _pte_control_tag
        quietly egen byte `_pte_control_tag' = tag(`panelvar') if missing(`_pte_ntvar')
        quietly count if `_pte_control_tag' == 1
        local N_control = r(N)
        quietly drop if missing(`_pte_ntvar')
    }
    
    // Post-condition: no missing nt
    capture assert !missing(`_pte_ntvar')
    if _rc {
        di as error "[pte] Internal error: missing nt after control group exclusion"
        exit 9
    }
    
    // ================================================================
    // STEP 3: Retain analysis window
    // keep if nt >= -1 & nt <= attperiods_max
    // Lower bound fixed at -1 (for L.omega at nt=0)
    // ================================================================
    
    quietly count if `_pte_ntvar' < -1 | `_pte_ntvar' > `attperiods_max'
    local N_outside_window = r(N)
    
    if `N_outside_window' > 0 {
        quietly keep if `_pte_ntvar' >= -1 & `_pte_ntvar' <= `attperiods_max'
    }
    
    // Post-condition: all nt in [-1, attperiods_max]
    quietly count
    local N_filtered = r(N)
    
    if `N_filtered' == 0 {
        di as error "[pte] Error: no observations remain after filtering"
        di as error "[pte] Check attperiods_max=`attperiods_max' and data coverage"
        exit 2000
    }
    
    // Verify window bounds
    quietly summarize `_pte_ntvar'
    local nt_min = r(min)
    local nt_max = r(max)
    
    capture assert `_pte_ntvar' >= -1
    if _rc {
        di as error "[pte] Internal error: nt < -1 after window filtering"
        exit 9
    }
    capture assert `_pte_ntvar' <= `attperiods_max'
    if _rc {
        di as error "[pte] Internal error: nt > attperiods_max after window filtering"
        exit 9
    }
    
    // ================================================================
    // DATA INTEGRITY: omega unchanged (TASK-E3-001-05)
    // SHALL NOT modify omega values
    // Note: We only drop rows and generate nt; omega is never touched.
    // The integrity guarantee is structural (no replace/modify omega).
    // ================================================================
    
    // ================================================================
    // STEP 4: Return values and statistics (TASK-E3-001-06)
    // Requirements Section 6.3: e() scalars
    // Note: This is rclass; caller (_pte_att.ado) transfers r() -> e()
    // ================================================================
    
    // Count treated firms (using egen tag, Stata 14.0 compatible)
    tempvar _tag
    quietly egen byte `_tag' = tag(`panelvar')
    quietly count if `_tag'
    local N_treated_firms = r(N)
    
    // Re-sort and re-xtset to maintain panel structure
    sort `panelvar' `timevar'
    quietly xtset `panelvar' `timevar'`_pte_restore_delta_opt'
    
    // ================================================================
    // VERBOSE output (TASK-E3-001-08)
    // ================================================================
    
    if "`verbose'" != "" {
        di as text ""
        di as text "[pte] Sample filtering summary:"
        di as text "  Original observations:   " as result %10.0fc `N_original'
        di as text "  Control firms excluded:  " as result %10.0fc `N_control'
        di as text "  Control obs excluded:    " as result %10.0fc `N_control_obs'
        di as text "  Outside window excluded: " as result %10.0fc `N_outside_window'
        di as text "  Final sample:            " as result %10.0fc `N_filtered'
        di as text "  Treated firms:           " as result %10.0fc `N_treated_firms'
        di as text "  nt range:                [" as result `nt_min' as text ", " as result `nt_max' as text "]"
        di as text "  attperiods_max:          " as result `attperiods_max'
    }
    
    // ================================================================
    // Return scalars (rclass -> eclass delegation)
    // Caller (_pte_att.ado) maps r(X) -> e(X)
    // ================================================================
    
    return scalar N_original = `N_original'
    return scalar N_control = `N_control'
    return scalar N_control_obs = `N_control_obs'
    return scalar N_outside_window = `N_outside_window'
    return scalar N_filtered = `N_filtered'
    return scalar N_treated_firms = `N_treated_firms'
    return scalar nt_min = `nt_min'
    return scalar nt_max = `nt_max'
    return scalar attperiods_max = `attperiods_max'
    
end
