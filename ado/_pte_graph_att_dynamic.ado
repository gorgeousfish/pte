*! _pte_graph_att_dynamic.ado
*! ATT Dynamic Effects Graph

version 14.0
program define _pte_graph_att_dynamic, rclass
    version 14.0

    local _pte_raw_opts `"`0'"'
    local _pte_has_alpha = regexm(lower(`"`_pte_raw_opts'"'), "(^|[ ,])alp(h(a)?)?[(]")
    
    syntax [, LEVEL(string) TItle(string) XTItle(string) YTItle(string) ///
        SUBtitle(string) NOTE(string) SCHeme(string) PReset(string)       ///
        ALpha(integer 100) NOLEGend                                       ///
        SAVE(string) EXPort(string) Width(integer 1200) Height(integer 800) ///
        NOREFLine *]

    if "`preset'" != "" | `alpha' != 100 {
        _pte_style_validate, preset(`preset') alpha(`alpha')
    }

    if "`preset'" != "" {
        quietly _pte_style_preset `preset'
        if "`scheme'" == "" {
            local scheme "`r(scheme)'"
        }
    }

    // -----------------------------------------------------------------------
    // Validate e(att) matrix exists
    // -----------------------------------------------------------------------
    local _pte_graph_mats : e(matrices)
    local _pte_has_att_exact : list posof "att" in _pte_graph_mats
    tempname ATT
    if `_pte_has_att_exact' == 0 {
        display as error "e(att) matrix not found; run {bf:pte} estimation first"
        exit 198
    }
    matrix `ATT' = e(att)

    // -----------------------------------------------------------------------
    // Check CI availability
    // -----------------------------------------------------------------------
    local has_ci = 0
    local has_att_lb = 0
    local has_att_ub = 0
    local has_att_ci_lower = 0
    local has_att_ci_upper = 0
    tempname ATT_LB ATT_UB

    local _pte_has_att_lb_exact : list posof "att_lb" in _pte_graph_mats
    if `_pte_has_att_lb_exact' > 0 local has_att_lb = 1
    local _pte_has_att_ub_exact : list posof "att_ub" in _pte_graph_mats
    if `_pte_has_att_ub_exact' > 0 local has_att_ub = 1
    local _pte_has_att_ci_lower_exact : list posof "att_ci_lower" in _pte_graph_mats
    if `_pte_has_att_ci_lower_exact' > 0 local has_att_ci_lower = 1
    local _pte_has_att_ci_upper_exact : list posof "att_ci_upper" in _pte_graph_mats
    if `_pte_has_att_ci_upper_exact' > 0 local has_att_ci_upper = 1

    if (`has_att_lb' != `has_att_ub') {
        display as error "stored ATT dynamic confidence intervals are incomplete"
        display as error "e(att_lb) and e(att_ub) must be published as a matched pair"
        exit 198
    }
    if (`has_att_ci_lower' != `has_att_ci_upper') {
        display as error "stored ATT dynamic confidence intervals are incomplete"
        display as error "e(att_ci_lower) and e(att_ci_upper) must be published as a matched pair"
        exit 198
    }

    if `has_att_lb' {
        matrix `ATT_LB' = e(att_lb)
        matrix `ATT_UB' = e(att_ub)
        local has_ci = 1
    }
    else if `has_att_ci_lower' {
        matrix `ATT_LB' = e(att_ci_lower)
        matrix `ATT_UB' = e(att_ci_upper)
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
        display as error "stored ATT dynamic confidence intervals are missing e(level) metadata"
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
                display as error "stored ATT dynamic confidence intervals were computed at level(`stored_level')"
                display as error "omit level() to reuse the stored bootstrap level, or re-run pte with bootstrap at level(`requested_level')"
                exit 198
            }
        }
        local level `requested_level'
    }

    // -----------------------------------------------------------------------
    // Dimensions: last column is pooled ATT, exclude it
    // -----------------------------------------------------------------------
    local ncols = colsof(`ATT')
    local nperiods = `ncols' - 1

    if `nperiods' < 1 {
        display as error "ATT matrix has no dynamic period columns"
        exit 198
    }

    quietly _pte_graph_attperiods_contract, ///
        dyncols(`nperiods') context("pte_graph, att_dynamic")
    local periodlist `"`r(periodlist)'"'
    local minperiod = r(minperiod)
    local maxperiod = r(maxperiod)
    local use_stored_periods = r(used_stored)
    tempname PERIODS
    if `use_stored_periods' {
        matrix `PERIODS' = r(periods)
    }

    quietly _pte_dynamic_colstripe_contract `ATT' `PERIODS' `nperiods' ///
        "pte_graph, att_dynamic" "e(att)"

    if `has_att_lb' {
        quietly _pte_dynamic_colstripe_contract `ATT_LB' `PERIODS' `nperiods' ///
            "pte_graph, att_dynamic" "ATT confidence intervals"
        quietly _pte_dynamic_colstripe_contract `ATT_UB' `PERIODS' `nperiods' ///
            "pte_graph, att_dynamic" "ATT confidence intervals"
        mata: st_numscalar("__pte_att_ci_shape_ok",                 ///
            rows(st_matrix("e(att_lb)")) == 1                       ///
            & rows(st_matrix("e(att_ub)")) == 1                     ///
            & cols(st_matrix("e(att_lb)")) >= `nperiods'            ///
            & cols(st_matrix("e(att_ub)")) >= `nperiods')
        if scalar(__pte_att_ci_shape_ok) == 0 {
            display as error "stored ATT dynamic confidence intervals must cover the graphed dynamic support"
            display as error "e(att_lb) and e(att_ub) must be row vectors with at least `nperiods' dynamic-period columns"
            scalar drop __pte_att_ci_shape_ok
            exit 198
        }
        capture scalar drop __pte_att_ci_shape_ok
    }

    forvalues j = 1/`nperiods' {
        if missing(`ATT'[1, `j']) {
            display as error "stored ATT point estimates are incomplete on e(attperiods)"
            display as error "every dynamic period listed in e(attperiods) must have a nonmissing ATT value"
            exit 198
        }
    }

    if `has_att_lb' {
        forvalues j = 1/`nperiods' {
            if missing(`ATT_LB'[1, `j']) | missing(`ATT_UB'[1, `j']) {
                display as error "stored ATT dynamic confidence intervals are incomplete on e(attperiods)"
                display as error "every dynamic period listed in e(attperiods) must have nonmissing ATT lower and upper bounds"
                exit 198
            }
        }
    }

    if `has_att_ci_lower' {
        quietly _pte_dynamic_colstripe_contract e(att_ci_lower) `PERIODS' `nperiods' ///
            "pte_graph, att_dynamic" "ATT bootstrap confidence intervals"
        quietly _pte_dynamic_colstripe_contract e(att_ci_upper) `PERIODS' `nperiods' ///
            "pte_graph, att_dynamic" "ATT bootstrap confidence intervals"
        mata: st_numscalar("__pte_att_boot_ci_shape_ok",            ///
            rows(st_matrix("e(att_ci_lower)")) == 1                 ///
            & rows(st_matrix("e(att_ci_upper)")) == 1               ///
            & cols(st_matrix("e(att_ci_lower)")) >= `nperiods'      ///
            & cols(st_matrix("e(att_ci_upper)")) >= `nperiods')
        if scalar(__pte_att_boot_ci_shape_ok) == 0 {
            display as error "stored ATT bootstrap confidence intervals must cover the graphed dynamic support"
            display as error "e(att_ci_lower) and e(att_ci_upper) must be row vectors with at least `nperiods' dynamic-period columns"
            scalar drop __pte_att_boot_ci_shape_ok
            exit 198
        }
        capture scalar drop __pte_att_boot_ci_shape_ok
    }

    if `has_att_ci_lower' {
        forvalues j = 1/`nperiods' {
            if missing(`ATT_LB'[1, `j']) | missing(`ATT_UB'[1, `j']) {
                display as error "stored ATT bootstrap confidence intervals are incomplete on e(attperiods)"
                display as error "every dynamic period listed in e(attperiods) must have nonmissing ATT lower and upper bounds"
                exit 198
            }
        }
    }

    // When both the bootstrap ATT CI pair and the legacy graph aliases are
    // posted, they describe the same dynamic-period CI object. The graph
    // consumer must fail-close on disagreement instead of silently preferring
    // one naming family over the other.
    if `has_att_lb' & `has_att_ci_lower' {
        mata: st_numscalar("__pte_dual_ci_alias_ok",                 ///
            rows(st_matrix("e(att_lb)")) == 1                        ///
            & rows(st_matrix("e(att_ub)")) == 1                      ///
            & rows(st_matrix("e(att_ci_lower)")) == 1                ///
            & rows(st_matrix("e(att_ci_upper)")) == 1                ///
            & cols(st_matrix("e(att_lb)")) >= `nperiods'             ///
            & cols(st_matrix("e(att_ub)")) >= `nperiods'             ///
            & cols(st_matrix("e(att_ci_lower)")) >= `nperiods'       ///
            & cols(st_matrix("e(att_ci_upper)")) >= `nperiods'       ///
            & allof(((st_matrix("e(att_lb)")[1,1..`nperiods'] :==    ///
                      st_matrix("e(att_ci_lower)")[1,1..`nperiods']) :| ///
                     (missing(st_matrix("e(att_lb)")[1,1..`nperiods']) :& ///
                      missing(st_matrix("e(att_ci_lower)")[1,1..`nperiods']))), 1) ///
            & allof(((st_matrix("e(att_ub)")[1,1..`nperiods'] :==    ///
                      st_matrix("e(att_ci_upper)")[1,1..`nperiods']) :| ///
                     (missing(st_matrix("e(att_ub)")[1,1..`nperiods']) :& ///
                      missing(st_matrix("e(att_ci_upper)")[1,1..`nperiods']))), 1))
        if scalar(__pte_dual_ci_alias_ok) == 0 {
            display as error "stored ATT dynamic confidence intervals disagree across alias families"
            display as error "e(att_lb)/e(att_ub) and e(att_ci_lower)/e(att_ci_upper) must match on the graphed dynamic support"
            scalar drop __pte_dual_ci_alias_ok
            exit 198
        }
        capture scalar drop __pte_dual_ci_alias_ok
    }

    // -----------------------------------------------------------------------
    // Build temporary dataset
    // -----------------------------------------------------------------------
    preserve
    clear
    quietly set obs `nperiods'

    // Period support follows stored e(attperiods) when available; otherwise
    // fall back to the legacy contiguous 0..L indexing used by older fixtures.
    quietly gen double ell = .
    forvalues j = 1/`nperiods' {
        local ell_val = `j' - 1
        if `use_stored_periods' {
            local ell_val = `PERIODS'[1, `j']
        }
        quietly replace ell = `ell_val' in `j'
    }

    // ATT values
    quietly gen double att = .
    forvalues j = 1/`nperiods' {
        quietly replace att = `ATT'[1, `j'] in `j'
    }

    // CI values if available
    if `has_ci' {
        quietly gen double att_lb = .
        quietly gen double att_ub = .
        forvalues j = 1/`nperiods' {
            quietly replace att_lb = `ATT_LB'[1, `j'] in `j'
            quietly replace att_ub = `ATT_UB'[1, `j'] in `j'
        }
    }

    // -----------------------------------------------------------------------
    // Default labels
    // -----------------------------------------------------------------------
    if `"`title'"' == "" {
        local title "ATT Dynamic Effects"
    }
    if `"`xtitle'"' == "" {
        local xtitle `"Periods since treatment ({&ell})"'
    }
    if `"`ytitle'"' == "" {
        local ytitle "ATT on Productivity"
    }
    if "`scheme'" == "" {
        local scheme "s1color"
    }

    local ci_fill_alpha = 20
    if `_pte_has_alpha' {
        local ci_fill_alpha = `alpha'
    }

    // -----------------------------------------------------------------------
    // Build graph command
    // -----------------------------------------------------------------------
    local graph_cmd ""

    if `has_ci' {
        // CI band + connected ATT
        local graph_cmd `"twoway"'
        local graph_cmd `"`graph_cmd' (rarea att_lb att_ub ell,"'
        local graph_cmd `"`graph_cmd'     fcolor(navy%`ci_fill_alpha') lcolor(navy%50) lwidth(thin))"'
        local graph_cmd `"`graph_cmd' (connected att ell,"'
        local graph_cmd `"`graph_cmd'     lcolor(navy) mcolor(navy) msymbol(O)"'
        local graph_cmd `"`graph_cmd'     lpattern(solid) lwidth(medium) msize(medlarge))"'
    }
    else {
        // Connected ATT only
        local graph_cmd `"twoway"'
        local graph_cmd `"`graph_cmd' (connected att ell,"'
        local graph_cmd `"`graph_cmd'     lcolor(navy) mcolor(navy) msymbol(O)"'
        local graph_cmd `"`graph_cmd'     lpattern(solid) lwidth(medium) msize(medlarge))"'
    }

    // Reference line at y=0
    if "`norefline'" == "" {
        local graph_cmd `"`graph_cmd', yline(0, lcolor(gs8) lpattern(dash) lwidth(thin))"'
    }
    else {
        local graph_cmd `"`graph_cmd',"'
    }

    // Titles and labels
    local graph_cmd `"`graph_cmd' title(`"`title'"')"'
    local graph_cmd `"`graph_cmd' xtitle(`"`xtitle'"')"'
    local graph_cmd `"`graph_cmd' ytitle(`"`ytitle'"')"'

    if `"`subtitle'"' != "" {
        local graph_cmd `"`graph_cmd' subtitle(`"`subtitle'"')"'
    }
    if `"`note'"' != "" {
        local graph_cmd `"`graph_cmd' note(`"`note'"')"'
    }

    local graph_cmd `"`graph_cmd' scheme(`scheme')"'

    // Legend
    if "`nolegend'" != "" {
        local graph_cmd `"`graph_cmd' legend(off)"'
    }
    else if `has_ci' {
        local graph_cmd `"`graph_cmd' legend(order(2 "ATT" 1 "`level'% CI") rows(1) position(6))"'
    }

    // Pass-through options
    if `"`options'"' != "" {
        local graph_cmd `"`graph_cmd' `options'"'
    }

    // Execute graph
    `graph_cmd'

    // -----------------------------------------------------------------------
    // Export graph to file
    // -----------------------------------------------------------------------
    if `"`export'"' != "" {
        // Detect file extension
        local ext = lower(substr(`"`export'"', -4, .))
        if `"`ext'"' == ".pdf" {
            quietly graph export `"`export'"', replace
        }
        else if `"`ext'"' == ".eps" {
            quietly graph export `"`export'"', replace
        }
        else {
            // Default to PNG with specified dimensions
            local ext2 = lower(substr(`"`export'"', -4, .))
            if `"`ext2'"' != ".png" {
                local export `"`export'.png"'
            }
            quietly graph export `"`export'"', replace width(`width') height(`height')
        }
        display as text "Graph exported to: `export'"
    }

    // -----------------------------------------------------------------------
    // Save .gph file
    // -----------------------------------------------------------------------
    if `"`save'"' != "" {
        local savext = lower(substr(`"`save'"', -4, .))
        if `"`savext'"' != ".gph" {
            local save `"`save'.gph"'
        }
        quietly graph save `"`save'"', replace
        display as text "Graph saved to: `save'"
    }

    // -----------------------------------------------------------------------
    // Return values
    // -----------------------------------------------------------------------
    return local type "att_dynamic"
    return local graph_type "att_dynamic"
    return scalar n_periods = `nperiods'
    return local periods `"`periodlist'"'
    return scalar has_ci = `has_ci'
    if `"`save'"' != "" {
        return local filename `"`save'"'
    }
    if `"`export'"' != "" {
        return local export_file `"`export'"'
    }

    // -----------------------------------------------------------------------
    // Summary display
    // -----------------------------------------------------------------------
    display ""
    display as text "{hline 60}"
    display as text "ATT Dynamic Effects Graph"
    display as text "{hline 60}"
    display as text "  Periods plotted:  " as result `nperiods'
    display as text "  Period support:   " as result "`periodlist'"
    display as text "  CI displayed:     " as result cond(`has_ci', "Yes (`level'%)", "No")
    display as text "  Reference line:   " as result cond("`norefline'" == "", "Yes (y=0)", "No")
    display as text "{hline 60}"

    restore
end
