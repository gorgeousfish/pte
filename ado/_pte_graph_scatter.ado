*! _pte_graph_scatter.ado
*! TT vs Initial Productivity Scatter Plot
*! Internal program for pte_graph, scatter

version 14.0
program define _pte_graph_scatter, rclass
    version 14.0
    
    syntax , [NT(numlist) BYPERiod LEVel(cilevel) REGstat CURRENTLAWCHECKED ///
              TItle(string) XTItle(string) YTItle(string) ///
              SCHeme(string) ///
              SAVE(string) EXPORT(string) ///
              WIDTH(integer 800) HEIGHT(integer 600)]

    tempvar restore_order
    quietly gen long `restore_order' = _n
    
    // =========================================================================
    // Step 1: Resolve panel/time contract
    // =========================================================================

    // Scatter uses lag operators on the same calendar axis that generated the
    // stored ATT timing objects. Reuse the shared setup/e() contract when a
    // certified setup fragment or live pte payload is present, but keep the
    // narrow legacy _pte_firm/_pte_year fallback for a pure compatibility
    // stub that advertises only e(cmd)="pte" and nothing else.
    local panelvar ""
    local timevar ""
    local xtdelta ""
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
    local have_setup_fragment = ///
        (`"`setup_panel'"' != "") | ///
        (`"`setup_time'"' != "") | ///
        (`"`setup_treatment'"' != "") | ///
        (`"`setup_treatsig'"' != "") | ///
        (`"`setup_xtdelta'"' != "")
    local have_setup_helper_bundle = 0
    foreach helper in _pte_D _pte_mid _pte_cohort _pte_treat_year ///
        _pte_first_treat_year {
        capture confirm variable `helper', exact
        if _rc == 0 {
            local have_setup_helper_bundle = 1
            continue, break
        }
    }
    local have_live_panel_contract = ///
        (`"`live_id'"' != "") | (`"`live_time'"' != "") | (`"`live_treatsig'"' != "")
    local have_live_payload = ///
        (`"`live_predict'"' != "")
    local have_live_pte = (`have_live_panel_contract' | `have_live_payload')

    if "`currentlawchecked'" == "" {
        capture quietly _pte_diag_panel_contract, context("pte_graph scatter") ///
            allowsetupmissingxtdelta
        local panel_contract_rc = _rc
        if `panel_contract_rc' == 0 {
            local panelvar "`r(idvar)'"
            local timevar "`r(timevar)'"
            local xtdelta "`r(xtdelta)'"
        }
        else if `have_setup_fragment' | `have_live_pte' | `have_setup_helper_bundle' {
            exit `panel_contract_rc'
        }
    }
    else {
        capture quietly xtset
        if _rc == 0 {
            local xtset_id "`r(panelvar)'"
            local xtset_time "`r(timevar)'"
            local xtset_delta "`r(tdelta)'"
            if "`xtset_delta'" == "." {
                local xtset_delta ""
            }
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
        if `"`setup_time'"' != "" {
            local timevar "`setup_time'"
        }
        else if `"`live_time'"' != "" {
            local timevar "`live_time'"
        }
        else if `"`xtset_time'"' != "" {
            local timevar "`xtset_time'"
        }
        if `"`setup_xtdelta'"' != "" {
            local xtdelta "`setup_xtdelta'"
        }
        else if `"`xtset_delta'"' != "" {
            local xtdelta "`xtset_delta'"
        }
    }
    if "`panelvar'" == "" & "`timevar'" == "" & !`have_setup_fragment' & !`have_live_pte' {
        capture confirm variable _pte_firm, exact
        if !_rc {
            local panelvar "_pte_firm"
        }
        capture confirm variable _pte_year, exact
        if !_rc {
            local timevar "_pte_year"
        }
        capture quietly xtset
        if _rc == 0 {
            local xtdelta "`r(tdelta)'"
            if "`xtdelta'" == "." {
                local xtdelta ""
            }
        }
    }
    if "`panelvar'" == "" | "`timevar'" == "" {
        di as error "pte_graph scatter: panel/time variables not found"
        di as error "re-run pte on the current dataset or restore the canonical _pte_firm/_pte_year legacy bridge"
        exit 111
    }
    
    // =========================================================================
    // Step 2: Validate prerequisite variables
    // =========================================================================
    
    foreach var in _pte_tt _pte_nt _pte_omega {
        capture confirm variable `var', exact
        if _rc {
            di as error "pte_graph requires prior pte estimation"
            di as error "variable `var' not found"
            di as error "run {bf:pte} command first"
            exit 111
        }
    }
    _pte_validate_internal_state _pte_tt numeric ///
        "pte_graph, scatter requires _pte_tt to remain the numeric firm-level TT bridge."
    _pte_validate_internal_state _pte_nt integer ///
        "pte_graph, scatter requires _pte_nt to remain the integer event-time bridge."
    _pte_validate_internal_state _pte_omega numeric ///
        "pte_graph, scatter requires _pte_omega to remain the numeric productivity bridge."
    local _pte_scatter_treat_and ""
    capture confirm variable _pte_treat, exact
    if _rc == 0 {
        _pte_validate_internal_state _pte_treat binary ///
            "pte_graph, scatter requires _pte_treat to remain the certified binary ever-treated indicator."
        local _pte_scatter_treat_and " & _pte_treat == 1"
    }
    
    // =========================================================================
    // Step 3: Parse options
    // =========================================================================
    
    // Default periods
    if "`byperiod'" != "" {
        local periods "0 1 2 3 4"
    }
    else if "`nt'" == "" {
        local periods "0"
    }
    else {
        local periods "`nt'"
    }
    
    // Default confidence level
    if "`level'" == "" local level 95
    
    // Default scheme
    if "`scheme'" == "" local scheme "s1color"
    
    // Default X axis title
    if "`xtitle'" == "" local xtitle "initial productivity"
    
    // =========================================================================
    // Step 4: Check industry variable
    // =========================================================================
    
    local skip_normalize = 0
    local have_exact_industry = 0
    capture confirm variable _pte_industry, exact
    if _rc {
        di as text "{bf:Warning}: variable _pte_industry not found"
        di as text "Skipping industry normalization"
        local skip_normalize = 1
    }
    else {
        local have_exact_industry = 1
    }
    
    // =========================================================================
    // Step 5: Compute normalized productivity
    // =========================================================================
    
    tempvar omega_norm ind_mean
    preserve
    local tsset_delta_opt ""
    if "`xtdelta'" != "" {
        local tsset_delta_opt "delta(`xtdelta')"
    }
    capture quietly tsset `panelvar' `timevar', `tsset_delta_opt'
    if _rc != 0 {
        local _pte_scatter_rc = _rc
        capture restore
        quietly sort `restore_order'
        exit `_pte_scatter_rc'
    }

    if `skip_normalize' == 0 {
        quietly bys _pte_industry: egen double `ind_mean' = mean(_pte_omega)
        quietly gen double `omega_norm' = _pte_omega - `ind_mean'
    }
    else {
        qui gen double `omega_norm' = _pte_omega
    }
    quietly sort `panelvar' `timevar'
    
    // =========================================================================
    // Step 6: Loop over periods and generate scatter plots
    // =========================================================================
    
    local graph_names ""
    local plot_count = 0
    local periods_plotted ""
    local total_nobs = 0
    
    foreach nt of numlist `periods' {
        // Calculate lag period
        local lag = `nt' + 1
        
        // Check data availability for this period
        qui count if !missing(_pte_tt) & _pte_nt == `nt'`_pte_scatter_treat_and' ///
            & !missing(L`lag'.`omega_norm')
        local nobs_`nt' = r(N)
        
        if `nobs_`nt'' == 0 {
            di as text "{bf:Warning}: no valid observations for nt=`nt' (lag=`lag'), skipping"
            continue
        }
        
        // Compute regression statistics
        capture qui reg _pte_tt L`lag'.`omega_norm' if _pte_nt == `nt'`_pte_scatter_treat_and'
        if _rc {
            local _pte_scatter_rc = _rc
            capture restore
            quietly sort `restore_order'
            exit `_pte_scatter_rc'
        }
        local slope_`nt' = _b[L`lag'.`omega_norm']
        local se_`nt' = _se[L`lag'.`omega_norm']
        local r2_`nt' = e(r2)
        local total_nobs = `total_nobs' + `nobs_`nt''
        
        // Generate Y axis title
        if "`ytitle'" == "" {
            if `nt' == 0 {
                local ytitle_nt `"{&omega}{sub:e}{sup:TT}"'
            }
            else {
                local ytitle_nt `"{&omega}{sub:e+`nt'}{sup:TT}"'
            }
        }
        else {
            local ytitle_nt "`ytitle'"
        }
        
        // Generate chart title
        if "`title'" == "" {
            local title_nt "TT vs Initial Productivity (nt=`nt')"
        }
        else {
            local title_nt "`title'"
        }
        
        // Build and execute twoway command
        capture noisily twoway (lfitci _pte_tt L`lag'.`omega_norm' if _pte_nt == `nt'`_pte_scatter_treat_and', level(`level')) ///
                              (scatter _pte_tt L`lag'.`omega_norm' if _pte_nt == `nt'`_pte_scatter_treat_and', ///
                               msize(0.3) mc(blue)), ///
                              xtitle("`xtitle'") ytitle(`"`ytitle_nt'"') ///
                              title("`title_nt'") ///
                              legend(off) ///
                              ylabel(, grid) xlabel(, grid) ///
                              scheme(`scheme') ///
                              name(scatter_nt`nt', replace)
        if _rc {
            local _pte_scatter_rc = _rc
            capture restore
            quietly sort `restore_order'
            exit `_pte_scatter_rc'
        }
        
        local graph_names "`graph_names' scatter_nt`nt'"
        local plot_count = `plot_count' + 1
        local periods_plotted "`periods_plotted' `nt'"
    }

    if `plot_count' == 0 {
        di as error "pte_graph scatter: no valid observations for the requested nt() support"
        di as error "re-run pte on a dataset that preserves the lagged omega support, or request periods with nonempty TT scatter support"
        capture restore
        quietly sort `restore_order'
        exit 2000
    }
    
    // =========================================================================
    // Step 7: Combine graphs (if multiple periods)
    // =========================================================================
    
    if `plot_count' > 1 {
        capture noisily graph combine `graph_names', scheme(`scheme')
        if _rc {
            local _pte_scatter_rc = _rc
            capture restore
            quietly sort `restore_order'
            exit `_pte_scatter_rc'
        }
        foreach gname of local graph_names {
            capture graph drop `gname'
        }
    }
    
    // =========================================================================
    // Step 8: Save/Export
    // =========================================================================
    
    if "`save'" != "" {
        if !regexm("`save'", "\.gph$") {
            local save "`save'.gph"
        }
        capture noisily graph save "`save'", replace
        if _rc {
            local _pte_scatter_rc = _rc
            capture restore
            quietly sort `restore_order'
            exit `_pte_scatter_rc'
        }
        di as text "graph saved to `save'"
    }
    
    if "`export'" != "" {
        capture noisily graph export "`export'", width(`width') height(`height') replace
        if _rc {
            local _pte_scatter_rc = _rc
            capture restore
            quietly sort `restore_order'
            exit `_pte_scatter_rc'
        }
        di as text "graph exported to `export'"
    }

    // =========================================================================
    // Step 9: Output regression statistics (if requested)
    // =========================================================================
    
    if "`regstat'" != "" {
        di as text ""
        di as text "{bf:Simple OLS Regression (matches fit line):}"
        di as text "{hline 70}"
        di as text "{col 5}nt{col 15}Slope{col 30}Std.Err.{col 45}R-squared{col 60}N"
        di as text "{hline 70}"
        
        foreach nt of numlist `periods' {
            if `nobs_`nt'' > 0 {
                di as text "{col 5}`nt'" ///
                           "{col 15}" %9.4f `slope_`nt'' ///
                           "{col 30}" %9.4f `se_`nt'' ///
                           "{col 45}" %9.4f `r2_`nt'' ///
                           "{col 60}" %7.0fc `nobs_`nt''
            }
        }
        di as text "{hline 70}"
        
        // Part 2: Full regression with fixed effects (matches replication code L304-316)
        di as text ""
        di as text "{bf:Full Regression (with Year and Industry FE, robust SE):}"
        foreach nt of numlist `periods' {
            if `nobs_`nt'' > 0 {
                local lag = `nt' + 1
                di as text ""
                di as text "{ul:Period `nt' (lag=`lag'):}"
                local fe_rc = 0
                if `have_exact_industry' {
                    capture {
                        qui reg _pte_tt L`lag'.`omega_norm' i.`timevar' i._pte_industry ///
                            if _pte_nt == `nt'`_pte_scatter_treat_and', r
                        di as text "  Slope: " %9.4f _b[L`lag'.`omega_norm'] ///
                                   "  (SE: " %9.4f _se[L`lag'.`omega_norm'] ", robust)"
                    }
                    local fe_rc = _rc
                }
                else {
                    local fe_rc = 111
                }
                if `fe_rc' {
                    di as text "  (Insufficient data or missing variables for FE regression)"
                }
            }
        }
    }
    
    // =========================================================================
    // Step 10: Set return values
    // =========================================================================
    
    restore
    quietly sort `restore_order'

    return local nt "`periods_plotted'"
    return scalar nobs = `total_nobs'
    
    foreach nt of numlist `periods' {
        if `nobs_`nt'' > 0 {
            return scalar nobs_`nt' = `nobs_`nt''
            return scalar slope_`nt' = `slope_`nt''
            return scalar se_`nt' = `se_`nt''
            return scalar r2_`nt' = `r2_`nt''
        }
    }
    
    // =========================================================================
    // Step 11: Display summary
    // =========================================================================
    
    di as text ""
    di as text "{bf:TT vs Initial Productivity Scatter Plot}"
    di as text "{hline 50}"
    di as text "Periods plotted: `periods_plotted'"
    di as text "Total observations: " %10.0fc `total_nobs'
    di as text "CI level: `level'%"
    di as text ""
    
end
