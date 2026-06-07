*! _pte_att.ado
*! ATT Estimation Module
*!
*! This module implements the ATT estimation pipeline:
*!   Step 1: Extract eps0 pool and compute sigma (raw + trimmed)
*!   Step 2: Filter treated sample (drop controls, keep nt in [-1, attperiods])
*!   Step 3: Path expansion (expand nsim when nsim > 1)
*!   Step 4: Prepare eps0 shock sequences (dual-track: bsample + rnormal)
*!   Step 5: Recursive counterfactual simulation (omega_0 using h_bar_0 only)
*!   Step 6: Compute TT = omega - omega_0, aggregate to ATT by nt
*!
*! Key principle: Counterfactual uses ONLY h_bar_0 (untreated evolution),
*!   NOT treatment interaction terms (gamma, delta).
*!
*! Dual-track computation:
*!   Track 1 (raw):  defaults to bsample over the observed eps0 pool,
*!                  with official translog Gaussian exceptions preserved
*!                  for order-1 point paths and order-3 expanded paths
*!   Track 2 (trim): eps0_trim from rnormal(0, sigma_eps_trim)

version 14.0
capture program drop _pte_att
program define _pte_att, eclass
    version 14.0
    
    // ================================================================
    // Syntax parsing
    // ================================================================
    // Failure rollback is state-sensitive:
    //   * preserve known upstream bridge states, because
    //     _pte_att has not yet published a new ATT object;
    //   * clear stale _pte_att or unrelated eclass results, because a failed
    //     rerun must not leave them posing as the current ATT output.
    // ATT-owned data bridges must always be cleared on failure; only the
    // eclass object is conditional on whether the caller state is a valid
    // upstream producer.
    local _pte_prev_cmd `"`e(cmd)'"'
    local _pte_prev_noatt = 0
    if "`_pte_prev_cmd'" == "pte" {
        capture scalar _pte_prev_noatt_scalar = e(noatt)
        if _rc == 0 & _pte_prev_noatt_scalar == 1 {
            local _pte_prev_noatt = 1
        }
        capture scalar drop _pte_prev_noatt_scalar
    }
    local _pte_preserve_prev_eclass = ///
        inlist("`_pte_prev_cmd'", "_pte_winsorize", "_pte_eps0_sample", ///
            "_pte_evolution", "_pte_treatdep_evolution", "_pte_omega")
    local _pte_preserve_prev_timing = ///
        inlist("`_pte_prev_cmd'", "_pte_winsorize", "_pte_eps0_sample")
    if !`_pte_preserve_prev_eclass' & "`_pte_prev_cmd'" == "pte" & `_pte_prev_noatt' {
        // Public pte,noatt is an producer wrapper, not a stale ATT
        // result. Failed ATT reruns must preserve that usable upstream state.
        local _pte_preserve_prev_eclass = 1
        local _pte_preserve_prev_timing = 1
    }
    tempvar _pte_att_prev_treat_year _pte_att_prev_treat_yr0 _pte_att_prev_nt
    local _pte_has_prev_treat_year = 0
    local _pte_has_prev_treat_yr0 = 0
    local _pte_has_prev_nt = 0

    // Shared timing variables belong only to upstream states that actually
    // publish the certified timing bridge used by downstream/003
    // helpers. Restoring a generic upstream eclass (for example _pte_omega or
    // _pte_evolution) must not also resurrect stale ATT timing leftovers.
    if `_pte_preserve_prev_timing' {
        capture confirm variable _pte_treat_year, exact
        if _rc == 0 {
            quietly clonevar `_pte_att_prev_treat_year' = _pte_treat_year
            local _pte_has_prev_treat_year = 1
        }

        capture confirm variable treat_yr0, exact
        if _rc == 0 {
            quietly clonevar `_pte_att_prev_treat_yr0' = treat_yr0
            local _pte_has_prev_treat_yr0 = 1
        }

        capture confirm variable _pte_nt, exact
        if _rc == 0 {
            quietly clonevar `_pte_att_prev_nt' = _pte_nt
            local _pte_has_prev_nt = 1
        }
    }
    local _pte_clear_eclass `"capture quietly _pte_att_failure_cleanup, hastreatyear(`_pte_has_prev_treat_year') treatyearbackup(`_pte_att_prev_treat_year') hastreatalias(`_pte_has_prev_treat_yr0') treataliasbackup(`_pte_att_prev_treat_yr0') hasnt(`_pte_has_prev_nt') ntbackup(`_pte_att_prev_nt')"'
    if !`_pte_preserve_prev_eclass' {
        local _pte_clear_eclass `"capture quietly _pte_att_failure_cleanup, cleareclass hastreatyear(`_pte_has_prev_treat_year') treatyearbackup(`_pte_att_prev_treat_year') hastreatalias(`_pte_has_prev_treat_yr0') treataliasbackup(`_pte_att_prev_treat_yr0') hasnt(`_pte_has_prev_nt') ntbackup(`_pte_att_prev_nt')"'
    }
    local _pte_att_optscan `"`0'"'
    local _pte_att_has_omegapoly = regexm(lower(`"`_pte_att_optscan'"'), "(^|[ ,])omegapoly[(]")
    capture noisily syntax, treatment(name) ///
        [omegapoly(integer -1) ///
         attpoly(integer -1) ///
         attperiods(integer 4) ///
         nsim(integer -1) ///
         seed(integer -1) ///
         PRESERVERNG ///
         TOUSE(name) ///
         NOTRIMeps ///
         LEGACYPOOLEDeps0 ///
         LEGACYATTGaussian ///
         LEGACYATTPanelorder ///
         NODIAGnose ///
         noCLIPOMG ///
         CLIPRANGE(real 50) ///
         noSTABILITYCHECK ///
         VERBOSE ///
         VERIFY]
    if _rc != 0 {
        local _pte_att_syntax_rc = _rc
        `_pte_clear_eclass'
        exit `_pte_att_syntax_rc'
    }
    
    // ================================================================
    // Seed sentinel parsing ( Task 1/2/3)
    // -1 is sentinel: user did not specify seed → use default 123456
    // preserverng is the internal grouped-bootstrap contract: do not reset
    // the RNG, consume the caller's live stream, then restore caller state.
    // ================================================================
    local preserve_rng = ("`preserverng'" != "")
    local legacy_att_panel_order = ("`legacyattpanelorder'" != "")
    local seed_source = "default"
    if `preserve_rng' {
        if `seed' != -1 {
            di as error "[pte] Error: preserverng cannot be combined with seed()"
            `_pte_clear_eclass'
            exit 198
        }
        local seed = .
        local seed_source = "inherited"
    }
    else if `seed' != -1 {
        // Validate user-specified seed (Task 2)
        if `seed' < 1 {
            di as error "[pte] Error: seed() must be a positive integer"
            `_pte_clear_eclass'
            exit 198
        }
        if `seed' > 2147483647 {
            di as error "[pte] Error: seed() exceeds maximum value (2147483647)"
            `_pte_clear_eclass'
            exit 198
        }
        local seed_source = "user"
    }
    
    // ================================================================
    // Step 0: Input validation
    // ================================================================
    
    // 0.0b Validate cliprange ( IMPL-001)
    if `cliprange' <= 0 {
        di as error "[pte] Error: cliprange() must be a positive number, got `cliprange'"
        `_pte_clear_eclass'
        exit 198
    }

    // 0.0c When omegapoly() is omitted, inherit the live order
    // before any downstream defaults depend on it. consumes the
    // Stage-2 evolution state, so the active rho_0 / e(omegapoly) contract
    // must take precedence over the helper's legacy syntax default.
    if `omegapoly' == -1 & !`_pte_att_has_omegapoly' {
        capture local omegapoly = e(omegapoly)
        if _rc != 0 | missing(`omegapoly') {
            capture confirm matrix e(rho_0)
            if _rc == 0 {
                tempname _pte_att_rho_probe
                matrix `_pte_att_rho_probe' = e(rho_0)
                local omegapoly = colsof(`_pte_att_rho_probe') - 1
            }
        }
        if missing(`omegapoly') {
            local omegapoly = 3
        }
    }
    
    // 0.1 Validate omegapoly
    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "[pte] Error: omegapoly must be 1, 2, 3, or 4"
        `_pte_clear_eclass'
        exit 198
    }
    
    // 0.1b Validate and set attpoly (default = omegapoly)
    // Paper Section 4 / official DO scripts recurse ATT using the same
    // untreated law order that was estimated in. A separate
    // lower-order ATT recursion would change h_bar_0 itself rather than
    // merely toggling a reporting option.
    if `attpoly' == -1 {
        local attpoly = `omegapoly'
    }
    else if `attpoly' < 1 {
        di as error "[pte] Error: attpoly() must be at least 1"
        `_pte_clear_eclass'
        exit 198
    }
    else if `attpoly' != `omegapoly' {
        di as error "[pte] Error: attpoly() must match omegapoly() in the canonical ATT recursion"
        di as error "[pte]        Received attpoly(`attpoly') with omegapoly(`omegapoly')"
        `_pte_clear_eclass'
        exit 198
    }
    
    // 0.2 Validate attperiods
    if `attperiods' < 0 {
        di as error "[pte] Error: attperiods must be non-negative"
        `_pte_clear_eclass'
        exit 198
    }
    
    // 0.3 Smart nsim default — must mirror _pte_path_expand contract
    if `nsim' == -1 {
        if `omegapoly' == 1 {
            local nsim = 1
        }
        else {
            local nsim = 100
        }
    }
    
    // 0.4 Validate nsim
    if `nsim' < 1 {
        di as error "[pte] Error: nsim must be >= 1"
        `_pte_clear_eclass'
        exit 198
    }

    // 0.4b Seed default resolution for direct ATT consumers.
    // Public pte replicate(order3/table*) routes pin the point ATT seed at
    // 10000 to match the official translog benchmark DO scripts. When users
    // stop after pte,noatt and then call _pte_att directly on that live
    // state, omitting seed() should preserve the benchmark seed law
    // instead of silently reverting to the generic helper default 123456.
    if !`preserve_rng' & `seed' == -1 {
        local _pte_live_cmd `"`e(cmd)'"'
        local _pte_live_noatt = 0
        if "`_pte_live_cmd'" == "pte" {
            capture scalar _pte_att_prev_noatt = e(noatt)
            if _rc == 0 & _pte_att_prev_noatt == 1 {
                local _pte_live_noatt = 1
            }
            capture scalar drop _pte_att_prev_noatt
        }

        local _pte_live_seed_replicate `"`e(replicate)'"'
        local _pte_live_seed_replicate = lower(strtrim(`"`_pte_live_seed_replicate'"'))
        local _pte_live_seed_pfunc `"`e(prodfunc)'"'
        if "`_pte_live_seed_pfunc'" == "" {
            local _pte_live_seed_pfunc `"`e(pfunc)'"'
        }
        local _pte_live_seed_pfunc = lower(strtrim(`"`_pte_live_seed_pfunc'"'))

        if "`_pte_live_cmd'" == "pte" & `_pte_live_noatt' & ///
            "`_pte_live_seed_pfunc'" == "translog" & `omegapoly' == 3 & `nsim' == 100 & ///
            inlist("`_pte_live_seed_replicate'", "order3", "table1", "table5", "table_e4") {
            local seed = 10000
            local seed_source = "replicate"
        }
        else {
            local seed = 123456
            local seed_source = "default"
        }
    }
    
    // 0.5 Validate required variables
    capture confirm variable omega, exact
    if _rc != 0 {
        di as error "[pte] Error: variable 'omega' not found"
        di as error "[pte] Please run _pte_omega first"
        `_pte_clear_eclass'
        exit 111
    }
    
    capture confirm variable `treatment', exact
    if _rc != 0 {
        di as error "[pte] Error: treatment variable '`treatment'' not found"
        `_pte_clear_eclass'
        exit 111
    }
    capture confirm numeric variable `treatment'
    if _rc != 0 {
        di as error "[pte] Error: treatment variable '`treatment'' must be numeric"
        `_pte_clear_eclass'
        exit 111
    }

    tempvar _pte_sample _pte_target_sample
    if "`touse'" != "" {
        capture confirm variable `touse', exact
        if _rc != 0 {
            di as error "[pte] Error: touse variable '`touse'' not found"
            `_pte_clear_eclass'
            exit 111
        }
        capture confirm numeric variable `touse'
        if _rc != 0 {
            di as error "[pte] Error: touse variable '`touse'' must be numeric"
            `_pte_clear_eclass'
            exit 111
        }
        quietly gen byte `_pte_target_sample' = (`touse' != 0 & !missing(`touse'))

        // touse() is a target-reporting mask, not the recursive work sample.
        // Counterfactual ATT_l can require nt=0,...,l-1 rows even when only a
        // later treated period is requested for reporting.
        local _pte_last_cmd `"`e(cmd)'"'
        capture confirm variable _pte_active_sample, exact
        if _rc == 0 {
            capture confirm numeric variable _pte_active_sample
            if _rc != 0 {
                di as error "[pte] Error: persisted active sample '_pte_active_sample' must be numeric"
                di as error "[pte]        Re-run _pte_evolution or _pte_omega to rebuild the bridge state"
                `_pte_clear_eclass'
                exit 111
            }
            quietly gen byte `_pte_sample' = (_pte_active_sample != 0 & !missing(_pte_active_sample))
        }
        else {
            if inlist("`_pte_last_cmd'", "_pte_winsorize", "_pte_eps0_sample", ///
                "_pte_evolution", "_pte_treatdep_evolution", "_pte_omega", "pte") {
                di as error "[pte] Error: current `_pte_last_cmd' state is missing '_pte_active_sample'"
                di as error "[pte]        e(sample) from `_pte_last_cmd' is not the active sample"
                di as error "[pte]        required for ATT estimation"
                di as error "[pte]        Rebuild '_pte_active_sample' before using _pte_att, touse()"
                `_pte_clear_eclass'
                exit 498
            }
            capture confirm matrix e(b)
            if _rc == 0 {
                quietly gen byte `_pte_sample' = e(sample)
            }
            else {
                quietly gen byte `_pte_sample' = 1
            }
        }
    }
    else {
        // ATT must consume the same live sample that identified
        // omega, h_bar_0, and the untreated innovation support. Falling back
        // to the full dataset would reintroduce treated rows excluded upstream.
        local _pte_last_cmd `"`e(cmd)'"'
        capture confirm variable _pte_active_sample, exact
        if _rc == 0 {
            capture confirm numeric variable _pte_active_sample
            if _rc != 0 {
                di as error "[pte] Error: persisted active sample '_pte_active_sample' must be numeric"
                di as error "[pte]        Re-run _pte_evolution or _pte_omega to rebuild the bridge state"
                `_pte_clear_eclass'
                exit 111
            }
            quietly gen byte `_pte_sample' = (_pte_active_sample != 0 & !missing(_pte_active_sample))
        }
        else {
            if inlist("`_pte_last_cmd'", "_pte_winsorize", "_pte_eps0_sample", ///
                "_pte_evolution", "_pte_treatdep_evolution", "_pte_omega", "pte") {
                di as error "[pte] Error: current `_pte_last_cmd' state is missing '_pte_active_sample'"
                di as error "[pte]        e(sample) from `_pte_last_cmd' is not the active sample"
                di as error "[pte]        required for ATT estimation"
                di as error "[pte]        Re-run _pte_att with touse(), or rebuild '_pte_active_sample'"
                `_pte_clear_eclass'
                exit 498
            }
            capture confirm matrix e(b)
            if _rc == 0 {
                quietly gen byte `_pte_sample' = e(sample)
            }
            else {
                quietly gen byte `_pte_sample' = 1
            }
        }
        quietly gen byte `_pte_target_sample' = `_pte_sample'
    }

    quietly count if `_pte_sample'
    if r(N) == 0 {
        di as error "[pte] Error: active ATT work sample is empty"
        `_pte_clear_eclass'
        exit 2000
    }
    quietly count if `_pte_target_sample'
    if r(N) == 0 {
        di as error "[pte] Error: touse() excludes all target observations"
        `_pte_clear_eclass'
        exit 2000
    }

    capture assert inlist(`treatment', 0, 1) if `_pte_sample' & !missing(`treatment')
    if _rc {
        di as error "[pte] Error: treatment variable '`treatment'' must be binary (0/1)"
        di as error "[pte]        Found values outside {0, 1}"
        `_pte_clear_eclass'
        exit 450
    }
    
    // 0.6 Validate panel structure
    capture _xt, trequired
    if _rc != 0 {
        di as error "[pte] Error: data must be xtset as panel"
        `_pte_clear_eclass'
        exit 459
    }
    local panelvar = r(ivar)
    local timevar = r(tvar)
    local pte_xtset_switched = 0
    quietly xtset
    local pte_panel_delta "`r(tdelta)'"
    local pte_restore_xtset "capture quietly xtset `panelvar' `timevar'"
    if "`pte_panel_delta'" != "" {
        local pte_restore_xtset ///
            "capture quietly xtset `panelvar' `timevar', delta(`pte_panel_delta')"
    }
    local pte_time_delta = real("`pte_panel_delta'")
    if missing(`pte_time_delta') | `pte_time_delta' <= 0 {
        local pte_time_delta = 1
    }

    // ATT timing must consume the same panel/time contract that generated the
    // live state. If the caller drifted xtset after _pte_omega or
    // _pte_eps0_sample, recomputing e_i on the current xtset silently changes
    // treat-year and nt while leaving the upstream rho/eps0 state untouched.
    local pte_stored_panel `"`e(idvar)'"'
    if "`pte_stored_panel'" == "" {
        local pte_stored_panel `"`e(id)'"'
    }
    local pte_stored_time `"`e(timevar)'"'
    if "`pte_stored_time'" == "" {
        local pte_stored_time `"`e(time)'"'
    }
    local pte_stored_treatsig `"`e(treatsig)'"'
    if "`pte_stored_treatsig'" == "." {
        local pte_stored_treatsig ""
    }
    local pte_stored_xtdelta = .
    tempname pte_stored_xtdelta_scalar
    capture scalar `pte_stored_xtdelta_scalar' = e(xtdelta)
    if _rc == 0 & !missing(`pte_stored_xtdelta_scalar') {
        local pte_stored_xtdelta = `pte_stored_xtdelta_scalar'
    }
    if "`pte_stored_panel'" == "" {
        local pte_stored_panel "`panelvar'"
    }
    if "`pte_stored_time'" == "" {
        local pte_stored_time "`timevar'"
    }
    if missing(`pte_stored_xtdelta') {
        local pte_stored_xtdelta = `pte_time_delta'
    }
    if `"`pte_stored_treatsig'"' == "" {
        di as error "[pte] Error: live state is missing e(treatsig)"
        di as error "[pte]        ATT must certify the current treatment path before recomputing _pte_treat_year/_pte_nt"
        di as error "[pte]        Re-run _pte_omega/_pte_winsorize/_pte_evolution on the current dataset before _pte_att"
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        `_pte_clear_eclass'
        exit 459
    }
    if `"`pte_stored_panel'"' == "" | `"`pte_stored_time'"' == "" {
        di as error "[pte] Error: live state is missing panel/time metadata required for treatment-law certification"
        di as error "[pte]        Re-run _pte_omega/_pte_winsorize/_pte_evolution on the current dataset before _pte_att"
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        `_pte_clear_eclass'
        exit 459
    }
    capture noisily _pte_assert_setup_current_law, ///
        panelvar(`pte_stored_panel') timevar(`pte_stored_time') ///
        treatment(`treatment') treatsig(`"`pte_stored_treatsig'"') ///
        context("_pte_att")
    local pte_current_law_rc = _rc
    if `pte_current_law_rc' != 0 {
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        `_pte_clear_eclass'
        exit `pte_current_law_rc'
    }
    if "`pte_stored_panel'" != "`panelvar'" | "`pte_stored_time'" != "`timevar'" | ///
        `pte_stored_xtdelta' != `pte_time_delta' {
        capture confirm variable `pte_stored_panel', exact
        if _rc != 0 {
            di as error "[pte] Error: stored panel variable '`pte_stored_panel'' not found"
            di as error "[pte]        Re-run _pte_omega or _pte_eps0_sample on the current dataset"
            `_pte_clear_eclass'
            exit 111
        }
        capture confirm variable `pte_stored_time', exact
        if _rc != 0 {
            di as error "[pte] Error: stored time variable '`pte_stored_time'' not found"
            di as error "[pte]        Re-run _pte_omega or _pte_eps0_sample on the current dataset"
            `_pte_clear_eclass'
            exit 111
        }
        local pte_stored_delta_opt ""
        if !missing(`pte_stored_xtdelta') {
            local pte_stored_delta_opt "delta(`pte_stored_xtdelta')"
        }
        capture quietly xtset `pte_stored_panel' `pte_stored_time', `pte_stored_delta_opt'
        local _pte_restore_stored_xtset_rc = _rc
        if `_pte_restore_stored_xtset_rc' != 0 {
            di as error "[pte] Error: could not restore stored panel structure `pte_stored_panel' `pte_stored_time'"
            di as error "[pte]        Ensure the current data still matches the live state"
            `_pte_clear_eclass'
            exit `_pte_restore_stored_xtset_rc'
        }
        local pte_xtset_switched = 1
        local panelvar "`pte_stored_panel'"
        local timevar "`pte_stored_time'"
        local pte_time_delta = `pte_stored_xtdelta'
    }
    
    // Preserve production-function metadata from the live context
    // before ereturn post rebuilds the ATT result object.
    local pte_prodfunc `"`e(prodfunc)'"'
    local pte_pfunc `"`e(pfunc)'"'
    if `"`pte_prodfunc'"' == "" {
        local pte_prodfunc `"`pte_pfunc'"'
    }
    if `"`pte_pfunc'"' == "" {
        local pte_pfunc `"`pte_prodfunc'"'
    }
    local pte_pf_is_translog = (lower(`"`pte_prodfunc'"') == "translog")
    if !`pte_pf_is_translog' {
        local pte_pf_is_translog = (lower(`"`pte_pfunc'"') == "translog")
    }
    local pte_tl_o3_raw_g = ///
        (`pte_pf_is_translog' & `omegapoly' == 3 & `nsim' > 1)
    local pte_legacy_att_gaussian = ("`legacyattgaussian'" != "")
    local pte_context_treatment `"`e(treatment)'"'
    if "`pte_context_treatment'" != "" {
        if "`pte_context_treatment'" != "`treatment'" {
            di as error "[pte] Error: treatment(`treatment') does not match the current state"
            di as error "[pte]        Last treatment: treatment(`pte_context_treatment')"
            di as error "[pte]        Re-run _pte_omega or _pte_winsorize with treatment(`treatment') before _pte_att"
            if `pte_xtset_switched' {
                `pte_restore_xtset'
            }
            `_pte_clear_eclass'
            exit 198
        }
    }
    tempname pte_rho_1_mat
    local pte_has_rho_1 = 0
    local pte_has_lag_supported = 0
    local pte_lag_treated_supported = .
    capture local pte_lag_treated_supported = e(lag_treated_supported)
    if _rc == 0 {
        local pte_has_lag_supported = 1
    }
    if `pte_has_lag_supported' {
        if `pte_lag_treated_supported' {
            capture confirm matrix e(rho_1)
            if _rc == 0 {
                matrix `pte_rho_1_mat' = e(rho_1)
                local pte_has_rho_1 = 1
            }
        }
    }
    else {
        // Legacy bridge states may not publish lag_treated_supported. In that
        // case preserve the prior fallback to rho_1 matrix presence.
        capture confirm matrix e(rho_1)
        if _rc == 0 {
            matrix `pte_rho_1_mat' = e(rho_1)
            local pte_has_rho_1 = 1
        }
    }
    
    // 0.7 Validate evolution parameters exist (from _pte_evolution)
    capture confirm matrix e(rho_0)
    local has_rho_matrix = (_rc == 0)
    
    if !`has_rho_matrix' {
        di as error "[pte] Error: evolution parameters not found"
        di as error "[pte] Please run _pte_evolution first"
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        `_pte_clear_eclass'
        exit 198
    }
    
    // 0.8 Extract evolution parameters from e(rho_0)
    tempname rho_0_mat
    matrix `rho_0_mat' = e(rho_0)
    local ncols_rho = colsof(`rho_0_mat')
    
    if `ncols_rho' != `omegapoly' + 1 {
        di as error "[pte] Error: rho_0 matrix has `ncols_rho' columns, expected " (`omegapoly' + 1)
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        `_pte_clear_eclass'
        exit 198
    }
    
    // Extract rho coefficients into scalars
    scalar _pte_att_rho0 = `rho_0_mat'[1,1]
    scalar _pte_att_rho1 = `rho_0_mat'[1,2]
    if `omegapoly' >= 2 scalar _pte_att_rho2 = `rho_0_mat'[1,3]
    if `omegapoly' >= 3 scalar _pte_att_rho3 = `rho_0_mat'[1,4]
    if `omegapoly' >= 4 scalar _pte_att_rho4 = `rho_0_mat'[1,5]
    forvalues _pte_r = 0/`omegapoly' {
        if missing(_pte_att_rho`_pte_r') {
            di as error "[pte] Error: untreated evolution coefficient rho`_pte_r' is missing"
            di as error "[pte]        Re-run _pte_evolution/_pte_omega before _pte_att"
            if `pte_xtset_switched' {
                `pte_restore_xtset'
            }
            `_pte_clear_eclass'
            exit 198
        }
    }
    
    // 0.9 Optional rho usage verification ( Task 7)
    if "`verify'" != "" {
        _pte_verify_rho_usage, verbose strict
        if r(verified) == 0 {
            if `pte_xtset_switched' {
                `pte_restore_xtset'
            }
            `_pte_clear_eclass'
            exit 198
        }
    }
    
    // ================================================================
    // Step 1: Extract eps0 pool and read sigma from
    // Must be done BEFORE filtering, since eps0 is on control obs
    // ================================================================
    
    // 1.1 Check if _pte_eps0 variable exists (from _pte_eps0_sample)
    capture confirm variable _pte_eps0, exact
    local has_eps0_var = (_rc == 0)
    
    if !`has_eps0_var' {
        di as error "[pte] Error: variable '_pte_eps0' not found"
        di as error "[pte] Please run _pte_eps0_sample first"
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        `_pte_clear_eclass'
        exit 111
    }
    capture confirm numeric variable _pte_eps0
    if _rc != 0 {
        di as error "[pte] Error: variable '_pte_eps0' must be numeric"
        di as error "[pte]        Run _pte_eps0_sample again to rebuild the untreated innovation pool"
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        `_pte_clear_eclass'
        exit 111
    }
    
    // 1.2 Persist caller data before restricting ATT work to touse().
    // Event time must be anchored to each firm's full observed treatment path,
    // but only to observed 0->1 entries. A firm already treated at its first
    // observed nonmissing state is left-censored and must keep missing timing
    // metadata rather than being assigned a fabricated e_i.
    tempfile eps0_pool_file eps0_sample_file pte_att_orig_data pte_att_output_file
    tempvar pte_att_obsid pte_att_treat_year_full pte_att_entry_obs
    quietly bysort `panelvar' (`timevar'): gen byte `pte_att_entry_obs' = ///
        (L.`treatment' == 0 & `treatment' == 1) if _n > 1
    quietly bysort `panelvar': egen double `pte_att_treat_year_full' = ///
        min(cond(`pte_att_entry_obs' == 1, `timevar', .))
    quietly gen long `pte_att_obsid' = _n
    quietly save `pte_att_orig_data', replace

    // 1.3 Extract the untreated innovation pool from the full live
    // state before touse() narrows the target treated sample. Proposition 4.3
    // identifies G^0_epsilon first and then applies it to the treated targets;
    // the shock pool must therefore remain independent of subgroup selection.
    //
    // When the live state publishes the explicit support indicator
    // from _pte_eps0_sample, use that identified support rather than every
    // nonmissing _pte_eps0 cell. This prevents stale or polluted values outside
    // G^0_epsilon from entering the empirical innovation pool.
    local pte_eps0window = 0
    capture local pte_eps0window = e(eps0window)
    if _rc != 0 | missing(`pte_eps0window') {
        local pte_eps0window = 0
    }

    local pte_eps0_pool_if "!missing(_pte_eps0)"
    capture confirm variable _pte_eps0_ind, exact
    if _rc != 0 {
        di as error "[pte] Error: variable '_pte_eps0_ind' not found"
        if `pte_eps0window' > 0 {
            di as error "[pte]        Windowed eps0 support cannot be rebuilt safely without the exact support indicator"
        }
        else {
            di as error "[pte]        ATT requires the exact untreated innovation support published by _pte_eps0_sample"
            di as error "[pte]        and cannot safely fall back to all nonmissing _pte_eps0 values"
        }
        di as error "[pte]        Re-run _pte_eps0_sample/_pte_winsorize or keep _pte_eps0_ind in the current data"
        // No ATT-owned data bridge has been materialized yet. Reloading the
        // saved dataset here would sever the caller's live e(sample) contract
        // even though the only work so far is tempvar bookkeeping.
        `pte_restore_xtset'
        `_pte_clear_eclass'
        exit 111
    }
    capture confirm numeric variable _pte_eps0_ind
    if _rc != 0 {
        di as error "[pte] Error: variable '_pte_eps0_ind' must be numeric"
        di as error "[pte]        Run _pte_eps0_sample again to rebuild the untreated innovation support"
        `pte_restore_xtset'
        `_pte_clear_eclass'
        exit 111
    }
    capture assert inlist(_pte_eps0_ind, 0, 1) if !missing(_pte_eps0_ind)
    if _rc != 0 {
        di as error "[pte] Error: variable '_pte_eps0_ind' must be binary (0/1)"
        di as error "[pte]        _pte_eps0_ind is the exact untreated innovation support indicator from _pte_eps0_sample"
        `pte_restore_xtset'
        `_pte_clear_eclass'
        exit 450
    }

    // Shield the ATT working copy from stale shocks outside the identified
    // untreated support. Proposition 4.3 first identifies G^0_epsilon and
    // only then simulates counterfactual paths; support-external _pte_eps0
    // values must be inert even if they remain in the caller's dataset.
    quietly replace _pte_eps0 = . if _pte_eps0_ind != 1
    local pte_eps0_pool_if "_pte_eps0_ind == 1 & !missing(_pte_eps0)"

    quietly count if `pte_eps0_pool_if'
    local N_eps0_pool = r(N)

    if `N_eps0_pool' == 0 {
        di as error "[pte] Error: no nonmissing _pte_eps0 observations found in the live state"
        di as error "[pte]        ATT simulation requires an identified untreated innovation pool"
        di as error "[pte]        Run _pte_omega or _pte_eps0_sample before running _pte_att"
        // This support gate may have already masked support-external _pte_eps0
        // values in the working copy; reload the caller snapshot so failed ATT
        // runs never mutate upstream bridge state.
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_clear_eclass'
        exit 2000
    }
    
    if `N_eps0_pool' < 30 {
        if "`nodiagnose'" == "" {
            di as text "{bf:Warning}: Small eps0 pool size (N=`N_eps0_pool' < 30)"
            di as text "          Counterfactual simulation remains feasible but may be noisy"
        }
    }
    
    // 1.4 Persist eps0 pool for later shock generation.
    preserve
        quietly keep if `pte_eps0_pool_if'
        quietly keep _pte_eps0
        quietly gen long _pte_eps0_id = _n
        quietly save `eps0_pool_file'
    restore

    // After the empirical pool is fixed, downstream ATT recursion should no
    // longer depend on any live _pte_eps0 columns in the working sample.
    // Remove them from the working copy so stale support-external shocks
    // cannot leak into later sample sorting, simulation, or merge steps.
    capture drop _pte_eps0
    capture drop _pte_eps0_ind

    // Restrict the ATT work sample only after the untreated innovation pool is
    // fixed. This allows target treated subgroups to reuse the same G^0_epsilon.
    quietly keep if `_pte_sample'

    // 1.5 Read sigma values from (_pte_omega / _pte_winsorize)
    local sigma_eps = e(sigma_eps)
    if missing(`sigma_eps') | `sigma_eps' < 0 {
        di as error "[pte] Error: e(sigma_eps) missing or invalid"
        di as error "[pte] Please run _pte_omega before _pte_att"
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_clear_eclass'
        exit 198
    }
    
    local sigma_eps_trim = e(sigma_eps_trim)
    if missing(`sigma_eps_trim') | `sigma_eps_trim' < 0 {
        di as error "[pte] Error: e(sigma_eps_trim) missing or invalid"
        di as error "[pte] Please run _pte_omega before _pte_att"
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_clear_eclass'
        exit 198
    }
    
    // 1.5 Use the upstream eps0 trimming contract as the single source of truth.
    local upstream_trimeps = .
    capture local upstream_trimeps = e(trimeps)
    if _rc != 0 | missing(`upstream_trimeps') {
        di as error "[pte] Error: e(trimeps) missing from upstream omega state"
        di as error "[pte]        Re-run _pte_omega before _pte_att"
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_clear_eclass'
        exit 198
    }
    if "`notrimeps'" != "" & `upstream_trimeps' == 1 {
        di as error "[pte] Error: notrimeps conflicts with the upstream trimmed eps0 state"
        di as error "[pte]        Re-run _pte_omega, notrimeps before _pte_att, notrimeps"
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_clear_eclass'
        exit 198
    }
    if "`notrimeps'" == "" & `upstream_trimeps' == 0 {
        local notrimeps "notrimeps"
    }
    if `upstream_trimeps' == 0 {
        local sigma_eps_trim = `sigma_eps'
    }
    
    // ================================================================
    // Diagnostic header
    // ================================================================
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "{hline 70}"
        di as text "ATT Estimation"
        di as text "{hline 70}"
        di as text "  Polynomial order:     " as result "`omegapoly'"
        di as text "  ATT poly order:       " as result "`attpoly'"
        di as text "  ATT periods:          " as result "0 to `attperiods'"
        di as text "  Simulation paths:     " as result "`nsim'"
        if `preserve_rng' {
            di as text "  Inner seed:           " as result "current RNG stream"
        }
        else {
            di as text "  Inner seed:           " as result "`seed'"
        }
        di as text "  eps0 pool size:       " as result %10.0fc `N_eps0_pool'
        di as text "  sigma_eps (raw):      " as result %10.6f `sigma_eps'
        di as text "  sigma_eps (trimmed):  " as result %10.6f `sigma_eps_trim'
        if "`notrimeps'" != "" {
            di as text "  notrimeps:            " as result "ON (canonical Gaussian track uses raw sigma)"
        }
        di as text "{hline 70}"
    }
    
    // ================================================================
    // Step 2: Treated sample selection
    // Delegates to _pte_att_filter_sample (modular, reusable)
    // ================================================================
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "Step 1: Treated Sample Selection"
    }
    
    // 2.0 Always recompute event time from the current treatment() context.
    // e_i is a firm-level object and must remain invariant to touse(); using
    // only the contracted ATT sample can shift e_i forward when the first
    // treated row is excluded, which in turn corrupts nt and drops valid firms.
    // Left-censored treated firms keep missing timing metadata because the
    // sample never reveals an observed 0->1 entry.

    local _pte_legacy_treat_year_var ""
    if "`legacypooledeps0'" != "" {
        capture confirm numeric variable treat_yr0, exact
        if _rc == 0 {
            local _pte_legacy_treat_year_var "treat_yr0"
        }
    }

    capture confirm variable _pte_treat_year, exact
    if _rc == 0 {
        quietly drop _pte_treat_year
    }
    quietly gen double _pte_treat_year = `pte_att_treat_year_full'
    if "`_pte_legacy_treat_year_var'" != "" {
        quietly replace _pte_treat_year = `_pte_legacy_treat_year_var'
    }
    label variable _pte_treat_year "Observed treatment entry year (recomputed from full treatment path)"

    capture confirm variable treat_yr0, exact
    if _rc == 0 {
        quietly drop treat_yr0
    }
    quietly gen double treat_yr0 = _pte_treat_year
    label variable treat_yr0 "Observed treatment entry year (recomputed from full treatment path)"

    capture confirm variable _pte_nt, exact
    if _rc == 0 {
        quietly drop _pte_nt
    }
    quietly gen double _pte_nt = (`timevar' - _pte_treat_year) / `pte_time_delta'
    quietly replace _pte_nt = . if missing(_pte_treat_year)
    quietly replace _pte_nt = round(_pte_nt) if ///
        !missing(_pte_nt) & abs(_pte_nt - round(_pte_nt)) <= 1e-10
    label variable _pte_nt "Relative time to observed treatment entry (anchored to full treatment path)"
    
    // 2.1 Call modular filter (TASK-E3-001-07: integration)
    local _verbose_opt ""
    if "`nodiagnose'" == "" {
        local _verbose_opt "verbose"
    }
    capture noisily _pte_att_filter_sample, attperiods_max(`attperiods') replace `_verbose_opt'
    if _rc != 0 {
        local _pte_att_filter_rc = _rc
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_clear_eclass'
        exit `_pte_att_filter_rc'
    }
    
    // 2.2 Capture r() return values from filter for later e() storage
    local N_original = r(N_original)
    local N_control = r(N_control)
    local N_outside = r(N_outside_window)
    local N_filtered = r(N_filtered)
    local N_treated_firms = r(N_treated_firms)
    
    // ================================================================
    // Step 2b: nt=-1 validation
    // Ensures every treated firm has nt=-1 for L.omega at nt=0
    // Must run AFTER sample filtering, BEFORE path expansion
    // ================================================================
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "Step 1b: nt=-1 Validation"
    }
    
    // Build option string for validation call
    local _validate_opts "firm(`panelvar') nt(_pte_nt)"
    
    // Pass omega if available (for debug mode L.omega check)
    capture confirm variable omega, exact
    if _rc == 0 {
        local _validate_opts "`_validate_opts' omega(omega)"
    }
    
    // Pass verbose/debug flags
    if "`nodiagnose'" == "" {
        local _validate_opts "`_validate_opts' verbose"
    }
    
    if "`legacypooledeps0'" == "" {
        // Call validation - errors propagate automatically (Task 7)
        capture noisily _pte_validate_nt_neg1, `_validate_opts'
        if _rc != 0 {
            local _pte_att_nt_rc = _rc
            // Error already displayed by _pte_validate_nt_neg1
            capture quietly use `pte_att_orig_data', clear
            `pte_restore_xtset'
            `_pte_clear_eclass'
            exit `_pte_att_nt_rc'
        }

        // Capture validation return values (Task 8: verbose output)
        local N_neg1 = r(n_neg1)
        local N_validated_firms = r(n_firms)
        local N_filtered = _N
        local N_treated_firms = `N_validated_firms'
    }
    else {
        quietly count if _pte_nt == -1
        local N_neg1 = r(N)
        tempvar _pte_legacy_att_tag
        quietly egen byte `_pte_legacy_att_tag' = tag(`panelvar')
        quietly count if `_pte_legacy_att_tag' == 1
        local N_validated_firms = r(N)
        local N_filtered = _N
        local N_treated_firms = `N_validated_firms'
    }
    
    if "`nodiagnose'" == "" {
        di as text "  Validated: `N_neg1' nt=-1 obs, `N_validated_firms' firms"
    }

    // ================================================================
    // Step 2c: Require treatment-onset support inside the ATT work sample
    // A firm left with only nt=-1 after touse()/window selection provides
    // an anchor but cannot contribute any ATT_l, and must not alter the
    // simulation sample or treated-firm counts.
    // ================================================================

    if "`legacypooledeps0'" == "" {
        tempvar _pte_has_nt0
        quietly bysort `panelvar': egen byte `_pte_has_nt0' = max(_pte_nt == 0)
        quietly count if `_pte_has_nt0' == 0
        local N_missing_nt0_obs = r(N)
        local N_missing_nt0_firms = 0

        if `N_missing_nt0_obs' > 0 {
            capture drop _pte_att_drop_nt0_tag
            quietly bysort `panelvar' (`timevar'): gen byte _pte_att_drop_nt0_tag = ///
                (_n == 1) if `_pte_has_nt0' == 0
            quietly count if _pte_att_drop_nt0_tag == 1
            local N_missing_nt0_firms = r(N)
            capture drop _pte_att_drop_nt0_tag

            if "`nodiagnose'" == "" {
                di as error ""
                di as error "{bf:pte warning}: `N_missing_nt0_firms' firms missing nt=0 in the active ATT sample — dropped"
                di as error "{hline 70}"
            }

            quietly drop if `_pte_has_nt0' == 0
        }

        quietly count
        local N_filtered = r(N)
        if `N_filtered' == 0 {
            di as error "[pte] Error: no treated firms remain with nt=0 after touse()/window selection"
            capture quietly use `pte_att_orig_data', clear
            `pte_restore_xtset'
            `_pte_clear_eclass'
            exit 2000
        }
        capture drop _pte_att_treated_tag
        quietly bysort `panelvar' (`timevar'): gen byte _pte_att_treated_tag = (_n == 1)
        quietly count if _pte_att_treated_tag == 1
        local N_treated_firms = r(N)
        capture drop _pte_att_treated_tag

        if `N_treated_firms' == 0 {
            di as error "[pte] Error: no treated firms remain with nt=0 after touse()/window selection"
            capture quietly use `pte_att_orig_data', clear
            `pte_restore_xtset'
            `_pte_clear_eclass'
            exit 2000
        }
    }

    // ================================================================
    // Step 2d: Prune ATT-dead rows before shock indexing
    // Rows that never enter any TT_l and never support a later recursion
    // state must not consume shock slots. Keep anchors (nt=-1) and all rows
    // up to each firm's last observed post-treatment omega, including
    // intermediate missing periods that are still needed to recurse forward.
    // ================================================================

    if "`legacypooledeps0'" == "" {
        tempvar _pte_last_obs_nt _pte_dead_tail_tag _pte_no_postomega_tag
        quietly bysort `panelvar': egen double `_pte_last_obs_nt' = ///
            max(cond(inrange(_pte_nt, 0, `attperiods') & !missing(omega), _pte_nt, .))

        quietly gen byte `_pte_dead_tail_tag' = ///
            (_pte_nt >= 0 & !missing(`_pte_last_obs_nt') & _pte_nt > `_pte_last_obs_nt')
        quietly count if `_pte_dead_tail_tag' == 1
        local N_dead_tail_obs = r(N)

        quietly bysort `panelvar' (`timevar'): gen byte `_pte_no_postomega_tag' = ///
            (_n == 1) if missing(`_pte_last_obs_nt')
        quietly count if `_pte_no_postomega_tag' == 1
        local N_no_postomega_firms = r(N)
        capture drop `_pte_no_postomega_tag'

        if `N_dead_tail_obs' > 0 | `N_no_postomega_firms' > 0 {
            if "`nodiagnose'" == "" {
                if `N_no_postomega_firms' > 0 {
                    di as text "{bf:Warning}: dropping `N_no_postomega_firms' treated firms with no observed omega in nt=0..`attperiods'"
                }
                if `N_dead_tail_obs' > 0 {
                    di as text "{bf:Warning}: dropping `N_dead_tail_obs' ATT-dead tail observations beyond each firm's last observed omega"
                }
            }
            quietly drop if missing(`_pte_last_obs_nt') | `_pte_dead_tail_tag' == 1
        }
    }

    quietly count
    local N_filtered = r(N)
    if `N_filtered' == 0 {
        di as error "[pte] Error: no treated observations remain with observed omega support in nt=0..`attperiods'"
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_clear_eclass'
        exit 2000
    }

    capture drop _pte_att_treated_tag
    quietly bysort `panelvar' (`timevar'): gen byte _pte_att_treated_tag = (_n == 1)
    quietly count if _pte_att_treated_tag == 1
    local N_treated_firms = r(N)
    capture drop _pte_att_treated_tag

    if `N_treated_firms' == 0 {
        di as error "[pte] Error: no treated firms remain with observed omega support in nt=0..`attperiods'"
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_clear_eclass'
        exit 2000
    }
    
    // ================================================================
    // Step 3: Path expansion (nsim > 1)
    //   expand $npath
    //   g tr_id = _n
    //   bys firm nt: g copy_id = _n
    //   egen firm_id = group(firm copy_id)
    //   tsset firm_id nt
    // ================================================================
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "Step 2: Path Expansion"
    }
    
    local expanded = 0
    
    if `nsim' > 1 {
        local _pte_expand_obs = _N * `nsim'
        local _pte_expand_max_obs = 5000000
        if `_pte_expand_obs' > `_pte_expand_max_obs' {
            di as error "[pte] Error: nsim(`nsim') would expand the ATT work sample to " ///
                %21.0fc `_pte_expand_obs' " observations"
            di as error "[pte]        Maximum allowed expansion is " ///
                %21.0fc `_pte_expand_max_obs' " observations"
            di as error "[pte]        Reduce nsim(), shorten attperiods(), or narrow the active treated sample"
            capture quietly use `pte_att_orig_data', clear
            `pte_restore_xtset'
            `_pte_clear_eclass'
            exit 908
        }
        // 3.1 Expand each observation nsim times
        quietly expand `nsim'
        local expanded = 1
        
        // 3.2 Generate copy_id: within firm-nt copy number
        capture drop _pte_copy_id
        quietly bysort `panelvar' _pte_nt: gen long _pte_copy_id = _n
        
        // 3.3 Generate firm_sim_id: unique panel ID for each path
        capture drop _pte_firm_sim_id
        quietly egen long _pte_firm_sim_id = group(`panelvar' _pte_copy_id)
        
        // 3.4 Re-tsset with new panel ID
        quietly tsset _pte_firm_sim_id _pte_nt
        local pte_xtset_switched = 1
        
        quietly count
        local N_expanded = r(N)
        
        if "`nodiagnose'" == "" {
            di as text "  Expanded by nsim:       " as result "`nsim'"
            di as text "  Total obs after expand: " as result %10.0fc `N_expanded'
        }
    }
    else {
        // Keep the downstream counterfactual recursion on one panel-id
        // contract. Some legacy Gaussian branches use _pte_firm_sim_id even
        // when nsim == 1; in that case it is just the original treated-panel
        // id crossed with a single copy.
        capture drop _pte_copy_id
        quietly gen byte _pte_copy_id = 1
        capture drop _pte_firm_sim_id
        quietly egen long _pte_firm_sim_id = group(`panelvar' _pte_copy_id)
        if "`nodiagnose'" == "" {
            di as text "  nsim = 1, no expansion needed"
        }
    }
    
    // ================================================================
    // Step 4: Prepare eps0 shock sequences (dual-track)
    //
    // Track 1 (raw):
    //   Defaults to bsample from the actual eps0 residuals (non-parametric),
    //   except for the official translog Gaussian-law branches preserved below.
    // Track 2 (trim):
    //   Always: rnormal(0, sigma_eps_trim) (parametric, trimmed sd)
    // ================================================================
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "Step 3: eps0 Shock Sequence Preparation"
    }
    
    // 4.0 Save caller RNG state before any internal simulation draws.
    // Fixed-seed paths restore the caller state on exit, but preserverng is
    // the grouped-bootstrap contract: consume the live stream and leave the
    // advanced RNG state with the caller.
    local orig_rngstate = c(rngstate)
    local _pte_restore_rngstate_failure "capture set rngstate `orig_rngstate'"
    local _pte_restore_rngstate_success ""
    if !`preserve_rng' {
        local _pte_restore_rngstate_success "capture set rngstate `orig_rngstate'"
    }
    
    // 4.1 Generate sequential observation ID for eps0 matching
    // Prefix invariance requires lower horizons to keep the same shock prefix
    // when users request additional future periods. Order by nt first so any
    // newly requested nt = L+1 rows are appended after the existing nt <= L
    // prefix instead of being interleaved by panel-major sort order.
    if `legacy_att_panel_order' {
        if `expanded' {
            quietly sort _pte_firm_sim_id _pte_nt
        }
        else {
            quietly sort `panelvar' _pte_nt
        }
    }
    else {
        if `expanded' {
            quietly sort _pte_nt _pte_firm_sim_id
        }
        else {
            quietly sort _pte_nt `panelvar'
        }
    }
    capture drop _pte_tr_id
    quietly gen long _pte_tr_id = _n
    label variable _pte_tr_id "Sequential observation ID for eps0 matching"
    
    quietly summarize _pte_tr_id
    local nobs = r(max)
    
    // 4.1b Validate sigma values
    if `sigma_eps' < 0 {
        di as error "[pte] Error: sigma_eps must be non-negative (got `sigma_eps')"
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_restore_rngstate_failure'
        `_pte_clear_eclass'
        exit 198
    }
    if `sigma_eps_trim' < 0 {
        di as error "[pte] Error: sigma_eps_trim must be non-negative (got `sigma_eps_trim')"
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_restore_rngstate_failure'
        `_pte_clear_eclass'
        exit 198
    }
    
    // 4.2 Prepare eps0 sample in tempfile
    preserve
        if (`pte_tl_o3_raw_g' & "`legacypooledeps0'" != "") | `pte_legacy_att_gaussian' {
            quietly sort _pte_firm_sim_id _pte_nt
            quietly tsset _pte_firm_sim_id _pte_nt
            capture drop _pte_eps0_draw
            capture drop _pte_eps0_trim_draw
            tempvar _pte_eps0_target_draw _pte_eps0_trim_target_draw
            quietly gen double _pte_eps0_draw = .
            quietly gen double _pte_eps0_trim_draw = .
            quietly gen double `_pte_eps0_target_draw' = .
            quietly gen double `_pte_eps0_trim_target_draw' = .
            if !`preserve_rng' {
                set seed `seed'
            }
            quietly replace `_pte_eps0_target_draw' = rnormal(0, `sigma_eps') ///
                if _pte_nt == 0
            quietly replace `_pte_eps0_trim_target_draw' = rnormal(0, `sigma_eps_trim') ///
                if _pte_nt == 0
            forvalues _pte_s = 1/`attperiods' {
                quietly replace `_pte_eps0_target_draw' = rnormal(0, `sigma_eps') ///
                    if _pte_nt == `_pte_s'
                quietly replace `_pte_eps0_trim_target_draw' = rnormal(0, `sigma_eps_trim') ///
                    if _pte_nt == `_pte_s'
            }
            forvalues _pte_s = 0/`attperiods' {
                local _pte_draw_nt = `_pte_s' - 1
                quietly replace _pte_eps0_draw = F.`_pte_eps0_target_draw' ///
                    if _pte_nt == `_pte_draw_nt' & F._pte_nt == `_pte_s'
                quietly replace _pte_eps0_trim_draw = F.`_pte_eps0_trim_target_draw' ///
                    if _pte_nt == `_pte_draw_nt' & F._pte_nt == `_pte_s'
            }
        }
        else if `pte_tl_o3_raw_g' {
            // Official translog order-3 simulation replaces the raw empirical
            // eps0 support with Gaussian draws once the ATT sample is expanded
            // into multiple paths. Preserve that law here so notrimeps and the
            // reported raw track match the reference DO behavior.
            quietly clear
            quietly set obs `nobs'
            quietly gen long _pte_tr_id = _n

            if !`preserve_rng' {
                set seed `seed'
            }
            quietly gen double _pte_eps0_draw = rnormal(0, `sigma_eps')
            quietly gen double _pte_eps0_trim_draw = rnormal(0, `sigma_eps_trim')
        }
        else {
            quietly use `eps0_pool_file', clear
            
            if `nsim' == 1 {
                // --- nsim=1: bsample (non-parametric) for raw track ---
                // Exception: official translog order-1 point estimation
                // replaces the raw empirical eps0 support with Gaussian
                // draws after bsample has aligned the tr_id/nobs mapping.
                quietly summarize _pte_eps0_id
                scalar _pte_nid = r(max)
                scalar _pte_copy = ceil(`nobs' / _pte_nid)
                quietly expand _pte_copy
                capture drop _pte_eps0_id
                quietly gen long _pte_eps0_id = _n
                
                if !`preserve_rng' {
                    set seed `seed'
                }
                quietly bsample `nobs', cluster(_pte_eps0_id) idcluster(_pte_tr_id)
                capture drop _pte_eps0_id

                if `pte_pf_is_translog' & `omegapoly' == 1 {
                    // Preserve the Translog/order-1 Gaussian raw law, but
                    // continue the bsample RNG stream instead of restarting the
                    // same seed before drawing the raw shocks.
                    quietly replace _pte_eps0 = rnormal(0, `sigma_eps')
                }
                
                // Canonical track is always Gaussian; under notrimeps the
                // upstream sigma alias makes sigma_eps_trim = sigma_eps. Use
                // the live RNG stream after the raw-track draw so raw and trim
                // tracks are not restarted from the same seed.
                if `legacy_att_panel_order' & !`preserve_rng' {
                    set seed `seed'
                }
                quietly gen double _pte_eps0_trim = rnormal(0, `sigma_eps_trim')
            }
            else {
                // --- nsim>1: raw track remains empirical, trim track Gaussian ---
                // Need to expand eps0 pool to match nobs (= N_filtered * nsim)
                quietly summarize _pte_eps0_id
                scalar _pte_nid = r(max)
                scalar _pte_copy = ceil(`nobs' / _pte_nid)
                quietly expand _pte_copy
                capture drop _pte_eps0_id
                quietly gen long _pte_eps0_id = _n
                
                if !`preserve_rng' {
                    set seed `seed'
                }
                quietly bsample `nobs', cluster(_pte_eps0_id) idcluster(_pte_tr_id)
                capture drop _pte_eps0_id
                // Continue the RNG stream after bsample; resetting to the same
                // seed would couple the empirical raw track with the Gaussian
                // trim track.
                quietly gen double _pte_eps0_trim = rnormal(0, `sigma_eps_trim')
            }
            
            quietly rename _pte_eps0 _pte_eps0_draw
            quietly rename _pte_eps0_trim _pte_eps0_trim_draw
        }

        // Keep only needed variables
        quietly keep _pte_tr_id _pte_eps0_draw _pte_eps0_trim_draw
        quietly save `eps0_sample_file'
    restore
    
    // 4.3 Merge eps0 shocks back to treated sample
    capture drop _pte_eps0_draw
    capture drop _pte_eps0_trim_draw
    quietly merge 1:1 _pte_tr_id using `eps0_sample_file', nogen keep(3)
    
    label variable _pte_eps0_draw "eps0 shock draw (raw track)"
    label variable _pte_eps0_trim_draw "eps0 shock draw (canonical sigma track)"
    
    // 4.4 Re-tsset after merge
    if `expanded' {
        quietly tsset _pte_firm_sim_id _pte_nt
    }
    else {
        quietly xtset `panelvar' _pte_nt
    }
    local pte_xtset_switched = 1

    tempvar _pte_lomega_anchor
    quietly gen double `_pte_lomega_anchor' = L.omega if _pte_nt == 0
    quietly count if _pte_nt == 0 & missing(`_pte_lomega_anchor')
    local N_missing_anchor_omega = r(N)
    if `N_missing_anchor_omega' > 0 & "`legacypooledeps0'" == "" {
        tempvar _pte_bad_anchor_tag
        quietly egen byte `_pte_bad_anchor_tag' = tag(`panelvar') ///
            if _pte_nt == 0 & missing(`_pte_lomega_anchor')
        quietly count if `_pte_bad_anchor_tag' == 1
        local N_missing_anchor_firms = r(N)
        di as error "[pte] Error: counterfactual path has missing L.omega at nt=0"
        di as error "[pte]        Missing anchor observations: `N_missing_anchor_omega'"
        di as error "[pte]        Affected treated firms: `N_missing_anchor_firms'"
        di as error "[pte]        Counterfactual simulation must start from observed omega at nt=-1"
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_restore_rngstate_failure'
        `_pte_clear_eclass'
        exit 3002
    }
    
    // 4.5 Compute eps0 diagnostics (always, for e() returns)
    quietly summarize _pte_eps0_draw
    local eps0_N_all = r(N)
    local eps0_mean_all = r(mean)
    local eps0_sd_all = r(sd)
    quietly summarize _pte_eps0_trim_draw
    local eps0t_mean_all = r(mean)
    local eps0t_sd_all = r(sd)
    
    if "`nodiagnose'" == "" {
        quietly summarize _pte_eps0_draw
        local eps0_N = r(N)
        local eps0_mean = r(mean)
        local eps0_sd = r(sd)
        local eps0_min = r(min)
        local eps0_max = r(max)
        
        quietly summarize _pte_eps0_trim_draw
        local eps0t_N = r(N)
        local eps0t_mean = r(mean)
        local eps0t_sd = r(sd)
        local eps0t_min = r(min)
        local eps0t_max = r(max)
        
        // Degenerate innovation laws with sigma=0 are valid and should
        // satisfy diagnostics when the simulated draws are exactly zero.
        local diag_zero_tol = 1e-12

        // Compute tolerance bounds for mean
        local tol_mean = 3 * `sigma_eps' / sqrt(`eps0_N')
        local tol_mean_t = 3 * `sigma_eps_trim' / sqrt(`eps0t_N')
        
        // Validation status
        if abs(`sigma_eps') <= `diag_zero_tol' {
            local mean_ok = (abs(`eps0_mean') <= `diag_zero_tol')
            local sd_ok = (abs(`eps0_sd' - `sigma_eps') <= `diag_zero_tol')
        }
        else {
            local mean_ok = (abs(`eps0_mean') <= `tol_mean')
            local sd_ok = (abs(`eps0_sd' - `sigma_eps') / `sigma_eps' < 0.05)
        }

        if abs(`sigma_eps_trim') <= `diag_zero_tol' {
            local mean_t_ok = (abs(`eps0t_mean') <= `diag_zero_tol')
            local sd_t_ok = (abs(`eps0t_sd' - `sigma_eps_trim') <= `diag_zero_tol')
        }
        else {
            local mean_t_ok = (abs(`eps0t_mean') <= `tol_mean_t')
            local sd_t_ok = (abs(`eps0t_sd' - `sigma_eps_trim') / `sigma_eps_trim' < 0.05)
        }
        
        di as text "  --- Raw track ---"
        di as text "  N shocks:               " as result %10.0fc `eps0_N'
        di as text "  Mean:                   " as result %10.6f `eps0_mean' _c
        if `mean_ok' di as text "  [OK]"
        else di as error "  [WARNING: |mean| > 3*sigma/sqrt(N)]"
        di as text "  Std.Dev:                " as result %10.6f `eps0_sd' _c
        if `sd_ok' di as text "  [OK]"
        else di as error "  [WARNING: >5% deviation from sigma]"
        di as text "  Range:                  [" as result %8.4f `eps0_min' as text ", " as result %8.4f `eps0_max' as text "]"
        
        di as text "  --- Trim track ---"
        di as text "  N shocks:               " as result %10.0fc `eps0t_N'
        di as text "  Mean:                   " as result %10.6f `eps0t_mean' _c
        if `mean_t_ok' di as text "  [OK]"
        else di as error "  [WARNING: |mean| > 3*sigma/sqrt(N)]"
        di as text "  Std.Dev:                " as result %10.6f `eps0t_sd' _c
        if `sd_t_ok' di as text "  [OK]"
        else di as error "  [WARNING: >5% deviation from sigma_trim]"
        di as text "  Range:                  [" as result %8.4f `eps0t_min' as text ", " as result %8.4f `eps0t_max' as text "]"
    }
    
    // ================================================================
    // Step 5: Recursive counterfactual simulation (dual-track)
    //
    // CRITICAL: Use ONLY h_bar_0 (untreated evolution function)
    //   omega_0 = rho0 + rho1*L.omega + rho2*(L.omega)^2 + ... + eps0
    //   NOT using gamma or delta (treatment interaction terms)
    //
    // For nt=0: use L.omega (actual lagged productivity at nt=-1)
    // For nt>=1: use L.omega_0 (lagged counterfactual)
    //
    // Dual-track: omega_0 (raw eps0) and omega_0_trim (trimmed eps0)
    // ================================================================
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "Step 4: Counterfactual Simulation (dual-track)"
    }
    // Paper Section 6.3.3 and the official ATT DO files trim eps0 but do not
    // hard-clip the simulated counterfactual omega_0 path. Keep the legacy
    // noclipomg/cliprange() parser tokens for backward compatibility, but the
    // canonical ATT path now runs without hidden clipping by default so the
    // live recursion matches the paper/DO law.
    local _pte_clip_enabled = 0
    local _pte_clip_tau = `cliprange'
    local _pte_clip_seen = 0
    local _pte_clip_upper_runtime = 0
    local _pte_clip_lower_runtime = 0
    local _pte_clip_max_runtime = .
    local _pte_clip_min_runtime = .
    
    // 5.1 Initialize counterfactual variables - raw track
    capture drop _pte_omega_0
    quietly gen double _pte_omega_0 = .
    label variable _pte_omega_0 "Counterfactual productivity (raw track)"
    
    if `omegapoly' >= 2 {
        capture drop _pte_omega_02
        quietly gen double _pte_omega_02 = .
    }
    if `omegapoly' >= 3 {
        capture drop _pte_omega_03
        quietly gen double _pte_omega_03 = .
    }
    if `omegapoly' >= 4 {
        capture drop _pte_omega_04
        quietly gen double _pte_omega_04 = .
    }
    
    // 5.2 Initialize counterfactual variables - trim track
    capture drop _pte_omega_0_trim
    quietly gen double _pte_omega_0_trim = .
    label variable _pte_omega_0_trim "Counterfactual productivity (trim track)"
    
    if `omegapoly' >= 2 {
        capture drop _pte_omega_02_trim
        quietly gen double _pte_omega_02_trim = .
    }
    if `omegapoly' >= 3 {
        capture drop _pte_omega_03_trim
        quietly gen double _pte_omega_03_trim = .
    }
    if `omegapoly' >= 4 {
        capture drop _pte_omega_04_trim
        quietly gen double _pte_omega_04_trim = .
    }
    
    // 5.3 Period nt=0: Proposition 4.3 simulates the untreated potential path
    // from the pre-entry state using the innovation draw on the nt=-1 anchor.
    // This mirrors the official DO recursion:
    //   omega_0 = h_bar_0(L.omega) + L.eps0  if nt == 0
    // and keeps the nonlinear future path from dropping the first untreated
    // innovation.
    // NOTE: attpoly is locked to omegapoly so the recursion always uses the
    // same estimated untreated law order as the evolution step.
    
    if `attpoly' == 1 {
        quietly replace _pte_omega_0 = _pte_att_rho0 ///
            + _pte_att_rho1 * L.omega ///
            + L._pte_eps0_draw ///
            if _pte_nt == 0
        quietly replace _pte_omega_0_trim = _pte_att_rho0 ///
            + _pte_att_rho1 * L.omega ///
            + L._pte_eps0_trim_draw ///
            if _pte_nt == 0
    }
    else if `attpoly' == 2 {
        quietly replace _pte_omega_0 = _pte_att_rho0 ///
            + _pte_att_rho1 * L.omega ///
            + _pte_att_rho2 * (L.omega)^2 ///
            + L._pte_eps0_draw ///
            if _pte_nt == 0
        quietly replace _pte_omega_0_trim = _pte_att_rho0 ///
            + _pte_att_rho1 * L.omega ///
            + _pte_att_rho2 * (L.omega)^2 ///
            + L._pte_eps0_trim_draw ///
            if _pte_nt == 0
    }
    else if `attpoly' == 3 {
        quietly replace _pte_omega_0 = _pte_att_rho0 ///
            + _pte_att_rho1 * L.omega ///
            + _pte_att_rho2 * (L.omega)^2 ///
            + _pte_att_rho3 * (L.omega)^3 ///
            + L._pte_eps0_draw ///
            if _pte_nt == 0
        quietly replace _pte_omega_0_trim = _pte_att_rho0 ///
            + _pte_att_rho1 * L.omega ///
            + _pte_att_rho2 * (L.omega)^2 ///
            + _pte_att_rho3 * (L.omega)^3 ///
            + L._pte_eps0_trim_draw ///
            if _pte_nt == 0
    }
    else if `attpoly' == 4 {
        quietly replace _pte_omega_0 = _pte_att_rho0 ///
            + _pte_att_rho1 * L.omega ///
            + _pte_att_rho2 * (L.omega)^2 ///
            + _pte_att_rho3 * (L.omega)^3 ///
            + _pte_att_rho4 * (L.omega)^4 ///
            + L._pte_eps0_draw ///
            if _pte_nt == 0
        quietly replace _pte_omega_0_trim = _pte_att_rho0 ///
            + _pte_att_rho1 * L.omega ///
            + _pte_att_rho2 * (L.omega)^2 ///
            + _pte_att_rho3 * (L.omega)^3 ///
            + _pte_att_rho4 * (L.omega)^4 ///
            + L._pte_eps0_trim_draw ///
            if _pte_nt == 0
    }
    if `_pte_clip_enabled' {
        quietly summarize _pte_omega_0 if _pte_nt == 0 & !missing(_pte_omega_0), meanonly
        if r(N) > 0 {
            if missing(`_pte_clip_max_runtime') | r(max) > `_pte_clip_max_runtime' {
                local _pte_clip_max_runtime = r(max)
            }
            if missing(`_pte_clip_min_runtime') | r(min) < `_pte_clip_min_runtime' {
                local _pte_clip_min_runtime = r(min)
            }
        }
        quietly count if _pte_nt == 0 & _pte_omega_0 > `_pte_clip_tau' & !missing(_pte_omega_0)
        local _pte_clip_upper_step = r(N)
        quietly count if _pte_nt == 0 & _pte_omega_0 < -`_pte_clip_tau' & !missing(_pte_omega_0)
        local _pte_clip_lower_step = r(N)
        if `_pte_clip_upper_step' > 0 | `_pte_clip_lower_step' > 0 {
            local _pte_clip_seen = 1
            local _pte_clip_upper_runtime = `_pte_clip_upper_runtime' + `_pte_clip_upper_step'
            local _pte_clip_lower_runtime = `_pte_clip_lower_runtime' + `_pte_clip_lower_step'
        }
        quietly replace _pte_omega_0 = `_pte_clip_tau' ///
            if _pte_nt == 0 & _pte_omega_0 > `_pte_clip_tau' & !missing(_pte_omega_0)
        quietly replace _pte_omega_0 = -`_pte_clip_tau' ///
            if _pte_nt == 0 & _pte_omega_0 < -`_pte_clip_tau' & !missing(_pte_omega_0)
        quietly replace _pte_omega_0_trim = `_pte_clip_tau' ///
            if _pte_nt == 0 & _pte_omega_0_trim > `_pte_clip_tau' & !missing(_pte_omega_0_trim)
        quietly replace _pte_omega_0_trim = -`_pte_clip_tau' ///
            if _pte_nt == 0 & _pte_omega_0_trim < -`_pte_clip_tau' & !missing(_pte_omega_0_trim)
    }
    
    // 5.4 Periods nt=1,...,attperiods: recursive counterfactual (dual-track)
    //
    // IMPORTANT: Update higher-order terms at nt=s-1 BEFORE computing nt=s
    // The replication code pattern:
    //   replace omega_02 = omega_0^2 if nt==s-1
    //   replace omega_02_trim = omega_0_trim^2 if nt==s-1
    //   replace omega_0 = rho0 + rho1*L.omega_0 + rho2*L.omega_02 + ... if nt==s
    //   replace omega_0_trim = rho0 + rho1*L.omega_0_trim + ... if nt==s
    
    forvalues s = 1/`attperiods' {
        // Update higher-order terms at nt=s-1 (for use as L. at nt=s)
        if `attpoly' >= 2 {
            quietly replace _pte_omega_02 = _pte_omega_0^2 if _pte_nt == `s' - 1
            quietly replace _pte_omega_02_trim = _pte_omega_0_trim^2 if _pte_nt == `s' - 1
        }
        if `attpoly' >= 3 {
            quietly replace _pte_omega_03 = _pte_omega_0^3 if _pte_nt == `s' - 1
            quietly replace _pte_omega_03_trim = _pte_omega_0_trim^3 if _pte_nt == `s' - 1
        }
        if `attpoly' >= 4 {
            quietly replace _pte_omega_04 = _pte_omega_0^4 if _pte_nt == `s' - 1
            quietly replace _pte_omega_04_trim = _pte_omega_0_trim^4 if _pte_nt == `s' - 1
        }
        
        // Compute counterfactual at nt=s using lagged counterfactual state and
        // the untreated innovation draw carried on the previous event-time row.
        if `attpoly' == 1 {
            quietly replace _pte_omega_0 = _pte_att_rho0 ///
                + _pte_att_rho1 * L._pte_omega_0 ///
                + L._pte_eps0_draw ///
                if _pte_nt == `s'
            quietly replace _pte_omega_0_trim = _pte_att_rho0 ///
                + _pte_att_rho1 * L._pte_omega_0_trim ///
                + L._pte_eps0_trim_draw ///
                if _pte_nt == `s'
        }
        else if `attpoly' == 2 {
            quietly replace _pte_omega_0 = _pte_att_rho0 ///
                + _pte_att_rho1 * L._pte_omega_0 ///
                + _pte_att_rho2 * L._pte_omega_02 ///
                + L._pte_eps0_draw ///
                if _pte_nt == `s'
            quietly replace _pte_omega_0_trim = _pte_att_rho0 ///
                + _pte_att_rho1 * L._pte_omega_0_trim ///
                + _pte_att_rho2 * L._pte_omega_02_trim ///
                + L._pte_eps0_trim_draw ///
                if _pte_nt == `s'
        }
        else if `attpoly' == 3 {
            quietly replace _pte_omega_0 = _pte_att_rho0 ///
                + _pte_att_rho1 * L._pte_omega_0 ///
                + _pte_att_rho2 * L._pte_omega_02 ///
                + _pte_att_rho3 * L._pte_omega_03 ///
                + L._pte_eps0_draw ///
                if _pte_nt == `s'
            quietly replace _pte_omega_0_trim = _pte_att_rho0 ///
                + _pte_att_rho1 * L._pte_omega_0_trim ///
                + _pte_att_rho2 * L._pte_omega_02_trim ///
                + _pte_att_rho3 * L._pte_omega_03_trim ///
                + L._pte_eps0_trim_draw ///
                if _pte_nt == `s'
        }
        else if `attpoly' == 4 {
            quietly replace _pte_omega_0 = _pte_att_rho0 ///
                + _pte_att_rho1 * L._pte_omega_0 ///
                + _pte_att_rho2 * L._pte_omega_02 ///
                + _pte_att_rho3 * L._pte_omega_03 ///
                + _pte_att_rho4 * L._pte_omega_04 ///
                + L._pte_eps0_draw ///
                if _pte_nt == `s'
            quietly replace _pte_omega_0_trim = _pte_att_rho0 ///
                + _pte_att_rho1 * L._pte_omega_0_trim ///
                + _pte_att_rho2 * L._pte_omega_02_trim ///
                + _pte_att_rho3 * L._pte_omega_03_trim ///
                + _pte_att_rho4 * L._pte_omega_04_trim ///
                + L._pte_eps0_trim_draw ///
                if _pte_nt == `s'
        }
        if `_pte_clip_enabled' {
            quietly summarize _pte_omega_0 if _pte_nt == `s' & !missing(_pte_omega_0), meanonly
            if r(N) > 0 {
                if missing(`_pte_clip_max_runtime') | r(max) > `_pte_clip_max_runtime' {
                    local _pte_clip_max_runtime = r(max)
                }
                if missing(`_pte_clip_min_runtime') | r(min) < `_pte_clip_min_runtime' {
                    local _pte_clip_min_runtime = r(min)
                }
            }
            quietly count if _pte_nt == `s' & _pte_omega_0 > `_pte_clip_tau' & !missing(_pte_omega_0)
            local _pte_clip_upper_step = r(N)
            quietly count if _pte_nt == `s' & _pte_omega_0 < -`_pte_clip_tau' & !missing(_pte_omega_0)
            local _pte_clip_lower_step = r(N)
            if `_pte_clip_upper_step' > 0 | `_pte_clip_lower_step' > 0 {
                local _pte_clip_seen = 1
                local _pte_clip_upper_runtime = `_pte_clip_upper_runtime' + `_pte_clip_upper_step'
                local _pte_clip_lower_runtime = `_pte_clip_lower_runtime' + `_pte_clip_lower_step'
            }
            quietly replace _pte_omega_0 = `_pte_clip_tau' ///
                if _pte_nt == `s' & _pte_omega_0 > `_pte_clip_tau' & !missing(_pte_omega_0)
            quietly replace _pte_omega_0 = -`_pte_clip_tau' ///
                if _pte_nt == `s' & _pte_omega_0 < -`_pte_clip_tau' & !missing(_pte_omega_0)
            quietly replace _pte_omega_0_trim = `_pte_clip_tau' ///
                if _pte_nt == `s' & _pte_omega_0_trim > `_pte_clip_tau' & !missing(_pte_omega_0_trim)
            quietly replace _pte_omega_0_trim = -`_pte_clip_tau' ///
                if _pte_nt == `s' & _pte_omega_0_trim < -`_pte_clip_tau' & !missing(_pte_omega_0_trim)
        }
    }
    
    // 5.5 Validate counterfactual
    quietly count if !missing(_pte_omega_0) & _pte_nt >= 0
    local N_cf = r(N)
    quietly count if !missing(_pte_omega_0_trim) & _pte_nt >= 0
    local N_cf_trim = r(N)
    
    if `N_cf' == 0 {
        di as error "[pte] Error: counterfactual simulation produced no valid values"
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_restore_rngstate_failure'
        `_pte_clear_eclass'
        exit 2000
    }
    
    if "`nodiagnose'" == "" {
        di as text "  Counterfactual obs (raw):  " as result %10.0fc `N_cf'
        di as text "  Counterfactual obs (trim): " as result %10.0fc `N_cf_trim'
        quietly summarize _pte_omega_0 if _pte_nt >= 0
        di as text "  omega_0 (raw) mean:        " as result %10.4f r(mean)
        quietly summarize _pte_omega_0_trim if _pte_nt >= 0
        di as text "  omega_0 (trim) mean:       " as result %10.4f r(mean)
    }
    
    // 5.5b Validate missing value pattern
    // nt=-1 should have missing omega_0 (counterfactual starts at nt=0)
    quietly count if !missing(_pte_omega_0) & _pte_nt == -1
    if r(N) > 0 {
        di as error "[pte] Warning: " r(N) " obs have non-missing omega_0 at nt=-1"
    }
    
    // Check for unexpected missing values at nt>=0
    quietly count if missing(_pte_omega_0) & _pte_nt >= 0 & !missing(omega) & !missing(_pte_eps0_draw)
    local N_unexpected_miss = r(N)
    quietly count if missing(_pte_omega_0_trim) & _pte_nt >= 0 & !missing(omega) & !missing(_pte_eps0_trim_draw)
    local N_unexpected_miss_trim = r(N)
    if `N_unexpected_miss' > 0 & "`nodiagnose'" == "" {
        di as text "  Warning: `N_unexpected_miss' obs with valid inputs but missing omega_0"
    }
    if `N_unexpected_miss_trim' > 0 & "`nodiagnose'" == "" {
        di as text "  Warning: `N_unexpected_miss_trim' obs with valid inputs but missing omega_0_trim"
    }
    
    // 5.5c Numerical precision check (optional, non-blocking)
    if "`nodiagnose'" == "" & `attpoly' >= 2 & `attperiods' >= 1 {
        // Verify higher-order terms consistency at nt=0
        quietly count if abs(_pte_omega_02 - _pte_omega_0^2) > 1e-10 & _pte_nt == 0 & !missing(_pte_omega_0)
        if r(N) > 0 {
            di as text "  Precision warning: " r(N) " obs with omega_02 != omega_0^2 at nt=0"
        }
        else {
            di as text "  Precision check: higher-order terms consistent [OK]"
        }
    }
    
    // ================================================================
    // Step 6: Compute Treatment Effects (dual-track)
    // TT_i(nt) = omega_i(nt) - omega_0_i(nt)
    // ================================================================
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "Step 5: Treatment Effect Calculation"
    }
    
    // 6.1 Compute firm-level treatment effect (TT)
    // Canonical TT follows the paper's trimmed-Gaussian track.
    capture confirm variable _pte_tt_raw, exact
    if !_rc drop _pte_tt_raw
    quietly gen double _pte_tt_raw = omega - _pte_omega_0 if _pte_nt >= 0
    label variable _pte_tt_raw "Treatment effect (raw track)"
    
    capture confirm variable _pte_tt, exact
    if !_rc drop _pte_tt
    quietly gen double _pte_tt = omega - _pte_omega_0_trim if _pte_nt >= 0
    label variable _pte_tt "Treatment effect (canonical trimmed track)"
    
    capture confirm variable _pte_tt_trim, exact
    if !_rc drop _pte_tt_trim
    quietly gen double _pte_tt_trim = _pte_tt if _pte_nt >= 0
    label variable _pte_tt_trim "Treatment effect (trim track alias)"
    
    // 6.2 Numerical validity detection
    // Task 14: Verify TT correctness
    quietly count if _pte_nt == -1 & !missing(_pte_tt)
    if r(N) > 0 {
        di as error "Error: TT should be missing when nt=-1, found " r(N) " non-missing"
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_restore_rngstate_failure'
        `_pte_clear_eclass'
        exit 9
    }
    
    quietly count if _pte_nt >= 0 & !missing(omega) & !missing(_pte_omega_0) & missing(_pte_tt)
    if r(N) > 0 {
        di as error "Error: " r(N) " obs with valid inputs but missing TT"
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_restore_rngstate_failure'
        `_pte_clear_eclass'
        exit 9
    }
    
    // Task 15-17: Extreme values, missing ratio, all-missing detection
    quietly count if abs(_pte_tt) > 10 & !missing(_pte_tt)
    local tt_extreme_count = r(N)
    
    quietly count if missing(_pte_tt) & _pte_nt >= 0
    local tt_miss_count = r(N)
    quietly count if _pte_nt >= 0
    local tt_total_count = r(N)
    
    if `tt_total_count' > 0 {
        local tt_miss_pct = `tt_miss_count' / `tt_total_count' * 100
    }
    else {
        local tt_miss_pct = 100
    }
    
    // Task 17: All-missing check
    if `tt_total_count' == `tt_miss_count' {
        di as error "all TT values are missing (nt>=0)"
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_restore_rngstate_failure'
        `_pte_clear_eclass'
        exit 2000
    }
    
    // Task 18: Stability flag
    local tt_unstable = (`tt_extreme_count' > 0 | `tt_miss_pct' > 5)
    
    // Task 19: TT_trim detection
    quietly count if abs(_pte_tt_trim) > 10 & !missing(_pte_tt_trim)
    local tt_trim_extreme_count = r(N)
    
    // Task 20: Mean reasonableness
    quietly summarize _pte_tt_raw if _pte_nt >= 0
    local tt_raw_mean = r(mean)
    local tt_raw_sd = r(sd)
    local tt_raw_min = r(min)
    local tt_raw_max = r(max)
    
    quietly summarize _pte_tt if _pte_nt >= 0
    local tt_mean = r(mean)
    local tt_sd = r(sd)
    local tt_min = r(min)
    local tt_max = r(max)
    local tt_N = r(N)
    
    // Task 21: Store diagnostic scalars
    scalar __pte_tt_extreme_count = `tt_extreme_count'
    scalar __pte_tt_miss_pct = `tt_miss_pct'
    scalar __pte_tt_unstable = `tt_unstable'
    scalar __pte_tt_trim_extreme_count = `tt_trim_extreme_count'
    
    // Task 23: Diagnostic output
    if "`nodiagnose'" == "" {
        quietly count if _pte_nt == -1
        local nt_neg1_count = r(N)
        
        di as text "  {hline 55}"
        di as text "  TT Diagnostics"
        di as text "  {hline 55}"
        di as text "  Valid TT obs (nt>=0):     " as result %10.0fc `tt_N'
        di as text "  Missing TT (nt=-1):       " as result %10.0fc `nt_neg1_count'
        di as text "  Extreme values (|TT|>10): " as result %10.0fc `tt_extreme_count'
        di as text "  TT range (canonical):     [" as result %9.4f `tt_min' as text ", " as result %9.4f `tt_max' as text "]"
        di as text "  TT mean (raw):            " as result %9.6f `tt_raw_mean'
        di as text "  TT mean (canonical):      " as result %9.6f `tt_mean'
        di as text "  TT std (raw):             " as result %9.6f `tt_raw_sd'
        di as text "  TT std (canonical):       " as result %9.6f `tt_sd'
        
        if `tt_extreme_count' > 0 {
            di as text "  {bf:Warning}: `tt_extreme_count' TT values exceed |10|"
        }
        if `tt_miss_pct' > 5 {
            di as text "  {bf:Warning}: " %4.1f `tt_miss_pct' "% of TT values missing (nt>=0)"
        }
        if abs(`tt_mean') > 1 {
            di as text "  {bf:Warning}: TT mean = " %6.4f `tt_mean' " seems large"
        }
    }
    
    // ================================================================
    // Step 6b: Numerical Stability Checks
    // Checks: overflow, omega_0 range, truncation, rho1, missing, TT outlier
    // ================================================================
    
    // 6b.0 Bootstrap flag detection (IMPL-010)
    capture confirm scalar _pte_in_bootstrap
    if _rc == 0 {
        local _pte_in_bootstrap = scalar(_pte_in_bootstrap)
    }
    else {
        local _pte_in_bootstrap = 0
    }
    
    // 6b.0b Initialize stability locals
    local stability_passed = 1
    local stability_issues = 0
    local overflow_detected = 0
    local omega0_unstable = 0
    local omega0_max = .
    local omega0_min = .
    local omega0_sd = .
    local omega0_truncated_n = 0
    local omega0_truncated_upper = 0
    local omega0_truncated_lower = 0
    local rho1_unstable = 0
    local rho1_abs = .
    local missing_propagation_issue = 0
    local tt_extreme_n_017 = 0
    local tt_extreme_pct_017 = 0
    local tt_mean_017 = .
    local tt_sd_017 = .
    local tt_min_017 = .
    local tt_max_017 = .
    
    // 6b.0c Quick exit: nostabilitycheck + noclipomg → skip all
    if "`stabilitycheck'" == "nostabilitycheck" & "`clipomg'" == "noclipomg" {
        // Fully skip — consistent with replication code behavior
    }
    else {
    
    // === IMPL-005: rho1 stability check (early, before omega_0 checks) ===
    local rho1_val = `rho_0_mat'[1, 2]
    local rho1_abs = abs(`rho1_val')
    
    if "`stabilitycheck'" != "nostabilitycheck" {
        if `rho1_abs' >= 1 {
            local rho1_unstable = 1
            if !`_pte_in_bootstrap' & "`nodiagnose'" == "" {
                di as text "{p 4 4 2}Warning: |rho1| = " ///
                    %9.6f `rho1_abs' " >= 1. " ///
                    "AR(1) process is non-stationary.{p_end}"
            }
        }
        else if `rho1_abs' > 0.95 {
            if !`_pte_in_bootstrap' & "`nodiagnose'" == "" {
                di as text "{p 4 4 2}Note: |rho1| = " ///
                    %9.6f `rho1_abs' " is near unit root " ///
                    "(> 0.95).{p_end}"
            }
        }
    }
    
    // === IMPL-002: High-order term overflow detection ===
    // NOTE: Higher-order terms (_pte_omega_02, etc.) are only set at nt=0..attperiods-1
    // because they are used as L. inputs for the NEXT period. At nt=attperiods,
    // omega_0 is computed but omega_02 is not needed (no nt=attperiods+1).
    if "`stabilitycheck'" != "nostabilitycheck" {
        if `attpoly' >= 2 {
            quietly count if !missing(_pte_omega_0) & missing(_pte_omega_02) ///
                & _pte_nt >= 0 & _pte_nt <= `attperiods' - 1
            if r(N) > 0 {
                local overflow_detected = 1
                di as error "Overflow detected: omega_02 has `=r(N)' " ///
                    "unexpected missing values where omega_0 is non-missing"
                if `pte_xtset_switched' {
                    `pte_restore_xtset'
                }
                capture quietly use `pte_att_orig_data', clear
                `pte_restore_xtset'
                `_pte_restore_rngstate_failure'
                `_pte_clear_eclass'
                exit 459
            }
        }
        if `attpoly' >= 3 {
            quietly count if !missing(_pte_omega_0) & missing(_pte_omega_03) ///
                & _pte_nt >= 0 & _pte_nt <= `attperiods' - 1
            if r(N) > 0 {
                local overflow_detected = 1
                di as error "Overflow detected: omega_03 has `=r(N)' " ///
                    "unexpected missing values"
                if `pte_xtset_switched' {
                    `pte_restore_xtset'
                }
                capture quietly use `pte_att_orig_data', clear
                `pte_restore_xtset'
                `_pte_restore_rngstate_failure'
                `_pte_clear_eclass'
                exit 459
            }
        }
        if `attpoly' >= 4 {
            quietly count if !missing(_pte_omega_0) & missing(_pte_omega_04) ///
                & _pte_nt >= 0 & _pte_nt <= `attperiods' - 1
            if r(N) > 0 {
                local overflow_detected = 1
                di as error "Overflow detected: omega_04 has `=r(N)' " ///
                    "unexpected missing values"
                if `pte_xtset_switched' {
                    `pte_restore_xtset'
                }
                capture quietly use `pte_att_orig_data', clear
                `pte_restore_xtset'
                `_pte_restore_rngstate_failure'
                `_pte_clear_eclass'
                exit 459
            }
        }
    }
    
    // === IMPL-003: omega_0 range detection ===
    local tau = `cliprange'
    quietly summarize _pte_omega_0 if !missing(_pte_omega_0), detail
    local omega0_max = r(max)
    local omega0_min = r(min)
    local omega0_sd = r(sd)
    
    if `_pte_clip_seen' {
        if !missing(`_pte_clip_max_runtime') & (missing(`omega0_max') | `_pte_clip_max_runtime' > `omega0_max') {
            local omega0_max = `_pte_clip_max_runtime'
        }
        if !missing(`_pte_clip_min_runtime') & (missing(`omega0_min') | `_pte_clip_min_runtime' < `omega0_min') {
            local omega0_min = `_pte_clip_min_runtime'
        }
        local omega0_unstable = 1
        if !`_pte_in_bootstrap' & "`nodiagnose'" == "" {
            di as text "{p 4 4 2}Warning: omega_0 range " ///
                "[" %9.4f `omega0_min' ", " %9.4f `omega0_max' "] exceeds " ///
                "[-`tau', `tau']{p_end}"
        }
    }
    else if `omega0_max' > `tau' | `omega0_min' < -`tau' {
        local omega0_unstable = 1
        if !`_pte_in_bootstrap' & "`nodiagnose'" == "" {
            di as text "{p 4 4 2}Warning: omega_0 range " ///
                "[" %9.4f `omega0_min' ", " %9.4f `omega0_max' "] exceeds " ///
                "[-`tau', `tau']{p_end}"
        }
    }
    
    // === IMPL-004: omega_0 truncation ===
    if `_pte_clip_enabled' & `omega0_unstable' == 1 {
        local omega0_truncated_upper = `_pte_clip_upper_runtime'
        local omega0_truncated_lower = `_pte_clip_lower_runtime'
        quietly count if _pte_omega_0 > `tau' & !missing(_pte_omega_0)
        local _pte_clip_pending_upper = r(N)
        quietly count if _pte_omega_0 < -`tau' & !missing(_pte_omega_0)
        local _pte_clip_pending_lower = r(N)
        local omega0_truncated_upper = `omega0_truncated_upper' + `_pte_clip_pending_upper'
        local omega0_truncated_lower = `omega0_truncated_lower' + `_pte_clip_pending_lower'
        local omega0_truncated_n = `omega0_truncated_upper' ///
            + `omega0_truncated_lower'
        
        quietly replace _pte_omega_0 = `tau' ///
            if _pte_omega_0 > `tau' & !missing(_pte_omega_0)
        quietly replace _pte_omega_0 = -`tau' ///
            if _pte_omega_0 < -`tau' & !missing(_pte_omega_0)
        quietly replace _pte_omega_0_trim = `tau' ///
            if _pte_omega_0_trim > `tau' & !missing(_pte_omega_0_trim)
        quietly replace _pte_omega_0_trim = -`tau' ///
            if _pte_omega_0_trim < -`tau' & !missing(_pte_omega_0_trim)

        // TT must reflect the final clipped counterfactual path.
        quietly replace _pte_tt_raw = omega - _pte_omega_0 ///
            if _pte_nt >= 0 & !missing(_pte_omega_0)
        quietly replace _pte_tt = omega - _pte_omega_0_trim ///
            if _pte_nt >= 0 & !missing(_pte_omega_0_trim)
        quietly replace _pte_tt_trim = _pte_tt ///
            if _pte_nt >= 0 & !missing(_pte_tt)
        
        if !`_pte_in_bootstrap' & "`nodiagnose'" == "" {
            di as text "  Truncated `omega0_truncated_n' observations " ///
                "(upper: `omega0_truncated_upper', " ///
                "lower: `omega0_truncated_lower')"
        }
    }
    
    // === IMPL-006: Missing value propagation detection ===
    if "`stabilitycheck'" != "nostabilitycheck" & !`_pte_in_bootstrap' {
        local n_periods_017 = `attperiods' + 2
        tempname Missing_Diag
        matrix `Missing_Diag' = J(`n_periods_017', 3, 0)
        
        local row_017 = 0
        local prev_miss_rate = 0
        
        forvalues nt_val = -1/`attperiods' {
            local ++row_017
            quietly count if _pte_nt == `nt_val'
            local n_total_017 = r(N)
            quietly count if _pte_nt == `nt_val' & missing(_pte_omega_0)
            local n_miss_017 = r(N)
            matrix `Missing_Diag'[`row_017', 1] = `nt_val'
            matrix `Missing_Diag'[`row_017', 2] = `n_total_017'
            matrix `Missing_Diag'[`row_017', 3] = `n_miss_017'
            
            if `nt_val' == -1 {
                if `n_miss_017' < `n_total_017' & `n_total_017' > 0 {
                    local missing_propagation_issue = 1
                }
            }
            else {
                local miss_rate = cond(`n_total_017' > 0, ///
                    `n_miss_017' / `n_total_017', 0)
                if `miss_rate' - `prev_miss_rate' > 0.10 {
                    local missing_propagation_issue = 1
                }
                local prev_miss_rate = `miss_rate'
            }
        }
        
        if "`verbose'" != "" {
            matrix colnames `Missing_Diag' = nt N_total N_missing
            matrix list `Missing_Diag', title("Missing Value Propagation")
        }
    }
    else {
        // Create empty matrix placeholder when checks skipped
        tempname Missing_Diag
        matrix `Missing_Diag' = J(1, 3, 0)
    }
    
    // === IMPL-007: TT outlier detection ===
    if "`stabilitycheck'" != "nostabilitycheck" {
        quietly summarize _pte_tt if !missing(_pte_tt) ///
            & _pte_nt >= 0 & _pte_nt <= `attperiods'
        local tt_mean_017 = r(mean)
        local tt_sd_017 = r(sd)
        local tt_min_017 = r(min)
        local tt_max_017 = r(max)
        local tt_n_017 = r(N)
        
        quietly count if abs(_pte_tt) > 5 & !missing(_pte_tt) ///
            & _pte_nt >= 0 & _pte_nt <= `attperiods'
        local tt_extreme_n_017 = r(N)
        local tt_extreme_pct_017 = cond(`tt_n_017' > 0, ///
            `tt_extreme_n_017' / `tt_n_017', 0)
        
        if `tt_extreme_n_017' > 0 & !`_pte_in_bootstrap' & "`nodiagnose'" == "" {
            di as text "{p 4 4 2}Note: `tt_extreme_n_017' observations " ///
                "(" %5.2f `tt_extreme_pct_017'*100 "%) have |TT| > 5{p_end}"
        }
    }
    
    // === IMPL-008: Comprehensive stability report ===
    local stability_issues = `omega0_unstable' ///
        + `rho1_unstable' * 2 ///
        + `missing_propagation_issue' ///
        + (`tt_extreme_pct_017' > 0.05)
    local stability_passed = (`stability_issues' == 0)
    
    if !`_pte_in_bootstrap' & "`nodiagnose'" == "" ///
        & "`stabilitycheck'" != "nostabilitycheck" {
        di as text _n "{hline 60}"
        di as text "Numerical Stability Report"
        di as text "{hline 60}"
        di as text "  omega_0 range:       " ///
            cond(`omega0_unstable', "WARNING", "PASS")
        di as text "  rho1 stability:      " ///
            cond(`rho1_unstable', "WARNING (|rho1|>=1)", "PASS")
        di as text "  Missing propagation: " ///
            cond(`missing_propagation_issue', " WARNING", " PASS")
        if `tt_extreme_pct_017' > 0.05 {
            di as text "  TT extreme values:   " ///
                "WARNING (" %5.1f `tt_extreme_pct_017'*100 "%)"
        }
        else {
            di as text "  TT extreme values:    PASS"
        }
        di as text "{hline 60}"
        if `stability_passed' {
            di as text "  Overall:              PASSED"
        }
        else {
            di as text "  Overall:              " ///
                "ISSUES DETECTED (" string(`stability_issues') ")"
        }
        di as text "{hline 60}"
    }
    
    }  // end of stability check block (closing brace for quick-exit else)
    
    // ================================================================
    // Step 7: Path averaging (nsim > 1)
    // When nsim > 1, average TT across simulation paths per firm-nt
    //   bys firm nt: egen omg_tt = mean(omg_att)
    //   bys firm nt: egen omg_tt_trim = mean(omg_att_trim)
    //   duplicates drop firm nt, force
    // ================================================================
    
    if `expanded' {
        quietly count
        local N_pre_agg = r(N)
        
        if "`nodiagnose'" == "" {
            di as text ""
            di as text "Step 5b: Path Averaging (nsim=`nsim')"
        }
        
        // 7.1 Average TT across paths for each firm-nt
        capture drop _pte_tt_raw_mean
        quietly bysort `panelvar' _pte_nt: egen double _pte_tt_raw_mean = mean(_pte_tt_raw)
        
        capture drop _pte_tt_mean
        quietly bysort `panelvar' _pte_nt: egen double _pte_tt_mean = mean(_pte_tt)
        
        capture drop _pte_tt_trim_mean
        quietly bysort `panelvar' _pte_nt: egen double _pte_tt_trim_mean = mean(_pte_tt_trim)
        
        // 7.1a Average omega_0 across paths (maintains TT = omega - omega_0)
        capture drop _pte_omega_0_mean
        quietly bysort `panelvar' _pte_nt: egen double _pte_omega_0_mean = mean(_pte_omega_0)
        
        capture drop _pte_omega_0_trim_mean
        quietly bysort `panelvar' _pte_nt: egen double _pte_omega_0_trim_mean = mean(_pte_omega_0_trim)

        // Published shock draws must live on the same collapsed firm-nt
        // support as the averaged counterfactual path. Keeping an arbitrary
        // single-path draw after duplicates drop makes the returned draw
        // variables inconsistent with the returned path-averaged omega_0/TT.
        capture drop _pte_eps0_draw_mean
        quietly bysort `panelvar' _pte_nt: egen double _pte_eps0_draw_mean = mean(_pte_eps0_draw)

        capture drop _pte_eps0_trim_draw_mean
        quietly bysort `panelvar' _pte_nt: egen double _pte_eps0_trim_draw_mean = mean(_pte_eps0_trim_draw)
        
        // 7.1b Compute cross-path standard deviation ( Task 4)
        capture drop _pte_tt_raw_sd
        quietly bysort `panelvar' _pte_nt: egen double _pte_tt_raw_sd = sd(_pte_tt_raw)
        
        capture drop _pte_tt_sd
        quietly bysort `panelvar' _pte_nt: egen double _pte_tt_sd = sd(_pte_tt)
        
        capture drop _pte_tt_trim_sd
        quietly bysort `panelvar' _pte_nt: egen double _pte_tt_trim_sd = sd(_pte_tt_trim)
        
        // 7.2 Collapse to one observation per firm-nt
        quietly duplicates drop `panelvar' _pte_nt, force
        
        // 7.2b Verify uniqueness ( Task 8)
        capture isid `panelvar' _pte_nt
        if _rc {
            di as error "Error: firm-nt does not uniquely identify observations after dedup"
            if `pte_xtset_switched' {
                `pte_restore_xtset'
            }
            capture quietly use `pte_att_orig_data', clear
            `pte_restore_xtset'
            `_pte_restore_rngstate_failure'
            `_pte_clear_eclass'
            exit 9
        }
        
        // 7.3 Replace TT with path-averaged TT
        quietly replace _pte_tt_raw = _pte_tt_raw_mean
        quietly replace _pte_tt = _pte_tt_mean
        quietly replace _pte_tt_trim = _pte_tt_trim_mean
        
        // 7.3b Replace omega_0 with path-averaged omega_0
        quietly replace _pte_omega_0 = _pte_omega_0_mean
        quietly replace _pte_omega_0_trim = _pte_omega_0_trim_mean

        // Keep the published draw variables on the same firm-nt averaged
        // support as the returned counterfactual objects.
        quietly replace _pte_eps0_draw = _pte_eps0_draw_mean
        quietly replace _pte_eps0_trim_draw = _pte_eps0_trim_draw_mean
        
        // 7.4 Clean up expansion variables
        capture drop _pte_copy_id
        capture drop _pte_firm_sim_id
        capture drop _pte_tt_raw_mean
        capture drop _pte_tt_mean
        capture drop _pte_tt_trim_mean
        capture drop _pte_omega_0_mean
        capture drop _pte_omega_0_trim_mean
        capture drop _pte_eps0_draw_mean
        capture drop _pte_eps0_trim_draw_mean
        
        // 7.5 Re-sort and re-xtset
        sort `panelvar' `timevar'
        `pte_restore_xtset'
        
        quietly count
        local N_collapsed = r(N)
        
        // 7.6 Diagnostic output ( Tasks 12-13)
        if "`nodiagnose'" == "" {
            di as text "  Pre-aggregation obs:    " as result %10.0fc `N_pre_agg' as text " obs"
            di as text "  Collapsed to:           " as result %10.0fc `N_collapsed' as text " obs"
            di as text "  Aggregation factor:     " as result %10.0fc `nsim' as text " (nsim)"
            
            quietly summarize _pte_tt_sd if _pte_nt >= 0
            if r(N) > 0 {
                di as text "  TT_sd range (nt>=0):    [" as result %9.4f r(min) as text ", " as result %9.4f r(max) as text "]"
                di as text "  TT_sd mean (nt>=0):     " as result %9.4f r(mean)
            }
        }
    }
    
    // ================================================================
    // Step 8: Dynamic ATT aggregation
    // ATT(nt) = (1/N_nt) * sum_i TT_i(nt)  [Equation 17]
    // ATT_avg = sum(N_nt * ATT_nt) / sum(N_nt)  [weighted average]
    // ================================================================
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "Step 6: Dynamic ATT Aggregation"
    }
    
    // 8.0 Validate input from
    // TT variable should exist (raw track always, trim track always)
    // For nsim>1: _pte_tt already contains path-averaged TT_mean
    // For nsim=1: _pte_tt is the direct firm-level TT
    
    quietly count if _pte_nt >= 0 & !missing(_pte_tt) & `_pte_target_sample'
    local N_valid_att = r(N)
    if `N_valid_att' == 0 {
        di as error "[pte] Error: no valid TT observations for ATT aggregation"
        if `pte_xtset_switched' {
            `pte_restore_xtset'
        }
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_restore_rngstate_failure'
        `_pte_clear_eclass'
        exit 2000
    }
    
    // 8.1 Compute ATT by period (both tracks) and build matrices
    // Matrix dimensions: 1 x (attperiods + 2)
    // Columns: [ATT_0, ATT_1, ..., ATT_L, ATT_avg]
    local ncols_att = `attperiods' + 2
    
    tempname att_vec att_trim_vec att_raw_vec att_sd_vec att_sd_trim_vec att_sd_raw_vec att_se_vec n_by_period
    matrix `att_vec' = J(1, `ncols_att', .)
    matrix `att_trim_vec' = J(1, `ncols_att', .)
    matrix `att_raw_vec' = J(1, `ncols_att', .)
    matrix `att_sd_vec' = J(1, `ncols_att', .)
    matrix `att_sd_trim_vec' = J(1, `ncols_att', .)
    matrix `att_sd_raw_vec' = J(1, `ncols_att', .)
    matrix `att_se_vec' = J(1, `ncols_att', .)
    matrix `n_by_period' = J(1, `attperiods' + 1, 0)
    
    // Also keep the legacy 5-column table for display
    local nperiods = `attperiods' + 1
    tempname att_mat att_trim_mat att_raw_mat
    matrix `att_mat' = J(`nperiods', 5, .)
    matrix colnames `att_mat' = nt ATT sd N se
    matrix `att_trim_mat' = J(`nperiods', 5, .)
    matrix colnames `att_trim_mat' = nt ATT_trim sd_trim N_trim se_trim
    matrix `att_raw_mat' = J(`nperiods', 5, .)
    matrix colnames `att_raw_mat' = nt ATT_raw sd_raw N_raw se_raw
    
    // Set column names for e(att) matrices: "0 1 2 ... L avg"
    local colnames ""
    forvalues s = 0/`attperiods' {
        local colnames "`colnames' `s'"
    }
    local colnames "`colnames' avg"
    matrix colnames `att_vec' = `colnames'
    matrix colnames `att_trim_vec' = `colnames'
    matrix colnames `att_raw_vec' = `colnames'
    matrix colnames `att_sd_vec' = `colnames'
    matrix colnames `att_sd_trim_vec' = `colnames'
    matrix colnames `att_sd_raw_vec' = `colnames'
    matrix colnames `att_se_vec' = `colnames'
    matrix rownames `att_vec' = "att"
    matrix rownames `att_trim_vec' = "att_trim"
    matrix rownames `att_raw_vec' = "att_raw"
    matrix rownames `att_sd_vec' = "att_sd"
    matrix rownames `att_sd_trim_vec' = "att_sd_trim"
    matrix rownames `att_sd_raw_vec' = "att_sd_raw"
    matrix rownames `att_se_vec' = "att_se"
    
    // Set column names for e(N_by_period): "0 1 2 ... L"
    local n_colnames ""
    forvalues s = 0/`attperiods' {
        local n_colnames "`n_colnames' `s'"
    }
    matrix colnames `n_by_period' = `n_colnames'
    matrix rownames `n_by_period' = "N"
    
    // 8.2 Loop over periods to compute ATT(nt) and fill matrices
    local sum_N_att_raw = 0
    local sum_N_att = 0
    local sum_NxATT = 0
    local sum_NxATT_trim = 0
    local sum_NxATT_raw = 0
    
    forvalues s = 0/`attperiods' {
        local col = `s' + 1
        local row = `s' + 1
        
        // Legacy table
        matrix `att_mat'[`row', 1] = `s'
        matrix `att_trim_mat'[`row', 1] = `s'
        matrix `att_raw_mat'[`row', 1] = `s'
        
        // Canonical raw aliases
        quietly summarize _pte_tt_raw if _pte_nt == `s' & `_pte_target_sample'
        local n_s = r(N)
        if `n_s' > 0 {
            local att_raw_s = r(mean)
            local sd_raw_s = r(sd)
            local se_raw_s = r(sd) / sqrt(r(N))
            
            matrix `att_raw_vec'[1, `col'] = `att_raw_s'
            matrix `att_sd_raw_vec'[1, `col'] = `sd_raw_s'
            
            matrix `att_raw_mat'[`row', 2] = `att_raw_s'
            matrix `att_raw_mat'[`row', 3] = `sd_raw_s'
            matrix `att_raw_mat'[`row', 4] = `n_s'
            matrix `att_raw_mat'[`row', 5] = `se_raw_s'
            
            local sum_N_att_raw = `sum_N_att_raw' + `n_s'
            local sum_NxATT_raw = `sum_NxATT_raw' + `n_s' * `att_raw_s'
        }
        
        // Canonical paper track
        quietly summarize _pte_tt if _pte_nt == `s' & `_pte_target_sample'
        local n_s = r(N)
        if `n_s' > 0 {
            local att_s = r(mean)
            local sd_s = r(sd)
            local se_s = r(sd) / sqrt(r(N))
            
            matrix `att_vec'[1, `col'] = `att_s'
            matrix `att_sd_vec'[1, `col'] = `sd_s'
            matrix `att_se_vec'[1, `col'] = `se_s'
            matrix `n_by_period'[1, `col'] = `n_s'
            
            // Legacy table
            matrix `att_mat'[`row', 2] = `att_s'
            matrix `att_mat'[`row', 3] = `sd_s'
            matrix `att_mat'[`row', 4] = `n_s'
            matrix `att_mat'[`row', 5] = `se_s'
            
            // Accumulate for weighted average
            local sum_N_att = `sum_N_att' + `n_s'
            local sum_NxATT = `sum_NxATT' + `n_s' * `att_s'
        }
        else {
            // Empty period: N=0, ATT=missing
            matrix `n_by_period'[1, `col'] = 0
            if "`nodiagnose'" == "" {
                di as text "  Warning: no observations at nt=`s'"
            }
        }
        
        // Explicit trim aliases mirror the canonical paper track
        if `n_s' > 0 {
            matrix `att_trim_vec'[1, `col'] = `att_s'
            matrix `att_sd_trim_vec'[1, `col'] = `sd_s'
            
            matrix `att_trim_mat'[`row', 2] = `att_s'
            matrix `att_trim_mat'[`row', 3] = `sd_s'
            matrix `att_trim_mat'[`row', 4] = `n_s'
            matrix `att_trim_mat'[`row', 5] = `se_s'
            
            local sum_NxATT_trim = `sum_NxATT_trim' + `n_s' * `att_s'
        }
    }
    
    // 8.3 Compute weighted ATT_avg = sum(N_nt * ATT_nt) / sum(N_nt)
    // Here N_nt counts treated firm-period observations at event time nt,
    // matching the paper's "Treated Obs." totals rather than firm counts.
    if `sum_N_att_raw' > 0 {
        local att_raw_overall = `sum_NxATT_raw' / `sum_N_att_raw'
    }
    else {
        local att_raw_overall = .
    }
    if `sum_N_att' > 0 {
        local att_overall = `sum_NxATT' / `sum_N_att'
        local att_trim_overall = `sum_NxATT_trim' / `sum_N_att'
    }
    else {
        local att_overall = .
        local att_trim_overall = .
    }
    local att_N = `sum_N_att'
    local att_trim_N = `sum_N_att'
    local att_raw_N = `sum_N_att_raw'
    
    // Store ATT_avg in the last column of e(att) matrices
    matrix `att_vec'[1, `ncols_att'] = `att_overall'
    matrix `att_trim_vec'[1, `ncols_att'] = `att_trim_overall'
    matrix `att_raw_vec'[1, `ncols_att'] = `att_raw_overall'
    
    // 8.3b Compute pooled SD across all nt>=0 (for att_sd last column)
    quietly summarize _pte_tt_raw if _pte_nt >= 0 & `_pte_target_sample'
    local att_raw_sd = r(sd)
    local att_raw_se = cond(r(N) > 0, r(sd) / sqrt(r(N)), .)
    matrix `att_sd_raw_vec'[1, `ncols_att'] = `att_raw_sd'
    
    quietly summarize _pte_tt if _pte_nt >= 0 & `_pte_target_sample'
    local att_sd = r(sd)
    local att_se = cond(r(N) > 0, r(sd) / sqrt(r(N)), .)
    matrix `att_sd_vec'[1, `ncols_att'] = `att_sd'
    matrix `att_se_vec'[1, `ncols_att'] = `att_se'
    
    quietly summarize _pte_tt_trim if _pte_nt >= 0 & `_pte_target_sample'
    local att_trim_sd = r(sd)
    local att_trim_se = cond(r(N) > 0, r(sd) / sqrt(r(N)), .)
    matrix `att_sd_trim_vec'[1, `ncols_att'] = `att_trim_sd'

    // 8.3c Publish only the exact realized dynamic ATT support. Dynamic
    // consumers treat e(attperiods) as the certified event-time contract,
    // so any nt with N=0 must be pruned rather than posted as a missing ATT
    // column that downstream graph/predict/export paths must reject.
    local pte_att_support_periods ""
    forvalues s = 0/`attperiods' {
        if `n_by_period'[1, `s' + 1] > 0 {
            local pte_att_support_periods "`pte_att_support_periods' `s'"
        }
    }
    local pte_att_support_periods : list retokenize pte_att_support_periods
    local pte_att_nperiods : word count `pte_att_support_periods'

    if `pte_att_nperiods' == 0 {
        di as error "[pte] Internal error: no realized ATT periods remain after aggregation"
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_restore_rngstate_failure'
        `_pte_clear_eclass'
        exit 498
    }

    if `pte_att_nperiods' < `attperiods' + 1 & "`nodiagnose'" == "" {
        di as text "  Pruned unsupported ATT periods from certified support: " ///
            as result trim("`pte_att_support_periods'")
    }

    tempname att_vec_post att_trim_vec_post att_raw_vec_post
    tempname att_sd_vec_post att_sd_trim_vec_post att_sd_raw_vec_post
    tempname att_se_vec_post n_by_period_post attperiods_post
    tempname att_mat_post att_trim_mat_post att_raw_mat_post
    local pte_att_post_cols = `pte_att_nperiods' + 1

    matrix `att_vec_post' = J(1, `pte_att_post_cols', .)
    matrix `att_trim_vec_post' = J(1, `pte_att_post_cols', .)
    matrix `att_raw_vec_post' = J(1, `pte_att_post_cols', .)
    matrix `att_sd_vec_post' = J(1, `pte_att_post_cols', .)
    matrix `att_sd_trim_vec_post' = J(1, `pte_att_post_cols', .)
    matrix `att_sd_raw_vec_post' = J(1, `pte_att_post_cols', .)
    matrix `att_se_vec_post' = J(1, `pte_att_post_cols', .)
    matrix `n_by_period_post' = J(1, `pte_att_nperiods', 0)
    matrix `attperiods_post' = J(1, `pte_att_nperiods', .)
    matrix `att_mat_post' = J(`pte_att_nperiods', 5, .)
    matrix colnames `att_mat_post' = nt ATT sd N se
    matrix `att_trim_mat_post' = J(`pte_att_nperiods', 5, .)
    matrix colnames `att_trim_mat_post' = nt ATT_trim sd_trim N_trim se_trim
    matrix `att_raw_mat_post' = J(`pte_att_nperiods', 5, .)
    matrix colnames `att_raw_mat_post' = nt ATT_raw sd_raw N_raw se_raw

    local pte_att_post_colnames ""
    local pte_att_post_ncolnames ""
    local pte_att_row = 0
    foreach s of local pte_att_support_periods {
        local ++pte_att_row
        local pte_att_src_col = `s' + 1
        local pte_att_src_row = `s' + 1

        matrix `att_vec_post'[1, `pte_att_row'] = `att_vec'[1, `pte_att_src_col']
        matrix `att_trim_vec_post'[1, `pte_att_row'] = `att_trim_vec'[1, `pte_att_src_col']
        matrix `att_raw_vec_post'[1, `pte_att_row'] = `att_raw_vec'[1, `pte_att_src_col']
        matrix `att_sd_vec_post'[1, `pte_att_row'] = `att_sd_vec'[1, `pte_att_src_col']
        matrix `att_sd_trim_vec_post'[1, `pte_att_row'] = `att_sd_trim_vec'[1, `pte_att_src_col']
        matrix `att_sd_raw_vec_post'[1, `pte_att_row'] = `att_sd_raw_vec'[1, `pte_att_src_col']
        matrix `att_se_vec_post'[1, `pte_att_row'] = `att_se_vec'[1, `pte_att_src_col']
        matrix `n_by_period_post'[1, `pte_att_row'] = `n_by_period'[1, `pte_att_src_col']
        matrix `attperiods_post'[1, `pte_att_row'] = `s'

        matrix `att_mat_post'[`pte_att_row', 1] = `att_mat'[`pte_att_src_row', 1]
        matrix `att_mat_post'[`pte_att_row', 2] = `att_mat'[`pte_att_src_row', 2]
        matrix `att_mat_post'[`pte_att_row', 3] = `att_mat'[`pte_att_src_row', 3]
        matrix `att_mat_post'[`pte_att_row', 4] = `att_mat'[`pte_att_src_row', 4]
        matrix `att_mat_post'[`pte_att_row', 5] = `att_mat'[`pte_att_src_row', 5]

        matrix `att_trim_mat_post'[`pte_att_row', 1] = `att_trim_mat'[`pte_att_src_row', 1]
        matrix `att_trim_mat_post'[`pte_att_row', 2] = `att_trim_mat'[`pte_att_src_row', 2]
        matrix `att_trim_mat_post'[`pte_att_row', 3] = `att_trim_mat'[`pte_att_src_row', 3]
        matrix `att_trim_mat_post'[`pte_att_row', 4] = `att_trim_mat'[`pte_att_src_row', 4]
        matrix `att_trim_mat_post'[`pte_att_row', 5] = `att_trim_mat'[`pte_att_src_row', 5]

        matrix `att_raw_mat_post'[`pte_att_row', 1] = `att_raw_mat'[`pte_att_src_row', 1]
        matrix `att_raw_mat_post'[`pte_att_row', 2] = `att_raw_mat'[`pte_att_src_row', 2]
        matrix `att_raw_mat_post'[`pte_att_row', 3] = `att_raw_mat'[`pte_att_src_row', 3]
        matrix `att_raw_mat_post'[`pte_att_row', 4] = `att_raw_mat'[`pte_att_src_row', 4]
        matrix `att_raw_mat_post'[`pte_att_row', 5] = `att_raw_mat'[`pte_att_src_row', 5]

        local pte_att_post_colnames "`pte_att_post_colnames' `s'"
        local pte_att_post_ncolnames "`pte_att_post_ncolnames' `s'"
    }

    matrix `att_vec_post'[1, `pte_att_post_cols'] = `att_overall'
    matrix `att_trim_vec_post'[1, `pte_att_post_cols'] = `att_trim_overall'
    matrix `att_raw_vec_post'[1, `pte_att_post_cols'] = `att_raw_overall'
    matrix `att_sd_vec_post'[1, `pte_att_post_cols'] = `att_sd'
    matrix `att_sd_trim_vec_post'[1, `pte_att_post_cols'] = `att_trim_sd'
    matrix `att_sd_raw_vec_post'[1, `pte_att_post_cols'] = `att_raw_sd'
    matrix `att_se_vec_post'[1, `pte_att_post_cols'] = `att_se'

    local pte_att_post_colnames "`pte_att_post_colnames' avg"
    matrix colnames `att_vec_post' = `pte_att_post_colnames'
    matrix colnames `att_trim_vec_post' = `pte_att_post_colnames'
    matrix colnames `att_raw_vec_post' = `pte_att_post_colnames'
    matrix colnames `att_sd_vec_post' = `pte_att_post_colnames'
    matrix colnames `att_sd_trim_vec_post' = `pte_att_post_colnames'
    matrix colnames `att_sd_raw_vec_post' = `pte_att_post_colnames'
    matrix colnames `att_se_vec_post' = `pte_att_post_colnames'
    matrix rownames `att_vec_post' = "att"
    matrix rownames `att_trim_vec_post' = "att_trim"
    matrix rownames `att_raw_vec_post' = "att_raw"
    matrix rownames `att_sd_vec_post' = "att_sd"
    matrix rownames `att_sd_trim_vec_post' = "att_sd_trim"
    matrix rownames `att_sd_raw_vec_post' = "att_sd_raw"
    matrix rownames `att_se_vec_post' = "att_se"

    matrix colnames `n_by_period_post' = `pte_att_post_ncolnames'
    matrix rownames `n_by_period_post' = "N"
    matrix colnames `attperiods_post' = `pte_att_post_ncolnames'
    matrix rownames `attperiods_post' = "period"

    matrix `att_vec' = `att_vec_post'
    matrix `att_trim_vec' = `att_trim_vec_post'
    matrix `att_raw_vec' = `att_raw_vec_post'
    matrix `att_sd_vec' = `att_sd_vec_post'
    matrix `att_sd_trim_vec' = `att_sd_trim_vec_post'
    matrix `att_sd_raw_vec' = `att_sd_raw_vec_post'
    matrix `att_se_vec' = `att_se_vec_post'
    matrix `n_by_period' = `n_by_period_post'
    matrix `att_mat' = `att_mat_post'
    matrix `att_trim_mat' = `att_trim_mat_post'
    matrix `att_raw_mat' = `att_raw_mat_post'
    local nperiods = `pte_att_nperiods'
    local ncols_att = `pte_att_post_cols'
    
    // 8.4 Validation: verify weighted average consistency
    if "`nodiagnose'" == "" & `sum_N_att' > 0 {
        di as text "  ATT_avg_raw (weighted): " as result %10.6f `att_raw_overall'
        di as text "  ATT_avg (weighted):     " as result %10.6f `att_overall'
        di as text "  ATT_avg_trim (weighted):" as result %10.6f `att_trim_overall'
        di as text "  Total ATT observations (all nt):" as result %10.0fc `att_N'
        di as text "  Periods with data:      " as result `nperiods'
    }
    
    // ================================================================
    // Step 9: Display results
    // ================================================================
    
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "{hline 70}"
        di as text "ATT Estimation Results"
        di as text "{hline 70}"
        di as text ""
        di as text "  Dynamic ATT by Period (raw track):"
        di as text "  " _col(4) "{hline 54}"
        di as text "  " _col(4) %6s "nt" _col(11) %12s "ATT" _col(24) %12s "Std.Dev." _col(37) %8s "N" _col(46) %12s "SE"
        di as text "  " _col(4) "{hline 54}"
        
        local _pte_disp_row = 0
        foreach s of local pte_att_support_periods {
            local ++_pte_disp_row
            local row = `_pte_disp_row'
            local att_s = `att_raw_mat'[`row', 2]
            local sd_s = `att_raw_mat'[`row', 3]
            local n_s = `att_raw_mat'[`row', 4]
            local se_s = `att_raw_mat'[`row', 5]
            
            if !missing(`att_s') {
                di as text "  " _col(4) %6.0f `s' ///
                    _col(11) as result %12.4f `att_s' ///
                    _col(24) as result %12.4f `sd_s' ///
                    _col(37) as result %8.0f `n_s' ///
                    _col(46) as result %12.4f `se_s'
            }
        }
        
        di as text "  " _col(4) "{hline 54}"
        di as text "  " _col(4) %6s "All" ///
            _col(11) as result %12.4f `att_raw_overall' ///
            _col(24) as result %12.4f `att_raw_sd' ///
            _col(37) as result %8.0f `att_raw_N' ///
            _col(46) as result %12.4f `att_raw_se'
        
        di as text ""
        di as text "  Dynamic ATT by Period (trim track):"
        di as text "  " _col(4) "{hline 54}"
        di as text "  " _col(4) %6s "nt" _col(11) %12s "ATT" _col(24) %12s "Std.Dev." _col(37) %8s "N" _col(46) %12s "SE"
        di as text "  " _col(4) "{hline 54}"
        
        local _pte_disp_row = 0
        foreach s of local pte_att_support_periods {
            local ++_pte_disp_row
            local row = `_pte_disp_row'
            local att_s = `att_trim_mat'[`row', 2]
            local sd_s = `att_trim_mat'[`row', 3]
            local n_s = `att_trim_mat'[`row', 4]
            local se_s = `att_trim_mat'[`row', 5]
            
            if !missing(`att_s') {
                di as text "  " _col(4) %6.0f `s' ///
                    _col(11) as result %12.4f `att_s' ///
                    _col(24) as result %12.4f `sd_s' ///
                    _col(37) as result %8.0f `n_s' ///
                    _col(46) as result %12.4f `se_s'
            }
        }
        
        di as text "  " _col(4) "{hline 54}"
        di as text "  " _col(4) %6s "All" ///
            _col(11) as result %12.4f `att_trim_overall' ///
            _col(24) as result %12.4f `att_trim_sd' ///
            _col(37) as result %8.0f `att_trim_N' ///
            _col(46) as result %12.4f `att_trim_se'
        di as text "{hline 70}"
    }
    
    // ================================================================
    // Step 10: Restore xtset to original time variable
    // ================================================================
    
    `pte_restore_xtset'

    // Publish ATT outputs back onto the original caller dataset without
    // overwriting the raw eps0 residual pool from.
    local _pte_merge_vars "`pte_att_obsid' _pte_treat_year treat_yr0 _pte_nt _pte_omega_0 _pte_omega_0_trim _pte_tt_raw _pte_tt _pte_tt_trim _pte_eps0_draw _pte_eps0_trim_draw"
    foreach _maybe in _pte_tt_raw_sd _pte_tt_sd _pte_tt_trim_sd {
        capture confirm variable `_maybe'
        if _rc == 0 {
            local _pte_merge_vars "`_pte_merge_vars' `_maybe'"
        }
    }
    quietly preserve
        quietly keep `_pte_merge_vars'
        quietly save `pte_att_output_file', replace
    restore

    quietly use `pte_att_orig_data', clear
    foreach _outvar in _pte_treat_year treat_yr0 _pte_nt _pte_omega_0 _pte_omega_0_trim _pte_tt_raw _pte_tt _pte_tt_trim _pte_eps0_draw _pte_eps0_trim_draw _pte_tt_raw_sd _pte_tt_sd _pte_tt_trim_sd {
        capture drop `_outvar'
    }
    quietly merge 1:1 `pte_att_obsid' using `pte_att_output_file', nogen
    capture drop `pte_att_obsid'
    `pte_restore_xtset'

    // ================================================================
    // Step 11: Store e() return values
    // ================================================================
    
    // Rebuild a self-consistent ATT eclass result. Without an explicit
    // ereturn post, upstream e(b)/e(V)/e(sample) leak into _pte_att.
    // nt=-1 is retained only as the state anchor for counterfactual
    // simulation and must not enter the posted ATT estimation sample.
    tempvar _pte_att_esample
    quietly gen byte `_pte_att_esample' = !missing(_pte_tt) ///
        & inrange(_pte_nt, 0, `attperiods') & `_pte_target_sample'
    quietly count if `_pte_att_esample'
    local N_att_esample = r(N)

    tempname __b __V
    local _att_bnames ""
    local _att_post_cols ""
    foreach s of local pte_att_support_periods {
        local _att_bnames "`_att_bnames' ATT_`s'"
    }
    local _att_bnames "`_att_bnames' ATT_avg"

    local _att_bdim_full = colsof(`att_vec')
    forvalues i = 1/`_att_bdim_full' {
        local _att_coef_i = `att_vec'[1, `i']
        if !missing(`_att_coef_i') {
            local _att_post_cols "`_att_post_cols' `i'"
        }
    }

    local _att_bdim : word count `_att_post_cols'
    if `_att_bdim' == 0 {
        di as error "[pte] Internal error: ATT repost found no estimable coefficients"
        capture quietly use `pte_att_orig_data', clear
        `pte_restore_xtset'
        `_pte_restore_rngstate_failure'
        `_pte_clear_eclass'
        exit 498
    }

    matrix `__b' = J(1, `_att_bdim', .)
    matrix `__V' = J(`_att_bdim', `_att_bdim', 0)
    local _att_post_bnames ""
    local _att_j = 0
    foreach _att_i of local _att_post_cols {
        local ++_att_j
        matrix `__b'[1, `_att_j'] = `att_vec'[1, `_att_i']
        local _att_post_bnames "`_att_post_bnames' `: word `_att_i' of `_att_bnames''"
        local _att_se_i = `att_se_vec'[1, `_att_i']
        if !missing(`_att_se_i') {
            matrix `__V'[`_att_j', `_att_j'] = `=(`_att_se_i')^2'
        }
    }
    matrix colnames `__b' = `_att_post_bnames'
    matrix rownames `__b' = ATT
    matrix coleq `__b' = ""

    matrix rownames `__V' = `_att_post_bnames'
    matrix colnames `__V' = `_att_post_bnames'
    matrix coleq `__V' = ""
    matrix roweq `__V' = ""

    ereturn clear
    ereturn post `__b' `__V', esample(`_pte_att_esample') obs(`N_att_esample') depname("ATT")

    // --- Scalar returns: ATT results (canonical paper track) ---
    // NOTE: att and att_sd scalars removed — now stored as matrices e(att), e(att_sd)
    //       Overall values available via e(ATT_avg) and period-specific via e(att_0), etc.
    // Keep the dynamic SE path in matrix e(att_se); publishing the overall
    // scalar under the same name makes matrix consumers resolve a 1x1 object.
    ereturn scalar att_se_overall = `att_se'
    ereturn scalar att_N = `att_N'
    
    // --- Scalar returns: ATT results (trim aliases) ---
    // NOTE: att_trim and att_trim_sd scalars mirror the canonical paper track.
    ereturn scalar att_trim_se = `att_trim_se'
    ereturn scalar att_trim_N = `att_trim_N'
    ereturn scalar att_raw_se = `att_raw_se'
    ereturn scalar att_raw_N = `att_raw_N'
    
    // --- Scalar returns: Period-specific ATT (canonical + explicit aliases) ---
    // Sparse realized support is already compacted into att_*_mat and
    // e(attperiods). Publish scalar aliases by the actual event-time label,
    // not by compacted row index, so e(att_2) continues to mean ATT at nt=2.
    local _pte_att_scalar_row = 0
    foreach s of local pte_att_support_periods {
        local ++_pte_att_scalar_row
        local att_s = `att_mat'[`_pte_att_scalar_row', 2]
        local n_s = `att_mat'[`_pte_att_scalar_row', 4]
        if !missing(`att_s') {
            ereturn scalar att_`s' = `att_s'
            ereturn scalar att_N_`s' = `n_s'
        }
        local att_trim_s = `att_trim_mat'[`_pte_att_scalar_row', 2]
        local n_trim_s = `att_trim_mat'[`_pte_att_scalar_row', 4]
        if !missing(`att_trim_s') {
            ereturn scalar att_trim_`s' = `att_trim_s'
            ereturn scalar att_trim_N_`s' = `n_trim_s'
        }
        local att_raw_s = `att_raw_mat'[`_pte_att_scalar_row', 2]
        local n_raw_s = `att_raw_mat'[`_pte_att_scalar_row', 4]
        if !missing(`att_raw_s') {
            ereturn scalar att_raw_`s' = `att_raw_s'
            ereturn scalar att_raw_N_`s' = `n_raw_s'
        }
    }
    
    // --- Scalar returns: Sample sizes ---
    ereturn scalar N_original = `N_original'
    ereturn scalar N_control = `N_control'
    ereturn scalar N_outside = `N_outside'
    ereturn scalar N_filtered = `N_filtered'
    ereturn scalar N_treated_firms = `N_treated_firms'
    ereturn scalar N_counterfactual = `N_cf'
    ereturn scalar N_counterfactual_trim = `N_cf_trim'
    ereturn scalar N_cf_missing_unexpected = `N_unexpected_miss'
    ereturn scalar N_cf_trim_missing_unexpected = `N_unexpected_miss_trim'
    ereturn scalar N_eps0_pool = `N_eps0_pool'
    
    // --- Scalar returns: Configuration ---
    ereturn scalar omegapoly = `omegapoly'
    ereturn scalar attpoly = `attpoly'
    ereturn scalar nsim = `nsim'
    if `preserve_rng' {
        ereturn scalar seed = .
    }
    else {
        ereturn scalar seed = `seed'
    }
    ereturn local seed_source "`seed_source'"
    ereturn scalar sigma_eps = `sigma_eps'
    ereturn scalar sigma_eps_trim = `sigma_eps_trim'
    ereturn scalar trimeps = `upstream_trimeps'
    
    // --- Scalar returns: eps0 shock diagnostics ---
    ereturn scalar n_shocks = `eps0_N_all'
    ereturn scalar mean_eps0 = `eps0_mean_all'
    ereturn scalar sd_eps0 = `eps0_sd_all'
    ereturn scalar mean_eps0_trim = `eps0t_mean_all'
    ereturn scalar sd_eps0_trim = `eps0t_sd_all'
    
    // --- Matrix returns: table format (nperiods x 5) ---
    ereturn matrix att_table = `att_mat'
    ereturn matrix att_trim_table = `att_trim_mat'
    ereturn matrix att_raw_table = `att_raw_mat'
    
    // --- Matrix returns: spec-format row vectors ( TASK-008.7~009) ---
    ereturn matrix att = `att_vec'
    ereturn matrix att_trim = `att_trim_vec'
    ereturn matrix att_raw = `att_raw_vec'
    ereturn matrix att_sd = `att_sd_vec'
    ereturn matrix att_sd_trim = `att_sd_trim_vec'
    ereturn matrix att_sd_raw = `att_sd_raw_vec'
    ereturn matrix att_se = `att_se_vec'
    ereturn matrix N_by_period = `n_by_period'
    
    // --- Scalar returns: ATT_avg aliases ( TASK-008.5) ---
    ereturn scalar ATT_avg = `att_overall'
    ereturn scalar ATT_avg_trim = `att_trim_overall'
    ereturn scalar ATT_avg_raw = `att_raw_overall'
    ereturn scalar N_treated = `N_treated_firms'
    ereturn scalar attperiods_max = `attperiods'
    
    // --- Matrix returns: attperiods vector ( TASK-008.11.3) ---
    tempname attperiods_vec attperiods_mat
    matrix `attperiods_vec' = `attperiods_post'
    matrix `attperiods_mat' = `attperiods_vec'
    ereturn matrix attperiods = `attperiods_mat'
    ereturn matrix attperiods_vec = `attperiods_vec'
    
    tempname rho_0_ret
    matrix `rho_0_ret' = `rho_0_mat'
    ereturn matrix rho_0 = `rho_0_ret'
    if `pte_has_lag_supported' {
        ereturn scalar lag_treated_supported = `pte_lag_treated_supported'
    }
    if `pte_has_rho_1' {
        ereturn matrix rho_1 = `pte_rho_1_mat'
    }
    
    // --- Scalar returns: Stability checks ( IMPL-009) ---
    ereturn scalar stability_passed = `stability_passed'
    ereturn scalar stability_issues = `stability_issues'
    ereturn scalar overflow_detected = `overflow_detected'
    ereturn scalar omega0_unstable = `omega0_unstable'
    if !missing(`omega0_max') {
        ereturn scalar omega0_max = `omega0_max'
        ereturn scalar omega0_min = `omega0_min'
        ereturn scalar omega0_sd = `omega0_sd'
    }
    ereturn scalar omega0_truncated_n = `omega0_truncated_n'
    ereturn scalar omega0_truncated_upper = `omega0_truncated_upper'
    ereturn scalar omega0_truncated_lower = `omega0_truncated_lower'
    ereturn scalar rho1_unstable = `rho1_unstable'
    if !missing(`rho1_abs') {
        ereturn scalar rho1_abs = `rho1_abs'
    }
    ereturn scalar missing_propagation_issue = `missing_propagation_issue'
    if "`stabilitycheck'" != "nostabilitycheck" ///
        & `_pte_clip_enabled' {
        capture ereturn matrix missing_diag = `Missing_Diag'
    }
    ereturn scalar tt_extreme_n_017 = `tt_extreme_n_017'
    ereturn scalar tt_extreme_pct_017 = `tt_extreme_pct_017'
    if !missing(`tt_mean_017') {
        ereturn scalar tt_mean_017 = `tt_mean_017'
        ereturn scalar tt_sd_017 = `tt_sd_017'
        ereturn scalar tt_min_017 = `tt_min_017'
        ereturn scalar tt_max_017 = `tt_max_017'
    }
    
    // --- Local returns ---
    ereturn local treatment "`treatment'"
    if `"`pte_prodfunc'"' != "" {
        ereturn local prodfunc `"`pte_prodfunc'"'
    }
    if `"`pte_pfunc'"' != "" {
        ereturn local pfunc `"`pte_pfunc'"'
    }
    if `"`pte_stored_panel'"' != "" {
        ereturn local id `"`pte_stored_panel'"'
        ereturn local panelvar `"`pte_stored_panel'"'
        ereturn local idvar `"`pte_stored_panel'"'
    }
    if `"`pte_stored_time'"' != "" {
        ereturn local time `"`pte_stored_time'"'
        ereturn local timevar `"`pte_stored_time'"'
    }
    if !missing(`pte_stored_xtdelta') {
        ereturn scalar xtdelta = `pte_stored_xtdelta'
    }
    ereturn local cmd "_pte_att"
    ereturn local title "PTE ATT Estimation"
    if "`notrimeps'" != "" {
        ereturn local notrimeps "notrimeps"
    }
    if "`touse'" != "" {
        ereturn local touse "`touse'"
    }
    
    // ================================================================
    // Cleanup temporary scalars
    // ================================================================
    
    capture scalar drop _pte_att_rho0
    capture scalar drop _pte_att_rho1
    capture scalar drop _pte_att_rho2
    capture scalar drop _pte_att_rho3
    capture scalar drop _pte_att_rho4
    capture scalar drop _pte_nid
    capture scalar drop _pte_copy
    `_pte_restore_rngstate_success'
    
end
