*! _pte_graph_diag_diff_omega0.ado
*! Differenced counterfactual productivity distribution

version 14.0
program define _pte_graph_diag_diff_omega0, rclass
    version 14.0
    
    syntax , [NT(numlist) CURRENTLAWCHECKED ///
              TItle(string) XTItle(string) YTItle(string) ///
              SAVE(string) EXPORT(string) ///
              WIDTH(integer 800) HEIGHT(integer 600)]
    
    // =========================================
    // Step 1: Validate prerequisites
    // =========================================
    foreach var in _pte_omega _pte_tt _pte_nt _pte_treat {
        capture confirm variable `var', exact
        if _rc {
            di as error "pte_graph diagnose type(diff_omega0): variable `var' not found"
            di as error "run {bf:pte} command first"
            exit 111
        }
    }
    _pte_validate_internal_state _pte_omega numeric ///
        "pte_graph diagnose type(diff_omega0) requires _pte_omega to remain the certified numeric productivity bridge."
    _pte_validate_internal_state _pte_tt numeric ///
        "pte_graph diagnose type(diff_omega0) requires _pte_tt to remain the certified numeric firm-level TT bridge."
    _pte_validate_internal_state _pte_treat binary ///
        "pte_graph diagnose type(diff_omega0) requires _pte_treat to remain the certified binary ever-treated indicator."
    _pte_validate_internal_state _pte_nt integer ///
        "pte_graph diagnose type(diff_omega0) requires _pte_nt to remain the certified integer event-time index."

    tempname _pte_diff_periods
    capture matrix list e(attperiods)
    local _pte_diff_has_support = (_rc == 0)
    local _pte_diff_supported ""
    if `_pte_diff_has_support' {
        matrix `_pte_diff_periods' = e(attperiods)
        local _pte_diff_dyncols = colsof(`_pte_diff_periods')
        quietly _pte_graph_attperiods_contract, dyncols(`_pte_diff_dyncols') ///
            context("pte_graph diagnose type(diff_omega0)")
        local _pte_diff_supported `"`r(periodlist)'"'
    }

    // Resolve the panel id through the shared diagnostics contract so
    // post-setup graph calls keep using the setup-selected panel axis.
    local panelvar ""
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
    // else; keep the legacy _pte_firm fallback for that narrow case. Once
    // any additional live predict payload is present, this worker must honor
    // the shared diagnostics contract instead of reviving legacy fallback. A
    // bare e(treatment) name alone does not certify the active graph law.
    local have_live_pte = (`have_live_panel_contract' | `have_live_payload')
    local have_setup_fragment = ///
        (`"`setup_panel'"' != "") | ///
        (`"`setup_time'"' != "") | ///
        (`"`setup_treatment'"' != "") | ///
        (`"`setup_treatsig'"' != "") | ///
        (`"`setup_xtdelta'"' != "")
    if "`currentlawchecked'" == "" {
        if `have_setup_fragment' | `have_live_pte' {
            // This subtype uses the certified panel identifier for firm baselines;
            // setup-backed panel spacing can bridge a missing live e(xtdelta).
            capture quietly _pte_diag_panel_contract, ///
                context("pte_graph diagnose type(diff_omega0)") allowsetupmissingxtdelta
            local panel_contract_rc = _rc
            if `panel_contract_rc' == 0 {
                local panel_candidate "`r(idvar)'"
                if "`panel_candidate'" != "" {
                    capture confirm variable `panel_candidate', exact
                    if !_rc {
                        local panelvar "`panel_candidate'"
                    }
                }
            }
            else {
                exit `panel_contract_rc'
            }
        }
    }
    else {
        capture quietly xtset
        if _rc == 0 {
            local xtset_id "`r(panelvar)'"
        }
        if `"`setup_panel'"' != "" {
            local panelvar "`setup_panel'"
        }
        else if `"`live_id'"' != "" {
            local panelvar "`live_id'"
        }
        else if `"`xtset_id'"' != "" {
            local panelvar "`xtset_id'"
        }
    }
    if "`panelvar'" == "" & !`have_setup_fragment' & !`have_live_pte' {
        capture confirm variable _pte_firm, exact
        if !_rc {
            local panelvar "_pte_firm"
        }
    }
    if "`panelvar'" == "" {
        di as error "pte_graph diagnose type(diff_omega0): panel variable not found"
        di as error "re-run pte or xtset the panel data before graphing"
        exit 111
    }
    
    // =========================================
    // Step 2: Compute counterfactual productivity mean
    // omega_0_mean = omega - tt (for treated post-treatment obs)
    // For nt=-1, omega_0 = omega (not yet treated)
    // =========================================
    preserve
    
    tempvar omega_0_mean
    gen double `omega_0_mean' = _pte_omega - _pte_tt if !missing(_pte_tt) ///
        & _pte_treat == 1
    replace `omega_0_mean' = _pte_omega if _pte_nt == -1 & _pte_treat == 1
    
    // =========================================
    // Step 3: Compute baseline productivity (nt=-1)
    // (DD-014.1: use nt=-1 as baseline, consistent with replication code L209)
    // =========================================
    tempvar omega_0_base omega_0_baseline
    gen double `omega_0_base' = `omega_0_mean' if _pte_nt == -1 ///
        & _pte_treat == 1
    bys `panelvar': egen double `omega_0_baseline' = max(`omega_0_base')
    
    // Check baseline data availability
    qui count if !missing(`omega_0_baseline') & _pte_treat == 1
    if r(N) == 0 {
        di as error "no baseline (nt=-1) observations for treated firms"
        di as error "diff_omega0 requires pre-treatment observations"
        restore
        exit 2000
    }
    
    // =========================================
    // Step 4: Compute differenced counterfactual
    // =========================================
    tempvar diff_omega0
    gen double `diff_omega0' = `omega_0_mean' - `omega_0_baseline'
    
    // =========================================
    // Step 5: Parse period list
    // =========================================
    if "`nt'" == "" & `_pte_diff_has_support' {
        local nt `"`_pte_diff_supported'"'
    }
    else if "`nt'" == "" {
        local nt "0 1 2 3 4"
    }
    else {
        foreach period of numlist `nt' {
            local _pte_diff_period = trim(string(`period', "%21.0g"))
            if `_pte_diff_has_support' & !`: list _pte_diff_period in _pte_diff_supported' {
                di as error "pte_graph diagnose type(diff_omega0): nt(`period') is outside the stored support."
                di as error "Stored support: `_pte_diff_supported'"
                restore
                exit 198
            }
        }
    }
    
    // =========================================
    // Step 6: Set default titles
    // =========================================
    if `"`title'"' == "" local title "Distribution of Counterfactual Productivity Changes"
    if `"`xtitle'"' == "" local xtitle `"Δω⁰ = ω^0_{e+ℓ} - ω^0_{e-1}"'
    if `"`ytitle'"' == "" local ytitle "kernel density"
    
    // =========================================
    // Step 7: Build twoway command
    // (DD-014.2: 5 decreasing linewidths + different patterns, matches replication L212)
    // =========================================
    local linewidths "0.8 0.6 0.6 0.4 0.2"
    local linepatterns "solid dash shortdash dash_dot dot"
    
    local graph_cmd "twoway"
    local legend_order ""
    local plot_count = 0
    local periods_plotted ""
    local total_nobs = 0
    local idx = 1
    
    foreach period of numlist `nt' {
        // Check data availability
        qui count if !missing(`diff_omega0') & _pte_nt == `period' ///
            & _pte_treat == 1
        local nobs_p = r(N)
        
        if `nobs_p' == 0 {
            if `_pte_diff_has_support' {
                di as error "{bf:Error}: supported diff_omega0 period `period' has no nonmissing treated observations."
                di as error "pte_graph diagnose type(diff_omega0) requires every event time declared in e(attperiods) to remain realized in the treated counterfactual path."
                di as error "Re-run pte so e(attperiods) reflects realized support, or repair the damaged _pte_tt/_pte_nt bridge before graphing."
                restore
                exit 198
            }
            di as text "{bf:Warning}: no observations for nt=`period', skipping"
            local idx = `idx' + 1
            continue
        }
        
        local total_nobs = `total_nobs' + `nobs_p'
        local periods_plotted "`periods_plotted' `period'"
        
        // Get line style specs
        local lw: word `idx' of `linewidths'
        local lp: word `idx' of `linepatterns'
        if "`lw'" == "" local lw "0.5"
        if "`lp'" == "" local lp "solid"
        
        // Add separator
        if `plot_count' > 0 {
            local graph_cmd "`graph_cmd' ||"
        }
        
        // Build kdensity subcommand
        local graph_cmd "`graph_cmd' (kdensity `diff_omega0' if _pte_nt==`period' & _pte_treat==1, lw(`lw') lp(`lp'))"
        
        // Update legend
        local plot_count = `plot_count' + 1
        local legend_order `"`legend_order' `plot_count' "t=`period'""'
        
        local idx = `idx' + 1
    }
    
    // Check for valid data
    if `plot_count' == 0 {
        di as error "no valid observations for any specified period"
        restore
        exit 2000
    }
    local periods_plotted = trim("`periods_plotted'")
    
    // =========================================
    // Step 8: Add legend and titles
    // =========================================
    local graph_cmd "`graph_cmd', legend(order(`legend_order') cols(3))"
    local graph_cmd `"`graph_cmd' ytitle(`"`ytitle'"') xtitle(`"`xtitle'"')"'
    local graph_cmd `"`graph_cmd' title(`"`title'"')"'
    
    // =========================================
    // Step 9: Execute plot
    // =========================================
    `graph_cmd'
    
    // =========================================
    // Step 10: Save/export
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
    // Step 11: Return values
    // =========================================
    return local type "diff_omega0"
    return local periods "`periods_plotted'"
    return scalar nobs = `total_nobs'
    return scalar n_periods = `plot_count'
    
    // Display summary
    di as text ""
    di as text "{bf:Differenced Counterfactual Productivity Distribution}"
    di as text "{hline 50}"
    di as text "Periods plotted: `periods_plotted'"
    di as text "Total observations: " %10.0fc `total_nobs'
end
