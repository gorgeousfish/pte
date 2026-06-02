*! pte_compare.ado
*! Method comparison command for pte package
*! Dispatches to specific method implementations
*!
*! Methods:
*!   expost   - Ex-post regression + TWFE (Method I)
*!   endog    - Endogenous productivity + TWFE (Method II)
*!   clktwfe  - CLK + TWFE (Method III)
*!   all      - Run all three methods

version 14.0
capture program drop pte_compare
program define pte_compare, eclass
    version 14.0

    local _pte_compare_optscan " `0' "
    // Keep the omission sentinel aligned with Stata's documented minimum
    // abbreviation omegap:. Legal spellings such as omegap(-1) are still
    // explicit public inputs and must not be mistaken for omission.
    local _pte_compare_has_omegapoly = ///
        regexm(lower(`"`_pte_compare_optscan'"'), ///
        "(^|[ ,])(omegapoly|omegapol|omegapo|omegap)[ ]*[(]")

    syntax , [Method(string) ALL ///
              treatment(name) ///
              OMEGApoly(integer -1) ///
              SPECs(numlist integer min=1 max=3 >0 <4) ///
              ABsorb(string) VCE(string) INDustry(string) ///
              LAGTreatment DIAGnose noREPort]
    
    // =========================================================================
    // Validate prerequisites
    // =========================================================================
    
    if "`e(cmd)'" != "pte" {
        di as error "Error 301: pte has not been run."
        di as error "Please run {bf:pte} first."
        exit 301
    }
    
    local _pte_compare_live_treatment ""
    capture local _pte_compare_live_treatment = e(treatment)
    if `"`_pte_compare_live_treatment'"' == "." {
        local _pte_compare_live_treatment ""
    }
    if `"`_pte_compare_live_treatment'"' == "" {
        di as error "Error 459: active pte result is missing e(treatment)."
        di as error "Re-run {bf:pte} on the current data before {bf:pte_compare}."
        exit 459
    }

    // pte_compare reports bias relative to the active pte ATT baseline, so
    // the compare worker must stay on that exact treatment contract. Using a
    // different treatment() variable would mix the stored pte ATT with TWFE
    // estimates computed on another treatment law.
    if "`treatment'" == "" {
        local treatment "`_pte_compare_live_treatment'"
    }
    else if `"`treatment'"' != `"`_pte_compare_live_treatment'"' {
        di as error "Error 459: treatment(`treatment') conflicts with the active pte treatment contract `e(treatment)'."
        di as error "Re-run {bf:pte} with treatment(`treatment') before {bf:pte_compare}, or omit treatment() to compare against the active pte baseline."
        exit 459
    }
    capture confirm variable `treatment', exact
    if _rc != 0 {
        di as error "Error 111: treatment() variable `treatment' not found."
        di as error "Specify the exact existing treatment variable name; abbreviation fallback is not allowed."
        exit 111
    }
    capture confirm numeric variable `treatment'
    if _rc != 0 {
        di as error "Error 111: treatment() variable `treatment' must be numeric."
        exit 111
    }

    // pte_compare is a postestimation consumer of the active pte treatment
    // law. When it reuses the same treatment() as the live pte result, it
    // must certify that the stored live law still matches the current data
    // before dispatching any compare worker.
    if `"`_pte_compare_live_treatment'"' == `"`treatment'"' {
        local _pte_compare_live_id ""
        local _pte_compare_live_time ""
        local _pte_compare_live_treatsig ""
        local _pte_compare_live_xtdelta ""
        local _pte_compare_live_comparesig ""
        local _pte_compare_live_depvar ""
        local _pte_compare_live_free ""
        local _pte_compare_live_state ""
        local _pte_compare_live_proxy ""
        local _pte_compare_live_controls ""

        capture local _pte_compare_live_id = e(idvar)
        if `"`_pte_compare_live_id'"' == "." {
            local _pte_compare_live_id ""
        }
        if _rc != 0 | `"`_pte_compare_live_id'"' == "" {
            capture local _pte_compare_live_id = e(id)
            if `"`_pte_compare_live_id'"' == "." {
                local _pte_compare_live_id ""
            }
        }

        capture local _pte_compare_live_time = e(timevar)
        if `"`_pte_compare_live_time'"' == "." {
            local _pte_compare_live_time ""
        }
        if _rc != 0 | `"`_pte_compare_live_time'"' == "" {
            capture local _pte_compare_live_time = e(time)
            if `"`_pte_compare_live_time'"' == "." {
                local _pte_compare_live_time ""
            }
        }

        capture local _pte_compare_live_treatsig = e(treatsig)
        if `"`_pte_compare_live_treatsig'"' == "." {
            local _pte_compare_live_treatsig ""
        }

        capture local _pte_compare_live_xtdelta = e(xtdelta)
        if `"`_pte_compare_live_xtdelta'"' == "." {
            local _pte_compare_live_xtdelta ""
        }
        capture local _pte_compare_live_comparesig = e(comparesig)
        if `"`_pte_compare_live_comparesig'"' == "." {
            local _pte_compare_live_comparesig ""
        }
        capture local _pte_compare_live_depvar = e(depvar)
        if `"`_pte_compare_live_depvar'"' == "." {
            local _pte_compare_live_depvar ""
        }
        capture local _pte_compare_live_free = e(free)
        if `"`_pte_compare_live_free'"' == "." {
            local _pte_compare_live_free ""
        }
        capture local _pte_compare_live_state = e(state)
        if `"`_pte_compare_live_state'"' == "." {
            local _pte_compare_live_state ""
        }
        capture local _pte_compare_live_proxy = e(proxy)
        if `"`_pte_compare_live_proxy'"' == "." {
            local _pte_compare_live_proxy ""
        }
        capture local _pte_compare_live_controls = e(controls)
        if `"`_pte_compare_live_controls'"' == "." {
            local _pte_compare_live_controls ""
        }

        if `"`_pte_compare_live_id'"' == "" | ///
            `"`_pte_compare_live_time'"' == "" | ///
            `"`_pte_compare_live_treatsig'"' == "" | ///
            `"`_pte_compare_live_xtdelta'"' == "" | ///
            `"`_pte_compare_live_comparesig'"' == "" | ///
            `"`_pte_compare_live_depvar'"' == "" | ///
            `"`_pte_compare_live_free'"' == "" | ///
            `"`_pte_compare_live_state'"' == "" | ///
            `"`_pte_compare_live_proxy'"' == "" {
            di as error "Error 459: live pte panel/treatment contract is incomplete for pte_compare."
            di as error "Re-run pte on the current data before pte_compare."
            exit 459
        }

        capture quietly _pte_treatment_signature, ///
            panelvar(`_pte_compare_live_id') ///
            timevar(`_pte_compare_live_time') ///
            treatment(`treatment')
        local _pte_compare_current_law_rc = _rc
        local _pte_compare_current_treatsig ""
        if `_pte_compare_current_law_rc' == 0 {
            local _pte_compare_current_treatsig `"`r(signature)'"'
        }
        if `_pte_compare_current_law_rc' != 0 | `"`_pte_compare_current_treatsig'"' == "" {
            di as error "Error 459: pte_compare could not certify the current treatment path."
            di as error "Re-run pte on the current data before pte_compare."
            exit 459
        }
        if `"`_pte_compare_current_treatsig'"' != `"`_pte_compare_live_treatsig'"' {
            di as error "Error 459: pte_compare detected stale live pte treatment law."
            di as error "Re-run pte on the current data before pte_compare."
            exit 459
        }

        // The compare workers run L. operators after temporarily rebuilding
        // xtset from the live pte contract. Certify that live e(xtdelta)
        // still matches the exact current data spacing before dispatch, or
        // the router can mix a current treatment law with a stale lag law.
        local _pte_compare_had_xtset 0
        local _pte_compare_prev_panel ""
        local _pte_compare_prev_time ""
        local _pte_compare_prev_delta ""
        capture quietly xtset
        if _rc == 0 {
            local _pte_compare_had_xtset 1
            local _pte_compare_prev_panel "`r(panelvar)'"
            local _pte_compare_prev_time "`r(timevar)'"
            local _pte_compare_prev_delta "`r(tdelta)'"
        }

        capture quietly xtset `_pte_compare_live_id' `_pte_compare_live_time'
        local _pte_compare_current_xtdelta_rc = _rc
        local _pte_compare_current_xtdelta ""
        if `_pte_compare_current_xtdelta_rc' == 0 {
            local _pte_compare_current_xtdelta "`r(tdelta)'"
        }

        if `_pte_compare_had_xtset' {
            local _pte_compare_restore_delta_opt ""
            if "`_pte_compare_prev_delta'" != "" {
                local _pte_compare_restore_delta_opt "delta(`_pte_compare_prev_delta')"
            }
            capture quietly xtset `_pte_compare_prev_panel' `_pte_compare_prev_time', `_pte_compare_restore_delta_opt'
        }
        else {
            capture quietly xtset, clear
        }

        if `_pte_compare_current_xtdelta_rc' != 0 | `"`_pte_compare_current_xtdelta'"' == "" {
            di as error "Error 459: pte_compare could not certify the current panel spacing."
            di as error "Re-run pte on the current data before pte_compare."
            exit 459
        }

        local _pte_cmp_live_xd_clean = strtrim(`"`_pte_compare_live_xtdelta'"')
        local _pte_cmp_curr_xd_clean = strtrim(`"`_pte_compare_current_xtdelta'"')
        local _pte_cmp_xd_conflict = 0
        if `"`_pte_cmp_live_xd_clean'"' != "" & `"`_pte_cmp_curr_xd_clean'"' != "" {
            local _pte_cmp_live_xd_num = real(`"`_pte_cmp_live_xd_clean'"')
            local _pte_cmp_curr_xd_num = real(`"`_pte_cmp_curr_xd_clean'"')
            if !missing(`_pte_cmp_live_xd_num') & !missing(`_pte_cmp_curr_xd_num') {
                if `_pte_cmp_live_xd_num' != `_pte_cmp_curr_xd_num' {
                    local _pte_cmp_xd_conflict = 1
                }
            }
            else if `"`_pte_cmp_live_xd_clean'"' != `"`_pte_cmp_curr_xd_clean'"' {
                local _pte_cmp_xd_conflict = 1
            }
        }

        if `_pte_cmp_xd_conflict' {
            di as error "Error 459: pte_compare detected stale live pte panel spacing."
            di as error "Re-run pte on the current data before pte_compare."
            exit 459
        }

        local _pte_compare_controls_opt ""
        if `"`_pte_compare_live_controls'"' != "" {
            local _pte_compare_controls_opt `"controls(`_pte_compare_live_controls')"'
        }
        capture quietly _pte_compare_signature, ///
            panelvar(`_pte_compare_live_id') ///
            timevar(`_pte_compare_live_time') ///
            treatment(`treatment') ///
            depvar(`_pte_compare_live_depvar') ///
            free(`_pte_compare_live_free') ///
            state(`_pte_compare_live_state') ///
            proxy(`_pte_compare_live_proxy') ///
            `_pte_compare_controls_opt'
        local pte_compare_current_inputsig_rc = _rc
        local pte_compare_current_inputsig ""
        if `pte_compare_current_inputsig_rc' == 0 {
            local pte_compare_current_inputsig `"`r(signature)'"'
        }
        if `pte_compare_current_inputsig_rc' != 0 | ///
            `"`pte_compare_current_inputsig'"' == "" {
            di as error "Error 459: pte_compare could not certify the current compare-input state."
            di as error "Re-run pte on the current data before pte_compare."
            exit 459
        }
        if `"`pte_compare_current_inputsig'"' != `"`_pte_compare_live_comparesig'"' {
            di as error "Error 459: pte_compare detected stale live pte input state."
            di as error "Re-run pte on the current data before pte_compare."
            exit 459
        }
    }
    
    // Normalize public method() keywords before conflict checks so the
    // released router treats enum-like method names consistently with other
    // public string options that are not data payloads.
    local method = lower(trim(`"`method'"'))

    // all is only a convenience alias for method(all); reject ambiguous
    // calls instead of silently overriding an explicit method().
    if "`all'" != "" {
        if "`method'" != "" & "`method'" != "all" {
            di as error "Error 198: options all and method(`method') may not be combined."
            di as error "Use either {bf:all} or {bf:method(all)}, but not both with another method."
            exit 198
        }
        local method "all"
    }
    if "`method'" == "" local method "expost"

    // The paper/DO compare bundle for method(all) is the full Table 3
    // lattice m1-m9. Allowing subset specs() here publishes a partial
    // compare contract that downstream graph consumers correctly reject.
    if "`method'" == "all" & "`specs'" != "" & strtrim("`specs'") != "1 2 3" {
        di as error "Error 198: method(all) requires the full compare bundle specs(1 2 3)."
        di as error "Use standalone methods for subset specifications, or omit specs() with {bf:method(all)}."
        exit 198
    }

    // Match the live-order contract used elsewhere in the package: when the
    // caller omits omegapoly(), Method II inherits the active pte order.
    if `omegapoly' == -1 & !`_pte_compare_has_omegapoly' {
        capture local omegapoly = e(omegapoly)
        if _rc != 0 | missing(`omegapoly') {
            local omegapoly = 3
        }
    }
    if `omegapoly' < 1 | `omegapoly' > 4 {
        di as error "Error 198: omegapoly(`omegapoly') must be 1, 2, 3, or 4."
        exit 198
    }

    // The paper/DO comparison scripts use explicit sample splits (full sample,
    // electronics-only, other industries) rather than a general public
    // industry() API. Reject the option at the router so Method I/II do not
    // silently run on the full sample while appearing industry-specific.
    if "`industry'" != "" {
        di as error "Error 198: industry() is not supported by the public pte_compare API."
        di as error "The released comparison workflow does not implement a general by-industry public interface."
        di as error "Subset the data before calling pte_compare if an industry-specific comparison is required."
        exit 198
    }

    // Public compare routes all dispatch branches through the same TWFE
    // dependency surface. Check the shared compare gate here so the router
    // fails before worker dispatch instead of relying on method-specific
    // reghdfe checks to discover a missing public prerequisite later.
    capture quietly pte_check_deps, compare
    local _pte_compare_dep_rc = _rc
    if `_pte_compare_dep_rc' != 0 {
        di as error "Error 601: compare dependency check failed to run (rc = `_pte_compare_dep_rc')."
        di as error "Verify that pte_check_deps.ado is on adopath and re-run pte_compare."
        exit 601
    }
    local _pte_compare_deps_ok = r(all_satisfied)
    if missing(`_pte_compare_deps_ok') | `_pte_compare_deps_ok' != 1 {
        noisily pte_check_deps, compare
        di as error "Error 601: required compare workflow dependencies are missing."
        exit 601
    }

    // pte_compare is a consumer of an existing public pte result. If a worker
    // fails after posting its own regression eclass, the caller must still be
    // able to use the original pte state (for example pte_p / graph consumers)
    // instead of inheriting a partial compare worker payload.
    tempname _pte_compare_prior_est
    capture estimates store `_pte_compare_prior_est'
    if _rc {
        di as error "Error 498: unable to snapshot the caller's pte result before compare dispatch."
        di as error "Re-run {bf:pte} and then call {bf:pte_compare} again."
        exit 498
    }

    // Public compare publishes individual stored estimates only when the
    // requested compare bundle succeeds. A failing rerun must not leak
    // partial `_expost_m*' / `_endog_m*' / `_clktwfe_m*' artifacts, and it
    // must not destroy prior successful compare estimates with the same
    // names. Snapshot any pre-existing compare estimate namespace so the
    // router can fail-close back to the caller's exact pre-dispatch state.
    tempname _pte_compare_hold_expost_m1 _pte_compare_hold_expost_m2 _pte_compare_hold_expost_m3
    tempname _pte_compare_hold_endog_m4 _pte_compare_hold_endog_m5 _pte_compare_hold_endog_m6
    tempname _pte_compare_hold_clktwfe_m7 _pte_compare_hold_clktwfe_m8 _pte_compare_hold_clktwfe_m9
    local _pte_compare_had_expost_m1 0
    local _pte_compare_had_expost_m2 0
    local _pte_compare_had_expost_m3 0
    local _pte_compare_had_endog_m4 0
    local _pte_compare_had_endog_m5 0
    local _pte_compare_had_endog_m6 0
    local _pte_compare_had_clktwfe_m7 0
    local _pte_compare_had_clktwfe_m8 0
    local _pte_compare_had_clktwfe_m9 0

    capture estimates restore _expost_m1
    if !_rc {
        capture estimates store `_pte_compare_hold_expost_m1'
        if !_rc local _pte_compare_had_expost_m1 1
    }
    capture estimates restore _expost_m2
    if !_rc {
        capture estimates store `_pte_compare_hold_expost_m2'
        if !_rc local _pte_compare_had_expost_m2 1
    }
    capture estimates restore _expost_m3
    if !_rc {
        capture estimates store `_pte_compare_hold_expost_m3'
        if !_rc local _pte_compare_had_expost_m3 1
    }
    capture estimates restore _endog_m4
    if !_rc {
        capture estimates store `_pte_compare_hold_endog_m4'
        if !_rc local _pte_compare_had_endog_m4 1
    }
    capture estimates restore _endog_m5
    if !_rc {
        capture estimates store `_pte_compare_hold_endog_m5'
        if !_rc local _pte_compare_had_endog_m5 1
    }
    capture estimates restore _endog_m6
    if !_rc {
        capture estimates store `_pte_compare_hold_endog_m6'
        if !_rc local _pte_compare_had_endog_m6 1
    }
    capture estimates restore _clktwfe_m7
    if !_rc {
        capture estimates store `_pte_compare_hold_clktwfe_m7'
        if !_rc local _pte_compare_had_clktwfe_m7 1
    }
    capture estimates restore _clktwfe_m8
    if !_rc {
        capture estimates store `_pte_compare_hold_clktwfe_m8'
        if !_rc local _pte_compare_had_clktwfe_m8 1
    }
    capture estimates restore _clktwfe_m9
    if !_rc {
        capture estimates store `_pte_compare_hold_clktwfe_m9'
        if !_rc local _pte_compare_had_clktwfe_m9 1
    }
    capture estimates restore `_pte_compare_prior_est'

    local has_pte_att = 0
    capture confirm matrix e(att)
    if !_rc {
        tempname pte_att_baseline
        matrix `pte_att_baseline' = e(att)
        local pte_att_cols = colsof(`pte_att_baseline')
        local pte_att_colnames : colnames `pte_att_baseline'
        forvalues j = 1/`pte_att_cols' {
            local pte_att_`j' = `pte_att_baseline'[1, `j']
        }
        local has_pte_att = 1
    }
    
    // =========================================================================
    // Dispatch to method implementation
    // =========================================================================
    
    // Build common options
    local common_opts "treatment(`treatment')"
    if "`specs'"    != "" local common_opts "`common_opts' specs(`specs')"
    if "`absorb'"   != "" local common_opts "`common_opts' absorb(`absorb')"
    if "`vce'"      != "" local common_opts "`common_opts' vce(`vce')"
    if "`industry'" != "" local common_opts "`common_opts' industry(`industry')"
    if "`lagtreatment'" != "" local common_opts "`common_opts' lagtreatment"
    if "`diagnose'" != "" local common_opts "`common_opts' diagnose"
    if "`report'"   == "noreport" local common_opts "`common_opts' noreport"

    local endog_opts "`common_opts' omegapoly(`omegapoly')"

    local _pte_compare_dispatch_rc = 0
    if "`method'" == "expost" {
        capture noisily _pte_compare_expost, `common_opts'
        local _pte_compare_dispatch_rc = _rc
    }
    else if "`method'" == "endog" | "`method'" == "endogenous" {
        capture noisily _pte_compare_endog, `endog_opts'
        local _pte_compare_dispatch_rc = _rc
    }
    else if "`method'" == "clktwfe" | "`method'" == "clk_twfe" {
        capture noisily _pte_compare_clktwfe, `common_opts'
        local _pte_compare_dispatch_rc = _rc
    }
    else if "`method'" == "all" {
        capture noisily _pte_compare_all, `endog_opts'
        local _pte_compare_dispatch_rc = _rc
    }
    else {
        capture estimates drop `_pte_compare_prior_est'
        di as error "Error: unknown method '`method''."
        di as error "Valid methods: expost, endog, clktwfe, all"
        exit 198
    }

    if `_pte_compare_dispatch_rc' != 0 {
        capture estimates drop _expost_m1
        capture estimates drop _expost_m2
        capture estimates drop _expost_m3
        capture estimates drop _endog_m4
        capture estimates drop _endog_m5
        capture estimates drop _endog_m6
        capture estimates drop _clktwfe_m7
        capture estimates drop _clktwfe_m8
        capture estimates drop _clktwfe_m9

        if `_pte_compare_had_expost_m1' {
            capture estimates restore `_pte_compare_hold_expost_m1'
            if !_rc capture estimates store _expost_m1
            capture estimates drop `_pte_compare_hold_expost_m1'
        }
        if `_pte_compare_had_expost_m2' {
            capture estimates restore `_pte_compare_hold_expost_m2'
            if !_rc capture estimates store _expost_m2
            capture estimates drop `_pte_compare_hold_expost_m2'
        }
        if `_pte_compare_had_expost_m3' {
            capture estimates restore `_pte_compare_hold_expost_m3'
            if !_rc capture estimates store _expost_m3
            capture estimates drop `_pte_compare_hold_expost_m3'
        }
        if `_pte_compare_had_endog_m4' {
            capture estimates restore `_pte_compare_hold_endog_m4'
            if !_rc capture estimates store _endog_m4
            capture estimates drop `_pte_compare_hold_endog_m4'
        }
        if `_pte_compare_had_endog_m5' {
            capture estimates restore `_pte_compare_hold_endog_m5'
            if !_rc capture estimates store _endog_m5
            capture estimates drop `_pte_compare_hold_endog_m5'
        }
        if `_pte_compare_had_endog_m6' {
            capture estimates restore `_pte_compare_hold_endog_m6'
            if !_rc capture estimates store _endog_m6
            capture estimates drop `_pte_compare_hold_endog_m6'
        }
        if `_pte_compare_had_clktwfe_m7' {
            capture estimates restore `_pte_compare_hold_clktwfe_m7'
            if !_rc capture estimates store _clktwfe_m7
            capture estimates drop `_pte_compare_hold_clktwfe_m7'
        }
        if `_pte_compare_had_clktwfe_m8' {
            capture estimates restore `_pte_compare_hold_clktwfe_m8'
            if !_rc capture estimates store _clktwfe_m8
            capture estimates drop `_pte_compare_hold_clktwfe_m8'
        }
        if `_pte_compare_had_clktwfe_m9' {
            capture estimates restore `_pte_compare_hold_clktwfe_m9'
            if !_rc capture estimates store _clktwfe_m9
            capture estimates drop `_pte_compare_hold_clktwfe_m9'
        }
        capture estimates restore `_pte_compare_prior_est'
        capture estimates drop `_pte_compare_prior_est'
        exit `_pte_compare_dispatch_rc'
    }

    capture estimates drop `_pte_compare_prior_est'

    if `has_pte_att' {
        tempname pte_att_restore
        matrix `pte_att_restore' = J(1, `pte_att_cols', .)
        forvalues j = 1/`pte_att_cols' {
            matrix `pte_att_restore'[1, `j'] = `pte_att_`j''
        }
        matrix colnames `pte_att_restore' = `pte_att_colnames'
        ereturn matrix att = `pte_att_restore'
        capture confirm scalar e(ATT_avg)
        if _rc {
            ereturn scalar ATT_avg = `pte_att_`pte_att_cols''
        }
    }
    
    // =========================================================================
    // Bias source analysis report
    // =========================================================================
    
    if "`diagnose'" != "" {
        _pte_bias_report
    }
    
end
