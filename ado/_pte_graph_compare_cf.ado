*! _pte_graph_compare_cf.ado
*! ATT vs ATE^count Comparison Graph
*! Two-series connected plot with percentile CI error bars

version 14.0
program define _pte_graph_compare_cf, rclass
    version 14.0
    
    // =========================================================================
    // Step 1: Syntax parsing
    // =========================================================================
    
    syntax [, LEVEL(string) ///
              TItle(string) XTItle(string) YTItle(string) ///
              SUBtitle(string) NOTE(string) ///
              SCHeme(string) NOLEGend ///
              SAVE(string) EXPort(string) ///
              Width(integer 1200) Height(integer 800) ///
              NOREFLine ///
              *]
    
    // =========================================================================
    // Step 2: Validate e() returns exist
    // =========================================================================
    local _pte_graph_mats : e(matrices)
    
    // Check that a dedicated counterfactual result object has been run
    local _pte_has_att_exact : list posof "att" in _pte_graph_mats
    if `_pte_has_att_exact' == 0 {
        di as error "{bf:Error}: No ATT estimates found in e()."
        di as error ""
        di as text "Please run a dedicated counterfactual worker first."
        di as text ""
        di as text "Example:"
        di as text "    . _pte_bootstrap_cf, treatment(D) depvar(lny) free(lnl) ///"
        di as text "          state(lnk) proxy(lnm) id(firm) time(year) ///"
        di as text "          targetgroup(group) referencetime(2004) expansiontime(2006)"
        exit 198
    }
    
    local _pte_has_ate_count_exact : list posof "ate_count" in _pte_graph_mats
    if `_pte_has_ate_count_exact' == 0 {
        di as error "{bf:Error}: No ATE{sup:count} estimates found in e()."
        di as error ""
        di as text "Please run a dedicated counterfactual worker that stores {bf:e(ate_count)}."
        exit 198
    }
    
    // Check CI matrices (from bootstrap). Comparison confidence intervals are
    // a joint bundle: ATT and ATE^count must each publish a matched pair, and
    // the graph should fail closed if only part of that bundle survives.
    local has_att_lb = 0
    local has_att_ub = 0
    local has_att_ci_lower = 0
    local has_att_ci_upper = 0
    local has_ate_lb = 0
    local has_ate_ub = 0
    local has_ci = 0

    local _pte_has_att_lb_exact : list posof "att_lb" in _pte_graph_mats
    if `_pte_has_att_lb_exact' > 0 local has_att_lb = 1
    local _pte_has_att_ub_exact : list posof "att_ub" in _pte_graph_mats
    if `_pte_has_att_ub_exact' > 0 local has_att_ub = 1
    local _pte_has_att_ci_lower_exact : list posof "att_ci_lower" in _pte_graph_mats
    if `_pte_has_att_ci_lower_exact' > 0 local has_att_ci_lower = 1
    local _pte_has_att_ci_upper_exact : list posof "att_ci_upper" in _pte_graph_mats
    if `_pte_has_att_ci_upper_exact' > 0 local has_att_ci_upper = 1
    local _pte_has_ate_lb_exact : list posof "ate_count_lb" in _pte_graph_mats
    if `_pte_has_ate_lb_exact' > 0 local has_ate_lb = 1
    local _pte_has_ate_ub_exact : list posof "ate_count_ub" in _pte_graph_mats
    if `_pte_has_ate_ub_exact' > 0 local has_ate_ub = 1

    if (`has_att_lb' != `has_att_ub') {
        di as error "{bf:Error}: Stored comparison confidence intervals are incomplete."
        di as error "The ATT pair e(att_lb) and e(att_ub) must be published together."
        exit 198
    }
    if (`has_att_ci_lower' != `has_att_ci_upper') {
        di as error "{bf:Error}: Stored comparison confidence intervals are incomplete."
        di as error "The ATT bootstrap alias pair e(att_ci_lower) and e(att_ci_upper) must be published together."
        exit 198
    }
    if (`has_ate_lb' != `has_ate_ub') {
        di as error "{bf:Error}: Stored comparison confidence intervals are incomplete."
        di as error "The ATE{sup:count} pair e(ate_count_lb) and e(ate_count_ub) must be published together."
        exit 198
    }
    if (`has_att_lb' != `has_ate_lb') {
        di as error "{bf:Error}: Stored comparison confidence intervals are incomplete."
        di as error "ATT and ATE{sup:count} confidence-interval bundles must both be present or both be absent."
        exit 198
    }

    if `has_att_lb' {
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

    if !`has_ci' {
        di as text "{bf:Note}: Bootstrap CI not found. Plotting point estimates only."
    }
    else if "`stored_level'" == "" {
        di as error "{bf:Error}: Stored comparison confidence intervals are missing e(level) metadata."
        di as error "Re-run the bootstrap estimation so the graph can label the stored CI level correctly."
        exit 198
    }

    local requested_level_num = .
    local requested_level = trim("`level'")
    if "`requested_level'" != "" {
        local requested_level_num = real("`requested_level'")
        if missing(`requested_level_num') | floor(`requested_level_num') != `requested_level_num' {
            di as error "{bf:Error}: level() must be an integer between 10 and 99."
            exit 198
        }
        if `requested_level_num' < 10 | `requested_level_num' > 99 {
            di as error "{bf:Error}: level() must be between 10 and 99."
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
                di as error "{bf:Error}: Stored comparison confidence intervals were computed at level(`stored_level')."
                di as error "Omit level() to reuse the stored bootstrap level, or re-run the bootstrap estimation at level(`requested_level')."
                exit 198
            }
        }
        local level `requested_level'
    }
    
    // =========================================================================
    // Step 3: Extract matrices
    // =========================================================================
    
    tempname ATT ATT_LB ATT_UB ATE ATE_LB ATE_UB
    
    matrix `ATT' = e(att)
    matrix `ATE' = e(ate_count)

    local att_rows = rowsof(`ATT')
    local att_cols = colsof(`ATT')
    local ate_rows = rowsof(`ATE')
    local ate_cols = colsof(`ATE')

    if `att_rows' != 1 | `ate_rows' != 1 {
        di as error "{bf:Error}: compare_cf requires row-vector e(att) and e(ate_count) results."
        exit 198
    }

    if `att_cols' != `ate_cols' {
        di as error "{bf:Error}: e(att) and e(ate_count) must share the same event-time layout."
        di as error "Rebuild the counterfactual result so both matrices use the same dynamic periods and pooled final column."
        exit 198
    }
    
    local ncols = `att_cols'
    local nperiods = `ncols' - 1    // exclude pooled column

    if `nperiods' < 1 {
        di as error "{bf:Error}: Need at least 1 period for comparison graph."
        exit 198
    }

    quietly _pte_graph_attperiods_contract, ///
        dyncols(`nperiods') context("pte_graph, compare_cf")
    local periodlist `"`r(periodlist)'"'
    local minperiod = r(minperiod)
    local maxperiod = r(maxperiod)
    local use_stored_periods = r(used_stored)
    tempname PERIODS
    if `use_stored_periods' {
        matrix `PERIODS' = r(periods)
    }

    quietly _pte_dynamic_colstripe_contract `ATT' `PERIODS' `nperiods' ///
        "pte_graph, compare_cf" "e(att)"
    quietly _pte_dynamic_colstripe_contract `ATE' `PERIODS' `nperiods' ///
        "pte_graph, compare_cf" "e(ate_count)"
    
    if `has_ci' {
        matrix `ATT_LB' = e(att_lb)
        matrix `ATT_UB' = e(att_ub)
        matrix `ATE_LB' = e(ate_count_lb)
        matrix `ATE_UB' = e(ate_count_ub)

        quietly _pte_dynamic_colstripe_contract `ATT_LB' `PERIODS' `nperiods' ///
            "pte_graph, compare_cf" "ATT confidence intervals"
        quietly _pte_dynamic_colstripe_contract `ATT_UB' `PERIODS' `nperiods' ///
            "pte_graph, compare_cf" "ATT confidence intervals"
        quietly _pte_dynamic_colstripe_contract `ATE_LB' `PERIODS' `nperiods' ///
            "pte_graph, compare_cf" "ATE{sup:count} confidence intervals"
        quietly _pte_dynamic_colstripe_contract `ATE_UB' `PERIODS' `nperiods' ///
            "pte_graph, compare_cf" "ATE{sup:count} confidence intervals"

        foreach _pte_ci_mat in ATT_LB ATT_UB {
            if rowsof(``_pte_ci_mat'') != `att_rows' | colsof(``_pte_ci_mat'') != `att_cols' {
                di as error "{bf:Error}: ATT confidence-interval matrices must match e(att)."
                exit 198
            }
        }
        foreach _pte_ci_mat in ATE_LB ATE_UB {
            if rowsof(``_pte_ci_mat'') != `ate_rows' | colsof(``_pte_ci_mat'') != `ate_cols' {
                di as error "{bf:Error}: ATE{sup:count} confidence-interval matrices must match e(ate_count)."
                exit 198
            }
        }

        if `has_att_ci_lower' {
            quietly _pte_dynamic_colstripe_contract e(att_ci_lower) `PERIODS' `nperiods' ///
                "pte_graph, compare_cf" "ATT bootstrap confidence intervals"
            quietly _pte_dynamic_colstripe_contract e(att_ci_upper) `PERIODS' `nperiods' ///
                "pte_graph, compare_cf" "ATT bootstrap confidence intervals"
            mata: st_numscalar("__pte_compare_dual_ci_alias_ok",           ///
                rows(st_matrix("e(att_ci_lower)")) == `att_rows'           ///
                & rows(st_matrix("e(att_ci_upper)")) == `att_rows'         ///
                & cols(st_matrix("e(att_ci_lower)")) >= `nperiods'         ///
                & cols(st_matrix("e(att_ci_upper)")) >= `nperiods'         ///
                & allof(((st_matrix("e(att_lb)")[1,1..`nperiods'] :==      ///
                          st_matrix("e(att_ci_lower)")[1,1..`nperiods']) :| ///
                         (missing(st_matrix("e(att_lb)")[1,1..`nperiods']) :& ///
                          missing(st_matrix("e(att_ci_lower)")[1,1..`nperiods']))), 1) ///
                & allof(((st_matrix("e(att_ub)")[1,1..`nperiods'] :==      ///
                          st_matrix("e(att_ci_upper)")[1,1..`nperiods']) :| ///
                         (missing(st_matrix("e(att_ub)")[1,1..`nperiods']) :& ///
                          missing(st_matrix("e(att_ci_upper)")[1,1..`nperiods']))), 1))
            if scalar(__pte_compare_dual_ci_alias_ok) == 0 {
                di as error "{bf:Error}: Stored ATT comparison confidence intervals disagree across alias families."
                di as error "e(att_lb)/e(att_ub) and e(att_ci_lower)/e(att_ci_upper) must match on the graphed dynamic support."
                scalar drop __pte_compare_dual_ci_alias_ok
                exit 198
            }
            capture scalar drop __pte_compare_dual_ci_alias_ok
        }

        mata: st_numscalar("__pte_compare_ci_order_ok",                  ///
            allof((st_matrix("`ATT_LB'")[|1,1 \ 1,`nperiods'|] :<=       ///
                   st_matrix("`ATT_UB'")[|1,1 \ 1,`nperiods'|]) :|       ///
                  (missing(st_matrix("`ATT_LB'")[|1,1 \ 1,`nperiods'|]) :& ///
                   missing(st_matrix("`ATT_UB'")[|1,1 \ 1,`nperiods'|])), 1) ///
            & allof((st_matrix("`ATE_LB'")[|1,1 \ 1,`nperiods'|] :<=    ///
                     st_matrix("`ATE_UB'")[|1,1 \ 1,`nperiods'|]) :|    ///
                    (missing(st_matrix("`ATE_LB'")[|1,1 \ 1,`nperiods'|]) :& ///
                     missing(st_matrix("`ATE_UB'")[|1,1 \ 1,`nperiods'|])), 1))
        if scalar(__pte_compare_ci_order_ok) == 0 {
            di as error "{bf:Error}: Stored comparison confidence-interval lower bounds exceed upper bounds."
            di as error "ATT and ATE{sup:count} confidence-interval matrices must form ordered intervals on the graphed dynamic support."
            scalar drop __pte_compare_ci_order_ok
            exit 198
        }
        capture scalar drop __pte_compare_ci_order_ok
    }

    // Exact stored support means each supported dynamic period must carry a
    // realized ATT/ATE_count point, and when CI metadata are posted those
    // supported periods must also have complete bounds rather than silent gaps.
    forvalues _pte_j = 1/`nperiods' {
        if missing(`ATT'[1, `_pte_j']) | missing(`ATE'[1, `_pte_j']) {
            di as error "{bf:Error}: Stored comparison point estimates are incomplete on e(attperiods)."
            di as error "Every dynamic period listed in e(attperiods) must have nonmissing ATT and ATE{sup:count} values."
            exit 198
        }
        if `has_ci' {
            if missing(`ATT_LB'[1, `_pte_j']) | missing(`ATT_UB'[1, `_pte_j']) | ///
                missing(`ATE_LB'[1, `_pte_j']) | missing(`ATE_UB'[1, `_pte_j']) {
                di as error "{bf:Error}: Stored comparison confidence intervals are incomplete on e(attperiods)."
                di as error "Every dynamic period listed in e(attperiods) must have nonmissing ATT and ATE{sup:count} bounds."
                exit 198
            }
        }
    }
    
    // =========================================================================
    // Step 4: Build plotting dataset
    // =========================================================================
    
    preserve
    clear
    quietly set obs `nperiods'
    
    // Dynamic support follows stored e(attperiods) when available.
    quietly gen double ell = .
    forvalues i = 1/`nperiods' {
        local ell_val = `i' - 1
        if `use_stored_periods' {
            local ell_val = `PERIODS'[1, `i']
        }
        quietly replace ell = `ell_val' in `i'
    }
    
    // ATT series
    quietly gen double att = .
    quietly gen double att_lb = .
    quietly gen double att_ub = .
    
    // ATE^count series
    quietly gen double ate_count = .
    quietly gen double ate_count_lb = .
    quietly gen double ate_count_ub = .
    
    // Fill data row-by-row so sparse stored event-time support maps to the
    // same matrix columns validated against e(attperiods).
    forvalues i = 1/`nperiods' {
        quietly replace att = `ATT'[1, `i'] in `i'
        quietly replace ate_count = `ATE'[1, `i'] in `i'
        
        if `has_ci' {
            quietly replace att_lb = `ATT_LB'[1, `i'] in `i'
            quietly replace att_ub = `ATT_UB'[1, `i'] in `i'
            quietly replace ate_count_lb = `ATE_LB'[1, `i'] in `i'
            quietly replace ate_count_ub = `ATE_UB'[1, `i'] in `i'
        }
    }
    
    // Shifted x-coordinate for ATE^count to avoid overlap
    quietly gen double ell_shift = ell + 0.1
    
    // =========================================================================
    // Step 5: Set default labels
    // =========================================================================
    
    if `"`title'"' == "" {
        local title "Comparison of ATT and Counterfactual ATE"
    }
    if `"`xtitle'"' == "" {
        local xtitle "Periods since treatment ({&ell})"
    }
    if `"`ytitle'"' == "" {
        local ytitle "Treatment Effect on Productivity"
    }
    if "`scheme'" == "" {
        local scheme "s1color"
    }
    
    // =========================================================================
    // Step 6: Build note text
    // =========================================================================
    
    local compare_reps = .
    capture scalar _pte_compare_reps = e(bootstrap)
    if _rc == 0 & !missing(_pte_compare_reps) & _pte_compare_reps > 0 {
        local compare_reps = _pte_compare_reps
    }
    capture scalar drop _pte_compare_reps
    if missing(`compare_reps') {
        capture scalar _pte_compare_reps = e(breps)
        if _rc == 0 & !missing(_pte_compare_reps) & _pte_compare_reps > 0 {
            local compare_reps = _pte_compare_reps
        }
        capture scalar drop _pte_compare_reps
    }
    if missing(`compare_reps') {
        capture scalar _pte_compare_reps = e(nboot)
        if _rc == 0 & !missing(_pte_compare_reps) & _pte_compare_reps > 0 {
            local compare_reps = _pte_compare_reps
        }
        capture scalar drop _pte_compare_reps
    }

    if `"`note'"' == "" {
        if `has_ci' {
            if !missing(`compare_reps') {
                local note "`level'% percentile confidence intervals (B=`compare_reps')"
            }
            else {
                local note "`level'% percentile confidence intervals"
            }
        }
        else {
            local note "Point estimates only (no bootstrap CI available)"
        }
    }
    
    // =========================================================================
    // Step 7: Generate graph
    // =========================================================================
    
    if `has_ci' {
        // Full graph with CI error bars
        twoway ///
            (rcap att_lb att_ub ell, ///
                lcolor(navy) lwidth(medium)) ///
            (connected att ell, ///
                lcolor(navy) mcolor(navy) msymbol(O) ///
                lpattern(solid) lwidth(medium) msize(medlarge)) ///
            (rcap ate_count_lb ate_count_ub ell_shift, ///
                lcolor(cranberry) lwidth(medium)) ///
            (connected ate_count ell_shift, ///
                lcolor(cranberry) mcolor(cranberry) msymbol(Oh) ///
                lpattern(dash) lwidth(medium) msize(medlarge)) ///
            `=cond("`norefline'" == "", "(function y=0, range(`=`minperiod'-0.3' `=`maxperiod'+0.3') lcolor(black) lpattern(shortdash) lwidth(thin))", "")' ///
            , ///
            xtitle(`"`xtitle'"', size(medium)) ///
            ytitle(`"`ytitle'"', size(medium)) ///
            xlabel(`periodlist', labsize(medium)) ///
            ylabel(, labsize(medium) angle(horizontal)) ///
            `=cond("`nolegend'" == "", `"legend(order(2 "ATT (Treated)" 4 "ATE{sup:count} (Counterfactual)") cols(2) position(1) ring(0) size(medium))"', "legend(off)")' ///
            title(`"`title'"', size(large)) ///
            `=cond(`"`subtitle'"' != "", `"subtitle(`"`subtitle'"')"', "")' ///
            note(`"`note'"', size(small)) ///
            graphregion(color(white)) ///
            plotregion(margin(zero)) ///
            scheme(`scheme')
    }
    else {
        // Point estimates only (no CI)
        twoway ///
            (connected att ell, ///
                lcolor(navy) mcolor(navy) msymbol(O) ///
                lpattern(solid) lwidth(medium) msize(medlarge)) ///
            (connected ate_count ell_shift, ///
                lcolor(cranberry) mcolor(cranberry) msymbol(Oh) ///
                lpattern(dash) lwidth(medium) msize(medlarge)) ///
            `=cond("`norefline'" == "", "(function y=0, range(`=`minperiod'-0.3' `=`maxperiod'+0.3') lcolor(black) lpattern(shortdash) lwidth(thin))", "")' ///
            , ///
            xtitle(`"`xtitle'"', size(medium)) ///
            ytitle(`"`ytitle'"', size(medium)) ///
            xlabel(`periodlist', labsize(medium)) ///
            ylabel(, labsize(medium) angle(horizontal)) ///
            `=cond("`nolegend'" == "", `"legend(order(1 "ATT (Treated)" 2 "ATE{sup:count} (Counterfactual)") cols(2) position(1) ring(0) size(medium))"', "legend(off)")' ///
            title(`"`title'"', size(large)) ///
            `=cond(`"`subtitle'"' != "", `"subtitle(`"`subtitle'"')"', "")' ///
            note(`"`note'"', size(small)) ///
            graphregion(color(white)) ///
            plotregion(margin(zero)) ///
            scheme(`scheme')
    }
    
    // =========================================================================
    // Step 8: Export graph
    // =========================================================================
    
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
    
    // =========================================================================
    // Step 9: Return values and cleanup
    // =========================================================================
    
    restore
    
    return local graph_type "compare_cf"
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
    di as text ""
    di as text "{bf:ATT vs ATE{sup:count} Comparison Graph}"
    di as text "{hline 50}"
    di as text "Period support: `periodlist'"
    di as text "CI available:    " cond(`has_ci', "Yes (percentile)", "No")
    di as text "{hline 50}"
    
end
