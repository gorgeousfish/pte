*! _pte_graph_catt.ado
*! CATT grouped graph subroutine (Figure 5 style)
*! Generates conditional ATT plots by initial productivity groups

version 14.0
capture program drop _pte_graph_catt
program define _pte_graph_catt, rclass
    version 14.0
    
    syntax , [Type(string) Quantiles(integer 3) NT(numlist) ///
              CURRENTLAWCHECKED ///
              BY(varname) TItle(string) XTItle(string) YTItle(string) ///
              SCHeme(string) SAVE(string) EXPORT(string) ///
              WIDTH(integer 800) HEIGHT(integer 600)]
    
    // =========================================================================
    // Task 1-2: Defaults and input validation
    // =========================================================================
    
    // Defaults
    if "`type'" == "" local type "byperiod"
    if "`nt'" == "" local nt "0 1 2 3 4"
    if "`scheme'" == "" local scheme "s1color"
    if `"`ytitle'"' == "" local ytitle "CATT"
    
    // Validate required variables
    foreach var in _pte_tt _pte_omega _pte_nt {
        capture confirm variable `var', exact
        if _rc {
            di as error "pte: variable `var' not found."
            di as error "  Please run {bf:pte} estimation first."
            exit 111
        }
    }

    _pte_validate_internal_state _pte_tt numeric ///
        "pte_graph, catt requires _pte_tt to remain the numeric firm-level TT bridge."

    _pte_validate_internal_state _pte_nt integer ///
        "pte_graph, catt requires _pte_nt to remain the integer event-time bridge."

    // Resolve the panel id through the shared diagnostics contract so CATT
    // graphs keep honoring the setup-selected panel axis after pte_setup or
    // postestimation flows that restore the caller's xtset state.
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
    // any additional live panel/time fragment or predict payload is present,
    // CATT must honor the shared diagnostics contract instead of reviving a
    // panel-only fallback. A bare e(treatment) name alone does not certify
    // the active graph law and remains the narrow compatibility stub.
    local have_live_pte = (`have_live_panel_contract' | `have_live_payload')
    local have_setup_fragment = ///
        (`"`setup_panel'"' != "") | ///
        (`"`setup_time'"' != "") | ///
        (`"`setup_treatment'"' != "") | ///
        (`"`setup_treatsig'"' != "") | ///
        (`"`setup_xtdelta'"' != "")
    if "`currentlawchecked'" == "" {
        capture quietly _pte_diag_panel_contract, context("pte_graph catt") ///
            allowsetupmissingxtdelta
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
        else if `have_setup_fragment' | `have_live_pte' {
            exit `panel_contract_rc'
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
        di as error "pte: panel variable not found."
        di as error "  Re-run {bf:pte} or {bf:xtset} the current panel data."
        exit 111
    }
    
    // Validate pre-treatment observations exist
    quietly count if _pte_nt == -1
    if r(N) == 0 {
        di as error "pte: no pre-treatment observations (nt=-1) found."
        exit 2000
    }
    local n_pretrt = r(N)
    
    // Validate quantiles
    if `quantiles' < 2 {
        di as error "pte: quantiles must be >= 2"
        exit 198
    }
    if `quantiles' > 10 {
        di as text "{bf:Warning}: quantiles > 10 may result in sparse groups"
    }
    
    // Validate type
    if !inlist("`type'", "byperiod", "bygroup") {
        di as error "pte: type must be 'byperiod' or 'bygroup'"
        exit 198
    }
    
    // Validate sufficient sample for grouping
    if `n_pretrt' < `quantiles' {
        di as error "pte: only `n_pretrt' pre-treatment observations,"
        di as error "  cannot create `quantiles' groups."
        exit 2001
    }
    
    // =========================================================================
    // Task 3-6: Data processing (preserve/restore protected)
    // =========================================================================
    
    preserve
    
    // --- Task 3: Normalize omega ---
    capture confirm variable _pte_industry, exact
    if _rc == 0 {
        // Industry-level normalization
        di as text "Normalizing productivity by industry..."
        tempvar ind_mean
        quietly bys _pte_industry: egen double `ind_mean' = mean(_pte_omega)
        quietly gen double _pte_omega_norm = _pte_omega - `ind_mean'
    }
    else {
        // Global normalization
        di as text "Note: no industry variable, using global normalization"
        quietly summarize _pte_omega, meanonly
        quietly gen double _pte_omega_norm = _pte_omega - r(mean)
    }
    
    // --- Task 4: Quantile grouping (nt=-1 only) ---
    di as text "Creating `quantiles' productivity groups using percentiles..."
    quietly xtile _pte_omg0_group = _pte_omega_norm if _pte_nt == -1, nq(`quantiles')
    
    // Validate grouping
    quietly summarize _pte_omg0_group
    if r(min) != 1 | r(max) != `quantiles' {
        di as error "pte: quantile grouping failed"
        restore
        exit 459
    }
    
    // Check group sizes
    forvalues g = 1/`quantiles' {
        quietly count if _pte_omg0_group == `g' & _pte_nt == -1
        if r(N) == 0 {
            di as error "pte: group `g' has no observations"
            restore
            exit 2001
        }
        else if r(N) < 5 {
            di as text "{bf:Warning}: group `g' has only " r(N) " observations"
        }
    }
    
    // --- Task 5: Fill group across periods ---
    di as text "Filling group information across periods..."
    tempvar group_filled
    quietly bys `panelvar': egen byte `group_filled' = max(_pte_omg0_group)
    quietly replace _pte_omg0_group = `group_filled'
    
    // Verify fill consistency
    tempvar group_sd
    quietly bys `panelvar': egen `group_sd' = sd(_pte_omg0_group)
    quietly count if `group_sd' != 0 & !missing(`group_sd')
    if r(N) > 0 {
        di as error "pte: group filling failed - inconsistent groups within firm"
        restore
        exit 459
    }
    
    // --- Task 6: Compute CATT means ---
    di as text "Computing CATT means by group and period..."
    quietly keep if _pte_nt >= 0
    quietly collapse (mean) tt_mean=_pte_tt (count) tt_n=_pte_tt ///
                     (sd) tt_sd=_pte_tt, by(_pte_omg0_group _pte_nt)
    
    // Filter to specified periods
    tempvar in_nt
    quietly gen byte `in_nt' = 0
    foreach t of numlist `nt' {
        quietly replace `in_nt' = 1 if _pte_nt == `t'
    }
    quietly keep if `in_nt' == 1
    
    // =========================================================================
    // Task 7-8: Plot construction
    // =========================================================================
    
    // Marker style sequence
    local markers "Oh Dh Th Sh X o d t s p"
    
    if "`type'" == "byperiod" {
        // --- Task 7: byperiod plot (Figure 5 format) ---
        if `"`xtitle'"' == "" local xtitle "periods"
        
        local graph_cmd "twoway"
        local legend_order ""
        
        forvalues g = 1/`quantiles' {
            local m: word `g' of `markers'
            local lp = cond(`g' <= 2, "solid", "dot")
            local lw = cond(`g' <= 2, "0.8", "0.5")
            
            local graph_cmd "`graph_cmd' (connected tt_mean _pte_nt if _pte_omg0_group==`g', m(`m') lp(`lp') lw(`lw'))"
            
            // Get group label
            _pte_get_group_label `g' `quantiles'
            local lab "`r(label)'"
            local legend_order `"`legend_order' `g' "`lab'""'
        }
    }
    else {
        // --- Task 8: bygroup plot ---
        if `"`xtitle'"' == "" local xtitle "bins of initial productivity"
        
        local graph_cmd "twoway"
        local legend_order ""
        local p = 0
        
        foreach t of numlist `nt' {
            local ++p
            local m: word `p' of `markers'
            local lp = cond(`p' <= 2, "solid", "dot")
            local lw = cond(`p' <= 2, "0.8", "0.5")
            
            local graph_cmd "`graph_cmd' (connected tt_mean _pte_omg0_group if _pte_nt==`t', m(`m') lp(`lp') lw(`lw'))"
            local legend_order `"`legend_order' `p' "period `t'""'
        }
    }
    
    // Add graph options
    local graph_cmd `"`graph_cmd', legend(order(`legend_order') ring(0) col(2) pos(11) region(fcolor(none) lpattern(blank)))"'
    local graph_cmd `"`graph_cmd' ylabel(, grid) xlabel(, grid)"'
    local graph_cmd `"`graph_cmd' xtitle(`"`xtitle'"') ytitle(`"`ytitle'"')"'
    if `"`title'"' != "" {
        local graph_cmd `"`graph_cmd' title(`"`title'"')"'
    }
    local graph_cmd `"`graph_cmd' scheme(`scheme')"'
    
    // Execute graph
    di as text "Drawing CATT grouped graph (`type')..."
    `graph_cmd'
    
    // =========================================================================
    // Task 10: Save and export
    // =========================================================================
    
    if "`save'" != "" {
        if !regexm("`save'", "\.gph$") {
            local save "`save'.gph"
        }
        graph save "`save'", replace
        di as text "graph saved to `save'"
    }
    
    if "`export'" != "" {
        local ext = lower(substr("`export'", -4, .))
        if !inlist("`ext'", ".png", ".eps", ".pdf", ".tif") {
            di as error "unsupported export format: `ext'"
            di as error "supported formats: .png, .eps, .pdf, .tif"
            restore
            exit 198
        }
        graph export "`export'", width(`width') height(`height') replace
        di as text "graph exported to `export'"
    }
    
    restore
    
    // =========================================================================
    // Return values
    // =========================================================================
    
    return local type "`type'"
    return scalar quantiles = `quantiles'
    return local periods "`nt'"
    
    // Summary display
    di as text ""
    di as text "{bf:CATT Grouped Graph (`type')}"
    di as text "{hline 50}"
    di as text "Type: `type'"
    di as text "Quantile groups: `quantiles'"
    di as text "Periods: `nt'"
    di as text "{hline 50}"
    
end
