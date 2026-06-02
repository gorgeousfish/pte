*! _pte_graph_combine.ado
*! Multi-graph combine implementation

version 14.0
program define _pte_graph_combine, rclass
    version 14.0
    
    syntax , GRAPH_TYPE(string) ///
        [BYPERIOD BYINDUSTRY BYGROUP(varname)] ///
        [ROWS(integer 0) COLS(integer 0)] ///
        [COMMONscale ISCALE(real 1)] ///
        [ADDsummary] ///
        [NT(numlist) TYPE(string) QUANtiles(integer 3) Level(integer 95)] ///
        [TItle(string) SUBtitle(string) XTItle(string) YTItle(string)] ///
        [SCHeme(string) COLor(string)] ///
        [SAVE(string) EXPORT(string)] ///
        [WIDTH(integer 800) HEIGHT(integer 600)]
    
    // =========================================================
    // 1. Validate grouping mode (T-011.03)
    // =========================================================
    
    local group_mode_count = 0
    if "`byperiod'" != "" local group_mode_count = `group_mode_count' + 1
    if "`byindustry'" != "" local group_mode_count = `group_mode_count' + 1
    if "`bygroup'" != "" local group_mode_count = `group_mode_count' + 1
    
    if `group_mode_count' > 1 {
        di as error "[pte] only one of byperiod, byindustry, bygroup() may be specified"
        exit 198
    }
    
    // =========================================================
    // 2. Determine grouping variable (T-011.04~07)
    // =========================================================
    
    local group_mode ""
    local group_var ""
    
    if "`byperiod'" != "" {
        local group_mode "byperiod"
        local group_var "_pte_nt"
    }
    else if "`byindustry'" != "" {
        local group_mode "byindustry"
        local group_var "_pte_industry"
    }
    else if "`bygroup'" != "" {
        local group_mode "bygroup"
        local group_var "`bygroup'"
        
        // Validate variable type (must be numeric)
        capture confirm numeric variable `bygroup'
        if _rc {
            di as error "[pte] bygroup() variable must be numeric"
            exit 109
        }
    }
    else {
        // Default grouping by graph type (T-011.07)
        if inlist("`graph_type'", "tt", "scatter", "catt", "evolution") {
            local group_mode "byperiod"
            local group_var "_pte_nt"
        }
        else if "`graph_type'" == "diagnose" {
            local group_mode "byindustry"
            local group_var "_pte_industry"
        }
        else {
            di as error "[pte] must specify byperiod, byindustry, or bygroup()"
            di as error "[pte] for graph type `graph_type'"
            exit 198
        }
    }
    
    // Validate grouping variable exists
    capture confirm variable `group_var'
    if _rc {
        di as error "[pte] variable `group_var' not found"
        di as error "[pte] run {bf:pte} command first"
        exit 111
    }
    
    // =========================================================
    // 3. Get group values (T-011.08)
    // =========================================================
    
    // Determine data variable for non-missing check
    local data_var ""
    if inlist("`graph_type'", "tt", "catt", "scatter") {
        local data_var "_pte_tt"
    }
    else if "`graph_type'" == "diagnose" {
        local data_var "_pte_eps0"
    }
    else {
        local data_var "_pte_omega"
    }
    
    // Get group levels
    qui levelsof `group_var' if !missing(`data_var'), local(groups)
    
    if "`groups'" == "" {
        di as error "[pte] no valid groups in `group_var'"
        exit 2000
    }
    
    local n_groups : word count `groups'
    di as text "[pte] found `n_groups' groups in `group_var'"
    
    // =========================================================
    // 4. Generate subgraphs (T-011.09, T-011.10)
    // =========================================================
    
    // Build sub-options string
    local subopts ""
    if "`nt'" != "" local subopts "`subopts' nt(`nt')"
    if "`type'" != "" local subopts "`subopts' type(`type')"
    if `quantiles' != 3 local subopts "`subopts' quantiles(`quantiles')"
    if `level' != 95 local subopts "`subopts' level(`level')"
    if "`scheme'" != "" local subopts "`subopts' scheme(`scheme')"
    if "`color'" != "" local subopts "`subopts' color(`color')"
    if "`xtitle'" != "" local subopts `"`subopts' xtitle(`"`xtitle'"')"'
    if "`ytitle'" != "" local subopts `"`subopts' ytitle(`"`ytitle'"')"'
    
    local graph_list ""
    local n_subgraphs = 0
    local groups_plotted ""
    
    foreach g of local groups {
        // Get value label (T-011.09)
        local g_label : label (`group_var') `g'
        
        // Default label if no value label
        if "`g_label'" == "" | "`g_label'" == "`g'" {
            if "`group_mode'" == "byperiod" {
                local g_label "Period `g'"
            }
            else if "`group_mode'" == "byindustry" {
                local g_label "Industry `g'"
            }
            else {
                local g_label "Group `g'"
            }
        }
        
        // Check group data count
        qui count if `group_var' == `g' & !missing(`data_var')
        local nobs_g = r(N)
        
        if `nobs_g' == 0 {
            di as text "[pte] warning: no observations for `group_var'==`g', skipping"
            continue
        }
        
        // Create temp file for subgraph
        tempfile tmpgraph_`n_subgraphs'
        
        di as text "[pte]   generating subgraph for `g_label' (N=`nobs_g')..."
        
        // Preserve and keep only group data
        preserve
        qui keep if `group_var' == `g'
        
        // Generate subgraph
        local subcmd "_pte_graph_`graph_type'"
        
        capture `subcmd', save("`tmpgraph_`n_subgraphs''") ///
            title("`g_label'") `subopts'
        
        local subrc = _rc
        restore
        
        if `subrc' {
            di as error "[pte] failed to generate subgraph for `g_label' (rc=`subrc')"
            exit 199
        }
        
        // Add to list
        local graph_list `"`graph_list' "`tmpgraph_`n_subgraphs''""'
        local n_subgraphs = `n_subgraphs' + 1
        local groups_plotted "`groups_plotted' `g'"
    }
    
    // Check subgraph count
    if `n_subgraphs' == 0 {
        di as error "[pte] no subgraphs generated"
        exit 2000
    }
    
    // =========================================================
    // 5. Add summary subgraph if requested (T-011.11)
    // =========================================================
    
    if "`addsummary'" != "" {
        tempfile tmpgraph_all
        
        di as text "[pte]   generating summary subgraph..."
        
        capture _pte_graph_`graph_type', save("`tmpgraph_all'") ///
            title("All") `subopts'
        
        if _rc == 0 {
            local graph_list `"`graph_list' "`tmpgraph_all'""'
            local n_subgraphs = `n_subgraphs' + 1
        }
        else {
            di as text "[pte] warning: failed to generate summary subgraph"
        }
    }
    
    // =========================================================
    // 6. Build graph combine command (T-011.12)
    // =========================================================
    
    local combine_opts ""
    
    // Layout parameters
    if `rows' > 0 {
        local combine_opts "`combine_opts' rows(`rows')"
    }
    if `cols' > 0 {
        local combine_opts "`combine_opts' cols(`cols')"
    }
    
    // Common scale
    if "`commonscale'" != "" {
        local combine_opts "`combine_opts' xcommon ycommon"
    }
    
    // iscale
    if `iscale' != 1 {
        local combine_opts "`combine_opts' iscale(`iscale')"
    }
    
    // Title
    if "`title'" != "" {
        local combine_opts `"`combine_opts' title(`"`title'"')"'
    }
    if "`subtitle'" != "" {
        local combine_opts `"`combine_opts' subtitle(`"`subtitle'"')"'
    }
    
    // Scheme
    if "`scheme'" != "" {
        local combine_opts "`combine_opts' scheme(`scheme')"
    }
    
    // =========================================================
    // 7. Execute combine (T-011.13)
    // =========================================================
    
    di as text ""
    di as text "[pte] combining `n_subgraphs' subgraphs..."
    
    graph combine `graph_list', `combine_opts'
    
    // =========================================================
    // 8. Save and export (T-011.14)
    // =========================================================
    
    if "`save'" != "" {
        // Ensure .gph extension
        if !regexm("`save'", "\.gph$") {
            local save "`save'.gph"
        }
        graph save "`save'", replace
        di as text "[pte] combined graph saved to `save'"
    }
    
    if "`export'" != "" {
        graph export "`export'", width(`width') height(`height') replace
        di as text "[pte] combined graph exported to `export'"
    }
    
    // =========================================================
    // 9. Return values and summary (T-011.15)
    // =========================================================
    
    return scalar n_subgraphs = `n_subgraphs'
    return local groups "`groups_plotted'"
    return local group_var "`group_var'"
    return local group_mode "`group_mode'"
    return local graph_type "`graph_type'"
    
    // Calculate actual layout
    if `rows' == 0 & `cols' == 0 {
        local auto_cols = ceil(sqrt(`n_subgraphs'))
        local auto_rows = ceil(`n_subgraphs' / `auto_cols')
    }
    else if `rows' == 0 {
        local auto_cols = `cols'
        local auto_rows = ceil(`n_subgraphs' / `auto_cols')
    }
    else if `cols' == 0 {
        local auto_rows = `rows'
        local auto_cols = ceil(`n_subgraphs' / `auto_rows')
    }
    else {
        local auto_rows = `rows'
        local auto_cols = `cols'
    }
    
    return scalar rows = `auto_rows'
    return scalar cols = `auto_cols'
    
    // Display summary
    di as text ""
    di as text "{bf:Multi-Graph Combine Summary}"
    di as text "{hline 50}"
    di as text "Graph type:      `graph_type'"
    di as text "Group mode:      `group_mode'"
    di as text "Group variable:  `group_var'"
    di as text "Subgraphs:       `n_subgraphs'"
    di as text "Layout:          `auto_rows' x `auto_cols'"
    di as text "Groups plotted:  `groups_plotted'"
    di as text "{hline 50}"
    
end
