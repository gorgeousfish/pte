*! _pte_graph_diagnose.ado
*! Diagnostic plots for pte package

version 14.0
program define _pte_graph_diagnose, rclass
    version 14.0
    
    syntax , [TYPE(string) COEF(varname) REFVAL(string) ///
              NT(numlist) YEARS(numlist) REFYEAR(numlist) ///
              WINSOR(numlist) BINS(integer 20) ///
              NOALL ///
              CURRENTLAWCHECKED ///
              INDUSTRY(varname) ///
              BY(varname) TItle(string) XTItle(string) YTItle(string) ///
              SCHeme(string) SAVE(string) EXPORT(string) ///
              WIDTH(integer 800) HEIGHT(integer 600)]
    
    // =========================================================================
    // Validate type option
    // =========================================================================
    
    if "`type'" == "" local type "cdf"
    
    local valid_types "cdf kdensity eps0_byyear diff_omega0 eps0_treat_control placebo omega_density"
    if !`:list type in valid_types' {
        di as error "pte_graph diagnose: invalid type '{bf:`type'}'"
        di as error "valid types: `valid_types'"
        exit 198
    }
    
    // =========================================================================
    // Set default scheme
    // =========================================================================
    
    if "`scheme'" == "" local scheme "s1color"
    
    // =========================================================================
    // Route to diagnostic subprograms
    // =========================================================================
    
    if "`type'" == "eps0_byyear" {
        _pte_graph_diag_eps0_byyear, `currentlawchecked' ///
            years(`years') refyear(`refyear') ///
            industry(`industry') title(`"`title'"') xtitle(`"`xtitle'"') ytitle(`"`ytitle'"') ///
            save(`save') export(`export') width(`width') height(`height')
        return add
        return local type "`type'"
        exit
    }
    
    if "`type'" == "diff_omega0" {
        _pte_graph_diag_diff_omega0, `currentlawchecked' nt(`nt') ///
            title(`"`title'"') xtitle(`"`xtitle'"') ytitle(`"`ytitle'"') ///
            save(`save') export(`export') width(`width') height(`height')
        return add
        return local type "`type'"
        exit
    }
    
    if "`type'" == "eps0_treat_control" {
        _pte_graph_diag_eps0_tc, `currentlawchecked' ///
            winsor(`winsor') industry(`industry') ///
            title(`"`title'"') xtitle(`"`xtitle'"') ytitle(`"`ytitle'"') ///
            save(`save') export(`export') width(`width') height(`height')
        return add
        return local type "`type'"
        exit
    }
    
    if "`type'" == "placebo" {
        if "`coef'" == "" {
            di as error "pte_graph diagnose type(placebo): {bf:coef()} is required"
            di as error "specify the variable that stores placebo coefficients"
            exit 198
        }
        // refval is required for placebo type (DD-014.5)
        if "`refval'" == "" {
            di as error "pte_graph diagnose type(placebo): {bf:refval()} is required"
            di as error "specify the actual estimate value for the reference line"
            exit 198
        }
        local refval_num = real("`refval'")
        if missing(`refval_num') {
            di as error "pte_graph diagnose type(placebo): refval() must be a number"
            exit 198
        }
        _pte_graph_diag_placebo, coef(`coef') refval(`refval_num') bins(`bins') ///
            title(`"`title'"') xtitle(`"`xtitle'"') ytitle(`"`ytitle'"') ///
            save(`save') export(`export') width(`width') height(`height')
        return add
        return local type "`type'"
        exit
    }
    
    if "`type'" == "omega_density" {
        _pte_graph_diag_omega_density, `noall' `currentlawchecked' ///
            industry(`industry') ///
            title(`"`title'"') xtitle(`"`xtitle'"') ytitle(`"`ytitle'"') ///
            save(`save') export(`export') width(`width') height(`height')
        return add
        return local type "`type'"
        exit
    }
    
    // =========================================================================
    // Original cdf/kdensity implementation (inline, backward compatible)
    // =========================================================================

    // Before validating package-owned treatment/event-time helpers, certify that
    // a stale pte_setup helper bundle has not been left behind by check mode.
    // Pure legacy fixtures that materialize only _pte_year/_pte_treat/_pte_nt
    // still fall through to the exact _pte_year bridge below.
    if "`currentlawchecked'" == "" {
        local _pte_pre_setup_panel : char _dta[_pte_setup_panelvar]
        local _pte_pre_setup_time : char _dta[_pte_setup_timevar]
        local _pte_pre_setup_treatment : char _dta[_pte_setup_treatment]
        local _pte_pre_setup_treatsig : char _dta[_pte_setup_treatsig]
        local _pte_pre_setup_xtdelta : char _dta[_pte_setup_xtdelta]
        local _pte_pre_have_setup_fragment = ///
            (`"`_pte_pre_setup_panel'"' != "") | ///
            (`"`_pte_pre_setup_time'"' != "") | ///
            (`"`_pte_pre_setup_treatment'"' != "") | ///
            (`"`_pte_pre_setup_treatsig'"' != "") | ///
            (`"`_pte_pre_setup_xtdelta'"' != "")
        local _pte_pre_hsh = 0
        foreach helper in _pte_D _pte_mid _pte_cohort _pte_treat_year ///
            _pte_first_treat_year {
            capture confirm variable `helper', exact
            if _rc == 0 {
                local _pte_pre_hsh = 1
                continue, break
            }
        }
        local _pte_pre_live_id ""
        local _pte_pre_live_time ""
        local _pte_pre_live_treatsig ""
        local _pte_pre_live_predict ""
        if "`e(cmd)'" == "pte" {
            capture local _pte_pre_live_id = e(idvar)
            if _rc != 0 | inlist("`_pte_pre_live_id'", "", ".") {
                capture local _pte_pre_live_id = e(id)
            }
            if "`_pte_pre_live_id'" == "." {
                local _pte_pre_live_id ""
            }
            capture local _pte_pre_live_time = e(timevar)
            if _rc != 0 | inlist("`_pte_pre_live_time'", "", ".") {
                capture local _pte_pre_live_time = e(time)
            }
            if "`_pte_pre_live_time'" == "." {
                local _pte_pre_live_time ""
            }
            capture local _pte_pre_live_treatsig = e(treatsig)
            if _rc != 0 | "`_pte_pre_live_treatsig'" == "." {
                local _pte_pre_live_treatsig ""
            }
            capture local _pte_pre_live_predict = e(predict)
            if _rc != 0 | "`_pte_pre_live_predict'" == "." {
                local _pte_pre_live_predict ""
            }
        }
        local _pte_pre_have_live_pte = ///
            (`"`_pte_pre_live_id'"' != "") | ///
            (`"`_pte_pre_live_time'"' != "") | ///
            (`"`_pte_pre_live_treatsig'"' != "") | ///
            (`"`_pte_pre_live_predict'"' != "")
        if `_pte_pre_have_setup_fragment' | `_pte_pre_have_live_pte' | ///
            `_pte_pre_hsh' {
            capture noisily _pte_diag_panel_contract, ///
                context("pte_graph diagnose type(`type')") allowsetupmissingxtdelta
            local _pte_pre_panel_contract_rc = _rc
            if `_pte_pre_panel_contract_rc' != 0 {
                exit `_pte_pre_panel_contract_rc'
            }
        }
    }
    
    // Prerequisite checks
    foreach var in _pte_eps0 _pte_treat _pte_nt {
        capture confirm variable `var', exact
        if _rc {
            di as error "pte_graph requires prior pte estimation"
            di as error "variable `var' not found"
            di as error "run {bf:pte} command first"
            exit 111
        }
    }
    _pte_validate_internal_state _pte_treat binary ///
        "pte_graph diagnose type(`type') requires _pte_treat to remain the certified binary ever-treated indicator."
    _pte_validate_internal_state _pte_nt integer ///
        "pte_graph diagnose type(`type') requires _pte_nt to remain the certified integer event-time index."

    quietly _pte_diag_eps0_support_if, epsvar(_pte_eps0) ///
        context("pte_graph diagnose type(`type')")
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
    // else; keep the legacy `_pte_year' fallback for that narrow case. Once
    // any additional live predict payload is present, the graph worker must
    // honor the shared diagnostics contract instead of reviving legacy
    // fallback. A bare e(treatment) name alone does not certify the current
    // panel/timing law for graph routing.
    local have_live_pte = (`have_live_panel_contract' | `have_live_payload')
    local have_setup_fragment = ///
        (`"`setup_panel'"' != "") | ///
        (`"`setup_time'"' != "") | ///
        (`"`setup_treatment'"' != "") | ///
        (`"`setup_treatsig'"' != "") | ///
        (`"`setup_xtdelta'"' != "")
    // The shared cdf/kdensity diagnose path consumes only the certified
    // calendar window, not the lag law itself, so a complete setup contract
    // may bridge a missing live e(xtdelta) while still failing on conflicts.
    if "`currentlawchecked'" == "" {
        capture noisily _pte_diag_panel_contract, ///
            context("pte_graph diagnose type(`type')") allowsetupmissingxtdelta
        local panel_contract_rc = _rc
        if `panel_contract_rc' == 0 {
            local timevar "`r(timevar)'"
        }
        else if `have_setup_fragment' | `have_live_pte' {
            exit `panel_contract_rc'
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

    // Pure-legacy graph fixtures may materialize the diagnostic calendar axis
    // directly as `_pte_year'` only when there is no live pte claim and no
    // setup contract to certify a current panel law.
    if "`timevar'" == "" & !`have_setup_fragment' & !`have_live_pte' {
        capture confirm variable _pte_year, exact
        if !_rc {
            local timevar "_pte_year"
        }
    }

    if "`timevar'" == "" {
        di as error "pte_graph diagnose type(`type'): panel time variable not found"
        di as error "re-run pte or xtset the panel data before graphing"
        exit 459
    }

    capture confirm numeric variable `timevar', exact
    if _rc {
        di as error "pte_graph diagnose type(`type'): time variable `timevar' not found"
        di as error "re-run pte on the current dataset or restore variable `timevar'"
        exit 111
    }
    
    if "`by'" != "" {
        capture confirm variable `by'
        if _rc {
            di as error "variable `by' not found"
            exit 111
        }
    }
    
    if `"`title'"' == "" {
        local title "Distribution of Productivity Innovations"
    }
    
    // Build the same matched untreated-support sample used by the released
    // diagnose workers. That law is identified by ever-treated status,
    // event time, and the stored panel calendar support; it does not require
    // a separate copied `_pte_D' status variable to exist in the dataset.
    preserve

    // Keep a worker-local copy of eps0 so the released diagnose worker can
    // apply its deterministic trim law without mutating caller data.
    tempvar _pte_eps0_use
    quietly gen double `_pte_eps0_use' = _pte_eps0
    if `use_support' {
        quietly replace `_pte_eps0_use' = . if _pte_eps0_ind != 1
    }

    quietly count if !missing(`_pte_eps0_use')
    if r(N) == 0 {
        di as error "no valid observations for CDF analysis"
        restore
        exit 2000
    }

    // Match the released CDF worker and the official DO diagnostics:
    // trim the copied eps0 pool before restricting to the treated/control
    // comparison window. Otherwise window-external outliers change the public
    // diagnose path and pte_graph diagnose path differently.
    quietly _pte_trim_var `_pte_eps0_use'
    drop if missing(`_pte_eps0_use')
    
    // Group variable generation must follow the paper/DO comparison window:
    // treated firms use the last three pretreatment periods, and controls are
    // restricted to the same calendar window.
    tempvar _treated_pre _control_window _window_year
    local prewindow = 3

    quietly gen byte `_treated_pre' = (_pte_treat == 1) & (_pte_nt < 0) ///
        & (_pte_nt >= -`prewindow') & !missing(`_pte_eps0_use')
    quietly count if `_treated_pre'
    local n_treated = r(N)
    if `n_treated' == 0 {
        di as error "no treated pre-treatment observations in the last `prewindow' periods"
        restore
        exit 2000
    }

    // Match controls to the exact treated pretreatment year support; a
    // closed min/max envelope would silently absorb gap years.
    quietly bysort `timevar': egen byte `_window_year' = max(`_treated_pre')
    quietly gen byte `_control_window' = (_pte_treat == 0) & !missing(`_pte_eps0_use') ///
        & `_window_year' == 1

    gen byte _eps_group = .
    replace _eps_group = 1 if `_treated_pre'
    replace _eps_group = 0 if `_control_window'
    drop if missing(_eps_group)

    local lab0 "control units"
    local lab1 "treated units (pre-treatment)"
    
    // Group data checks and statistics
    quietly count if _eps_group == 1 & !missing(`_pte_eps0_use')
    local n_treated = r(N)
    quietly count if _eps_group == 0 & !missing(`_pte_eps0_use')
    local n_control = r(N)
    
    if `n_treated' == 0 & `n_control' == 0 {
        di as error "no valid observations for either group"
        restore
        exit 2000
    }
    if `n_treated' == 0 {
        di as error "no observations for treated group"
        restore
        exit 2000
    }
    if `n_control' == 0 {
        di as error "no observations for control group"
        restore
        exit 2000
    }
    
    // Compute statistics
    local mean_treated = .
    local sd_treated = .
    local mean_control = .
    local sd_control = .
    
    quietly summarize `_pte_eps0_use' if _eps_group == 1, detail
    local mean_treated = r(mean)
    local sd_treated = r(sd)
    
    quietly summarize `_pte_eps0_use' if _eps_group == 0, detail
    local mean_control = r(mean)
    local sd_control = r(sd)
    
    // CDF calculation
    if "`type'" == "cdf" {
        cumul `_pte_eps0_use' if _eps_group == 0, gen(cdf_control)
        cumul `_pte_eps0_use' if _eps_group == 1, gen(cdf_treated)
        sort `_pte_eps0_use' _eps_group
    }
    
    // Build graph command
    local graph_cmd "twoway"
    local legend_order ""
    local plot_count = 0
    
    if "`type'" == "cdf" {
        // CDF plot
        local graph_cmd `"`graph_cmd' (line cdf_treated `_pte_eps0_use' if _eps_group == 1, lc(blue) lw(0.8))"'
        local plot_count = `plot_count' + 1
        local legend_order `"`legend_order' `plot_count' "`lab1'""'
        local graph_cmd `"`graph_cmd' (line cdf_control `_pte_eps0_use' if _eps_group == 0, lc(red) lw(0.8) lp(dash))"'
        local plot_count = `plot_count' + 1
        local legend_order `"`legend_order' `plot_count' "`lab0'""'
    }
    else {
        // Kernel density plot
        local graph_cmd `"`graph_cmd' (kdensity `_pte_eps0_use' if _eps_group == 1, lc(blue) lw(0.8))"'
        local plot_count = `plot_count' + 1
        local legend_order `"`legend_order' `plot_count' "`lab1'""'
        local graph_cmd `"`graph_cmd' (kdensity `_pte_eps0_use' if _eps_group == 0, lc(red) lw(0.8) lp(dash))"'
        local plot_count = `plot_count' + 1
        local legend_order `"`legend_order' `plot_count' "`lab0'""'
    }
    
    if `plot_count' == 0 {
        di as error "no valid curves to plot"
        restore
        exit 2000
    }
    
    // Graph elements (legend, title, grid)
    local graph_cmd `"`graph_cmd', legend(order(`legend_order') cols(2))"'
    
    if "`type'" == "cdf" {
        local graph_cmd `"`graph_cmd' ytitle("Probability")"'
    }
    else {
        local graph_cmd `"`graph_cmd' ytitle("Density")"'
    }
    
    local graph_cmd `"`graph_cmd' xtitle("productivity shocks")"'
    local graph_cmd `"`graph_cmd' title(`"`title'"')"'
    local graph_cmd `"`graph_cmd' xlabel(, grid gstyle(dot))"'
    local graph_cmd `"`graph_cmd' ylabel(, grid gstyle(dot))"'
    local graph_cmd `"`graph_cmd' scheme(`scheme')"'
    
    // Execute graph command
    `graph_cmd'
    
    // K-S test
    quietly ksmirnov `_pte_eps0_use', by(_eps_group)
    local ks_D = r(D)
    local ks_p = r(p)
    
    di as text ""
    di as text "{bf:Kolmogorov-Smirnov Test}"
    di as text "{hline 40}"
    di as text "D statistic = " %8.6f `ks_D'
    di as text "p-value     = " %8.6f `ks_p'
    di as text "{hline 40}"
    
    if `ks_p' > 0.05 {
        di as text "Cannot reject H0: distributions are equal (p > 0.05)"
        di as text "  Supports Assumption 4.3 (iid innovations)"
    }
    else {
        di as text "{bf:Warning}: Reject H0 at 5% level"
        di as text "  Assumption 4.3 may be violated"
    }
    
    // Save and export
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
    
    // Restore data
    restore
    
    // Return subtype-specific identifiers for the shared cdf/kdensity path.
    local graph_type "cdf_diagnose"
    if "`type'" == "kdensity" {
        local graph_type "kdensity_diagnose"
    }

    // Return values
    return local graph_type "`graph_type'"
    return local type "`type'"
    
    if "`save'" != "" {
        return local filename "`save'"
        return local format "gph"
    }
    if "`export'" != "" {
        return local export_file "`export'"
    }
    
    return scalar ks_D = `ks_D'
    return scalar ks_p = `ks_p'
    return scalar nobs_treated = `n_treated'
    return scalar nobs_control = `n_control'
    if !missing(`mean_treated') {
        return scalar mean_treated = `mean_treated'
    }
    else {
        return scalar mean_treated = .
    }
    if !missing(`mean_control') {
        return scalar mean_control = `mean_control'
    }
    else {
        return scalar mean_control = .
    }
    if !missing(`sd_treated') {
        return scalar sd_treated = `sd_treated'
    }
    else {
        return scalar sd_treated = .
    }
    if !missing(`sd_control') {
        return scalar sd_control = `sd_control'
    }
    else {
        return scalar sd_control = .
    }
    
    // Summary display
    di as text ""
    di as text "{bf:eps0 Diagnostic Summary}"
    di as text "{hline 50}"
    di as text "Type:            `type'"
    di as text "Treated obs:     " %8.0fc `n_treated'
    di as text "Control obs:     " %8.0fc `n_control'
    if !missing(`mean_treated') {
        di as text "Mean (treated):  " %10.6f `mean_treated'
        di as text "SD (treated):    " %10.6f `sd_treated'
    }
    if !missing(`mean_control') {
        di as text "Mean (control):  " %10.6f `mean_control'
        di as text "SD (control):    " %10.6f `sd_control'
    }
    di as text "{hline 50}"
    
end
