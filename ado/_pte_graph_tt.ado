*! _pte_graph_tt.ado
*! TT kernel density plot subroutine
*! Generates kernel density plots of Treatment Effects on the Treated (TT)
*! by period relative to treatment

version 14.0
capture program drop _pte_graph_tt
program define _pte_graph_tt, rclass
    version 14.0
    
    syntax , [NT(numlist) TItle(string) XTItle(string) YTItle(string) ///
              SCHeme(string) COLor(string) ///
              SAVE(string) EXPORT(string) ///
              WIDTH(integer 800) HEIGHT(integer 600) ///
              NOXLine]
    
    // =========================================================================
    // Task 2: Precondition validation
    // =========================================================================
    
    // Check that the canonical TT track exists exactly; shadow-prefixed
    // variables must not satisfy the public TT graph contract.
    capture confirm variable _pte_tt, exact
    if _rc {
        di as error "pte: variable _pte_tt not found."
        di as error "  Please run {bf:pte} estimation before using graph options."
        exit 111
    }

    _pte_validate_internal_state _pte_tt numeric ///
        "pte_graph, tt requires _pte_tt to remain the numeric firm-level TT bridge."
    
    // Check that the canonical event-time track exists exactly.
    capture confirm variable _pte_nt, exact
    if _rc {
        di as error "pte: variable _pte_nt not found."
        di as error "  Please run {bf:pte} estimation before using graph options."
        exit 111
    }

    _pte_validate_internal_state _pte_treat binary ///
        "pte_graph, tt requires _pte_treat to identify treated observations."

    _pte_validate_internal_state _pte_nt integer ///
        "pte_graph, tt requires _pte_nt to be the integer event-time bridge."
    
    // Check that _pte_tt has non-missing values
    quietly count if !missing(_pte_tt) & _pte_treat == 1
    if r(N) == 0 {
        di as error "pte: no valid (non-missing) TT values found in _pte_tt."
        di as error "  Please run {bf:pte} estimation to generate TT estimates."
        exit 2000
    }

    // TT postestimation must follow the same stored event-time support used by
    // predict, tt and the other dynamic graph consumers. The graph cannot
    // infer support from whichever _pte_tt rows happen to survive in data.
    tempname _pte_tt_periods
    capture matrix `_pte_tt_periods' = e(attperiods)
    if _rc {
        di as error "pte_graph, tt: e(attperiods) not found."
        di as error "  Re-run {bf:pte} so the TT support matrix is posted before graphing."
        exit 198
    }
    local _pte_tt_dyncols = colsof(`_pte_tt_periods')
    _pte_graph_attperiods_contract, dyncols(`_pte_tt_dyncols') context("pte_graph, tt")
    local _pte_tt_supported `"`r(periodlist)'"'
    
    // =========================================================================
    // Task 3: Option parsing and defaults
    // =========================================================================
    
    // Default periods: exact stored TT support
    if "`nt'" == "" {
        local nt `"`_pte_tt_supported'"'
    }
    else {
        foreach period of numlist `nt' {
            local _pte_tt_period = trim(string(`period', "%21.0g"))
            if !`: list _pte_tt_period in _pte_tt_supported' {
                di as error "pte_graph, tt: nt(`period') is outside the stored TT support."
                di as error "  Stored support: `_pte_tt_supported'"
                exit 198
            }
        }
    }
    
    // Default scheme: s1color (applied via twoway scheme(), not set scheme)
    if "`scheme'" == "" local scheme "s1color"
    
    // Default axis titles
    if `"`xtitle'"' == "" local xtitle "TT"
    if `"`ytitle'"' == "" local ytitle "Density"
    
    // === Task 5: Period data check and statistics ===
    local plot_count = 0
    local periods_plotted ""
    local total_nobs = 0
    
    foreach period of numlist `nt' {
        quietly count if !missing(_pte_tt) & _pte_treat == 1 & _pte_nt == `period'
        local nobs_`period' = r(N)
        
        if `nobs_`period'' == 0 {
            di as error "{bf:Error}: supported TT period `period' has no nonmissing treated observations."
            di as error "pte_graph, tt requires every event time declared in e(attperiods) to remain realized in the stored _pte_tt bridge."
            di as error "Re-run pte so e(attperiods) reflects realized TT support, or repair the damaged _pte_tt/_pte_nt bridge before graphing."
            exit 198
        }
        
        quietly summarize _pte_tt if _pte_treat == 1 & _pte_nt == `period', detail
        local mean_`period' = r(mean)
        local sd_`period' = r(sd)
        local total_nobs = `total_nobs' + `nobs_`period''
        
        local plot_count = `plot_count' + 1
        local periods_plotted "`periods_plotted' `period'"
    }
    local periods_plotted = trim("`periods_plotted'")
    
    if `plot_count' == 0 {
        di as error "no valid observations for any specified period"
        exit 2000
    }
    
    // === Task 6: Build twoway kdensity command ===
    local graph_cmd "twoway"
    local legend_order ""
    local plot_idx = 0
    
    foreach period of numlist `nt' {
        if `nobs_`period'' == 0 continue
        
        // Separator for non-first plot
        if `plot_idx' > 0 {
            local graph_cmd "`graph_cmd' ||"
        }
        
        // Get line style (Task 4 - positional arg)
        _pte_get_line_style `period'
        local lw "`r(lw)'"
        local lp "`r(lp)'"
        local lc "`r(lc)'"
        
        // Build kdensity sub-command
        local graph_cmd "`graph_cmd' (kdensity _pte_tt if _pte_treat==1 & _pte_nt==`period', lw(`lw') lp(`lp')"
        if "`lc'" != "" {
            local graph_cmd "`graph_cmd' lc(`lc')"
        }
        local graph_cmd "`graph_cmd')"
        
        // Update legend
        local plot_idx = `plot_idx' + 1
        local legend_order `"`legend_order' `plot_idx' "period `period'""'
    }
    
    // === Task 7: Add reference line (x=0) ===
    if "`noxline'" == "" {
        local xline_opt "xline(0, lc(gray) lp(dash) lw(0.3))"
    }
    else {
        local xline_opt ""
    }
    
    // === Task 8: Add legend and titles ===
    local graph_cmd "`graph_cmd', legend(order(`legend_order') ring(0) col(2) pos(10) region(fcolor(none) lpattern(blank)))"
    local graph_cmd "`graph_cmd' xtitle(`"`xtitle'"') ytitle(`"`ytitle'"')"
    if `"`title'"' != "" {
        local graph_cmd "`graph_cmd' title(`"`title'"')"
    }
    local graph_cmd "`graph_cmd' scheme(`scheme')"
    if "`xline_opt'" != "" {
        local graph_cmd "`graph_cmd' `xline_opt'"
    }
    
    // Execute graph command
    `graph_cmd'
    
    local save_file ""

    // === Task 12: Save option ===
    if "`save'" != "" {
        if !regexm("`save'", "\.gph$") {
            local save "`save'.gph"
        }
        graph save "`save'", replace
        local save_file "`save'"
        di as text "graph saved to `save'"
    }
    
    // === Task 13: Export option ===
    if "`export'" != "" {
        local ext = lower(substr("`export'", -4, .))
        if !inlist("`ext'", ".png", ".eps", ".pdf", ".tif") {
            di as error "unsupported export format: `ext'"
            di as error "supported formats: .png, .eps, .pdf, .tif"
            exit 198
        }
        graph export "`export'", width(`width') height(`height') replace
        di as text "graph exported to `export'"
    }
    
    // === Task 14: Set r() return values ===
    return local type "tt"
    return local graph_type "tt"
    return local periods "`periods_plotted'"
    return scalar n_periods = `plot_count'
    if "`save_file'" != "" {
        return local filename "`save_file'"
    }
    if "`export'" != "" {
        return local export_file "`export'"
    }
    return scalar nobs = `total_nobs'
    
    foreach period of numlist `nt' {
        if `nobs_`period'' > 0 {
            return scalar nobs_`period' = `nobs_`period''
            return scalar mean_`period' = `mean_`period''
            return scalar sd_`period' = `sd_`period''
        }
    }
    
    // === Task 15: Summary display ===
    di as text ""
    di as text "{bf:TT Distribution Kernel Density Plot}"
    di as text "{hline 50}"
    di as text "Periods plotted: `periods_plotted'"
    di as text "Total observations: " %10.0fc `total_nobs'
    di as text ""
    di as text "{col 5}Period{col 15}N{col 25}Mean{col 40}Std.Dev."
    di as text "{hline 50}"
    foreach period of numlist `nt' {
        if `nobs_`period'' > 0 {
            di as text "{col 5}`period'{col 15}" %7.0fc `nobs_`period'' ///
                       "{col 25}" %8.4f `mean_`period'' ///
                       "{col 40}" %8.4f `sd_`period''
        }
    }
    di as text "{hline 50}"
    
end
