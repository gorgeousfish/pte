*! _pte_graph_att.ado
*! Dynamic ATT Summary Graph (Table 1 visualization)
*! Generates coefficient plot of ATT estimates with confidence intervals

version 14.0
program define _pte_graph_att, rclass
    version 14.0
    
    syntax [, LEVEL(string) TItle(string) XTItle(string) YTItle(string) ///
              COLor(string) SCHeme(string) ///
              SAVE(string) EXPORT(string) ///
              WIDTH(integer 800) HEIGHT(integer 600) NOAVerage]
    
    // =========================================================================
    // Task 2: e() return value validation
    // =========================================================================
    
    // Check required e() returns
    capture confirm matrix e(att)
    if _rc {
        di as error "pte: e(att) not found."
        di as error "  Please run {bf:pte} estimation before using graph options."
        exit 198
    }
    
    capture confirm matrix e(attperiods)
    if _rc {
        di as error "pte: e(attperiods) not found."
        di as error "  Please run {bf:pte} estimation before using graph options."
        exit 198
    }
    
    local nboot = .
    capture confirm scalar e(bootstrap)
    if _rc == 0 {
        capture local nboot = e(bootstrap)
    }
    if _rc != 0 | missing(`nboot') {
        capture confirm scalar e(breps)
        if _rc == 0 {
            capture local nboot = e(breps)
        }
    }
    if _rc != 0 | missing(`nboot') {
        capture confirm scalar e(nboot)
        if _rc == 0 {
            capture local nboot = e(nboot)
        }
    }
    if _rc != 0 | missing(`nboot') | `nboot' <= 0 {
        local nboot = 0
    }

    // Check optional ATT CI bundle. ATT graph consumers must treat the
    // released alias family e(att_lb)/e(att_ub) and the legacy bootstrap
    // family e(att_ci_lower)/e(att_ci_upper) as the same CI object.
    local has_att_lb = 0
    local has_att_ub = 0
    local has_ci_lower = 0
    local has_ci_upper = 0
    capture confirm matrix e(att_lb)
    if _rc == 0 {
        local has_att_lb = 1
    }
    capture confirm matrix e(att_ub)
    if _rc == 0 {
        local has_att_ub = 1
    }
    capture confirm matrix e(att_ci_lower)
    if _rc == 0 {
        local has_ci_lower = 1
    }
    capture confirm matrix e(att_ci_upper)
    if _rc == 0 {
        local has_ci_upper = 1
    }

    if `has_att_lb' != `has_att_ub' {
        di as error "pte: e(att_lb) and e(att_ub) must be published as a matched pair."
        di as error "Repair the stored ATT confidence-interval alias bundle before graphing dynamic ATT."
        exit 198
    }
    if `has_ci_lower' != `has_ci_upper' {
        di as error "pte: e(att_ci_lower) and e(att_ci_upper) must be published as a matched pair."
        di as error "Repair the stored ATT bootstrap bundle before graphing dynamic ATT confidence intervals."
        exit 198
    }

    local has_ci = 0
    if `has_att_lb' {
        local has_ci = 1
    }
    else if `has_ci_lower' {
        local has_ci = 1
    }

    if !`has_ci' {
        if `nboot' > 0 {
            di as error "pte: bootstrap metadata are present, but the ATT confidence-interval bundle is missing."
            di as error "Expected matched e(att_lb)/e(att_ub) or e(att_ci_lower)/e(att_ci_upper) matrices for the stored bootstrap ATT graph."
            exit 198
        }
        di as text "{bf:Warning}: confidence intervals not available (no bootstrap results)"
    }
    
    local has_se = 0
    capture confirm matrix e(att_se)
    if !_rc {
        local has_se = 1
    }
    
    local has_n = 0
    capture confirm matrix e(N_by_period)
    if !_rc {
        local has_n = 1
    }

    // Stored bootstrap CIs are valid only at the estimation-time level.
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
        di as error "pte: stored ATT confidence intervals are missing e(level) metadata."
        di as error "Re-run pte with bootstrap so the graph can label the stored CI level correctly."
        exit 198
    }
    
    // =========================================================================
    // Task 3: Option parsing and defaults
    // =========================================================================
    
    // Validate confidence level
    local requested_level_num = .
    local requested_level = trim("`level'")
    if "`requested_level'" != "" {
        local requested_level_num = real("`requested_level'")
        if missing(`requested_level_num') | floor(`requested_level_num') != `requested_level_num' {
            di as error "pte: level() must be an integer between 10 and 99"
            exit 198
        }
        if `requested_level_num' < 10 | `requested_level_num' > 99 {
            di as error "pte: level() must be between 10 and 99"
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
                di as error "pte: stored ATT confidence intervals were computed at level(`stored_level')."
                di as error "Omit level() to reuse the stored bootstrap level, or re-run pte with bootstrap at level(`requested_level')."
                exit 198
            }
        }
        local level `requested_level'
    }
    
    // Set defaults
    if `"`title'"' == "" local title "Dynamic Treatment Effects on Productivity"
    if `"`xtitle'"' == "" local xtitle "Periods Since Treatment"
    if `"`ytitle'"' == "" local ytitle "ATT"
    if "`color'" == "" local color "navy"
    if "`scheme'" == "" local scheme "s1color"
    
    // =========================================================================
    // Task 4: Matrix data extraction
    // =========================================================================
    
    tempname ATT PERIODS CI_LO CI_HI SE_MAT N_MAT
    
    matrix `ATT' = e(att)

    if rowsof(`ATT') != 1 {
        di as error "pte: e(att) must be a 1 x K row vector."
        exit 503
    }

    local n_att = colsof(`ATT')
    local L = `n_att' - 1
    if `L' < 1 {
        di as error "pte: e(att) must contain at least one event-time column plus one pooled ATT column."
        exit 503
    }

    quietly _pte_graph_attperiods_contract, ///
        dyncols(`L') context("pte_graph, att")
    matrix `PERIODS' = r(periods)
    quietly _pte_dynamic_colstripe_contract `ATT' `PERIODS' `L' ///
        "pte_graph, att" "e(att)"

    forvalues _pte_j = 1/`L' {
        if missing(`ATT'[1, `_pte_j']) {
            di as error "pte: stored ATT point estimates are incomplete on e(attperiods)."
            di as error "Every dynamic period listed in e(attperiods) must have a nonmissing ATT value."
            exit 198
        }
    }

    if "`noaverage'" == "" {
        if missing(`ATT'[1, `n_att']) {
            di as error "pte: default ATT graph requires a nonmissing pooled ATT_avg value."
            di as error "Use noaverage to graph only dynamic periods, or repair the stored pooled ATT bundle."
            exit 198
        }
    }
    
    if `has_ci' {
        if `has_att_lb' {
            matrix `CI_LO' = e(att_lb)
            matrix `CI_HI' = e(att_ub)
            if rowsof(`CI_LO') != 1 | colsof(`CI_LO') != `n_att' {
                di as error "pte: e(att_lb) must match e(att) as a 1 x `n_att' row vector."
                exit 503
            }
            if rowsof(`CI_HI') != 1 | colsof(`CI_HI') != `n_att' {
                di as error "pte: e(att_ub) must match e(att) as a 1 x `n_att' row vector."
                exit 503
            }
            quietly _pte_dynamic_colstripe_contract `CI_LO' `PERIODS' `L' ///
                "pte_graph, att" "e(att_lb)"
            quietly _pte_dynamic_colstripe_contract `CI_HI' `PERIODS' `L' ///
                "pte_graph, att" "e(att_ub)"
        }
        else {
            matrix `CI_LO' = e(att_ci_lower)
            matrix `CI_HI' = e(att_ci_upper)
            if rowsof(`CI_LO') != 1 | colsof(`CI_LO') != `n_att' {
                di as error "pte: e(att_ci_lower) must match e(att) as a 1 x `n_att' row vector."
                exit 503
            }
            if rowsof(`CI_HI') != 1 | colsof(`CI_HI') != `n_att' {
                di as error "pte: e(att_ci_upper) must match e(att) as a 1 x `n_att' row vector."
                exit 503
            }
            quietly _pte_dynamic_colstripe_contract `CI_LO' `PERIODS' `L' ///
                "pte_graph, att" "e(att_ci_lower)"
            quietly _pte_dynamic_colstripe_contract `CI_HI' `PERIODS' `L' ///
                "pte_graph, att" "e(att_ci_upper)"
        }
    }

    if `has_att_lb' & `has_ci_lower' {
        quietly _pte_dynamic_colstripe_contract e(att_ci_lower) `PERIODS' `L' ///
            "pte_graph, att" "e(att_ci_lower)"
        quietly _pte_dynamic_colstripe_contract e(att_ci_upper) `PERIODS' `L' ///
            "pte_graph, att" "e(att_ci_upper)"
    }

    if `has_att_lb' & `has_ci_lower' {
        mata: st_numscalar("__pte_att_dual_ci_ok",                      ///
            rows(st_matrix("e(att_lb)")) == 1                           ///
            & rows(st_matrix("e(att_ub)")) == 1                         ///
            & rows(st_matrix("e(att_ci_lower)")) == 1                   ///
            & rows(st_matrix("e(att_ci_upper)")) == 1                   ///
            & cols(st_matrix("e(att_lb)")) == `n_att'                   ///
            & cols(st_matrix("e(att_ub)")) == `n_att'                   ///
            & cols(st_matrix("e(att_ci_lower)")) == `n_att'             ///
            & cols(st_matrix("e(att_ci_upper)")) == `n_att'             ///
            & allof(((st_matrix("e(att_lb)") :== st_matrix("e(att_ci_lower)")) :| ///
                     (missing(st_matrix("e(att_lb)")) :&                 ///
                      missing(st_matrix("e(att_ci_lower)")))), 1)        ///
            & allof(((st_matrix("e(att_ub)") :== st_matrix("e(att_ci_upper)")) :| ///
                     (missing(st_matrix("e(att_ub)")) :&                 ///
                      missing(st_matrix("e(att_ci_upper)")))), 1))
        if scalar(__pte_att_dual_ci_ok) == 0 {
            di as error "pte: stored ATT confidence intervals disagree across alias families."
            di as error "e(att_lb)/e(att_ub) and e(att_ci_lower)/e(att_ci_upper) must match on the full ATT support."
            scalar drop __pte_att_dual_ci_ok
            exit 198
        }
        capture scalar drop __pte_att_dual_ci_ok
    }

    if `has_ci' {
        forvalues _pte_j = 1/`L' {
            if missing(`CI_LO'[1, `_pte_j']) | missing(`CI_HI'[1, `_pte_j']) {
                di as error "pte: stored ATT confidence intervals are incomplete on e(attperiods)."
                di as error "Every dynamic period listed in e(attperiods) must have nonmissing ATT lower and upper bounds."
                exit 198
            }
        }

        if "`noaverage'" == "" {
            if missing(`CI_LO'[1, `n_att']) | missing(`CI_HI'[1, `n_att']) {
                di as error "pte: default ATT graph requires nonmissing pooled ATT confidence intervals."
                di as error "Use noaverage to graph only dynamic periods, or repair the stored pooled ATT CI bundle."
                exit 198
            }
        }
    }
    
    if `has_se' {
        matrix `SE_MAT' = e(att_se)
        if rowsof(`SE_MAT') != 1 | colsof(`SE_MAT') != `n_att' {
            di as error "pte: e(att_se) must match e(att) as a 1 x `n_att' row vector."
            exit 503
        }
        quietly _pte_dynamic_colstripe_contract `SE_MAT' `PERIODS' `L' ///
            "pte_graph, att" "e(att_se)"
    }
    
    if `has_n' {
        matrix `N_MAT' = e(N_by_period)
        if rowsof(`N_MAT') != 1 | colsof(`N_MAT') != `L' {
            di as error "pte: e(N_by_period) must be a 1 x `L' row vector aligned with e(attperiods)."
            exit 503
        }
        quietly _pte_dynamic_colstripe_contract `N_MAT' `PERIODS' `L' ///
            "pte_graph, att" "e(N_by_period)"
    }
    
    // =========================================================================
    // Task 5-6: Create and fill temporary dataset
    // =========================================================================
    
    preserve
    clear
    
    // Determine if average point should be included
    local has_avg = 0
    if "`noaverage'" == "" & `n_att' > `L' {
        local has_avg = 1
    }
    
    // Set number of observations
    local n_points = `L'
    if `has_avg' {
        local n_points = `L' + 1
    }
    quietly set obs `n_points'
    
    // Generate variables
    quietly gen double _pte_nt = .
    quietly gen double _pte_att = .
    quietly gen double _pte_ci_lower = .
    quietly gen double _pte_ci_upper = .
    quietly gen double _pte_n = .
    quietly gen str20 _pte_label = ""
    
    // Fill period-level data
    local total_n = 0
    local periods_list `"`r(periodlist)'"'
    local max_period = .
    
    forvalues i = 1/`L' {
        local period = `PERIODS'[1, `i']
        quietly replace _pte_nt = `period' in `i'
        quietly replace _pte_att = `ATT'[1, `i'] in `i'
        quietly replace _pte_label = "l=`period'" in `i'
        
        if `has_ci' {
            quietly replace _pte_ci_lower = `CI_LO'[1, `i'] in `i'
            quietly replace _pte_ci_upper = `CI_HI'[1, `i'] in `i'
        }
        
        if `has_n' {
            local n_i = `N_MAT'[1, `i']
            quietly replace _pte_n = `n_i' in `i'
            local total_n = `total_n' + `n_i'
        }
        
        // Track max period
        if missing(`max_period') | `period' > `max_period' {
            local max_period = `period'
        }
    }
    
    // Fill average point if applicable
    if `has_avg' {
        local avg_pos = `max_period' + 1
        local avg_idx = `L' + 1
        quietly replace _pte_nt = `avg_pos' in `avg_idx'
        quietly replace _pte_att = `ATT'[1, `n_att'] in `avg_idx'
        quietly replace _pte_label = "Avg" in `avg_idx'
        
        if `has_ci' {
            quietly replace _pte_ci_lower = `CI_LO'[1, `n_att'] in `avg_idx'
            quietly replace _pte_ci_upper = `CI_HI'[1, `n_att'] in `avg_idx'
        }
    }
    
    // =========================================================================
    // Task 7: Build CI plot command
    // =========================================================================
    
    local graph_cmd "twoway"
    
    if `has_ci' {
        local graph_cmd "`graph_cmd' (rcap _pte_ci_lower _pte_ci_upper _pte_nt if !missing(_pte_ci_lower), lcolor(`color') lwidth(medium))"
    }
    
    // =========================================================================
    // Task 8: Build point estimate plot command
    // =========================================================================
    
    if `has_avg' {
        // Connected line for main periods, diamond scatter for average
        local graph_cmd "`graph_cmd' (connected _pte_att _pte_nt if _pte_nt <= `max_period', msymbol(circle) mcolor(`color') msize(medium) lcolor(`color') lwidth(medium))"
        local graph_cmd "`graph_cmd' (scatter _pte_att _pte_nt if _pte_nt > `max_period', msymbol(diamond) mcolor(`color') msize(medlarge))"
    }
    else {
        // Single connected line for all points
        local graph_cmd "`graph_cmd' (connected _pte_att _pte_nt, msymbol(circle) mcolor(`color') msize(medium) lcolor(`color') lwidth(medium))"
    }
    
    // =========================================================================
    // Task 9: Add reference line and chart options
    // =========================================================================
    
    // Zero reference line
    local graph_cmd "`graph_cmd', yline(0, lcolor(black) lpattern(solid) lwidth(thin))"
    
    // Axis titles
    local graph_cmd `"`graph_cmd' xtitle(`"`xtitle'"') ytitle(`"`ytitle'"')"'
    
    // Title
    local graph_cmd `"`graph_cmd' title(`"`title'"')"'
    
    // Legend off
    local graph_cmd "`graph_cmd' legend(off)"
    
    // Build xlabel list
    local xlabel_list ""
    forvalues i = 1/`L' {
        local period = `PERIODS'[1, `i']
        local xlabel_list "`xlabel_list' `period'"
    }
    if `has_avg' {
        local xlabel_list `"`xlabel_list' `avg_pos' "Avg""'
    }
    local graph_cmd `"`graph_cmd' xlabel(`xlabel_list')"'
    
    // =========================================================================
    // Task 10: Add notes and style
    // =========================================================================
    
    if `has_n' & `nboot' > 0 {
        local graph_cmd `"`graph_cmd' note("`level'% CI, `nboot' bootstrap reps, N=`total_n'")"'
    }
    else if `nboot' > 0 {
        local graph_cmd `"`graph_cmd' note("`level'% CI, `nboot' bootstrap reps")"'
    }
    else if `has_n' {
        local graph_cmd `"`graph_cmd' note("N=`total_n'")"'
    }
    
    // Apply scheme
    local graph_cmd "`graph_cmd' scheme(`scheme')"
    
    // =========================================================================
    // Task 11: Execute plot
    // =========================================================================
    
    // Note: scheme applied via scheme() option in graph command, not set scheme
    // (avoids modifying global state per DD-001.5)
    `graph_cmd'
    
    // =========================================================================
    // Task 12: Save functionality
    // =========================================================================
    
    if "`save'" != "" {
        if !regexm("`save'", "\.gph$") {
            local save "`save'.gph"
        }
        graph save "`save'", replace
        di as text "graph saved to `save'"
    }
    
    // =========================================================================
    // Task 13: Export functionality
    // =========================================================================
    
    if "`export'" != "" {
        graph export "`export'", width(`width') height(`height') replace
        di as text "graph exported to `export'"
    }
    
    // =========================================================================
    // Restore original data before setting return values
    // =========================================================================
    
    restore
    
    // =========================================================================
    // Task 14: Set r() return values
    // =========================================================================
    
    return local periods "`periods_list'"
    return scalar n_periods = `L'
    return scalar level = `level'
    
    if `has_n' {
        return scalar total_n = `total_n'
    }
    
    // Per-period return values
    forvalues i = 1/`L' {
        local period = `PERIODS'[1, `i']
        local period_tag = trim(string(`period', "%21.0g"))
        local period_tag : subinstr local period_tag "-" "m", all
        local period_tag : subinstr local period_tag "." "p", all
        return scalar att_`period_tag' = `ATT'[1, `i']
        
        if `has_ci' {
            return scalar ci_lower_`period_tag' = `CI_LO'[1, `i']
            return scalar ci_upper_`period_tag' = `CI_HI'[1, `i']
        }
        
        if `has_n' {
            return scalar n_`period_tag' = `N_MAT'[1, `i']
        }
    }
    
    // Average return values
    if `n_att' > `L' {
        return scalar att_avg = `ATT'[1, `n_att']
        if `has_ci' {
            return scalar ci_lower_avg = `CI_LO'[1, `n_att']
            return scalar ci_upper_avg = `CI_HI'[1, `n_att']
        }
    }
    
    // =========================================================================
    // Task 15: Display summary
    // =========================================================================
    
    di as text ""
    di as text "{bf:Dynamic ATT Summary Graph}"
    di as text "{hline 60}"
    di as text "Periods plotted: `periods_list'"
    if `has_avg' {
        di as text "Average included: yes"
    }
    else {
        di as text "Average included: no"
    }
    if `has_n' {
        di as text "Total observations: " %10.0fc `total_n'
    }
    if `nboot' > 0 {
        di as text "Bootstrap replications: `nboot'"
    }
    di as text "Confidence level: `level'%"
    di as text ""
    
    // ATT table
    if `has_ci' {
        di as text "{col 5}Period{col 18}ATT{col 33}[`level'% CI]"
        di as text "{hline 60}"
        forvalues i = 1/`L' {
            local period = `PERIODS'[1, `i']
            local att_val = `ATT'[1, `i']
            local ci_lo_val = `CI_LO'[1, `i']
            local ci_hi_val = `CI_HI'[1, `i']
            di as text "{col 5}l=`period'" ///
                       "{col 16}" %9.4f `att_val' ///
                       "{col 28}[" %8.4f `ci_lo_val' ", " %8.4f `ci_hi_val' "]"
        }
        if `has_avg' {
            local att_avg_val = `ATT'[1, `n_att']
            local ci_lo_avg = `CI_LO'[1, `n_att']
            local ci_hi_avg = `CI_HI'[1, `n_att']
            di as text "{col 5}Avg" ///
                       "{col 16}" %9.4f `att_avg_val' ///
                       "{col 28}[" %8.4f `ci_lo_avg' ", " %8.4f `ci_hi_avg' "]"
        }
    }
    else {
        di as text "{col 5}Period{col 18}ATT"
        di as text "{hline 60}"
        forvalues i = 1/`L' {
            local period = `PERIODS'[1, `i']
            local att_val = `ATT'[1, `i']
            di as text "{col 5}l=`period'" ///
                       "{col 16}" %9.4f `att_val'
        }
        if `has_avg' {
            local att_avg_val = `ATT'[1, `n_att']
            di as text "{col 5}Avg" ///
                       "{col 16}" %9.4f `att_avg_val'
        }
    }
    di as text "{hline 60}"
    
end
