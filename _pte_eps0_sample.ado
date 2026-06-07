*! _pte_eps0_sample.ado
*! Build the untreated-innovation support used to estimate G_epsilon^0 for ATT
*! simulation. The selected rows follow the live untreated evolution law rather
*! than the raw replication shortcut.

version 14.0
capture program drop _pte_eps0_sample
program define _pte_eps0_sample, eclass
    version 14.0
    
    // Snapshot the caller state before any gate can fail so eps0 support
    // setup never destroys the last certifiable dataset or e() object.
    tempfile pte_eps0_input_data
    quietly save `pte_eps0_input_data', replace
    tempname _pte_prev_est
    local _pte_has_prev_est = 0
    capture estimates store `_pte_prev_est', copy
    if _rc == 0 {
        local _pte_has_prev_est = 1
    }
    // Parse touse() as a raw name token instead of varname so the helper can
    // enforce the exact-name active-sample contract before Stata expands any
    // shadow abbreviation.
    capture noisily syntax, treatment(name) [eps0window(integer 0) NODIAGnose TOUSE(name) LEGACYPOOLEDeps0]
    if _rc != 0 {
        local _pte_syntax_rc = _rc
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit `_pte_syntax_rc'
    }
    
    // omega must resolve to the exact realized-productivity column. Without
    // exact matching, Stata can silently bind omega -> omega_* via
    // abbreviation; without the numeric guard, the eps0 arithmetic fails
    // later with a generic type mismatch instead of an explicit contract
    // error at the input gate.
    capture confirm variable omega, exact
    if _rc != 0 {
        di as error "[pte] Error: variable 'omega' not found or not numeric"
        di as error "[pte] Please run and first"
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit 111
    }

    capture confirm numeric variable omega
    if _rc != 0 {
        di as error "[pte] Error: variable 'omega' not found or not numeric"
        di as error "[pte] Please run and first"
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit 111
    }
    
    // Preserve the literal treatment() token until the exact-name check so
    // the untreated-support contract cannot be satisfied by an abbreviation.
    capture confirm variable `treatment', exact
    if _rc != 0 {
        di as error "[pte] Error: treatment variable '`treatment'' not found"
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit 111
    }
    capture confirm numeric variable `treatment'
    if _rc != 0 {
        di as error "[pte] Error: treatment variable '`treatment'' must be numeric"
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit 111
    }
    
    // Lagged omega and treatment enter the untreated law, so panel structure
    // must be live before any support reconstruction starts.
    capture _xt, trequired
    if _rc != 0 {
        di as error "[pte] Error: data must be xtset as panel"
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit 459
    }
    local panelvar = r(ivar)
    local timevar = r(tvar)

    // eps0window() is a count of panel periods and cannot be negative.
    if `eps0window' < 0 {
        di as error "[pte] Error: eps0window must be non-negative"
        di as error "[pte]        Specified: eps0window(`eps0window')"
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit 198
    }
    
    // eps0 must be backed out from a live evolution state; the
    // accepted bridge commands are the standalone evolution step, the public
    // pte wrapper, and the downstream workers that preserve
    // rho_0/rho_1 metadata.
    local last_cmd = e(cmd)
    local bridge_from_epic2 = inlist("`last_cmd'", "_pte_evolution", "_pte_treatdep_evolution", "_pte_omega", "_pte_eps0_sample", "_pte_winsorize", "pte")
    if !`bridge_from_epic2' {
        di as error "[pte] Error: _pte_eps0_sample requires live evolution state"
        di as error "[pte]        Current e(cmd): `last_cmd'"
        di as error "[pte]        Run _pte_evolution, _pte_treatdep_evolution, _pte_omega, or pte before _pte_eps0_sample"
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit 301
    }

    capture confirm matrix e(rho_0)
    if _rc != 0 {
        di as error "[pte] Error: current _pte_evolution results are incomplete"
        di as error "[pte]        Missing e(rho_0); re-run _pte_evolution"
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit 301
    }

    tempname _pte_eps0_rho_0 _pte_eps0_rho_1
    matrix `_pte_eps0_rho_0' = e(rho_0)
    local evo_has_treated_state = 0

    local evo_omegapoly = e(omegapoly)
    local evo_rho0 = e(rho0)
    local evo_rho1 = e(rho1)
    if `evo_omegapoly' >= 2 local evo_rho2 = e(rho2)
    if `evo_omegapoly' >= 3 local evo_rho3 = e(rho3)
    if `evo_omegapoly' >= 4 local evo_rho4 = e(rho4)
    local evo_N_evo = e(N_evo)
    local evo_has_N_lag_untreated = 0
    local evo_has_N_lag_treated = 0
    local evo_has_lag_supported = 0
    local evo_has_trimeps = 0
    local evo_N_lag_untreated = .
    local evo_N_lag_treated = .
    local evo_lag_supported = .
    local evo_trimeps = .
    capture local evo_N_lag_untreated = e(N_lag_untreated)
    if _rc == 0 {
        local evo_has_N_lag_untreated = 1
    }
    capture local evo_N_lag_treated = e(N_lag_treated)
    if _rc == 0 {
        local evo_has_N_lag_treated = 1
    }
    capture local evo_lag_supported = e(lag_treated_supported)
    if _rc == 0 {
        local evo_has_lag_supported = 1
    }
    if `evo_has_lag_supported' {
        if `evo_lag_supported' {
            capture confirm matrix e(rho_1)
            if _rc == 0 {
                matrix `_pte_eps0_rho_1' = e(rho_1)
                local evo_has_treated_state = 1
            }
        }
    }
    else {
        // Legacy bridge states may predate lag_treated_supported while still
        // carrying a valid treated-law matrix. Fall back to matrix presence
        // only when the support flag itself is unavailable.
        capture confirm matrix e(rho_1)
        if _rc == 0 {
            matrix `_pte_eps0_rho_1' = e(rho_1)
            local evo_has_treated_state = 1
        }
    }
    if `evo_has_treated_state' {
        local evo_gamma1 = e(gamma1)
        if `evo_omegapoly' >= 2 local evo_gamma2 = e(gamma2)
        if `evo_omegapoly' >= 3 local evo_gamma3 = e(gamma3)
        if `evo_omegapoly' >= 4 local evo_gamma4 = e(gamma4)
        local evo_delta = e(delta)
    }
    capture local evo_trimeps = e(trimeps)
    if _rc == 0 & !missing(`evo_trimeps') {
        local evo_has_trimeps = 1
    }
    capture local evo_r2 = e(r2)
    if _rc != 0 | missing(`evo_r2') {
        capture local evo_r2 = e(r2_evo)
    }
    capture local evo_rmse = e(rmse)
    if _rc != 0 | missing(`evo_rmse') {
        capture local evo_rmse = e(rmse_evo)
    }
    local evo_prodfunc `"`e(prodfunc)'"'
    if "`evo_prodfunc'" == "" {
        local evo_prodfunc `"`e(pfunc)'"'
    }
    local evo_pfunc `"`e(pfunc)'"'
    if "`evo_pfunc'" == "" {
        local evo_pfunc `"`evo_prodfunc'"'
    }

    local evo_treatment = e(treatment)
    if "`evo_treatment'" != "`treatment'" {
        di as error "[pte] Error: treatment(`treatment') does not match current _pte_evolution results"
        di as error "[pte]        Last _pte_evolution used treatment(`evo_treatment')"
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit 198
    }

    local stored_panel `"`e(idvar)'"'
    if "`stored_panel'" == "" {
        local stored_panel `"`e(id)'"'
    }
    local stored_time `"`e(timevar)'"'
    if "`stored_time'" == "" {
        local stored_time `"`e(time)'"'
    }
    local stored_xtdelta = .
    tempname _pte_eps0_xtdelta
    capture scalar `_pte_eps0_xtdelta' = e(xtdelta)
    if _rc == 0 & !missing(`_pte_eps0_xtdelta') {
        local stored_xtdelta = `_pte_eps0_xtdelta'
    }
    local current_panelvar "`panelvar'"
    local current_timevar "`timevar'"
    local current_xtdelta = real("`r(tdelta)'")
    local restore_stored_xtset = 0
    if "`stored_panel'" == "" {
        local stored_panel "`current_panelvar'"
    }
    if "`stored_time'" == "" {
        local stored_time "`current_timevar'"
    }
    if missing(`stored_xtdelta') {
        local stored_xtdelta = `current_xtdelta'
    }

    tempvar _pte_sample
    if "`touse'" != "" {
        capture confirm variable `touse', exact
        if _rc != 0 {
            di as error "[pte] Error: touse variable '`touse'' not found"
            quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
                estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
            exit 111
        }
        capture confirm numeric variable `touse'
        if _rc != 0 {
            di as error "[pte] Error: touse variable '`touse'' must be numeric"
            quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
                estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
            exit 111
        }
        quietly gen byte `_pte_sample' = (`touse' != 0 & !missing(`touse'))
    }
    else {
        // Default to the persisted active sample when the caller
        // reruns eps0 construction after a live evolution fit. Falling back
        // to the full dataset would let rows outside the identified h_bar_0
        // sample re-enter the untreated innovation support.
        capture confirm variable _pte_active_sample, exact
        if _rc == 0 {
            capture confirm numeric variable _pte_active_sample
            if _rc != 0 {
                di as error "[pte] Error: persisted active sample '_pte_active_sample' must be numeric"
                di as error "[pte]        Re-run _pte_evolution or _pte_omega to rebuild the bridge state"
                quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
                    estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
                exit 111
            }
            quietly gen byte `_pte_sample' = (_pte_active_sample != 0 & !missing(_pte_active_sample))
        }
        else {
            di as error "[pte] Error: current `last_cmd' state is missing '_pte_active_sample'"
            if inlist("`last_cmd'", "_pte_winsorize", "_pte_eps0_sample") {
                di as error "[pte]        e(sample) from `last_cmd' is the eps0 shock support,"
                di as error "[pte]        not the active sample required for eps0 reconstruction"
            }
            else {
                di as error "[pte]        e(sample) from `last_cmd' is not the active sample"
                di as error "[pte]        required for eps0 reconstruction"
            }
            di as error "[pte]        Re-run _pte_eps0_sample with touse(), or rebuild '_pte_active_sample'"
            quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
                estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
            exit 498
        }
    }

    quietly count if `_pte_sample'
    if r(N) == 0 {
        di as error "[pte] Error: active sample excludes all observations"
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit 2000
    }

    // Treatment must be binary on the active sample only.
    // Values outside the live active sample do not enter the eps0 support and
    // must not veto it.
    quietly {
        count if `_pte_sample' & !inlist(`treatment', 0, 1) & !missing(`treatment')
        if r(N) > 0 {
            di as error "[pte] Error: treatment variable must be binary (0/1)"
            di as error "[pte]        Found non-binary values in '`treatment''"
            quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
                estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
            exit 450
        }
    }

    if "`stored_panel'" != "" & "`stored_time'" != "" {
        capture confirm variable `stored_panel', exact
        if _rc != 0 {
            di as error "[pte] Error: stored panel variable '`stored_panel'' not found"
            di as error "[pte]        Re-run _pte_evolution or _pte_omega on the current dataset"
            quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
                estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
            exit 111
        }
        capture confirm variable `stored_time', exact
        if _rc != 0 {
            di as error "[pte] Error: stored time variable '`stored_time'' not found"
            di as error "[pte]        Re-run _pte_evolution or _pte_omega on the current dataset"
            quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
                estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
            exit 111
        }

        local stored_xtdelta_mismatch = 0
        if !missing(`stored_xtdelta') & !missing(`current_xtdelta') ///
            & `current_xtdelta' != `stored_xtdelta' {
            local stored_xtdelta_mismatch = 1
        }
        if "`current_panelvar'" != "`stored_panel'" | "`current_timevar'" != "`stored_time'" | ///
            `stored_xtdelta_mismatch' {
            local stored_delta_opt ""
            if !missing(`stored_xtdelta') {
                local stored_delta_opt "delta(`stored_xtdelta')"
            }
            capture quietly xtset `stored_panel' `stored_time', `stored_delta_opt'
            local _pte_eps0_xtset_rc = _rc
            if `_pte_eps0_xtset_rc' != 0 {
                di as error "[pte] Error: could not restore stored panel structure `stored_panel' `stored_time'"
                di as error "[pte]        Ensure the current data still matches the live state"
                quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
                    estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
                exit `_pte_eps0_xtset_rc'
            }
            local restore_stored_xtset = 1
            local panelvar "`stored_panel'"
            local timevar "`stored_time'"
        }
    }

    local midvar "_pte_mid"
    capture confirm variable `midvar', exact
    if _rc != 0 {
        local midvar "mid"
        capture confirm variable `midvar', exact
        if _rc != 0 {
            di as error "[pte] Error: neither '_pte_mid' nor legacy 'mid' found from production function estimation"
            quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
                estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
            exit 111
        }
    }

    capture confirm numeric variable `midvar'
    if _rc != 0 {
        di as error "[pte] Error: transition indicator '`midvar'' must be numeric"
        di as error "[pte]        Run _pte_transition again to rebuild the switch indicator"
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit 111
    }

    capture noisily _pte_validate_mid_contract, midvar(`midvar') ///
        treatment(`treatment') panelvar(`panelvar') timevar(`timevar') ///
        touse(`_pte_sample') context("_pte_eps0_sample")
    if _rc != 0 {
        local _pte_mid_contract_rc = _rc
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit `_pte_mid_contract_rc'
    }

    tempvar _pte_evo_sample
    // Rebuild the admissible evolution rows from the live data contract
    // instead of relying on the current command's predict context. This makes
    // eps0 recovery robust to the wrapper commands while preserving
    // the same sample rules as _pte_evolution.
    quietly gen byte `_pte_evo_sample' = ///
        (`_pte_sample' & `midvar' == 0 & L.`_pte_sample' == 1)
    quietly replace `_pte_evo_sample' = 0 if ///
        missing(omega, `treatment', L.omega, L.`treatment')
    
    // Recover the first observed 0->1 entry date for each firm. The timing is
    // used only to delimit untreated support; left-censored treated firms keep
    // missing entry years because their pre-treatment state is not observed.
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "{hline 60}"
        di as text "eps0 Sample Selection"
        di as text "{hline 60}"
    }
    
    // Rebuild exact-name timing metadata from scratch on each call.
    capture drop _pte_treat_year
    
    // Calculate the observed 0->1 treatment-entry year from the full observed
    // treatment path. Left-censored treated firms have no observed entry event
    // and must therefore keep missing timing metadata.
    tempvar _pte_entry _pte_ever_treated_obs
    quietly gen byte `_pte_entry' = ///
        (`treatment' == 1 & L.`treatment' == 0) if ///
        !missing(`treatment', L.`treatment')
    quietly bysort `panelvar': egen _pte_treat_year = ///
        min(cond(`_pte_entry' == 1, `timevar', .))
    quietly bysort `panelvar': egen byte `_pte_ever_treated_obs' = ///
        max(cond(!missing(`treatment') & `treatment' == 1, 1, 0))
    label variable _pte_treat_year "Observed treatment entry year (missing if never-treated or left-censored)"
    
    // bysort disturbs the panel order expected by later lag operations.
    quietly sort `panelvar' `timevar'

    // If every treated cohort starts in the first observed period and there
    // are no never-treated evolution rows, the untreated innovation law is not
    // identified on the current sample.
    quietly levelsof _pte_treat_year if `_pte_sample' & !missing(_pte_treat_year), local(treat_years)
    quietly summarize `timevar' if `_pte_sample'
    local min_time = r(min)
    
    local all_first_period = 1
    local has_treated = ("`treat_years'" != "")
    foreach ty of local treat_years {
        if `ty' != `min_time' local all_first_period = 0
    }

    quietly count if `_pte_evo_sample' & `treatment' == 0 & `_pte_ever_treated_obs' == 0
    local N_never_evo = r(N)
    
    if `all_first_period' == 1 & `has_treated' == 1 & `N_never_evo' == 0 {
        di as error ""
        di as error "[pte] Error: all treated firms received treatment in the first period (year=`min_time')"
        di as error "[pte]        No pre-treatment observations available for eps0 estimation"
        di as error "[pte]        No never-treated control observations remain in the active evolution sample"
        di as error "[pte]        PTE method requires staggered treatment timing or never-treated controls"
        di as error ""
        di as error "[pte] Solutions:"
        di as error "[pte]   1. Include never-treated firms as control group"
        di as error "[pte]   2. Use data that includes pre-treatment periods"
        di as error "[pte]   3. Consider a different identification strategy"
        di as error ""
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit 2001
    }

    // The canonical untreated support is D==0 and strictly pre-entry on the
    // admissible evolution rows. This preserves the paper's untreated-law
    // interpretation while correcting the replication shortcut that can retain
    // treated-post observations in some branches. The legacy pooled benchmark
    // branch below is deliberately narrower: it reproduces the historical
    // att_estimation_pool_trlg.do shortcut for direct DO comparison only.

    // Drop the exact eps0 payload before its indicator. Otherwise Stata may
    // resolve _pte_eps0 to _pte_eps0_ind through abbreviation matching.
    // This is a namespace guard, not a logic step.
    // Clean up existing variables (order matters: drop _pte_eps0 BEFORE
    // _pte_eps0_ind exists, to avoid Stata abbreviation matching _pte_eps0
    // to _pte_eps0_ind)
    capture drop _pte_eps0
    capture drop _pte_eps0_ind
    
    // Ever-treated firms contribute only pre-entry untreated rows.
    quietly gen byte _pte_eps0_ind = (`_pte_evo_sample' & `treatment'==0 & `timevar' < _pte_treat_year)
    label variable _pte_eps0_ind "eps0 sample indicator (1=selected)"
    
    // Pure control group (never treated): use all D=0 observations.
    // Left-censored treated firms also have missing _pte_treat_year, but they
    // are not never-treated and must not enter the untreated innovation pool.
    quietly replace _pte_eps0_ind = ///
        (`_pte_evo_sample' & `treatment'==0 & `_pte_ever_treated_obs' == 0) ///
        if missing(_pte_treat_year)
    
    if "`legacypooledeps0'" != "" {
        if `eps0window' > 0 {
            di as error "[pte] Error: legacypooledeps0 cannot be combined with eps0window(`eps0window')"
            quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
                estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
            exit 198
        }
        quietly replace _pte_eps0_ind = (`_pte_evo_sample' & `treatment'==0 & `timevar' <= 2010)
        if "`nodiagnose'" == "" {
            di as text "  Using legacy pooled DO eps0 support: year<=2010 and untreated"
        }
    }
    
    // eps0window() restricts support to a common untreated window that is
    // anchored at the earliest treated entry still backed by admissible
    // untreated evolution rows in the live sample.
    if "`legacypooledeps0'" == "" & `eps0window' > 0 {
        quietly xtset
        local _pte_window_delta = real("`r(tdelta)'")
        if missing(`_pte_window_delta') | `_pte_window_delta' <= 0 {
            local _pte_window_delta = 1
        }
        local _pte_window_span = `eps0window' * `_pte_window_delta'

        // Anchor the common eps0 window at the earliest observed treatment
        // entry year among treated cohorts that remain active in the current
        // sample AND still contribute admissible untreated evolution support.
        // eps0window() selects support for epsilon^0, so a cohort whose live
        // rows are only post-treatment cannot pin the common untreated window.
        tempvar _pte_anchor_support
        quietly bysort `panelvar': egen byte `_pte_anchor_support' = ///
            max(cond(`_pte_evo_sample' & `treatment' == 0 & ///
            !missing(_pte_treat_year) & `timevar' < _pte_treat_year, 1, 0))
        quietly summarize _pte_treat_year if ///
            `_pte_sample' & `_pte_anchor_support' == 1 & ///
            !missing(_pte_treat_year), meanonly
        local anchor_year = r(min)

        if missing(`anchor_year') {
            di as error "[pte] Error: eps0window() requires at least one treated cohort with admissible untreated evolution support"
            quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
                estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
            exit 2000
        }

        // A too-wide window is informative but not fatal; the same common
        // untreated anchor rule still applies on the observed support.
        quietly summarize `timevar' if `treatment' == 0 & `_pte_evo_sample'
        local min_year = r(min)
        local max_year = r(max)
        local data_span = floor((`max_year' - `min_year') / `_pte_window_delta' + 1e-10) + 1
        
        if `eps0window' > `data_span' {
            if "`nodiagnose'" == "" {
                di as text ""
                di as text "{bf:Note}: eps0window(`eps0window') exceeds data span (`data_span' periods)"
                di as text "       Available time range: `min_year' to `max_year'"
                di as text "       The common anchor-year window is still applied on the live untreated support"
                di as text ""
            }
        }
        else {
            if "`nodiagnose'" == "" {
                di as text "  Using eps0window(`eps0window'): limiting to the `eps0window' periods before the earliest observed entry year among active treated cohorts (`anchor_year')"
            }
        }

        // Paper contract: eps0window() always defines a common anchor-year
        // window over untreated observations, including the overflow case.
        // Respect the live xtset delta(): eps0window(#) is a count of panel
        // periods, not a raw timevar difference.
        quietly replace _pte_eps0_ind = (`_pte_evo_sample' & `treatment'==0 & ///
            `timevar' >= `anchor_year' - `_pte_window_span' & ///
            `timevar' < `anchor_year' & ///
            (`_pte_ever_treated_obs' == 0 | ///
            (!missing(_pte_treat_year) & `timevar' < _pte_treat_year)))
    }
    
    // eps0 is the untreated innovation epsilon^0, so on the selected untreated
    // sample omega_hat must equal h_bar_0(L.omega). Rebuild it from the
    // published rho_0 coefficients instead of relying on predict, xb.

    capture drop _pte_omega_hat
    if "`legacypooledeps0'" != "" {
        quietly gen double _pte_omega_hat = . 
        quietly replace _pte_omega_hat = `evo_rho0' + `evo_rho1' * L.omega if `_pte_evo_sample'
        if `evo_omegapoly' >= 2 {
            quietly replace _pte_omega_hat = _pte_omega_hat + `evo_rho2' * ((L.omega)^2) if `_pte_evo_sample'
        }
        if `evo_omegapoly' >= 3 {
            quietly replace _pte_omega_hat = _pte_omega_hat + `evo_rho3' * ((L.omega)^3) if `_pte_evo_sample'
        }
        if `evo_omegapoly' >= 4 {
            quietly replace _pte_omega_hat = _pte_omega_hat + `evo_rho4' * ((L.omega)^4) if `_pte_evo_sample'
        }
        if `evo_has_treated_state' {
            quietly replace _pte_omega_hat = _pte_omega_hat + `evo_gamma1' * (L.omega * L.`treatment') if `_pte_evo_sample'
            if `evo_omegapoly' >= 2 {
                quietly replace _pte_omega_hat = _pte_omega_hat + `evo_gamma2' * ((L.omega)^2 * L.`treatment') if `_pte_evo_sample'
            }
            if `evo_omegapoly' >= 3 {
                quietly replace _pte_omega_hat = _pte_omega_hat + `evo_gamma3' * ((L.omega)^3 * L.`treatment') if `_pte_evo_sample'
            }
            if `evo_omegapoly' >= 4 {
                quietly replace _pte_omega_hat = _pte_omega_hat + `evo_gamma4' * ((L.omega)^4 * L.`treatment') if `_pte_evo_sample'
            }
            quietly replace _pte_omega_hat = _pte_omega_hat + `evo_delta' * L.`treatment' if `_pte_evo_sample'
        }
    }
    else {
        quietly gen double _pte_omega_hat = . 
        quietly replace _pte_omega_hat = `evo_rho0' + `evo_rho1' * L.omega if `_pte_evo_sample'
        if `evo_omegapoly' >= 2 {
            quietly replace _pte_omega_hat = _pte_omega_hat + `evo_rho2' * ((L.omega)^2) if `_pte_evo_sample'
        }
        if `evo_omegapoly' >= 3 {
            quietly replace _pte_omega_hat = _pte_omega_hat + `evo_rho3' * ((L.omega)^3) if `_pte_evo_sample'
        }
        if `evo_omegapoly' >= 4 {
            quietly replace _pte_omega_hat = _pte_omega_hat + `evo_rho4' * ((L.omega)^4) if `_pte_evo_sample'
        }
    }
    label variable _pte_omega_hat "Evolution regression predicted omega"

    // Outside the identified support there is no admissible untreated shock.
    quietly replace _pte_omega_hat = . if _pte_eps0_ind != 1

    // Large realized omega values can be genuine, but they often flag an
    // upstream staging problem before ATT simulation amplifies them.
    quietly summarize omega if _pte_eps0_ind == 1
    local omega_min = r(min)
    local omega_max = r(max)
    
    if abs(`omega_max') > 10 | abs(`omega_min') > 10 {
        if "`nodiagnose'" == "" {
            di as text ""
            di as text "{bf:Warning}: omega contains extreme values"
            di as text "          min = " %9.4f `omega_min' ", max = " %9.4f `omega_max'
            di as text "          Counterfactual simulation may be unstable"
            di as text "          Consider winsorizing omega before estimation"
            di as text ""
        }
    }
    
    // The recovered untreated innovation is the realized omega residual around
    // the untreated law h_bar_0 on the selected support.
    quietly gen double _pte_eps0 = omega - _pte_omega_hat if _pte_eps0_ind == 1
    label variable _pte_eps0 "Productivity shock residual (eps0)"

    // Count the live untreated-support rows that actually deliver eps0 draws.
    quietly count if _pte_eps0_ind == 1 & !missing(_pte_eps0)
    local N_eps0 = r(N)
    
    // Treated cohorts contribute only through their observed pre-entry rows.
    quietly count if _pte_eps0_ind == 1 & !missing(_pte_eps0) & !missing(_pte_treat_year)
    local N_eps0_treated = r(N)
    
    // Never-treated firms anchor the pure-control part of G_epsilon^0.
    quietly count if _pte_eps0_ind == 1 & !missing(_pte_eps0) & `_pte_ever_treated_obs' == 0
    local N_eps0_control = r(N)
    
    // ATT simulation cannot proceed without at least one identified untreated
    // innovation draw on the live support.
    if `N_eps0' == 0 {
        di as error "[pte] Error: eps0 sample is empty"
        di as error "[pte]        No observations satisfy D==0 & year < treat_year"
        quietly _pte_eps0_sample_restore, datafile(`pte_eps0_input_data') ///
            estname(`_pte_prev_est') hasest(`_pte_has_prev_est')
        exit 2000
    }
    
    if `N_eps0' < 30 {
        if "`nodiagnose'" == "" {
            di as text "{bf:Warning}: Small eps0 sample size (N=`N_eps0' < 30)"
            di as text "          Shock distribution is estimable but may be noisy"
        }
    }
    else if `N_eps0' < 50 {
        if "`nodiagnose'" == "" {
            di as text "{bf:Warning}: Small eps0 sample size (N=`N_eps0')"
            di as text "          Results may be less reliable"
        }
    }
    
    // These moments summarize the realized support that later gets winsorized
    // or reused directly, depending on the live trimeps bridge.
    quietly summarize _pte_eps0 if _pte_eps0_ind == 1
    local eps0_mean = r(mean)
    local eps0_sd = r(sd)
    local eps0_min = r(min)
    local eps0_max = r(max)
    local sigma_eps = r(sd)
    if `N_eps0' == 1 & missing(`sigma_eps') {
        local sigma_eps = 0
    }

    local eps0_p1 = .
    local eps0_p99 = .
    local sigma_eps_trim = .
    local N_eps0_trim = 0
    if `N_eps0' > 0 {
        quietly _pctile _pte_eps0 if _pte_eps0_ind == 1, p(1 99)
        local eps0_p1 = r(r1)
        local eps0_p99 = r(r2)

        tempvar _pte_eps0_trim_work
        quietly gen double `_pte_eps0_trim_work' = _pte_eps0 if _pte_eps0_ind == 1
        quietly replace `_pte_eps0_trim_work' = . if ///
            `_pte_eps0_trim_work' < `eps0_p1' | `_pte_eps0_trim_work' > `eps0_p99'
        quietly summarize `_pte_eps0_trim_work'
        local sigma_eps_trim = r(sd)
        local N_eps0_trim = r(N)

        if `N_eps0_trim' == 1 & missing(`sigma_eps_trim') {
            local sigma_eps_trim = 0
        }
    }

    if missing(`sigma_eps_trim') {
        local sigma_eps_trim = `sigma_eps'
        local N_eps0_trim = `N_eps0'
    }

    // _pte_eps0_sample owns support selection, not the upstream trim-law
    // choice. When a live bridge already disabled trimming, keep
    // that configuration while recomputing the raw sigma on the current
    // support so downstream ATT consumers stay on the same shock law.
    local bridge_trimeps = 1
    if `evo_has_trimeps' {
        local bridge_trimeps = `evo_trimeps'
    }
    if `bridge_trimeps' == 0 {
        local sigma_eps_trim = `sigma_eps'
        local N_eps0_trim = `N_eps0'
        local eps0_p1 = .
        local eps0_p99 = .
    }
    
    // Large mean drift is not an algebraic impossibility, but it often
    // signals that the selected support no longer aligns with the posted law.
    if abs(`eps0_mean') > 0.1 {
        if "`nodiagnose'" == "" {
            di as text "{bf:Warning}: eps0 mean = " %9.6f `eps0_mean' " (expected ≈ 0)"
        }
    }
    
    // Post eps0 support as the new estimation sample so downstream ATT code
    // can draw from the certified untreated innovation pool directly.
    tempvar touse
    quietly gen byte `touse' = (_pte_eps0_ind == 1 & !missing(_pte_eps0))

    ereturn post, esample(`touse') obs(`N_eps0')
    
    // Publish support size and shock moments for later simulation and
    // diagnostics.
    ereturn scalar N_eps0 = `N_eps0'
    ereturn scalar N_eps0_treated = `N_eps0_treated'
    ereturn scalar N_eps0_control = `N_eps0_control'
    ereturn scalar eps0_mean = `eps0_mean'
    ereturn scalar eps0_sd = `eps0_sd'
    ereturn scalar eps0_min = `eps0_min'
    ereturn scalar eps0_max = `eps0_max'
    ereturn scalar eps0window = `eps0window'
    local legacy_pooled_eps0_flag 0
    if "`legacypooledeps0'" != "" {
        local legacy_pooled_eps0_flag 1
    }
    ereturn scalar legacy_pooled_eps0 = `legacy_pooled_eps0_flag'
    ereturn scalar sigma_eps = `sigma_eps'
    ereturn scalar sigma_eps_trim = `sigma_eps_trim'
    ereturn scalar N_eps0_trim = `N_eps0_trim'
    ereturn scalar eps0_p1 = `eps0_p1'
    ereturn scalar eps0_p99 = `eps0_p99'
    ereturn scalar trimeps = `bridge_trimeps'
    
    // Keep the identifying variable names on the live bridge.
    ereturn local treatment = "`treatment'"
    ereturn local pfunc = "`evo_pfunc'"
    ereturn local prodfunc = "`evo_prodfunc'"
    ereturn local id = "`stored_panel'"
    ereturn local time = "`stored_time'"
    ereturn local idvar = "`stored_panel'"
    ereturn local timevar = "`stored_time'"
    ereturn local cmd = "_pte_eps0_sample"
    ereturn local title = "PTE eps0 Sample Selection"
    
    // Preserve evolution state for downstream modular steps such as
    // _pte_winsorize -> _pte_att, while intentionally leaving e(b)/e(V) empty.
    ereturn scalar omegapoly = `evo_omegapoly'
    ereturn scalar rho0 = `evo_rho0'
    ereturn scalar rho1 = `evo_rho1'
    if `evo_omegapoly' >= 2 {
        ereturn scalar rho2 = `evo_rho2'
    }
    if `evo_omegapoly' >= 3 {
        ereturn scalar rho3 = `evo_rho3'
    }
    if `evo_omegapoly' >= 4 {
        ereturn scalar rho4 = `evo_rho4'
    }
    if `evo_has_treated_state' {
        ereturn scalar gamma1 = `evo_gamma1'
        if `evo_omegapoly' >= 2 {
            ereturn scalar gamma2 = `evo_gamma2'
        }
        if `evo_omegapoly' >= 3 {
            ereturn scalar gamma3 = `evo_gamma3'
        }
        if `evo_omegapoly' >= 4 {
            ereturn scalar gamma4 = `evo_gamma4'
        }
        ereturn scalar delta = `evo_delta'
    }
    ereturn scalar N_evo = `evo_N_evo'
    if `evo_has_N_lag_untreated' {
        ereturn scalar N_lag_untreated = `evo_N_lag_untreated'
    }
    if `evo_has_N_lag_treated' {
        ereturn scalar N_lag_treated = `evo_N_lag_treated'
    }
    if `evo_has_lag_supported' {
        ereturn scalar lag_treated_supported = `evo_lag_supported'
    }
    ereturn scalar r2 = `evo_r2'
    ereturn scalar rmse = `evo_rmse'
    ereturn scalar r2_evo = `evo_r2'
    ereturn scalar rmse_evo = `evo_rmse'
    if !missing(`stored_xtdelta') {
        ereturn scalar xtdelta = `stored_xtdelta'
    }
    ereturn matrix rho_0 = `_pte_eps0_rho_0'
    if `evo_has_treated_state' {
        ereturn matrix rho_1 = `_pte_eps0_rho_1'
    }

    if `restore_stored_xtset' {
        local restore_delta_opt ""
        if !missing(`current_xtdelta') {
            local restore_delta_opt "delta(`current_xtdelta')"
        }
        capture quietly xtset `current_panelvar' `current_timevar', `restore_delta_opt'
    }

    if `_pte_has_prev_est' {
        capture estimates drop `_pte_prev_est'
        local _pte_has_prev_est = 0
    }
    
    // Optional diagnostics describe the certified support but do not change
    // the posted bridge contract.
    if "`nodiagnose'" == "" {
        di as text ""
        di as text "  eps0 Sample Diagnostics:"
        di as text "  {hline 50}"
        di as text "  Total observations:      " as result %10.0fc `N_eps0'
        di as text "  From treated firms:      " as result %10.0fc `N_eps0_treated'
        di as text "  From pure control:       " as result %10.0fc `N_eps0_control'
        di as text ""
        di as text "  eps0 Statistics:"
        di as text "    Mean:                  " as result %10.6f `eps0_mean'
        di as text "    Std. Dev.:             " as result %10.6f `eps0_sd'
        di as text "    Trimmed Std. Dev.:     " as result %10.6f `sigma_eps_trim'
        di as text "    Min:                   " as result %10.6f `eps0_min'
        di as text "    Max:                   " as result %10.6f `eps0_max'
        di as text ""
        if `eps0window' > 0 {
            di as text "  eps0window:              " as result %10.0f `eps0window'
        }
        else {
            di as text "  eps0window:              " as result "all pre-treatment"
        }
        di as text "{hline 60}"
    }
    
end
