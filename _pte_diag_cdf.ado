*! _pte_diag_cdf.ado
*! CDF Comparison Diagnostic Plot
*!
*! Plots empirical CDF of eps0 for the paper's three-year treated
*! pretreatment support versus time-matched control observations.
*! Visual diagnostic for the untreated-shock support used in Assumption 4.3.

version 14.0
program define _pte_diag_cdf, rclass
    version 14.0
    
    syntax , [eps0(varname) SAVing(string) TItle(string) ///
              NOTRIMeps FORMat(string) QUIetly]
    
    // =========================================================
    // 1. Parameter defaults
    // =========================================================
    
    if "`eps0'" == "" {
        local eps0 "_pte_eps0"
    }
    if "`title'" == "" {
        local title "Empirical CDF of Innovation Shocks (eps0)"
    }
    local format = lower("`format'")
    
    // =========================================================
    // 2. Validate inputs
    // =========================================================
    
    // The default diagnostic object is the package-owned canonical _pte_eps0.
    // Do not allow Stata abbreviation fallback to bind `_pte_eps0' to a
    // shadow variable like `_pte_eps0_shadow`, or the CDF graph will report
    // success on the wrong untreated-shock object.
    if `"`eps0'"' == "_pte_eps0" {
        capture confirm variable _pte_eps0, exact
        if _rc != 0 {
            di as error "Variable _pte_eps0 not found. Run pte estimation first."
            exit 111
        }
        capture confirm numeric variable _pte_eps0, exact
        if _rc != 0 {
            di as error "eps0() variable _pte_eps0 must be numeric"
            exit 111
        }
    }
    else {
        capture confirm variable `eps0', exact
        if _rc != 0 {
            di as error "Variable `eps0' not found. Run pte estimation first."
            exit 111
        }
        capture confirm numeric variable `eps0', exact
        if _rc != 0 {
            di as error "eps0() variable `eps0' must be numeric"
            exit 111
        }
    }

    quietly _pte_diag_eps0_support_if, epsvar(`eps0') ///
        context("CDF diagnostics")
    local use_support = r(uses_support)
    
    capture confirm variable _pte_treat, exact
    if _rc != 0 {
        di as error "Variable _pte_treat not found. Run pte_setup first."
        exit 111
    }
    _pte_validate_internal_state _pte_treat binary ///
        "CDF diagnostics require _pte_treat to remain the certified binary ever-treated indicator."

    capture confirm variable _pte_nt, exact
    if _rc != 0 {
        di as error "Variable _pte_nt not found. Run pte_setup first."
        exit 111
    }
    _pte_validate_internal_state _pte_nt integer ///
        "CDF diagnostics require _pte_nt to remain the certified integer event-time index."

    _pte_diag_panel_contract, context("CDF diagnostics") allowsetupmissingxtdelta
    local timevar = r(timevar)
    
    // =========================================================
    // 3. Prepare data
    // =========================================================
    
    preserve
    
    // Optional Winsorization
    tempvar eps0_use
    qui gen double `eps0_use' = `eps0'
    if `use_support' {
        qui replace `eps0_use' = . if _pte_eps0_ind != 1
    }
    
    if "`notrimeps'" == "" {
        // Match the replication trim law with the package-owned
        // deterministic worker instead of depending on winsor2.
        qui _pte_trim_var `eps0_use'
    }
    
    // Drop missing
    qui drop if missing(`eps0_use') | missing(_pte_treat)
    
    // =========================================================
    // 4. Compute empirical CDF for each group
    // =========================================================
    
    tempvar cdf_ctrl cdf_treat treated_pre control_window window_year
    local prewindow = 3

    qui gen byte `treated_pre' = (_pte_treat == 1) & (_pte_nt < 0) ///
        & (_pte_nt >= -`prewindow') & !missing(`eps0_use')
    qui count if `treated_pre'
    local n_treat = r(N)
    if `n_treat' == 0 {
        di as error "No treated pre-treatment observations"
        restore
        exit 2000
    }

    // Match controls to the exact calendar years that contain treated
    // pretreatment support; a min/max envelope can absorb unsupported gap years.
    qui bysort `timevar': egen byte `window_year' = max(`treated_pre')
    qui gen byte `control_window' = (_pte_treat == 0) & !missing(`eps0_use') ///
        & `window_year' == 1

    // Control group CDF
    qui count if `control_window'
    local n_ctrl = r(N)
    if `n_ctrl' > 0 {
        qui cumul `eps0_use' if `control_window', gen(`cdf_ctrl')
    }
    else {
        di as error "No control observations in the treated pre-treatment window"
        restore
        exit 2000
    }

    // Treated group CDF
    qui cumul `eps0_use' if `treated_pre', gen(`cdf_treat')
    
    // =========================================================
    // 5. Plot CDF comparison
    // =========================================================
    
    twoway (line `cdf_ctrl' `eps0_use' if `control_window', ///
                sort lcolor(blue) lwidth(medium) lpattern(solid)) ///
           (line `cdf_treat' `eps0_use' if `treated_pre', ///
                sort lcolor(red) lwidth(medium) lpattern(dash)), ///
           title("`title'") ///
           xtitle("eps0 (innovation shock)") ///
           ytitle("Cumulative Probability") ///
           legend(order(1 "Control (matched window)" 2 "Treated pre-treatment") ///
                  ring(0) pos(5) cols(1)) ///
           note("N(control)=`n_ctrl', N(treated)=`n_treat'") ///
           scheme(s2color)
    
    // =========================================================
    // 6. Save if requested
    // =========================================================
    
    if "`saving'" != "" {
        local export_format "`format'"
        local export_path "`saving'"

        if "`export_format'" == "" {
            _pte_detect_format "`saving'"
            local export_format "`r(format)'"
        }

        if "`export_format'" == "png" {
            qui graph export "`export_path'", as(png) replace width(1200)
        }
        else if "`export_format'" == "pdf" {
            qui graph export "`export_path'", as(pdf) replace
        }
        else if "`export_format'" == "eps" {
            qui graph export "`export_path'", as(eps) replace
        }
        else {
            // Default: append .png when no explicit format or supported extension is supplied.
            local export_format "png"
            local export_path "`saving'.png"
            qui graph export "`export_path'", as(png) replace width(1200)
        }
        
        if "`quietly'" == "" {
            di as text "Graph saved to: `export_path'"
        }
    }
    
    // =========================================================
    // 7. Return values
    // =========================================================
    
    return scalar n_control = `n_ctrl'
    return scalar n_treated = `n_treat'
    
    restore
end
