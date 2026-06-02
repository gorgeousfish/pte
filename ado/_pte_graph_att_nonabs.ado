*! _pte_graph_att_nonabs.ado
*! Non-absorbing Dual ATT Graph
*! Generates dual-panel, overlay, or difference graphs for ATT+ and ATT-

version 14.0
program define _pte_graph_att_nonabs, rclass
    version 14.0
    
    // =========================================================================
    // Syntax parsing
    // =========================================================================
    
    syntax , [OVerlay ATTDiff CI(string) LEvel(integer 95) ///
              COLORPlus(string) COLORMinus(string) COLORDiff(string) ///
              LPATTERNPlus(string) LPATTERNMinus(string) LWidth(real 0.8) ///
              MSYMBOLPlus(string) MSYMBOLMinus(string) MSize(real 2.5) ///
              TItle(string) XTItle(string) YTItle(string) SUBtitle(string) ///
              NOTE(string) LEGend(string) SCHeme(string) ///
              SAve(string) EXport(string) Width(integer 800) Height(integer 600) ///
              TABle ABSorbing *]
    
    // =========================================================================
    // Default values
    // =========================================================================
    
    if "`ci'" == "" local ci "area"
    if "`colorplus'" == "" local colorplus "navy"
    if "`colorminus'" == "" local colorminus "maroon"
    if "`colordiff'" == "" local colordiff "forest_green"
    if "`lpatternplus'" == "" local lpatternplus "solid"
    if "`lpatternminus'" == "" local lpatternminus "solid"
    if "`msymbolplus'" == "" local msymbolplus "O"
    if "`msymbolminus'" == "" local msymbolminus "D"
    if "`scheme'" == "" local scheme "s2color"
    if `"`xtitle'"' == "" local xtitle "Periods Since Treatment (n{sub:t})"
    
    // Determine graph type
    local graph_type "dual"
    if "`overlay'" != "" local graph_type "overlay"
    if "`attdiff'" != "" local graph_type "att_diff"
    
    // Default titles by graph type
    if `"`title'"' == "" {
        if "`graph_type'" == "dual" {
            local title "Non-absorbing Treatment Effects"
        }
        else if "`graph_type'" == "overlay" {
            local title "ATT{sup:+} and ATT{sup:-} (Overlay)"
        }
        else if "`graph_type'" == "att_diff" {
            local title "Difference in Treatment Effects"
        }
    }
    if "`graph_type'" == "att_diff" {
        if `"`ytitle'"' == "" local ytitle "ATT{sup:+} - ATT{sup:-}"
        if `"`subtitle'"' == "" local subtitle "(Difference in Entry and Exit Effects)"
        if `"`note'"' == "" local note "Zero line indicates symmetric effects"
    }
    else if `"`ytitle'"' == "" {
        local ytitle "ATT"
    }
    
    // =========================================================================
    // Input validation (Task 3)
    // =========================================================================
    
    local _pte_attdiff_validate ""
    if "`graph_type'" == "att_diff" {
        local _pte_attdiff_validate "attdiff"
    }
    _nonabs_graph_validate, ci("`ci'") level(`level') `absorbing' `_pte_attdiff_validate'
    local has_se = r(has_se)
    local has_boot_ci = r(has_boot_ci)
    local has_nt = r(has_nt)
    
    // =========================================================================
    // Data preparation (Task 4)
    // =========================================================================
    
    preserve
    clear
    
    // Get number of periods
    tempname m_att_p m_att_m
    matrix `m_att_p' = e(att_plus)
    matrix `m_att_m' = e(att_minus)
    local nperiods = rowsof(`m_att_p')
    
    qui set obs `nperiods'
    qui gen int nt = .
    if `has_nt' {
        forvalues j = 1/`nperiods' {
            quietly replace nt = `m_att_p'[`j', 4] in `j'
        }
    }
    else {
        qui replace nt = _n - 1
    }
    qui levelsof nt, local(nt_labels)
    
    // Extract ATT matrices
    qui svmat double `m_att_p', names(_att_plus_)
    qui svmat double `m_att_m', names(_att_minus_)
    qui rename _att_plus_1 att_plus
    qui rename _att_minus_1 att_minus
    
    // Extract SE matrices if available
    if `has_se' {
        tempname m_se_p m_se_m
        matrix `m_se_p' = e(att_plus_se)
        matrix `m_se_m' = e(att_minus_se)
        qui gen double se_plus = .
        qui gen double se_minus = .
        if rowsof(`m_se_p') == `nperiods' & colsof(`m_se_p') == 1 {
            qui svmat double `m_se_p', names(_se_plus_)
            qui replace se_plus = _se_plus_1
            capture drop _se_plus_1
        }
        else {
            forvalues j = 1/`nperiods' {
                quietly replace se_plus = `m_se_p'[1, `j'] in `j'
            }
        }
        if rowsof(`m_se_m') == `nperiods' & colsof(`m_se_m') == 1 {
            qui svmat double `m_se_m', names(_se_minus_)
            qui replace se_minus = _se_minus_1
            capture drop _se_minus_1
        }
        else {
            forvalues j = 1/`nperiods' {
                quietly replace se_minus = `m_se_m'[1, `j'] in `j'
            }
        }
    }
    else {
        qui gen double se_plus = .
        qui gen double se_minus = .
    }

    qui gen double ci_plus_lower = .
    qui gen double ci_plus_upper = .
    qui gen double ci_minus_lower = .
    qui gen double ci_minus_upper = .

    local ci_source "none"
    if `has_boot_ci' {
        tempname m_ci_p_lo m_ci_p_hi m_ci_m_lo m_ci_m_hi
        matrix `m_ci_p_lo' = e(att_plus_ci_lower)
        matrix `m_ci_p_hi' = e(att_plus_ci_upper)
        matrix `m_ci_m_lo' = e(att_minus_ci_lower)
        matrix `m_ci_m_hi' = e(att_minus_ci_upper)

        if rowsof(`m_ci_p_lo') == `nperiods' & colsof(`m_ci_p_lo') == 1 {
            qui svmat double `m_ci_p_lo', names(_ci_plus_lower_)
            qui replace ci_plus_lower = _ci_plus_lower_1
            capture drop _ci_plus_lower_1
        }
        else {
            forvalues j = 1/`nperiods' {
                quietly replace ci_plus_lower = `m_ci_p_lo'[1, `j'] in `j'
            }
        }
        if rowsof(`m_ci_p_hi') == `nperiods' & colsof(`m_ci_p_hi') == 1 {
            qui svmat double `m_ci_p_hi', names(_ci_plus_upper_)
            qui replace ci_plus_upper = _ci_plus_upper_1
            capture drop _ci_plus_upper_1
        }
        else {
            forvalues j = 1/`nperiods' {
                quietly replace ci_plus_upper = `m_ci_p_hi'[1, `j'] in `j'
            }
        }
        if rowsof(`m_ci_m_lo') == `nperiods' & colsof(`m_ci_m_lo') == 1 {
            qui svmat double `m_ci_m_lo', names(_ci_minus_lower_)
            qui replace ci_minus_lower = _ci_minus_lower_1
            capture drop _ci_minus_lower_1
        }
        else {
            forvalues j = 1/`nperiods' {
                quietly replace ci_minus_lower = `m_ci_m_lo'[1, `j'] in `j'
            }
        }
        if rowsof(`m_ci_m_hi') == `nperiods' & colsof(`m_ci_m_hi') == 1 {
            qui svmat double `m_ci_m_hi', names(_ci_minus_upper_)
            qui replace ci_minus_upper = _ci_minus_upper_1
            capture drop _ci_minus_upper_1
        }
        else {
            forvalues j = 1/`nperiods' {
                quietly replace ci_minus_upper = `m_ci_m_hi'[1, `j'] in `j'
            }
        }
        local ci_source "bootstrap"
    }
    else if `has_se' {
        local z = invnormal(1 - (100 - `level') / 200)
        qui replace ci_plus_lower = att_plus - `z' * se_plus
        qui replace ci_plus_upper = att_plus + `z' * se_plus
        qui replace ci_minus_lower = att_minus - `z' * se_minus
        qui replace ci_minus_upper = att_minus + `z' * se_minus
        local ci_source "normal"
    }
    
    // Compute difference
    qui gen double att_diff = att_plus - att_minus
    
    // Difference SE: direct bootstrap payload preferred; otherwise derive from
    // helper-produced ATT+ / ATT- bootstrap draw matrices before delta fallback.
    local diff_se_method "none"
    local diff_ci_source "none"
    capture confirm matrix e(att_diff_se_boot)
    if _rc == 0 {
        tempname m_se_diff_boot
        matrix `m_se_diff_boot' = e(att_diff_se_boot)
        qui gen double se_diff = .
        if rowsof(`m_se_diff_boot') == `nperiods' & colsof(`m_se_diff_boot') == 1 {
            qui svmat double `m_se_diff_boot', names(_se_diff_)
            qui replace se_diff = _se_diff_1
            capture drop _se_diff_1
        }
        else if rowsof(`m_se_diff_boot') == 1 & colsof(`m_se_diff_boot') == `nperiods' {
            forvalues j = 1/`nperiods' {
                quietly replace se_diff = `m_se_diff_boot'[1, `j'] in `j'
            }
        }
        else {
            di as error "Error: e(att_diff_se_boot) must match the ATT horizon as an N x 1 or 1 x N vector."
            restore
            exit 198
        }
        local diff_se_method "bootstrap"
    }
    else {
        local has_plus_boot = 0
        local has_minus_boot = 0
        capture confirm matrix e(att_plus_boot)
        if _rc == 0 local has_plus_boot = 1
        capture confirm matrix e(att_minus_boot)
        if _rc == 0 local has_minus_boot = 1

        if `has_plus_boot' | `has_minus_boot' {
            if !(`has_plus_boot' & `has_minus_boot') {
                di as error "Error: helper bootstrap draw matrices for ATT+ and ATT- must be posted as a matched pair."
                restore
                exit 198
            }

            tempname m_boot_plus m_boot_minus m_diff_se m_diff_ci_lo m_diff_ci_hi
            matrix `m_boot_plus' = e(att_plus_boot)
            matrix `m_boot_minus' = e(att_minus_boot)

            local plus_boot_rows = rowsof(`m_boot_plus')
            local minus_boot_rows = rowsof(`m_boot_minus')
            local plus_boot_cols = colsof(`m_boot_plus')
            local minus_boot_cols = colsof(`m_boot_minus')

            if `plus_boot_rows' != `minus_boot_rows' {
                di as error "Error: e(att_plus_boot) and e(att_minus_boot) must have the same number of bootstrap draws."
                restore
                exit 198
            }
            if `plus_boot_cols' != `nperiods' | `minus_boot_cols' != `nperiods' {
                di as error "Error: helper bootstrap draw matrices must match the ATT horizon width."
                restore
                exit 198
            }

            matrix `m_diff_se' = J(1, `nperiods', .)
            matrix `m_diff_ci_lo' = J(1, `nperiods', .)
            matrix `m_diff_ci_hi' = J(1, `nperiods', .)

            tempfile _pte_diff_boot_work
            qui save `"_pte_diff_boot_work"', replace
            clear
            qui set obs `plus_boot_rows'
            qui svmat double `m_boot_plus', names(_boot_plus_)
            qui svmat double `m_boot_minus', names(_boot_minus_)
            forvalues j = 1/`nperiods' {
                qui gen double _boot_diff_`j' = .
                qui replace _boot_diff_`j' = _boot_plus_`j' - _boot_minus_`j' ///
                    if !missing(_boot_plus_`j') & !missing(_boot_minus_`j')
                qui summarize _boot_diff_`j'
                if r(N) >= 2 {
                    matrix `m_diff_se'[1, `j'] = r(sd)
                    sort _boot_diff_`j'
                    qui count if !missing(_boot_diff_`j')
                    local nv = r(N)
                    local lo_idx = max(1, ceil(`nv' * (100 - `level') / 200))
                    local hi_idx = min(`nv', floor(`nv' * (1 - ((100 - `level') / 200))) + 1)
                    matrix `m_diff_ci_lo'[1, `j'] = _boot_diff_`j'[`lo_idx']
                    matrix `m_diff_ci_hi'[1, `j'] = _boot_diff_`j'[`hi_idx']
                }
                else if r(N) == 1 {
                    matrix `m_diff_se'[1, `j'] = 0
                    matrix `m_diff_ci_lo'[1, `j'] = _boot_diff_`j'[1]
                    matrix `m_diff_ci_hi'[1, `j'] = _boot_diff_`j'[1]
                }
            }
            qui use `"_pte_diff_boot_work"', clear

            qui gen double se_diff = .
            qui gen double ci_diff_lower = .
            qui gen double ci_diff_upper = .
            forvalues j = 1/`nperiods' {
                quietly replace se_diff = `m_diff_se'[1, `j'] in `j'
                quietly replace ci_diff_lower = `m_diff_ci_lo'[1, `j'] in `j'
                quietly replace ci_diff_upper = `m_diff_ci_hi'[1, `j'] in `j'
            }
            local diff_se_method "bootstrap"
            local diff_ci_source "bootstrap"
        }
        else if `has_se' {
            qui gen double se_diff = sqrt(se_plus^2 + se_minus^2)
            local diff_se_method "delta"
        }
        else {
            qui gen double se_diff = .
        }
    }
    
    // Difference CI
    if "`diff_ci_source'" == "bootstrap" {
        // Bootstrap percentile CI already derived from helper draw matrices.
    }
    else if "`diff_se_method'" != "none" {
        local z = invnormal(1 - (100 - `level') / 200)
        qui gen double ci_diff_lower = att_diff - `z' * se_diff
        qui gen double ci_diff_upper = att_diff + `z' * se_diff
        local diff_ci_source "normal"
    }
    else {
        qui gen double ci_diff_lower = .
        qui gen double ci_diff_upper = .
    }
    
    // =========================================================================
    // Y-axis alignment (Task 5)
    // =========================================================================
    
    // Compute global min/max across all CI bounds
    local all_min = .
    local all_max = .
    
    local has_ci_main = ("`ci_source'" != "none")
    local has_ci_diff = ("`diff_ci_source'" != "none")
    if "`ci'" != "none" & (`has_ci_main' | (`has_ci_diff' & "`graph_type'" == "att_diff")) {
        qui summ ci_plus_lower
        if `has_ci_main' & (r(min) < `all_min' | `all_min' == .) local all_min = r(min)
        qui summ ci_plus_upper
        if `has_ci_main' & (r(max) > `all_max' | `all_max' == .) local all_max = r(max)
        qui summ ci_minus_lower
        if `has_ci_main' & r(min) < `all_min' local all_min = r(min)
        qui summ ci_minus_upper
        if `has_ci_main' & r(max) > `all_max' local all_max = r(max)
        
        if `has_ci_diff' & "`graph_type'" == "att_diff" {
            qui summ ci_diff_lower
            if r(min) < `all_min' | `all_min' == . local all_min = r(min)
            qui summ ci_diff_upper
            if r(max) > `all_max' | `all_max' == . local all_max = r(max)
        }
    }
    else {
        qui summ att_plus
        local all_min = r(min)
        local all_max = r(max)
        qui summ att_minus
        if r(min) < `all_min' local all_min = r(min)
        if r(max) > `all_max' local all_max = r(max)
        
        if "`graph_type'" == "att_diff" {
            qui summ att_diff
            if r(min) < `all_min' local all_min = r(min)
            if r(max) > `all_max' local all_max = r(max)
        }
    }
    
    // Round to nice values
    local ymin = floor(`all_min' * 20) / 20
    local ymax = ceil(`all_max' * 20) / 20
    
    // Ensure zero is included
    if `ymin' > 0 local ymin = 0
    if `ymax' < 0 local ymax = 0
    
    // Determine step size
    local range = `ymax' - `ymin'
    if `range' <= 0.2 local step = 0.02
    else if `range' <= 0.5 local step = 0.05
    else if `range' <= 1 local step = 0.1
    else if `range' <= 2 local step = 0.2
    else local step = 0.5
    
    // =========================================================================
    // CI command builder (Task 6)
    // =========================================================================
    
    local ci_cmd_plus ""
    local ci_cmd_minus ""
    local ci_cmd_diff ""
    
    if "`ci'" == "area" & `has_ci_main' {
        local ci_cmd_plus `"(rarea ci_plus_lower ci_plus_upper nt, color(`colorplus'%30) lwidth(none))"'
        local ci_cmd_minus `"(rarea ci_minus_lower ci_minus_upper nt, color(`colorminus'%30) lwidth(none))"'
    }
    else if "`ci'" == "rcap" & `has_ci_main' {
        local ci_cmd_plus `"(rcap ci_plus_lower ci_plus_upper nt, lcolor(`colorplus'))"'
        local ci_cmd_minus `"(rcap ci_minus_lower ci_minus_upper nt, lcolor(`colorminus'))"'
    }
    else if "`ci'" == "rspike" & `has_ci_main' {
        local ci_cmd_plus `"(rspike ci_plus_lower ci_plus_upper nt, lcolor(`colorplus'))"'
        local ci_cmd_minus `"(rspike ci_minus_lower ci_minus_upper nt, lcolor(`colorminus'))"'
    }

    if "`ci'" == "area" & `has_ci_diff' {
        local ci_cmd_diff `"(rarea ci_diff_lower ci_diff_upper nt, color(`colordiff'%30) lwidth(none))"'
    }
    else if "`ci'" == "rcap" & `has_ci_diff' {
        local ci_cmd_diff `"(rcap ci_diff_lower ci_diff_upper nt, lcolor(`colordiff'))"'
    }
    else if "`ci'" == "rspike" & `has_ci_diff' {
        local ci_cmd_diff `"(rspike ci_diff_lower ci_diff_upper nt, lcolor(`colordiff'))"'
    }
    
    // =========================================================================
    // Graph generation (Tasks 7-9)
    // =========================================================================
    
    if "`graph_type'" == "dual" {
        // -----------------------------------------------------------------
        // Task 7: Dual panel graph
        // -----------------------------------------------------------------
        
        // Left panel: ATT+
        qui twoway `ci_cmd_plus' ///
            (connected att_plus nt, m(`msymbolplus') ///
             lc(`colorplus') lp(`lpatternplus') lw(`lwidth') ///
             mc(`colorplus') msize(`msize')), ///
            yline(0, lcolor(gray) lpattern(dash)) ///
            ylabel(`ymin'(`step')`ymax', grid format(%9.3f)) ///
            xlabel(`nt_labels', grid) ///
            xtitle("`xtitle'") ytitle("`ytitle'") ///
            title("{bf:ATT{sup:+}} (Entry Effects)", size(medium)) ///
            legend(off) scheme(`scheme') ///
            nodraw ///
            name(_g_plus, replace)
        
        // Right panel: ATT-
        qui twoway `ci_cmd_minus' ///
            (connected att_minus nt, m(`msymbolminus') ///
             lc(`colorminus') lp(`lpatternminus') lw(`lwidth') ///
             mc(`colorminus') msize(`msize')), ///
            yline(0, lcolor(gray) lpattern(dash)) ///
            ylabel(`ymin'(`step')`ymax', grid format(%9.3f)) ///
            xlabel(`nt_labels', grid) ///
            xtitle("`xtitle'") ytitle("`ytitle'") ///
            title("{bf:ATT{sup:-}} (Exit Effects)", size(medium)) ///
            legend(off) scheme(`scheme') ///
            nodraw ///
            name(_g_minus, replace)
        
        // Combine
        graph combine _g_plus _g_minus, cols(2) ///
            title(`"`title'"') xcommon ycommon ///
            imargin(small) scheme(`scheme')
        
        graph drop _g_plus _g_minus
    }
    else if "`graph_type'" == "overlay" {
        // -----------------------------------------------------------------
        // Task 8: Overlay graph
        // -----------------------------------------------------------------
        
        // Dynamic legend order depends on whether CI commands exist
        if "`ci_cmd_plus'" != "" {
            // CI areas are plots 1,2; connected lines are plots 3,4
            local legend_order `"order(3 "ATT{sup:+}" 4 "ATT{sup:-}")"'
        }
        else {
            // No CI; connected lines are plots 1,2
            local legend_order `"order(1 "ATT{sup:+}" 2 "ATT{sup:-}")"'
        }
        
        // Allow user override
        if `"`legend'"' != "" local legend_order `"`legend'"'
        
        twoway `ci_cmd_plus' `ci_cmd_minus' ///
            (connected att_plus nt, m(`msymbolplus') ///
             lc(`colorplus') lp(solid) lw(`lwidth') ///
             mc(`colorplus') msize(`msize')) ///
            (connected att_minus nt, m(`msymbolminus') ///
             lc(`colorminus') lp(dash) lw(`lwidth') ///
             mc(`colorminus') msize(`msize')), ///
            yline(0, lcolor(gray) lpattern(dash)) ///
            ylabel(, grid format(%9.3f)) ///
            xlabel(`nt_labels', grid) ///
            xtitle("`xtitle'") ytitle("`ytitle'") ///
            title(`"`title'"') ///
            legend(`legend_order' ///
                   ring(0) pos(2) col(1) region(fcolor(none) lpattern(blank))) ///
            scheme(`scheme')
    }
    else if "`graph_type'" == "att_diff" {
        // -----------------------------------------------------------------
        // Task 9: Difference graph
        // -----------------------------------------------------------------
        
        twoway `ci_cmd_diff' ///
            (connected att_diff nt, m(Oh) ///
             lc(`colordiff') lp(solid) lw(`lwidth') ///
             mc(`colordiff') msize(`msize')), ///
            yline(0, lcolor(gray) lpattern(dash) lwidth(0.5)) ///
            ylabel(, grid format(%9.3f)) ///
            xlabel(`nt_labels', grid) ///
            xtitle("`xtitle'") ytitle("`ytitle'") ///
            title(`"`title'"') ///
            subtitle(`"`subtitle'"') ///
            note(`"`note'"') ///
            legend(off) scheme(`scheme')
    }
    
    // =========================================================================
    // Table display (Task 11)
    // =========================================================================
    
    if "`table'" != "" {
        di as text ""
        di as text _dup(84) "="
        di as text "Dual ATT Summary (`level'% CI)"
        di as text _dup(84) "="
        di as text _col(4) "nt" _col(10) "ATT+" _col(20) "SE+" ///
            _col(30) "[CI+]" _col(46) "ATT-" _col(56) "SE-" _col(66) "[CI-]"
        di as text _dup(84) "-"
        
        forvalues i = 1/`nperiods' {
            local nt_val = nt[`i']
            local att_p = att_plus[`i']
            local se_p = se_plus[`i']
            local ci_p_l = ci_plus_lower[`i']
            local ci_p_u = ci_plus_upper[`i']
            local att_m = att_minus[`i']
            local se_m = se_minus[`i']
            local ci_m_l = ci_minus_lower[`i']
            local ci_m_u = ci_minus_upper[`i']
            
            if `has_ci_main' {
                di as result _col(4) %2.0f `nt_val' ///
                    _col(9) %8.4f `att_p' _col(19) %7.4f `se_p' ///
                    _col(28) "[" %6.3f `ci_p_l' "," %6.3f `ci_p_u' "]" ///
                    _col(45) %8.4f `att_m' _col(55) %7.4f `se_m' ///
                    _col(64) "[" %6.3f `ci_m_l' "," %6.3f `ci_m_u' "]"
            }
            else {
                di as result _col(4) %2.0f `nt_val' ///
                    _col(9) %8.4f `att_p' _col(19) "   ." ///
                    _col(28) "[  .  ,  .  ]" ///
                    _col(45) %8.4f `att_m' _col(55) "   ." ///
                    _col(64) "[  .  ,  .  ]"
            }
        }
        
        if "`graph_type'" == "att_diff" {
            di as text _dup(84) "-"
            di as text _col(4) "nt" _col(10) "Diff" _col(20) "SE_d" ///
                _col(30) "[CI_diff]"
            di as text _dup(84) "-"
            
            forvalues i = 1/`nperiods' {
                local nt_val = nt[`i']
                local d_val = att_diff[`i']
                local se_d = se_diff[`i']
                local ci_d_l = ci_diff_lower[`i']
                local ci_d_u = ci_diff_upper[`i']
                
                if "`diff_se_method'" != "none" {
                    di as result _col(4) %2.0f `nt_val' ///
                        _col(9) %8.4f `d_val' _col(19) %7.4f `se_d' ///
                        _col(28) "[" %6.3f `ci_d_l' "," %6.3f `ci_d_u' "]"
                }
                else {
                    di as result _col(4) %2.0f `nt_val' ///
                        _col(9) %8.4f `d_val' _col(19) "   ." ///
                        _col(28) "[  .  ,  .  ]"
                }
            }
            di as text "SE method: `diff_se_method'"
        }
        
        di as text _dup(84) "="
    }
    
    // =========================================================================
    // Save and export (Task 12)
    // =========================================================================
    
    if "`save'" != "" {
        if !regexm(lower("`save'"), "\.gph$") {
            local save "`save'.gph"
        }
        qui graph save "`save'", replace
        di as text "Graph saved to `save'"
    }
    
    local export_file ""
    if "`export'" != "" {
        local export_token = strtrim(`"`export'"')
        local export_token_lower = lower(`"`export_token'"')
        local export_is_format = inlist("`export_token_lower'", "png", "eps", "pdf")

        if `export_is_format' {
            local export_stem "pte_att_nonabs"
            if "`save'" != "" {
                local export_stem "`save'"
                if regexm(lower("`export_stem'"), "\.gph$") {
                    local export_stem = substr(`"`export_stem'"', 1, length(`"`export_stem'"') - 4)
                }
            }
            local export_file `"`export_stem'.`export_token_lower'"'
        }
        else {
            if !regexm("`export_token_lower'", "\.(png|eps|pdf)$") {
                di as error "Error: export() must be a filename ending in .png, .eps, or .pdf"
                di as error "Legacy format-only tokens png, eps, and pdf are also accepted"
                restore
                exit 198
            }
            local export_file `"`export_token'"'
        }

        if regexm(lower(`"`export_file'"'), "\.png$") {
            qui graph export `"`export_file'"', width(`width') height(`height') replace
        }
        else if regexm(lower(`"`export_file'"'), "\.eps$") {
            qui graph export `"`export_file'"', replace
        }
        else if regexm(lower(`"`export_file'"'), "\.pdf$") {
            qui graph export `"`export_file'"', replace
        }

        di as text "Graph exported to `export_file'"
    }
    
    // =========================================================================
    // Return values (Task 13)
    // =========================================================================
    
    return local graph_type "`graph_type'"
    return scalar n_periods = `nperiods'
    return scalar ci_level = `level'
    return local ci_source "`ci_source'"
    if "`save'" != "" {
        return local filename "`save'"
    }
    if `"`export_file'"' != "" {
        return local export_file `"`export_file'"'
    }
    
    // Return data matrices
    tempname r_att_plus r_att_minus
    mkmat att_plus, matrix(`r_att_plus')
    mkmat att_minus, matrix(`r_att_minus')
    return matrix att_plus = `r_att_plus'
    return matrix att_minus = `r_att_minus'
    tempname r_nt
    mkmat nt, matrix(`r_nt')
    return matrix nt = `r_nt'
    if `has_ci_main' {
        tempname r_ci_plus_lo r_ci_plus_hi r_ci_minus_lo r_ci_minus_hi
        mkmat ci_plus_lower, matrix(`r_ci_plus_lo')
        mkmat ci_plus_upper, matrix(`r_ci_plus_hi')
        mkmat ci_minus_lower, matrix(`r_ci_minus_lo')
        mkmat ci_minus_upper, matrix(`r_ci_minus_hi')
        return matrix att_plus_ci_lower = `r_ci_plus_lo'
        return matrix att_plus_ci_upper = `r_ci_plus_hi'
        return matrix att_minus_ci_lower = `r_ci_minus_lo'
        return matrix att_minus_ci_upper = `r_ci_minus_hi'
    }
    
    // Conditional returns for att_diff mode
    if "`graph_type'" == "att_diff" {
        tempname r_att_diff
        mkmat att_diff, matrix(`r_att_diff')
        return matrix att_diff = `r_att_diff'
        if "`diff_se_method'" != "none" {
            tempname r_att_diff_se
            mkmat se_diff, matrix(`r_att_diff_se')
            return matrix att_diff_se = `r_att_diff_se'
            tempname r_att_diff_ci_lo r_att_diff_ci_hi
            mkmat ci_diff_lower, matrix(`r_att_diff_ci_lo')
            mkmat ci_diff_upper, matrix(`r_att_diff_ci_hi')
            return matrix att_diff_ci_lower = `r_att_diff_ci_lo'
            return matrix att_diff_ci_upper = `r_att_diff_ci_hi'
        }
        return local diff_se_method "`diff_se_method'"
        return local diff_ci_source "`diff_ci_source'"
    }
    
    restore
    
end
