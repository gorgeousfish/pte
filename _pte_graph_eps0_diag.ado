*! _pte_graph_eps0_diag.ado
*! Epsilon-zero Diagnostic Graph
*! CDF comparison (treated vs control) + Q-Q plot for normality

version 14.0
capture program drop _pte_graph_eps0_diag
program define _pte_graph_eps0_diag, rclass
    version 14.0

    syntax [, TItle(string) XTItle(string) YTItle(string) ///
              SCHeme(string) SAVE(string) EXPort(string) ///
              Width(integer 1200) Height(integer 800) ///
              NOLEGend QQonly CDFonly *]

    if "`qqonly'" != "" & "`cdfonly'" != "" {
        di as error "{bf:Error}: qqonly and cdfonly cannot be combined."
        di as error "Choose either qqonly or cdfonly, or omit both for the two-panel diagnostic graph."
        exit 198
    }

    // =====================================================================
    // Validate: need _pte_eps0 and _pte_treat variables
    // =====================================================================

    capture confirm variable _pte_eps0, exact
    if _rc {
        di as error "{bf:Error}: Variable _pte_eps0 not found."
        di as error "Run pte estimation with omega recovery first."
        exit 111
    }

    capture confirm variable _pte_treat, exact
    local has_treat = (_rc == 0)

    quietly _pte_diag_eps0_support_if, epsvar(_pte_eps0) ///
        context("pte_graph eps0_diagnostic")
    local use_support = r(uses_support)

    // Defaults
    if "`scheme'" == "" local scheme "s1color"

    // =====================================================================
    // Determine graph mode: combined (default), qqonly, or cdfonly
    // =====================================================================

    local do_cdf = 1
    local do_qq  = 1
    if "`qqonly'" != "" {
        local do_cdf = 0
    }
    if "`cdfonly'" != "" {
        local do_qq = 0
    }

    local timevar ""
    if `do_cdf' & `has_treat' {
        local setup_panel_pre : char _dta[_pte_setup_panelvar]
        local setup_time_pre : char _dta[_pte_setup_timevar]
        local setup_treatment_pre : char _dta[_pte_setup_treatment]
        local setup_treatsig_pre : char _dta[_pte_setup_treatsig]
        local setup_xtdelta_pre : char _dta[_pte_setup_xtdelta]
        local live_id_pre ""
        local live_time_pre ""
        local live_treatsig_pre ""
        local live_predict_pre ""
        local live_treatment_pre ""
        if "`e(cmd)'" == "pte" {
            capture local live_id_pre = e(idvar)
            if _rc != 0 | inlist("`live_id_pre'", "", ".") {
                capture local live_id_pre = e(id)
            }
            if "`live_id_pre'" == "." {
                local live_id_pre ""
            }
            capture local live_time_pre = e(timevar)
            if _rc != 0 | inlist("`live_time_pre'", "", ".") {
                capture local live_time_pre = e(time)
            }
            if "`live_time_pre'" == "." {
                local live_time_pre ""
            }
            capture local live_treatsig_pre = e(treatsig)
            if _rc != 0 | "`live_treatsig_pre'" == "." {
                local live_treatsig_pre ""
            }
            capture local live_predict_pre = e(predict)
            if _rc != 0 | "`live_predict_pre'" == "." {
                local live_predict_pre ""
            }
            capture local live_treatment_pre = e(treatment)
            if _rc != 0 | "`live_treatment_pre'" == "." {
                local live_treatment_pre ""
            }
        }
        local have_setup_fragment_pre = ///
            (`"`setup_panel_pre'"' != "") | ///
            (`"`setup_time_pre'"' != "") | ///
            (`"`setup_treatment_pre'"' != "") | ///
            (`"`setup_treatsig_pre'"' != "") | ///
            (`"`setup_xtdelta_pre'"' != "")
        local have_setup_helper_bundle_pre = 0
        foreach helper in _pte_D _pte_mid _pte_cohort _pte_treat_year ///
            _pte_first_treat_year {
            capture confirm variable `helper', exact
            if _rc == 0 {
                local have_setup_helper_bundle_pre = 1
                continue, break
            }
        }
        local have_live_panel_contract_pre = ///
            (`"`live_id_pre'"' != "") | (`"`live_time_pre'"' != "") | ///
            (`"`live_treatsig_pre'"' != "")
        local have_live_payload_pre = (`"`live_predict_pre'"' != "")
        local have_live_pte_pre = ///
            (`have_live_panel_contract_pre' | `have_live_payload_pre')

        if `have_setup_fragment_pre' | `have_live_pte_pre' | ///
            `have_setup_helper_bundle_pre' {
            capture noisily _pte_diag_panel_contract, ///
                context("pte_graph eps0_diagnostic") allowsetupmissingxtdelta
            local panel_contract_pre_rc = _rc
            if `panel_contract_pre_rc' == 0 {
                local timevar "`r(timevar)'"
            }
            else {
                exit `panel_contract_pre_rc'
            }
        }

        _pte_validate_internal_state _pte_treat binary ///
            "pte_graph eps0_diagnostic CDF path requires _pte_treat to remain the certified binary ever-treated indicator."
        capture confirm variable _pte_nt, exact
        if _rc {
            di as error "{bf:Error}: Variable _pte_nt not found."
            di as error "Run pte_setup or pte before eps0_diagnostic CDF plots."
            exit 111
        }
        _pte_validate_internal_state _pte_nt integer ///
            "pte_graph eps0_diagnostic CDF path requires _pte_nt to remain the certified integer event-time index."

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
        local have_live_pte = (`have_live_panel_contract' | `have_live_payload')
        local have_setup_fragment = ///
            (`"`setup_panel'"' != "") | ///
            (`"`setup_time'"' != "") | ///
            (`"`setup_treatment'"' != "") | ///
            (`"`setup_treatsig'"' != "") | ///
            (`"`setup_xtdelta'"' != "")

        if `have_setup_fragment' | `have_live_pte' {
            // The grouped CDF panel reuses the same time-window law as
            // pte_diagnose, cdf and needs only the certified calendar axis.
            capture noisily _pte_diag_panel_contract, context("pte_graph eps0_diagnostic") allowsetupmissingxtdelta
            local panel_contract_rc = _rc
            if `panel_contract_rc' == 0 {
                local timevar "`r(timevar)'"
            }
            else {
                exit `panel_contract_rc'
            }
        }

        if "`timevar'" == "" & !`have_setup_fragment' & !`have_live_pte' {
            capture confirm variable _pte_year, exact
            if !_rc {
                local timevar "_pte_year"
            }
        }

        if "`timevar'" == "" {
            di as error "pte_graph eps0_diagnostic: panel time variable not found"
            di as error "re-run pte or xtset the panel data before graphing"
            exit 459
        }
    }

    // =====================================================================
    // Panel 1: CDF comparison (treated vs control)
    // =====================================================================

    if `do_cdf' & `do_qq' {
        // Combined: use graph combine
        if `has_treat' {
            // CDF by treatment group using the same exact untreated-shock law
            // as the released diagnose CDF worker: trim the copied support,
            // restrict treated firms to the last three pre-treatment periods,
            // and match controls to the treated calendar window.
            if `"`title'"' == "" local title "{c 949}{sup:0} Diagnostic: CDF and Q-Q Plot"

            preserve
            tempvar eps0_use cdf_control cdf_treat treated_pre control_window window_year
            quietly gen double `eps0_use' = _pte_eps0
            if `use_support' {
                quietly replace `eps0_use' = . if _pte_eps0_ind != 1
            }
            quietly _pte_trim_var `eps0_use'
            quietly drop if missing(`eps0_use') | missing(_pte_treat)

            local prewindow = 3
            quietly gen byte `treated_pre' = (_pte_treat == 1) & (_pte_nt < 0) ///
                & (_pte_nt >= -`prewindow') & !missing(`eps0_use')
            quietly count if `treated_pre'
            local n_treat = r(N)
            if `n_treat' == 0 {
                di as error "{bf:Error}: No treated pre-treatment observations in the last `prewindow' periods."
                restore
                exit 2000
            }

            quietly bysort `timevar': egen byte `window_year' = max(`treated_pre')
            quietly gen byte `control_window' = (_pte_treat == 0) & !missing(`eps0_use') ///
                & `window_year' == 1
            quietly count if `control_window'
            local n_ctrl = r(N)
            if `n_ctrl' == 0 {
                di as error "{bf:Error}: No control observations in the treated pre-treatment window."
                restore
                exit 2000
            }

            quietly cumul `eps0_use' if `control_window', gen(`cdf_control')
            quietly cumul `eps0_use' if `treated_pre', gen(`cdf_treat')

            // CDF graph
            twoway ///
                (line `cdf_control' `eps0_use' if `control_window', ///
                    sort lcolor(red) lpattern(dash) lwidth(medium)) ///
                (line `cdf_treat' `eps0_use' if `treated_pre', ///
                    sort lcolor(blue) lpattern(solid) lwidth(medium)) ///
                , ///
                xtitle("Innovation shock ({c 949}{sup:0})", size(medium)) ///
                ytitle("Cumulative probability", size(medium)) ///
                ylabel(0(0.2)1, labsize(medium) angle(horizontal)) ///
                legend(order(1 "Control (matched window)" 2 "Treated pre-treatment") ///
                    cols(1) position(6) size(medium)) ///
                title("CDF Comparison", size(medlarge)) ///
                graphregion(color(white)) ///
                scheme(`scheme') ///
                name(_pte_cdf_temp, replace) nodraw
            restore
        }
        else {
            // CDF without treatment groups
            if `"`title'"' == "" local title "{c 949}{sup:0} Diagnostic: CDF and Q-Q Plot"
            tempvar eps0_use cdf_all
            quietly gen double `eps0_use' = _pte_eps0
            if `use_support' {
                quietly replace `eps0_use' = . if _pte_eps0_ind != 1
            }
            quietly _pte_trim_var `eps0_use'
            quietly cumul `eps0_use' if !missing(`eps0_use'), gen(`cdf_all')

            twoway ///
                (line `cdf_all' `eps0_use' if !missing(`cdf_all'), ///
                    sort lcolor(navy) lpattern(solid) lwidth(medium)) ///
                , ///
                xtitle("Innovation shock ({c 949}{sup:0})", size(medium)) ///
                ytitle("Cumulative probability", size(medium)) ///
                ylabel(0(0.2)1, labsize(medium) angle(horizontal)) ///
                legend(off) ///
                title("CDF", size(medlarge)) ///
                graphregion(color(white)) ///
                scheme(`scheme') ///
                name(_pte_cdf_temp, replace) nodraw
        }

        // Q-Q plot against normal distribution
        quietly {
            tempvar eps0_use eps0_std eps0_rank eps0_pct eps0_qnorm
            gen double `eps0_use' = _pte_eps0
            if `use_support' {
                replace `eps0_use' = . if _pte_eps0_ind != 1
            }
            _pte_trim_var `eps0_use'
            summarize `eps0_use' if !missing(`eps0_use')
            if missing(r(sd)) | r(sd) <= 0 {
                di as error "{bf:Error}: eps0_diagnostic Q-Q panel requires positive variance in the untreated-shock support."
                di as error "The filtered _pte_eps0 sample is degenerate after applying the exact-support contract."
                exit 198
            }
            gen double `eps0_std' = `eps0_use' if !missing(`eps0_use')
            // Standardize
            sum `eps0_std'
            replace `eps0_std' = (`eps0_std' - r(mean)) / r(sd)
            // Rank and percentile
            egen `eps0_rank' = rank(`eps0_std')
            count if !missing(`eps0_std')
            local nobs = r(N)
            gen double `eps0_pct' = (`eps0_rank' - 0.5) / `nobs'
            gen double `eps0_qnorm' = invnormal(`eps0_pct')
            sort `eps0_std'
        }

        twoway ///
            (scatter `eps0_std' `eps0_qnorm', ///
                mcolor(navy%50) msymbol(oh) msize(small)) ///
            (function y=x, range(-3 3) ///
                lcolor(cranberry) lpattern(solid) lwidth(medium)) ///
            , ///
            xtitle("Theoretical quantiles (Normal)", size(medium)) ///
            ytitle("Sample quantiles ({c 949}{sup:0})", size(medium)) ///
            ylabel(, labsize(medium) angle(horizontal)) ///
            legend(off) ///
            title("Q-Q Plot (Normality Check)", size(medlarge)) ///
            graphregion(color(white)) ///
            scheme(`scheme') ///
            name(_pte_qq_temp, replace) nodraw

        // Combine panels
        graph combine _pte_cdf_temp _pte_qq_temp, ///
            cols(2) ///
            title(`"`title'"', size(large)) ///
            graphregion(color(white)) ///
            scheme(`scheme')

        // Clean up temporary graphs
        capture graph drop _pte_cdf_temp
        capture graph drop _pte_qq_temp
    }

    // =====================================================================
    // CDF-only mode
    // =====================================================================

    else if `do_cdf' {
        if `"`title'"' == "" local title "{c 949}{sup:0} CDF Comparison"

        if `has_treat' {
            preserve
            tempvar eps0_use cdf_control cdf_treat treated_pre control_window window_year
            quietly gen double `eps0_use' = _pte_eps0
            if `use_support' {
                quietly replace `eps0_use' = . if _pte_eps0_ind != 1
            }
            quietly _pte_trim_var `eps0_use'
            quietly drop if missing(`eps0_use') | missing(_pte_treat)

            local prewindow = 3
            quietly gen byte `treated_pre' = (_pte_treat == 1) & (_pte_nt < 0) ///
                & (_pte_nt >= -`prewindow') & !missing(`eps0_use')
            quietly count if `treated_pre'
            local n_treat = r(N)
            if `n_treat' == 0 {
                di as error "{bf:Error}: No treated pre-treatment observations in the last `prewindow' periods."
                restore
                exit 2000
            }

            quietly bysort `timevar': egen byte `window_year' = max(`treated_pre')
            quietly gen byte `control_window' = (_pte_treat == 0) & !missing(`eps0_use') ///
                & `window_year' == 1
            quietly count if `control_window'
            local n_ctrl = r(N)
            if `n_ctrl' == 0 {
                di as error "{bf:Error}: No control observations in the treated pre-treatment window."
                restore
                exit 2000
            }

            quietly cumul `eps0_use' if `control_window', gen(`cdf_control')
            quietly cumul `eps0_use' if `treated_pre', gen(`cdf_treat')
            twoway ///
                (line `cdf_control' `eps0_use' if `control_window', ///
                    sort lcolor(red) lpattern(dash) lwidth(medium)) ///
                (line `cdf_treat' `eps0_use' if `treated_pre', ///
                    sort lcolor(blue) lpattern(solid) lwidth(medium)) ///
                , ///
                xtitle("Innovation shock ({c 949}{sup:0})", size(medium)) ///
                ytitle("Cumulative probability", size(medium)) ///
                ylabel(0(0.2)1, labsize(medium) angle(horizontal)) ///
                `=cond("`nolegend'" == "", `"legend(order(1 "Control (matched window)" 2 "Treated pre-treatment") cols(1) position(6) size(medium))"', "legend(off)")' ///
                title(`"`title'"', size(large)) ///
                graphregion(color(white)) ///
                scheme(`scheme')
            restore
        }
        else {
            tempvar eps0_use cdf_all
            quietly gen double `eps0_use' = _pte_eps0
            if `use_support' {
                quietly replace `eps0_use' = . if _pte_eps0_ind != 1
            }
            quietly _pte_trim_var `eps0_use'
            quietly cumul `eps0_use' if !missing(`eps0_use'), gen(`cdf_all')
            twoway ///
                (line `cdf_all' `eps0_use' if !missing(`cdf_all'), ///
                    sort lcolor(navy) lpattern(solid) lwidth(medium)) ///
                , ///
                xtitle("Innovation shock ({c 949}{sup:0})", size(medium)) ///
                ytitle("Cumulative probability", size(medium)) ///
                ylabel(0(0.2)1, labsize(medium) angle(horizontal)) ///
                legend(off) ///
                title(`"`title'"', size(large)) ///
                graphregion(color(white)) ///
                scheme(`scheme')
        }
    }

    // =====================================================================
    // Q-Q only mode
    // =====================================================================

    else if `do_qq' {
        if `"`title'"' == "" local title "{c 949}{sup:0} Q-Q Plot (Normality Check)"

        quietly {
            tempvar eps0_use eps0_std eps0_rank eps0_pct eps0_qnorm
            gen double `eps0_use' = _pte_eps0
            if `use_support' {
                replace `eps0_use' = . if _pte_eps0_ind != 1
            }
            _pte_trim_var `eps0_use'
            summarize `eps0_use' if !missing(`eps0_use')
            if missing(r(sd)) | r(sd) <= 0 {
                di as error "{bf:Error}: eps0_diagnostic Q-Q panel requires positive variance in the untreated-shock support."
                di as error "The filtered _pte_eps0 sample is degenerate after applying the exact-support contract."
                exit 198
            }
            gen double `eps0_std' = `eps0_use' if !missing(`eps0_use')
            sum `eps0_std'
            replace `eps0_std' = (`eps0_std' - r(mean)) / r(sd)
            egen `eps0_rank' = rank(`eps0_std')
            count if !missing(`eps0_std')
            local nobs = r(N)
            gen double `eps0_pct' = (`eps0_rank' - 0.5) / `nobs'
            gen double `eps0_qnorm' = invnormal(`eps0_pct')
            sort `eps0_std'
        }

        twoway ///
            (scatter `eps0_std' `eps0_qnorm', ///
                mcolor(navy%50) msymbol(oh) msize(small)) ///
            (function y=x, range(-3 3) ///
                lcolor(cranberry) lpattern(solid) lwidth(medium)) ///
            , ///
            xtitle("Theoretical quantiles (Normal)", size(medium)) ///
            ytitle("Sample quantiles ({c 949}{sup:0})", size(medium)) ///
            ylabel(, labsize(medium) angle(horizontal)) ///
            legend(off) ///
            title(`"`title'"', size(large)) ///
            graphregion(color(white)) ///
            scheme(`scheme')
    }

    // =====================================================================
    // Export graph
    // =====================================================================

    if `"`save'"' != "" {
        if !regexm(`"`save'"', "\.gph$") {
            local save "`save'.gph"
        }
        quietly graph save `"`save'"', replace
        di as text "Graph saved to: `save'"
    }

    if `"`export'"' != "" {
        local ext ""
        if regexm(`"`export'"', "\.[a-zA-Z]+$") {
            local ext = regexs(0)
        }

        if inlist(`"`ext'"', ".png", ".PNG") {
            quietly graph export `"`export'"', as(png) width(`width') height(`height') replace
        }
        else if inlist(`"`ext'"', ".pdf", ".PDF") {
            quietly graph export `"`export'"', as(pdf) replace
        }
        else if inlist(`"`ext'"', ".eps", ".EPS") {
            quietly graph export `"`export'"', as(eps) replace
        }
        else {
            quietly graph export `"`export'"', as(png) width(`width') height(`height') replace
        }
        di as text "Graph exported to: `export'"
    }

    // =====================================================================
    // Return values
    // =====================================================================

    return local graph_type "eps0_diagnostic"
    return scalar has_treat = `has_treat'
    if `"`save'"' != "" {
        return local filename `"`save'"'
    }
    if `"`export'"' != "" {
        return local export_file `"`export'"'
    }

    // Summary display
    di as text ""
    di as text "{bf:{c 949}{sup:0} Diagnostic Graph}"
    di as text "{hline 50}"
    di as text "CDF panel:       " cond(`do_cdf', "Yes", "No")
    di as text "Q-Q panel:       " cond(`do_qq', "Yes", "No")
    di as text "Treatment groups: " cond(`has_treat', "Yes", "No")
    di as text "{hline 50}"

end
