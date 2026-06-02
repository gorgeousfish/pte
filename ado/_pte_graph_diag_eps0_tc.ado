*! _pte_graph_diag_eps0_tc.ado
*! eps0 treated vs control kernel density plot

version 14.0
program define _pte_graph_diag_eps0_tc, rclass
    version 14.0
    
    syntax , [WINSOR(numlist) INDUSTRY(varname) CURRENTLAWCHECKED ///
              TItle(string) XTItle(string) YTItle(string) ///
              SAVE(string) EXPORT(string) ///
              WIDTH(integer 800) HEIGHT(integer 600)]
    
    // =========================================
    // Step 1: Validate prerequisites
    // =========================================
    foreach var in _pte_eps0 _pte_D _pte_treat {
        capture confirm variable `var', exact
        if _rc {
            di as error "pte_graph diagnose type(eps0_treat_control): variable `var' not found"
            di as error "run {bf:pte} command first"
            exit 111
        }
    }

    _pte_validate_internal_state _pte_D binary ///
        "pte_graph diagnose type(eps0_treat_control) requires _pte_D to remain the certified current-treatment indicator."
    _pte_validate_internal_state _pte_treat binary ///
        "pte_graph diagnose type(eps0_treat_control) requires _pte_treat to remain the certified ever-treated indicator."
    
    // Check _pte_nt (optional, used for pre-treatment filtering)
    capture confirm variable _pte_nt, exact
    local has_nt = (_rc == 0)
    if `has_nt' {
        _pte_validate_internal_state _pte_nt integer ///
            "pte_graph diagnose type(eps0_treat_control) requires _pte_nt to remain the certified integer event-time index."
    }

    quietly _pte_diag_eps0_support_if, epsvar(_pte_eps0) ///
        context("pte_graph diagnose type(eps0_treat_control)")
    local use_support = r(uses_support)
    
    // =========================================
    // Step 2: Set default titles
    // =========================================
    if `"`title'"' == "" local title "Distribution of ε⁰: Treated vs Control"
    if `"`xtitle'"' == "" local xtitle "productivity shocks: ε⁰"
    if `"`ytitle'"' == "" local ytitle "kernel density"
    if "`industry'" != "" {
        di as error "pte_graph diagnose type(eps0_treat_control): industry() is not supported on this subtype"
        di as error "Use by(`industry') combine with the public pte_graph router for industry breakdowns."
        exit 198
    }
    
    // =========================================
    // Step 3: Prepare sample
    // (DD-014.3: only use _pte_D==0 observations, verifying untreated shock dist)
    // =========================================
    preserve
    
    // Keep only untreated observations
    keep if _pte_D == 0

    // Match controls to the same calendar window as the treated pre-treatment
    // support used in Appendix E.3 so the comparison does not absorb pure time
    // drift from much older control observations.
    local prewindow = 3
    local use_same_window = 0
    local timevar ""
    local setup_panel : char _dta[_pte_setup_panelvar]
    local setup_time : char _dta[_pte_setup_timevar]
    local setup_treatment : char _dta[_pte_setup_treatment]
    local setup_treatsig : char _dta[_pte_setup_treatsig]
    local setup_xtdelta : char _dta[_pte_setup_xtdelta]
    local live_id ""
    local live_time ""
    local live_treatsig ""
    local live_predict ""
    local live_treatment ""
    if "`e(cmd)'" == "pte" {
        capture local live_id = e(idvar)
        if _rc != 0 | inlist("`live_id'", "", ".") {
            capture local live_id = e(id)
        }
        if "`live_id'" == "." {
            local live_id ""
        }
        capture local live_time = e(timevar)
        if _rc != 0 | inlist("`live_time'", "", ".") {
            capture local live_time = e(time)
        }
        if "`live_time'" == "." {
            local live_time ""
        }
        capture local live_treatsig = e(treatsig)
        if _rc != 0 | "`live_treatsig'" == "." {
            local live_treatsig ""
        }
        capture local live_predict = e(predict)
        if _rc != 0 | "`live_predict'" == "." {
            local live_predict ""
        }
        capture local live_treatment = e(treatment)
        if _rc != 0 | "`live_treatment'" == "." {
            local live_treatment ""
        }
    }
    local have_live_panel_contract = ///
        (`"`live_id'"' != "") | (`"`live_time'"' != "") | (`"`live_treatsig'"' != "")
    local have_live_payload = ///
        (`"`live_predict'"' != "")
    // A pure compatibility stub may advertise only e(cmd)="pte" and nothing
    // else; keep the legacy untreated-window fallback for that narrow case.
    // Once any additional live predict payload is present, this worker must
    // honor the shared diagnostics contract instead of reviving legacy
    // fallback. A bare e(treatment) name alone does not certify the active
    // graph law.
    local have_live_pte = (`have_live_panel_contract' | `have_live_payload')
    local have_setup_fragment = ///
        (`"`setup_panel'"' != "") | ///
        (`"`setup_time'"' != "") | ///
        (`"`setup_treatment'"' != "") | ///
        (`"`setup_treatsig'"' != "") | ///
        (`"`setup_xtdelta'"' != "")
    if `has_nt' {
        if "`currentlawchecked'" == "" {
            if `have_setup_fragment' | `have_live_pte' {
                // Reuse the shared diagnostic panel/time bridge so this worker reads
                // the same stored calendar support as the K-S diagnostics.
                // This subtype reuses the certified calendar window only.
                capture quietly _pte_diag_panel_contract, ///
                    context("pte_graph diagnose type(eps0_treat_control)") allowsetupmissingxtdelta
                local panel_contract_rc = _rc
                if `panel_contract_rc' == 0 {
                    local time_candidate "`r(timevar)'"
                    if "`time_candidate'" != "" {
                        capture confirm variable `time_candidate', exact
                        if !_rc {
                            local timevar "`time_candidate'"
                        }
                    }
                    local use_same_window = 1
                }
                else {
                    restore
                    exit `panel_contract_rc'
                }
            }
        }
        else {
            capture quietly xtset
            if _rc == 0 {
                local xtset_time "`r(timevar)'"
            }
            if `"`setup_time'"' != "" {
                local timevar "`setup_time'"
            }
            else if `"`live_time'"' != "" {
                local timevar "`live_time'"
            }
            else if `"`xtset_time'"' != "" {
                local timevar "`xtset_time'"
            }
            if "`timevar'" != "" {
                local use_same_window = 1
            }
        }
    }

    tempvar _pte_eps0_use
    quietly gen double `_pte_eps0_use' = _pte_eps0
    if `use_support' {
        quietly replace `_pte_eps0_use' = . if _pte_eps0_ind != 1
    }

    // Create sample groups
    gen _sample_group = .
    if `use_same_window' {
        tempvar _pte_treated_pre _pte_window_year _pte_control_window
        quietly gen byte `_pte_treated_pre' = ///
            (_pte_treat == 1 & _pte_nt < 0 & _pte_nt >= -`prewindow' & !missing(`_pte_eps0_use'))
        quietly count if `_pte_treated_pre'
        local has_treated_window = (r(N) > 0)
        if `has_treated_window' {
            quietly bysort `timevar': egen byte `_pte_window_year' = max(`_pte_treated_pre')

            quietly gen byte `_pte_control_window' = ///
                (_pte_treat == 0 & !missing(`_pte_eps0_use') & `_pte_window_year' == 1)

            replace _sample_group = 0 if `_pte_control_window'
            replace _sample_group = 1 if `_pte_treated_pre'
        }
    }
    else {
        replace _sample_group = 0 if _pte_treat == 0 & !missing(`_pte_eps0_use')
        if `has_nt' {
            replace _sample_group = 1 if _pte_treat == 1 & _pte_nt < 0 & !missing(`_pte_eps0_use')
        }
        else {
            replace _sample_group = 1 if _pte_treat == 1 & !missing(`_pte_eps0_use')
        }
    }
    
    // Drop unclassifiable observations
    drop if missing(_sample_group)
    
    // =========================================
    // Step 4: Apply Winsorize (if specified)
    // =========================================
    if "`winsor'" == "" {
        local p1 1
        local p2 99
    }
    else {
        local p1: word 1 of `winsor'
        local p2: word 2 of `winsor'
        if "`p2'" == "" local p2 = 100 - `p1'
    }

    quietly count if !missing(`_pte_eps0_use')
    if r(N) > 0 {
        quietly _pctile `_pte_eps0_use' if !missing(`_pte_eps0_use'), p(`p1' `p2')
        local lb = r(r1)
        local ub = r(r2)
        quietly replace `_pte_eps0_use' = . if `_pte_eps0_use' < `lb' | `_pte_eps0_use' > `ub'
    }
    
    // =========================================
    // Step 5: Check post-trim sample sizes
    // =========================================
    qui count if _sample_group == 0 & !missing(`_pte_eps0_use')
    local nobs_control = r(N)
    qui count if _sample_group == 1 & !missing(`_pte_eps0_use')
    local nobs_treated = r(N)
    
    if `nobs_control' == 0 & `nobs_treated' == 0 {
        di as error "no valid observations in either group"
        restore
        exit 2000
    }
    if `nobs_control' == 0 {
        di as error "no control observations in the treated pre-treatment window"
        restore
        exit 2000
    }
    if `nobs_treated' == 0 {
        di as error "no treated pre-treatment observations"
        restore
        exit 2000
    }
    
    // =========================================
    // Step 6: Build twoway command
    // =========================================
    local graph_cmd "twoway"
    local legend_order ""
    local plot_count = 0
    
    // Control group: red dashed line
    if `nobs_control' > 0 {
        local graph_cmd "`graph_cmd' (kdensity `_pte_eps0_use' if _sample_group==0 & !missing(`_pte_eps0_use'), lp(dash) lw(0.8) lc(red))"
        local plot_count = `plot_count' + 1
        local legend_order `"`legend_order' `plot_count' "control""'
    }
    
    // Treated (pre-treatment): blue solid line
    if `nobs_treated' > 0 {
        if `plot_count' > 0 {
            local graph_cmd "`graph_cmd' ||"
        }
        local graph_cmd "`graph_cmd' (kdensity `_pte_eps0_use' if _sample_group==1 & !missing(`_pte_eps0_use'), lp(solid) lw(0.8) lc(blue))"
        local plot_count = `plot_count' + 1
        local legend_order `"`legend_order' `plot_count' "treated pre-treatment""'
    }
    
    // Legend and titles
    local graph_cmd "`graph_cmd', legend(order(`legend_order') cols(1))"
    local graph_cmd `"`graph_cmd' ytitle(`"`ytitle'"') xtitle(`"`xtitle'"')"'
    local graph_cmd `"`graph_cmd' title(`"`title'"')"'
    
    // =========================================
    // Step 7: Execute K-S test
    // (DD-014.4: auto-execute K-S test and return results)
    // =========================================
    local ks_D = .
    local ks_p = .
    
    if `nobs_control' > 0 & `nobs_treated' > 0 {
        qui ksmirnov `_pte_eps0_use', by(_sample_group)
        local ks_D = r(D)
        local ks_p = r(p)
        
        di as text ""
        di as text "{bf:Kolmogorov-Smirnov Test Results}"
        di as text "{hline 40}"
        di as text "K-S statistic D:  " %9.4f `ks_D'
        di as text "p-value:          " %9.4f `ks_p'
        di as text "{hline 40}"
        if `ks_p' > 0.05 {
            di as text "H0 (equal distributions) not rejected at 5% level"
        }
        else {
            di as result "H0 (equal distributions) rejected at 5% level"
        }
    }
    
    // =========================================
    // Step 8: Execute plot
    // =========================================
    `graph_cmd'
    
    // =========================================
    // Step 9: Save/export
    // =========================================
    if "`save'" != "" {
        if !regexm("`save'", "\.gph$") {
            local save "`save'.gph"
        }
        graph save "`save'", replace
        di as text "graph saved to `save'"
    }
    
    if "`export'" != "" {
        graph export "`export'", width(`width') height(`height') replace
        di as text "graph exported to `export'"
    }
    
    restore
    
    // =========================================
    // Step 10: Return values
    // =========================================
    return local type "eps0_treat_control"
    return scalar ks_D = `ks_D'
    return scalar ks_p = `ks_p'
    return scalar nobs_control = `nobs_control'
    return scalar nobs_treated = `nobs_treated'
    return scalar nobs = `nobs_control' + `nobs_treated'
end
