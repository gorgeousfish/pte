*! _pte_graph_tt_dist.ado
*! TT Distribution Density Graph
*! Kernel density of TT by period (ell)

version 14.0
capture program drop _pte_graph_tt_dist
program define _pte_graph_tt_dist, rclass
    version 14.0

    syntax [, TItle(string) XTItle(string) YTItle(string) ///
              SCHeme(string) SAVE(string) EXPort(string) ///
              Width(integer 1200) Height(integer 800) ///
              NOLEGend PReset(string) *]

    local setup_panel : char _dta[_pte_setup_panelvar]
    local setup_time : char _dta[_pte_setup_timevar]
    local setup_treatment : char _dta[_pte_setup_treatment]
    local setup_treatsig : char _dta[_pte_setup_treatsig]
    local setup_xtdelta : char _dta[_pte_setup_xtdelta]
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

    local have_setup_panel = (`"`setup_panel'"' != "")
    local have_setup_time = (`"`setup_time'"' != "")
    local have_setup_treatment = (`"`setup_treatment'"' != "")
    local have_setup_treatsig = (`"`setup_treatsig'"' != "")
    local have_setup_xtdelta = (`"`setup_xtdelta'"' != "")
    local have_setup_fragment = ///
        (`have_setup_panel' | `have_setup_time' | `have_setup_treatment' | ///
         `have_setup_treatsig' | `have_setup_xtdelta')
    local have_setup_helper_bundle = 0
    foreach helper in _pte_D _pte_mid _pte_cohort _pte_treat_year ///
        _pte_first_treat_year {
        capture confirm variable `helper', exact
        if _rc == 0 {
            local have_setup_helper_bundle = 1
            continue, break
        }
    }
    local have_live_complete_current_law = ///
        (`"`live_id'"' != "") & (`"`live_time'"' != "") & ///
        (`"`live_treatment'"' != "") & (`"`live_treatsig'"' != "")
    local have_live_current_law_claim = ///
        (`"`live_id'"' != "") | (`"`live_time'"' != "") | ///
        (`"`live_treatsig'"' != "") | (`"`live_predict'"' != "")

    // TT density graphs consume the same TT/event-time bridge as the other
    // TT-family workers. When setup/live metadata claim a current treatment
    // law, stale helper variables must fail closed instead of being graphed
    // as if they were current-law objects. Keep the narrow legacy fallback:
    // a bare e(cmd)="pte" stub with no law fragments can still rely on the
    // canonical helper variables plus e(attperiods).
    if `have_setup_fragment' {
        if !`have_setup_panel' | !`have_setup_time' | !`have_setup_treatment' | !`have_setup_treatsig' | !`have_setup_xtdelta' {
            di as error "Stored setup panel/time/treatment contract is incomplete for pte_graph, tt_distribution."
            di as error "Re-run pte_setup on the current dataset before pte_graph, tt_distribution."
            exit 459
        }

        capture noisily _pte_assert_setup_current_law, ///
            panelvar(`setup_panel') timevar(`setup_time') ///
            treatment(`setup_treatment') treatsig(`"`setup_treatsig'"') ///
            context("pte_graph, tt_distribution")
        local _pte_tt_setup_rc = _rc
        if `_pte_tt_setup_rc' != 0 {
            exit `_pte_tt_setup_rc'
        }

        if "`e(cmd)'" == "pte" {
            if `"`live_treatsig'"' != "" & `"`live_treatsig'"' != `"`setup_treatsig'"' {
                di as error "Stored setup treatment law conflicts with live e(treatsig) for pte_graph, tt_distribution."
                di as error "Re-run pte on the current treatment path or rerun pte_setup before pte_graph, tt_distribution."
                exit 459
            }
            if `"`live_treatment'"' != "" & `"`live_treatment'"' != `"`setup_treatment'"' {
                di as error "Stored setup treatment `setup_treatment' conflicts with live e(treatment)=`live_treatment' for pte_graph, tt_distribution."
                di as error "Re-run pte with treatment(`setup_treatment') or rerun pte_setup using the same treatment() as the active pte result."
                exit 459
            }
            if `"`live_treatsig'"' == "" {
                di as error "Stored setup treatment law is present but live e(treatsig) is missing for pte_graph, tt_distribution."
                di as error "Re-run pte on the current treatment path before pte_graph, tt_distribution."
                exit 459
            }
            if `"`live_id'"' == "" {
                di as error "Stored setup panel contract is present but live e(idvar) or legacy e(id) is missing for pte_graph, tt_distribution."
                di as error "Re-run pte on the current setup-selected panel axis before pte_graph, tt_distribution."
                exit 459
            }
            if `"`live_time'"' == "" {
                di as error "Stored setup panel contract is present but live e(timevar) or legacy e(time) is missing for pte_graph, tt_distribution."
                di as error "Re-run pte on the current setup-selected time axis before pte_graph, tt_distribution."
                exit 459
            }
            if `"`live_id'"' != `"`setup_panel'"' {
                di as error "Stored setup panel variable `setup_panel' conflicts with live e(idvar)=`live_id' for pte_graph, tt_distribution."
                di as error "Re-run pte on the current setup-selected panel axis before pte_graph, tt_distribution."
                exit 459
            }
            if `"`live_time'"' != `"`setup_time'"' {
                di as error "Stored setup time variable `setup_time' conflicts with live e(timevar)=`live_time' for pte_graph, tt_distribution."
                di as error "Re-run pte on the current setup-selected time axis before pte_graph, tt_distribution."
                exit 459
            }
        }
    }
    else if "`e(cmd)'" == "pte" & `have_live_complete_current_law' {
        capture noisily _pte_assert_setup_current_law, ///
            panelvar(`live_id') timevar(`live_time') ///
            treatment(`live_treatment') treatsig(`"`live_treatsig'"') ///
            context("pte_graph, tt_distribution")
        local _pte_tt_live_rc = _rc
        if `_pte_tt_live_rc' != 0 {
            exit `_pte_tt_live_rc'
        }
    }
    else if !`have_setup_fragment' & "`e(cmd)'" == "pte" & ///
        `have_live_current_law_claim' & !`have_live_complete_current_law' {
        di as error "Live pte panel/treatment contract is incomplete for pte_graph, tt_distribution."
        di as error "Publish e(idvar)/e(timevar) or legacy e(id)/e(time) together with e(treatment) and e(treatsig), or clear the live pte state before pte_graph, tt_distribution."
        exit 459
    }
    else if !`have_setup_fragment' & `have_setup_helper_bundle' {
        capture noisily _pte_diag_panel_contract, ///
            context("pte_graph, tt_distribution") allowsetupmissingxtdelta
        local _pte_tt_helper_rc = _rc
        if `_pte_tt_helper_rc' != 0 {
            exit `_pte_tt_helper_rc'
        }
    }

    // =====================================================================
    // Validate: need _pte_tt and _pte_nt variables in data
    // =====================================================================

    capture confirm variable _pte_tt, exact
    if _rc {
        di as error "{bf:Error}: Variable _pte_tt not found."
        di as error "Run pte estimation with ATT first."
        exit 111
    }

    _pte_validate_internal_state _pte_tt numeric ///
        "pte_graph, tt_distribution requires _pte_tt to remain the numeric firm-level TT bridge."

    capture confirm variable _pte_nt, exact
    if _rc {
        di as error "{bf:Error}: Variable _pte_nt not found."
        exit 111
    }

    _pte_validate_internal_state _pte_treat binary ///
        "pte_graph, tt_distribution requires _pte_treat to identify treated observations."

    _pte_validate_internal_state _pte_nt integer ///
        "pte_graph, tt_distribution requires _pte_nt to be the integer event-time bridge."

    // Defaults
    if `"`title'"' == "" local title "Distribution of Treatment Effects (TT)"
    if `"`xtitle'"' == "" local xtitle "TT"
    if `"`ytitle'"' == "" local ytitle "Kernel density"
    if "`scheme'" == "" local scheme "s1color"

    // TT distribution graphs must consume the same certified event-time
    // support as the other TT graph consumers. Falling back to raw _pte_nt
    // levels would silently re-introduce stale TT support into a public
    // postestimation graph.
    local periods ""
    tempname tt_periods
    capture matrix `tt_periods' = e(attperiods)
    if _rc {
        di as error "pte_graph, tt_distribution: e(attperiods) not found."
        di as error "pte_graph, tt_distribution: dynamic graph consumers require the exact stored event-time support and must not infer support from raw _pte_nt levels."
        exit 198
    }
    local dyncols = colsof(`tt_periods')
    quietly _pte_graph_attperiods_contract, ///
        dyncols(`dyncols') context("pte_graph, tt_distribution")
    local supported `"`r(periodlist)'"'

    foreach p of numlist `supported' {
        quietly count if !missing(_pte_tt) & _pte_treat == 1 & _pte_nt == `p'
        if r(N) == 0 {
            di as error "{bf:Error}: supported TT period `p' has no nonmissing treated observations."
            di as error "pte_graph, tt_distribution requires every event time declared in e(attperiods) to have a live TT density sample."
            di as error "Re-run pte so e(attperiods) reflects realized TT support, or repair the damaged _pte_tt/_pte_nt bridge before graphing."
            exit 198
        }
        local periods "`periods' `p'"
    }
    local periods = trim("`periods'")

    local nperiods : word count `periods'
    if `nperiods' == 0 {
        di as error "{bf:Error}: No non-missing TT values found on the supported horizon."
        exit 2000
    }

    // Build twoway command with kdensity for each period
    // Line patterns cycle: solid, dash, shortdash, dash_dot, longdash
    local patterns "solid dash shortdash dash_dot longdash"
    // Colors cycle: navy cranberry forest_green dkorange purple
    local colors "navy cranberry forest_green dkorange purple"

    local graph_cmd "twoway"
    local legend_order ""
    local pnum = 0

    foreach p of local periods {
        local ++pnum
        // Cycle through patterns and colors
        local pidx = mod(`pnum' - 1, 5) + 1
        local lp : word `pidx' of `patterns'
        local lc : word `pidx' of `colors'
        local lw = cond(`pnum' == 1, "0.8", "0.6")

        local graph_cmd "`graph_cmd' (kdensity _pte_tt if _pte_treat==1 & _pte_nt==`p', lw(`lw') lp(`lp') lc(`lc'))"
        local legend_order `"`legend_order' `pnum' "{&ell}=`p'""'
    }

    // Legend
    local legend_opt ""
    if "`nolegend'" != "" {
        local legend_opt "legend(off)"
    }
    else {
        local legend_opt `"legend(order(`legend_order') cols(`nperiods') position(6) size(medium))"'
    }

    // Execute graph
    `graph_cmd', ///
        xtitle(`"`xtitle'"', size(medium)) ///
        ytitle(`"`ytitle'"', size(medium)) ///
        ylabel(, labsize(medium) angle(horizontal)) ///
        `legend_opt' ///
        title(`"`title'"', size(large)) ///
        graphregion(color(white)) ///
        plotregion(margin(zero)) ///
        scheme(`scheme')

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
            // Default to PNG
            quietly graph export `"`export'"', as(png) width(`width') height(`height') replace
        }
        di as text "Graph exported to: `export'"
    }

    // =====================================================================
    // Return values
    // =====================================================================

    return local type "tt_distribution"
    return local graph_type "tt_distribution"
    return local periods "`periods'"
    return scalar n_periods = `nperiods'
    if `"`save'"' != "" {
        return local filename `"`save'"'
    }
    if `"`export'"' != "" {
        return local filename `"`export'"'
        return local export_file `"`export'"'
    }

    // Summary display
    di as text ""
    di as text "{bf:TT Distribution Density Graph}"
    di as text "{hline 50}"
    di as text "Periods plotted: `nperiods'"
    di as text "Period values:   `periods'"
    di as text "{hline 50}"

end
