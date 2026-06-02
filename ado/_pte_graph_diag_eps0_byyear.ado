*! _pte_graph_diag_eps0_byyear.ado
*! eps0 by year kernel density plot

version 14.0
program define _pte_graph_diag_eps0_byyear, rclass
    version 14.0
    
    syntax , [YEARS(numlist) REFYEAR(numlist) INDUSTRY(varname) CURRENTLAWCHECKED ///
              TItle(string) XTItle(string) YTItle(string) ///
              SAVE(string) EXPORT(string) ///
              WIDTH(integer 800) HEIGHT(integer 600)]
    
    // =========================================
    // Step 1: Validate prerequisites
    // =========================================
    capture confirm variable _pte_eps0, exact
    if _rc {
        di as error "pte_graph diagnose type(eps0_byyear): variable _pte_eps0 not found"
        di as error "run {bf:pte} command first"
        exit 111
    }

    quietly _pte_diag_eps0_support_if, epsvar(_pte_eps0) ///
        context("pte_graph diagnose type(eps0_byyear)")
    local use_support = r(uses_support)
    
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
    // else; keep the legacy _pte_year fallback for that narrow case. Once
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
            // This subtype only needs the certified time axis for year panels.
            capture quietly _pte_diag_panel_contract, ///
                context("pte_graph diagnose type(eps0_byyear)") allowsetupmissingxtdelta
            local panel_contract_rc = _rc
            if `panel_contract_rc' == 0 {
                local time_candidate "`r(timevar)'"
                if "`time_candidate'" != "" {
                    capture confirm variable `time_candidate', exact
                    if !_rc {
                        local timevar "`time_candidate'"
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
    }

    // Backward-compatible fallback for older fixtures that materialize _pte_year.
    if "`timevar'" == "" & !`have_setup_fragment' & !`have_live_pte' {
        capture confirm variable _pte_year, exact
        if !_rc {
            local timevar "_pte_year"
        }
    }

    if "`timevar'" == "" {
        di as error "pte_graph diagnose type(eps0_byyear): time variable not found"
        di as error "re-run pte or xtset the panel data before graphing"
        exit 111
    }

    capture confirm numeric variable `timevar', exact
    if _rc {
        di as error "pte_graph diagnose type(eps0_byyear): time variable `timevar' not found"
        exit 111
    }
    
    // =========================================
    // Step 2: Determine year list
    // =========================================
    if "`years'" == "" {
        qui levelsof `timevar', local(years)
    }
    
    // Sort years ascending
    local years_sorted : list sort years
    
    // =========================================
    // Step 3: Determine reference years
    // =========================================
    if "`refyear'" == "" {
        local refyear ""
    }
    
    // =========================================
    // Step 4: Set default titles
    // =========================================
    if `"`title'"' == "" local title "Distribution of ε⁰ by Year"
    if `"`xtitle'"' == "" local xtitle "productivity shocks: ε⁰"
    if `"`ytitle'"' == "" local ytitle "kernel density"
    if "`industry'" != "" {
        di as error "pte_graph diagnose type(eps0_byyear): industry() is not supported on this subtype"
        di as error "Use by(`industry') combine with the public pte_graph router for industry breakdowns."
        exit 198
    }
    
    // =========================================
    // Step 5: Build twoway command
    // (DD-014.7: ref years use lp(dash) lw(1.2), non-ref use lp(solid) lw(0.8))
    // =========================================
    local graph_cmd "twoway"
    local legend_order ""
    local plot_count = 0
    local total_nobs = 0
    local years_plotted ""
    
    foreach yr of local years_sorted {
        // Check data availability for this year
        if `use_support' {
            qui count if _pte_eps0_ind == 1 & !missing(_pte_eps0) & `timevar' == `yr'
        }
        else {
            qui count if !missing(_pte_eps0) & `timevar' == `yr'
        }
        local nobs_yr = r(N)
        
        if `nobs_yr' == 0 {
            di as text "{bf:Warning}: no observations for year `yr', skipping"
            continue
        }
        
        local total_nobs = `total_nobs' + `nobs_yr'
        local years_plotted "`years_plotted' `yr'"
        
        // Determine line style (DD-014.7)
        local is_ref : list yr in refyear
        if `is_ref' {
            local lp "dash"
            local lw "1.2"
        }
        else {
            local lp "solid"
            local lw "0.8"
        }
        
        // Add separator
        if `plot_count' > 0 {
            local graph_cmd "`graph_cmd' ||"
        }

        // Build kdensity subcommand
        if `use_support' {
            local graph_cmd "`graph_cmd' (kdensity _pte_eps0 if _pte_eps0_ind == 1 & `timevar'==`yr', lp(`lp') lw(`lw'))"
        }
        else {
            local graph_cmd "`graph_cmd' (kdensity _pte_eps0 if `timevar'==`yr', lp(`lp') lw(`lw'))"
        }
        
        // Update legend
        local plot_count = `plot_count' + 1
        if `is_ref' {
            local legend_order `"`legend_order' `plot_count' "`yr' (ref)""'
        }
        else {
            local legend_order `"`legend_order' `plot_count' "`yr'""'
        }
    }
    
    // Check for valid data
    if `plot_count' == 0 {
        di as error "no valid observations for any specified year"
        exit 2000
    }
    
    // =========================================
    // Step 6: Add legend and titles
    // =========================================
    local graph_cmd "`graph_cmd', legend(order(`legend_order') cols(3))"
    local graph_cmd `"`graph_cmd' ytitle(`"`ytitle'"') xtitle(`"`xtitle'"')"'
    local graph_cmd `"`graph_cmd' title(`"`title'"')"'
    
    // =========================================
    // Step 7: Execute plot
    // =========================================
    `graph_cmd'
    
    // =========================================
    // Step 8: Save/export
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
    // Step 9: Return values
    // =========================================
    return local type "eps0_byyear"
    return local years "`years_plotted'"
    return scalar nobs = `total_nobs'
    return scalar n_years = `plot_count'
    
    // Display summary
    di as text ""
    di as text "{bf:eps0 by Year Kernel Density Plot}"
    di as text "{hline 50}"
    di as text "Years plotted: `years_plotted'"
    di as text "Total observations: " %10.0fc `total_nobs'
end
