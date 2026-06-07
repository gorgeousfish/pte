*! _pte_graph_diag_omega_density.ado
*! Productivity distribution by treatment status

version 14.0
program define _pte_graph_diag_omega_density, rclass
    version 14.0
    
    syntax , [INDUSTRY(varname) CURRENTLAWCHECKED ///
              NOALL ///
              TItle(string) XTItle(string) YTItle(string) ///
              SAVE(string) EXPORT(string) ///
              WIDTH(integer 800) HEIGHT(integer 600)]

    if "`currentlawchecked'" == "" {
        local pre_setup_panel : char _dta[_pte_setup_panelvar]
        local pre_setup_time : char _dta[_pte_setup_timevar]
        local pre_setup_treatment : char _dta[_pte_setup_treatment]
        local pre_setup_treatsig : char _dta[_pte_setup_treatsig]
        local pre_setup_xtdelta : char _dta[_pte_setup_xtdelta]
        local pre_have_setup = ///
            (`"`pre_setup_panel'"' != "") | ///
            (`"`pre_setup_time'"' != "") | ///
            (`"`pre_setup_treatment'"' != "") | ///
            (`"`pre_setup_treatsig'"' != "") | ///
            (`"`pre_setup_xtdelta'"' != "")
        local pre_hsh = 0
        foreach helper in _pte_mid _pte_cohort _pte_treat_year ///
            _pte_first_treat_year {
            capture confirm variable `helper', exact
            if _rc == 0 {
                local pre_hsh = 1
                continue, break
            }
        }
        local pre_live_id ""
        local pre_live_time ""
        local pre_live_treatsig ""
        local pre_live_predict ""
        if "`e(cmd)'" == "pte" {
            capture local pre_live_id = e(idvar)
            if _rc != 0 | inlist("`pre_live_id'", "", ".") {
                capture local pre_live_id = e(id)
            }
            if "`pre_live_id'" == "." local pre_live_id ""
            capture local pre_live_time = e(timevar)
            if _rc != 0 | inlist("`pre_live_time'", "", ".") {
                capture local pre_live_time = e(time)
            }
            if "`pre_live_time'" == "." local pre_live_time ""
            capture local pre_live_treatsig = e(treatsig)
            if _rc != 0 | "`pre_live_treatsig'" == "." local pre_live_treatsig ""
            capture local pre_live_predict = e(predict)
            if _rc != 0 | "`pre_live_predict'" == "." local pre_live_predict ""
        }
        local pre_have_live = ///
            (`"`pre_live_id'"' != "") | ///
            (`"`pre_live_time'"' != "") | ///
            (`"`pre_live_treatsig'"' != "") | ///
            (`"`pre_live_predict'"' != "")
        if `pre_have_setup' | `pre_hsh' | `pre_have_live' {
            capture noisily _pte_diag_panel_contract, ///
                context("pte_graph diagnose type(omega_density)") allowsetupmissingxtdelta
            local pre_contract_rc = _rc
            if `pre_contract_rc' != 0 {
                exit `pre_contract_rc'
            }
        }
    }
    
    // =========================================
    // Step 1: Validate prerequisites
    // =========================================
    _pte_validate_internal_state _pte_omega numeric ///
        "pte_graph diagnose type(omega_density) requires _pte_omega to remain the certified numeric productivity state."
    _pte_validate_internal_state _pte_D binary ///
        "pte_graph diagnose type(omega_density) requires _pte_D to remain the certified current-treatment indicator."

    // The productivity-density split is defined by the current treatment law.
    // Re-certify any active setup/live claimant before counting `_pte_D'
    // groups so stale helper state cannot survive data-law mutations.
    local context "pte_graph diagnose type(omega_density)"
    local setup_panel : char _dta[_pte_setup_panelvar]
    local setup_time : char _dta[_pte_setup_timevar]
    local setup_treatment : char _dta[_pte_setup_treatment]
    local setup_treatsig : char _dta[_pte_setup_treatsig]
    local setup_xtdelta : char _dta[_pte_setup_xtdelta]
    local have_setup_fragment = ///
        (`"`setup_panel'"' != "") | ///
        (`"`setup_time'"' != "") | ///
        (`"`setup_treatment'"' != "") | ///
        (`"`setup_treatsig'"' != "") | ///
        (`"`setup_xtdelta'"' != "")

    local live_id ""
    local live_time ""
    local live_treatment ""
    local live_treatsig ""
    local live_predict ""
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
        capture local live_treatment = e(treatment)
        if _rc != 0 | "`live_treatment'" == "." {
            local live_treatment ""
        }
        capture local live_treatsig = e(treatsig)
        if _rc != 0 | "`live_treatsig'" == "." {
            local live_treatsig ""
        }
        capture local live_predict = e(predict)
        if _rc != 0 | "`live_predict'" == "." {
            local live_predict ""
        }
    }
    local have_live_panel_contract = ///
        (`"`live_id'"' != "") | (`"`live_time'"' != "") | (`"`live_treatsig'"' != "")
    local have_live_payload = (`"`live_predict'"' != "")
    local have_live_pte = (`have_live_panel_contract' | `have_live_payload')
    local have_complete_live_law = ///
        (`"`live_id'"' != "") & ///
        (`"`live_time'"' != "") & ///
        (`"`live_treatment'"' != "") & ///
        (`"`live_treatsig'"' != "")

    if "`currentlawchecked'" == "" {
        if `have_setup_fragment' {
            capture noisily _pte_diag_panel_contract, ///
                context("`context'") allowsetupmissingxtdelta
            local omega_density_contract_rc = _rc
            if `omega_density_contract_rc' != 0 {
                exit `omega_density_contract_rc'
            }
        }
        else if `have_live_pte' {
            if !`have_complete_live_law' {
                di as error "`context': live pte state must publish e(idvar)/e(timevar) or legacy e(id)/e(time), plus e(treatment) and e(treatsig)"
                di as error "Re-run pte on the current dataset before `context'."
                exit 459
            }
            capture confirm variable `live_id', exact
            if _rc != 0 {
                di as error "`context': live panel variable `live_id' not found"
                di as error "Re-run pte on the current dataset before `context'."
                exit 111
            }
            capture confirm variable `live_time', exact
            if _rc != 0 {
                di as error "`context': live time variable `live_time' not found"
                di as error "Re-run pte on the current dataset before `context'."
                exit 111
            }
            capture noisily _pte_assert_setup_current_law, ///
                panelvar(`live_id') timevar(`live_time') ///
                treatment(`live_treatment') ///
                treatsig(`"`live_treatsig'"') ///
                context("`context'")
            local omega_density_law_rc = _rc
            if `omega_density_law_rc' != 0 {
                exit `omega_density_law_rc'
            }
        }
    }
    
    // =========================================
    // Step 2: Set default titles
    // =========================================
    if `"`title'"' == "" local title "Productivity Distribution by Treatment Status"
    if `"`xtitle'"' == "" local xtitle "Productivity (ω)"
    if `"`ytitle'"' == "" local ytitle "Density"

    // Route industry() through the grouped graph wrapper so the option
    // actually splits the sample by industry rather than acting as a
    // boolean toggle that only suppresses the all-sample curve.
    if "`industry'" != "" {
        // The grouped industry graph excludes missing industry values, so the
        // returned sample counts must describe that plotted subsample rather
        // than the full dataset-level omega support.
        qui count if _pte_D == 0 & !missing(_pte_omega) & !missing(`industry')
        local nobs_control = r(N)
        qui count if _pte_D == 1 & !missing(_pte_omega) & !missing(`industry')
        local nobs_treated = r(N)
        qui count if !missing(_pte_omega) & !missing(`industry')
        local nobs_total = r(N)

        if `nobs_total' == 0 {
            di as error "no valid observations in _pte_omega"
            exit 2000
        }

        _pte_graph_by `industry', diagnose type(omega_density) noall combine ///
            currentlawchecked ///
            title(`"`title'"') xtitle(`"`xtitle'"') ytitle(`"`ytitle'"') ///
            save(`save') export(`export') width(`width') height(`height')

        return add
        return local type "omega_density"
        return scalar nobs = `nobs_total'
        return scalar nobs_control = `nobs_control'
        return scalar nobs_treated = `nobs_treated'
        exit
    }
    
    // =========================================
    // Step 3: Check sample sizes
    // =========================================
    qui count if _pte_D == 0 & !missing(_pte_omega)
    local nobs_control = r(N)
    
    qui count if _pte_D == 1 & !missing(_pte_omega)
    local nobs_treated = r(N)
    
    qui count if !missing(_pte_omega)
    local nobs_total = r(N)
    
    if `nobs_total' == 0 {
        di as error "no valid observations in _pte_omega"
        exit 2000
    }
    
    // =========================================
    // Step 4: Build twoway command
    // (DD-014.6: legend order correction, replication code L199 is wrong)
    // Correct order: 1=control (red dash), 2=treated (blue solid), 3=all (green dot)
    // =========================================
    local graph_cmd "twoway"
    local legend_order ""
    local plot_count = 0
    
    // Curve 1: Control group (red dashed) - plot order 1
    if `nobs_control' > 0 {
        local graph_cmd "`graph_cmd' (kdensity _pte_omega if _pte_D==0, lp(dash) lw(0.8) lc(red))"
        local plot_count = `plot_count' + 1
        local legend_order `"`legend_order' `plot_count' "control""'
    }
    
    // Curve 2: Treated group (blue solid) - plot order 2
    if `nobs_treated' > 0 {
        if `plot_count' > 0 {
            local graph_cmd "`graph_cmd' ||"
        }
        local graph_cmd "`graph_cmd' (kdensity _pte_omega if _pte_D==1, lp(solid) lw(0.8) lc(blue))"
        local plot_count = `plot_count' + 1
        local legend_order `"`legend_order' `plot_count' "treated""'
    }
    
    // Curve 3: All sample (green dotted) - plot order 3
    // Note: omit all-sample curve when plotting by industry (replication L187-194 vs L197-201)
    if "`noall'" == "" & `nobs_total' > 0 {
        if `plot_count' > 0 {
            local graph_cmd "`graph_cmd' ||"
        }
        local graph_cmd "`graph_cmd' (kdensity _pte_omega, lp(dot) lw(0.8) lc(green))"
        local plot_count = `plot_count' + 1
        local legend_order `"`legend_order' `plot_count' "all""'
    }
    
    // Legend and titles
    local graph_cmd "`graph_cmd', legend(order(`legend_order') cols(3))"
    local graph_cmd `"`graph_cmd' xtitle(`"`xtitle'"') ytitle(`"`ytitle'"')"'
    local graph_cmd `"`graph_cmd' title(`"`title'"')"'
    
    // =========================================
    // Step 5: Execute plot
    // =========================================
    `graph_cmd'
    
    // =========================================
    // Step 6: Save/export
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
    
    // =========================================
    // Step 7: Return values
    // =========================================
    return local type "omega_density"
    return scalar nobs = `nobs_total'
    return scalar nobs_control = `nobs_control'
    return scalar nobs_treated = `nobs_treated'
    
    // Display summary
    di as text ""
    di as text "{bf:Productivity Distribution by Treatment Status}"
    di as text "{hline 50}"
    di as text "Control observations (D=0): " %10.0fc `nobs_control'
    di as text "Treated observations (D=1): " %10.0fc `nobs_treated'
    di as text "Total observations:         " %10.0fc `nobs_total'
end
