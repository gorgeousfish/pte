*! _pte_graph_ate_dynamic.ado
*! ATE^count Dynamic Effects Graph

version 14.0
program define _pte_graph_ate_dynamic, rclass
    version 14.0
    
    syntax [, LEVEL(string) TItle(string) XTItle(string) YTItle(string) ///
        SUBtitle(string) NOTE(string) SCHeme(string) NOLEGend             ///
        SAVE(string) EXPort(string) Width(integer 1200) Height(integer 800) ///
        NOREFLine OVERlay_att *]

    // Validate e(ate_count) matrix exists
    local _pte_graph_mats : e(matrices)
    local _pte_has_ate_count_exact : list posof "ate_count" in _pte_graph_mats
    tempname ATE
    if `_pte_has_ate_count_exact' == 0 {
        display as error "e(ate_count) matrix not found; run {bf:pte} estimation first"
        exit 198
    }
    matrix `ATE' = e(ate_count)

    // Check CI availability
    local has_ci = 0
    local has_ate_lb = 0
    local has_ate_ub = 0
    tempname ATE_LB ATE_UB

    local _pte_has_ate_lb_exact : list posof "ate_count_lb" in _pte_graph_mats
    if `_pte_has_ate_lb_exact' > 0 local has_ate_lb = 1
    local _pte_has_ate_ub_exact : list posof "ate_count_ub" in _pte_graph_mats
    if `_pte_has_ate_ub_exact' > 0 local has_ate_ub = 1

    if (`has_ate_lb' != `has_ate_ub') {
        display as error "stored ATE{sup:count} dynamic confidence intervals are incomplete"
        display as error "e(ate_count_lb) and e(ate_count_ub) must be published as a matched pair"
        exit 198
    }

    if `has_ate_lb' {
        matrix `ATE_LB' = e(ate_count_lb)
        matrix `ATE_UB' = e(ate_count_ub)
        local has_ci = 1
    }

    local stored_level ""
    local stored_level_num = .
    if `has_ci' {
        capture local stored_level_num = e(level)
        if _rc | missing(`stored_level_num') {
            local stored_level ""
        }
        else {
            local stored_level = trim(string(`stored_level_num', "%21.0g"))
        }
    }

    if `has_ci' & "`stored_level'" == "" {
        display as error "stored ATE{sup:count} dynamic confidence intervals are missing e(level) metadata"
        display as error "re-run pte with bootstrap so the graph can label the stored CI level correctly"
        exit 198
    }

    local requested_level_num = .
    local requested_level = trim("`level'")
    if "`requested_level'" != "" {
        local requested_level_num = real("`requested_level'")
        if missing(`requested_level_num') | floor(`requested_level_num') != `requested_level_num' {
            display as error "level() must be an integer between 10 and 99"
            exit 198
        }
        if `requested_level_num' < 10 | `requested_level_num' > 99 {
            display as error "level() must be between 10 and 99"
            exit 198
        }
        local requested_level = trim(string(`requested_level_num', "%21.0g"))
    }

    if "`requested_level'" == "" {
        if "`stored_level'" != "" {
            local level `stored_level'
        }
        else {
            local level 95
        }
    }
    else {
        if "`stored_level'" != "" {
            if `requested_level_num' != `stored_level_num' {
                display as error "stored ATE{sup:count} dynamic confidence intervals were computed at level(`stored_level')"
                display as error "omit level() to reuse the stored bootstrap level, or re-run pte with bootstrap at level(`requested_level')"
                exit 198
            }
        }
        local level `requested_level'
    }

    // ATT lives on the same counterfactual bundle as ATE^count. Even when the
    // graph does not overlay the ATT line, malformed ATT CI payloads in the
    // shared e() state must fail closed rather than being silently ignored.
    local do_overlay = 0
    local has_att = 0
    local has_att_lb = 0
    local has_att_ub = 0
    local has_att_ci_lower = 0
    local has_att_ci_upper = 0
    tempname ATT
    local _pte_has_att_exact : list posof "att" in _pte_graph_mats
    if `_pte_has_att_exact' > 0 {
        matrix `ATT' = e(att)
        local has_att = 1
    }

    local _pte_has_att_lb_exact : list posof "att_lb" in _pte_graph_mats
    if `_pte_has_att_lb_exact' > 0 local has_att_lb = 1
    local _pte_has_att_ub_exact : list posof "att_ub" in _pte_graph_mats
    if `_pte_has_att_ub_exact' > 0 local has_att_ub = 1
    local _pte_has_att_ci_lower_exact : list posof "att_ci_lower" in _pte_graph_mats
    if `_pte_has_att_ci_lower_exact' > 0 local has_att_ci_lower = 1
    local _pte_has_att_ci_upper_exact : list posof "att_ci_upper" in _pte_graph_mats
    if `_pte_has_att_ci_upper_exact' > 0 local has_att_ci_upper = 1

    local has_any_att_ci = (`has_att_lb' | `has_att_ub' | `has_att_ci_lower' | `has_att_ci_upper')

    if (`has_att_lb' != `has_att_ub') {
        display as error "stored ATT dynamic confidence intervals are incomplete"
        display as error "e(att_lb) and e(att_ub) must be published as a matched pair on the shared ATT/ATE{sup:count} result bundle"
        exit 198
    }
    if (`has_att_ci_lower' != `has_att_ci_upper') {
        display as error "stored ATT dynamic confidence intervals are incomplete"
        display as error "e(att_ci_lower) and e(att_ci_upper) must be published as a matched pair on the shared ATT/ATE{sup:count} result bundle"
        exit 198
    }
    if `has_any_att_ci' & !`has_att' {
        display as error "stored ATT dynamic confidence intervals require the shared ATT path e(att)"
        display as error "repair the counterfactual result object so ATT intervals are not posted without ATT point estimates"
        exit 198
    }

    if "`overlay_att'" != "" {
        if `has_att' {
            local do_overlay = 1
        }
        else {
            display as text "Note: e(att) not found, overlay_att ignored"
        }
    }

    local _pte_has_attperiods_exact : list posof "attperiods" in _pte_graph_mats
    if `_pte_has_attperiods_exact' == 0 {
        display as error "pte_graph, ate_count_dynamic: e(attperiods) not found."
        display as error "pte_graph, ate_count_dynamic: dynamic graph consumers require the exact stored event-time support and must not infer 0..L-1 from matrix width."
        exit 198
    }

    tempname _pte_ate_support
    matrix `_pte_ate_support' = e(attperiods)
    local support_cols = colsof(`_pte_ate_support')
    local ncols = colsof(`ATE')
    local has_pooled = 0
    local nperiods = .
    if `ncols' == `support_cols' {
        local nperiods = `support_cols'
    }
    else if `ncols' == `support_cols' + 1 {
        local nperiods = `support_cols'
        local has_pooled = 1
    }
    else {
        display as error "stored ATE{sup:count} dynamic result dimensions do not match e(attperiods)"
        display as error "expected `support_cols' dynamic columns, with at most one optional pooled final column; found `ncols' columns"
        exit 198
    }
    if `nperiods' < 1 {
        display as error "ATE{sup:count} matrix has no dynamic period columns"
        exit 198
    }

    if `has_att' {
        local att_rows = rowsof(`ATT')
        local att_cols = colsof(`ATT')
        if `att_rows' != 1 | !inlist(`att_cols', `nperiods', `nperiods' + 1) {
            display as error "stored ATT path must share the same event-time layout as e(ate_count)"
            display as error "expected a 1 x `nperiods' or 1 x `=`nperiods' + 1'' ATT row vector aligned with the dynamic support, plus an optional pooled final column"
            exit 198
        }
    }

    if `has_any_att_ci' {
        if `has_att_lb' {
            mata: st_numscalar("__pte_ovl_lci_ok",                        ///
                rows(st_matrix("e(att_lb)")) == 1                         ///
                & rows(st_matrix("e(att_ub)")) == 1                       ///
                & cols(st_matrix("e(att_lb)")) >= `nperiods'              ///
                & cols(st_matrix("e(att_ub)")) >= `nperiods')
            if scalar(__pte_ovl_lci_ok) == 0 {
                display as error "stored ATT dynamic confidence intervals must cover the graphed dynamic support"
                display as error "e(att_lb) and e(att_ub) must be row vectors with at least `nperiods' dynamic-period columns"
                scalar drop __pte_ovl_lci_ok
                exit 198
            }
            capture scalar drop __pte_ovl_lci_ok
        }

        if `has_att_ci_lower' {
            mata: st_numscalar("__pte_ovl_bci_ok",                        ///
                rows(st_matrix("e(att_ci_lower)")) == 1                   ///
                & rows(st_matrix("e(att_ci_upper)")) == 1                 ///
                & cols(st_matrix("e(att_ci_lower)")) >= `nperiods'        ///
                & cols(st_matrix("e(att_ci_upper)")) >= `nperiods')
            if scalar(__pte_ovl_bci_ok) == 0 {
                display as error "stored ATT bootstrap confidence intervals must cover the graphed dynamic support"
                display as error "e(att_ci_lower) and e(att_ci_upper) must be row vectors with at least `nperiods' dynamic-period columns"
                scalar drop __pte_ovl_bci_ok
                exit 198
            }
            capture scalar drop __pte_ovl_bci_ok
        }

        if `has_att_lb' & `has_att_ci_lower' {
            mata: st_numscalar("__pte_ovl_dual_ok",                       ///
                allof(((st_matrix("e(att_lb)")[1,1..`nperiods'] :==       ///
                          st_matrix("e(att_ci_lower)")[1,1..`nperiods']) :| ///
                         (missing(st_matrix("e(att_lb)")[1,1..`nperiods']) :& ///
                          missing(st_matrix("e(att_ci_lower)")[1,1..`nperiods']))), 1) ///
                & allof(((st_matrix("e(att_ub)")[1,1..`nperiods'] :==     ///
                          st_matrix("e(att_ci_upper)")[1,1..`nperiods']) :| ///
                         (missing(st_matrix("e(att_ub)")[1,1..`nperiods']) :& ///
                          missing(st_matrix("e(att_ci_upper)")[1,1..`nperiods']))), 1))
            if scalar(__pte_ovl_dual_ok) == 0 {
                display as error "stored ATT dynamic confidence intervals disagree across alias families"
                display as error "e(att_lb)/e(att_ub) and e(att_ci_lower)/e(att_ci_upper) must match on the graphed dynamic support"
                scalar drop __pte_ovl_dual_ok
                exit 198
            }
            capture scalar drop __pte_ovl_dual_ok
        }
    }

    quietly _pte_graph_attperiods_contract, ///
        dyncols(`nperiods') context("pte_graph, ate_count_dynamic")
    local periodlist `"`r(periodlist)'"'
    local minperiod = r(minperiod)
    local maxperiod = r(maxperiod)
    local use_stored_periods = r(used_stored)
    tempname PERIODS
    if `use_stored_periods' {
        matrix `PERIODS' = r(periods)
    }

    quietly _pte_dynamic_colstripe_contract `ATE' `PERIODS' `nperiods' ///
        "pte_graph, ate_count_dynamic" "e(ate_count)"
    if `has_ci' {
        quietly _pte_dynamic_colstripe_contract `ATE_LB' `PERIODS' `nperiods' ///
            "pte_graph, ate_count_dynamic" "ATE{sup:count} confidence intervals"
        quietly _pte_dynamic_colstripe_contract `ATE_UB' `PERIODS' `nperiods' ///
            "pte_graph, ate_count_dynamic" "ATE{sup:count} confidence intervals"
    }
    if `has_att' {
        quietly _pte_dynamic_colstripe_contract `ATT' `PERIODS' `nperiods' ///
            "pte_graph, ate_count_dynamic" "e(att)"
    }
    if `has_att_lb' {
        quietly _pte_dynamic_colstripe_contract e(att_lb) `PERIODS' `nperiods' ///
            "pte_graph, ate_count_dynamic" "ATT confidence intervals"
        quietly _pte_dynamic_colstripe_contract e(att_ub) `PERIODS' `nperiods' ///
            "pte_graph, ate_count_dynamic" "ATT confidence intervals"
    }
    if `has_att_ci_lower' {
        quietly _pte_dynamic_colstripe_contract e(att_ci_lower) `PERIODS' `nperiods' ///
            "pte_graph, ate_count_dynamic" "ATT bootstrap confidence intervals"
        quietly _pte_dynamic_colstripe_contract e(att_ci_upper) `PERIODS' `nperiods' ///
            "pte_graph, ate_count_dynamic" "ATT bootstrap confidence intervals"
    }

    // Exact stored support means each listed dynamic period must carry a
    // realized ATE^count point estimate, and when CI metadata are posted the
    // same supported cells must also have complete bounds.
    forvalues _pte_j = 1/`nperiods' {
        if missing(`ATE'[1, `_pte_j']) {
            display as error "stored ATE{sup:count} dynamic point estimates are incomplete on e(attperiods)"
            display as error "every dynamic period listed in e(attperiods) must have a nonmissing e(ate_count) value"
            exit 198
        }
        if `has_ci' {
            if missing(`ATE_LB'[1, `_pte_j']) | missing(`ATE_UB'[1, `_pte_j']) {
                display as error "stored ATE{sup:count} dynamic confidence intervals are incomplete on e(attperiods)"
                display as error "every dynamic period listed in e(attperiods) must have nonmissing e(ate_count_lb) and e(ate_count_ub) bounds"
                exit 198
            }
        }
    }

    if `do_overlay' {
        forvalues _pte_j = 1/`nperiods' {
            if missing(`ATT'[1, `_pte_j']) {
                display as error "stored ATT overlay path is incomplete on e(attperiods)"
                display as error "ate_count_dynamic overlay_att requires every dynamic period listed in e(attperiods) to have a nonmissing e(att) value"
                exit 198
            }
        }
    }

    // Build temporary dataset
    preserve
    clear
    quietly set obs `nperiods'
    quietly gen double ell = .
    forvalues j = 1/`nperiods' {
        local ell_val = `j' - 1
        if `use_stored_periods' {
            local ell_val = `PERIODS'[1, `j']
        }
        quietly replace ell = `ell_val' in `j'
    }
    quietly gen double ate_count = .
    forvalues j = 1/`nperiods' {
        quietly replace ate_count = `ATE'[1, `j'] in `j'
    }
    if `has_ci' {
        quietly gen double ate_lb = .
        quietly gen double ate_ub = .
        forvalues j = 1/`nperiods' {
            quietly replace ate_lb = `ATE_LB'[1, `j'] in `j'
            quietly replace ate_ub = `ATE_UB'[1, `j'] in `j'
        }
    }
    if `do_overlay' {
        quietly gen double att = .
        forvalues j = 1/`nperiods' {
            quietly replace att = `ATT'[1, `j'] in `j'
        }
    }

    // Default labels
    if `"`title'"' == "" local title "ATE{sup:count} Dynamic Effects"
    if `"`xtitle'"' == "" local xtitle `"Periods since treatment ({&ell})"'
    if `"`ytitle'"' == "" local ytitle "ATE{sup:count} on Productivity"
    if "`scheme'" == "" local scheme "s1color"

    // Build graph command
    local plot_idx = 0
    local graph_cmd `"twoway"'
    if `has_ci' {
        local ++plot_idx
        local ate_ci_idx = `plot_idx'
        local graph_cmd `"`graph_cmd' (rarea ate_lb ate_ub ell, fcolor(cranberry%20) lcolor(cranberry%50) lwidth(thin))"'
    }
    local ++plot_idx
    local ate_line_idx = `plot_idx'
    local graph_cmd `"`graph_cmd' (connected ate_count ell, lcolor(cranberry) mcolor(cranberry) msymbol(Oh) lpattern(dash) lwidth(medium) msize(medlarge))"'
    if `do_overlay' {
        local ++plot_idx
        local att_line_idx = `plot_idx'
        local graph_cmd `"`graph_cmd' (connected att ell, lcolor(navy) mcolor(navy) msymbol(O) lpattern(solid) lwidth(medthin) msize(medium))"'
    }

    // Reference line and options separator
    if "`norefline'" == "" {
        local graph_cmd `"`graph_cmd', yline(0, lcolor(gs8) lpattern(dash) lwidth(thin))"'
    }
    else {
        local graph_cmd `"`graph_cmd',"'
    }
    local graph_cmd `"`graph_cmd' title(`"`title'"') xtitle(`"`xtitle'"') ytitle(`"`ytitle'"')"'
    if `"`subtitle'"' != "" local graph_cmd `"`graph_cmd' subtitle(`"`subtitle'"')"'
    if `"`note'"' != "" local graph_cmd `"`graph_cmd' note(`"`note'"')"'
    local graph_cmd `"`graph_cmd' scheme(`scheme')"'

    // Legend
    if "`nolegend'" != "" {
        local graph_cmd `"`graph_cmd' legend(off)"'
    }
    else {
        local legend_items ""
        if `has_ci' {
            local legend_items `"`ate_line_idx' "ATE{sup:count}" `ate_ci_idx' "`level'% CI""'
        }
        else {
            local legend_items `"`ate_line_idx' "ATE{sup:count}""'
        }
        if `do_overlay' {
            local legend_items `"`legend_items' `att_line_idx' "ATT""'
        }
        local graph_cmd `"`graph_cmd' legend(order(`legend_items') rows(1) position(6))"'
    }
    if `"`options'"' != "" local graph_cmd `"`graph_cmd' `options'"'

    // Execute graph
    `graph_cmd'

    // Export graph to file
    if `"`export'"' != "" {
        local ext = lower(substr(`"`export'"', -4, .))
        if `"`ext'"' == ".pdf" {
            quietly graph export `"`export'"', replace
        }
        else if `"`ext'"' == ".eps" {
            quietly graph export `"`export'"', replace
        }
        else {
            if lower(substr(`"`export'"', -4, .)) != ".png" {
                local export `"`export'.png"'
            }
            quietly graph export `"`export'"', replace width(`width') height(`height')
        }
        display as text "Graph exported to: `export'"
    }

    // Save .gph file
    if `"`save'"' != "" {
        if lower(substr(`"`save'"', -4, .)) != ".gph" {
            local save `"`save'.gph"'
        }
        quietly graph save `"`save'"', replace
        display as text "Graph saved to: `save'"
    }

    // Return values
    return local type "ate_count_dynamic"
    return local graph_type "ate_count_dynamic"
    return scalar n_periods = `nperiods'
    return local periods `"`periodlist'"'
    return scalar has_ci = `has_ci'
    if `"`save'"' != "" {
        return local filename `"`save'"'
    }
    if `"`export'"' != "" {
        return local export_file `"`export'"'
    }

    // Summary display
    display ""
    display as text "{hline 60}"
    display as text "ATE{sup:count} Dynamic Effects Graph"
    display as text "{hline 60}"
    display as text "  Periods plotted:  " as result `nperiods'
    display as text "  Period support:   " as result "`periodlist'"
    display as text "  CI displayed:     " as result cond(`has_ci', "Yes (`level'%)", "No")
    display as text "  ATT overlay:      " as result cond(`do_overlay', "Yes", "No")
    display as text "  Reference line:   " as result cond("`norefline'" == "", "Yes (y=0)", "No")
    display as text "{hline 60}"

    restore
end
