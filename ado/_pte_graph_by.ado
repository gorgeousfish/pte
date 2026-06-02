*! _pte_graph_by.ado
*! Industry-specific charts core implementation

version 14.0
program define _pte_graph_by, rclass
    version 14.0
    
    syntax varname [, ///
        GRAPHTYPE(string) ///
        TT CATT ATT SCATTER EVOLUTION COMPARE DIAGNOSE ///
        TYPE(string) NT(numlist) QUANtiles(integer 3) ///
        LEVEL(integer 95) ///
        TItle(string) XTItle(string) YTItle(string) ///
        COLor(string) SCHeme(string) ///
        SAVE(string) EXPORT(string) ///
        WIDTH(integer 800) HEIGHT(integer 600) ///
        COMBINE ///
        COLS(integer 0) ROWS(integer 0) ///
        TITLEPREfix(string) NOTItle ///
        SAVEALL(string) ///
        NOXCOMMON NOYCOMMON ///
        IMARGIN(string) ///
        *]

    local by_var "`varlist'"
    
    // =========================================================
    // 1. Validate by() variable (Task 2)
    // =========================================================
    
    capture confirm variable `by_var'
    if _rc {
        di as error "[pte] variable `by_var' not found"
        di as error "[pte] specify a valid grouping variable with by(varname)"
        exit 111
    }
    
    // Check variable type
    capture confirm numeric variable `by_var'
    local is_numeric = (_rc == 0)
    
    // Check value labels
    local has_labels = 0
    local lblname: value label `by_var'
    if "`lblname'" != "" {
        local has_labels = 1
    }
    
    // =========================================================
    // 2. Get group levels (Task 3)
    // =========================================================
    
    qui levelsof `by_var', local(groups)
    local n_groups: word count `groups'
    
    if `n_groups' == 0 {
        di as error "[pte] no valid groups found in `by_var'"
        di as error "[pte] check that the variable has non-missing values"
        exit 2000
    }
    
    if `n_groups' == 1 {
        di as text "[pte] warning: only 1 group found in `by_var'"
        di as text "[pte]          combine option will be ignored"
        local combine ""
    }
    
    if `n_groups' > 20 {
        di as text "[pte] warning: `n_groups' groups found in `by_var'"
        di as text "[pte]          this may result in a very large combined graph"
    }
    
    // =========================================================
    // 3. Identify graph type (Task 4)
    // =========================================================
    
    local graph_types "tt catt att scatter evolution compare diagnose"
    local selected_type ""
    local type_count = 0
    
    foreach gtype of local graph_types {
        if "``gtype''" != "" {
            local selected_type "`gtype'"
            local ++type_count
        }
    }
    
    // Allow graphtype() as alternative
    if `type_count' == 0 & "`graphtype'" != "" {
        local selected_type "`graphtype'"
        local type_count = 1
    }
    
    if `type_count' == 0 {
        di as error "[pte] must specify a graph type"
        di as error "[pte] options: tt, catt, att, scatter, evolution, compare, diagnose"
        exit 198
    }
    
    if `type_count' > 1 {
        di as error "[pte] only one graph type may be specified"
        exit 198
    }

    if "`selected_type'" == "evolution" {
        _pte_graph_evtreat, context("pte_graph, evolution by()")
    }
    
    di as text "[pte] generating `selected_type' charts by `by_var' (`n_groups' groups)"
    
    // =========================================================
    // 4. Build pass-through options
    // =========================================================
    
    local pass_options ""
    if "`type'" != "" local pass_options "`pass_options' type(`type')"
    if "`nt'" != "" local pass_options "`pass_options' nt(`nt')"
    if `quantiles' != 3 local pass_options "`pass_options' quantiles(`quantiles')"
    if `level' != 95 local pass_options "`pass_options' level(`level')"
    if "`xtitle'" != "" local pass_options `"`pass_options' xtitle(`"`xtitle'"')"'
    if "`ytitle'" != "" local pass_options `"`pass_options' ytitle(`"`ytitle'"')"'
    if "`color'" != "" local pass_options "`pass_options' color(`color')"
    if "`scheme'" != "" local pass_options "`pass_options' scheme(`scheme')"
    if `"`options'"' != "" local pass_options `"`pass_options' `options'"'

    if inlist("`selected_type'", "scatter", "catt", "evolution", "diagnose") {
        local setup_panel : char _dta[_pte_setup_panelvar]
        local setup_time : char _dta[_pte_setup_timevar]
        local setup_treatment : char _dta[_pte_setup_treatment]
        local setup_treatsig : char _dta[_pte_setup_treatsig]
        local setup_xtdelta : char _dta[_pte_setup_xtdelta]
        local have_setup_fragment = ///
            (`"`setup_panel'"' != "") | ///
            (`"`setup_time'"' != "") | ///
            (`"`setup_treatment'"' != "") | ///
            (`"`setup_treatsig'"' != "") | ///
            (`"`setup_xtdelta'"' != "")

        local live_id ""
        local live_time ""
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
            capture local live_treatsig = e(treatsig)
            if _rc != 0 | "`live_treatsig'" == "." {
                local live_treatsig ""
            }
            capture local live_predict = e(predict)
            if _rc != 0 | "`live_predict'" == "." {
                local live_predict ""
            }
        }
        local have_live_panel_contract = ///
            (`"`live_id'"' != "") | (`"`live_time'"' != "") | (`"`live_treatsig'"' != "")
        local have_live_payload = (`"`live_predict'"' != "")
        local have_live_pte = (`have_live_panel_contract' | `have_live_payload')

        capture quietly _pte_diag_panel_contract, context("pte_graph `selected_type' by()") ///
            allowsetupmissingxtdelta
        local by_contract_rc = _rc
        if `by_contract_rc' == 0 {
            local pass_options "`pass_options' currentlawchecked"
        }
        else if `have_setup_fragment' | `have_live_pte' {
            exit `by_contract_rc'
        }
    }
    
    // =========================================================
    // 5. Loop: generate subgraphs (Task 5-8)
    // =========================================================
    
    local graph_files ""
    local groups_plotted ""
    local i = 0
    local n_plotted = 0
    local first_subrc = .
    local preserved_type ""
    
    foreach g of local groups {
        local ++i
        
        // Get group label (Task 6)
        if `is_numeric' {
            local label: label (`by_var') `g'
        }
        else {
            local label "`g'"
        }
        
        // Default label if no value label
        if "`label'" == "" | "`label'" == "`g'" {
            if "`titleprefix'" != "" {
                local label "`titleprefix' `g'"
            }
            else {
                local label "`g'"
            }
        }
        
        // Set subtitle (unless notitle)
        local title_opt ""
        if "`notitle'" == "" {
            local title_opt `"title("`label'")"'
        }
        
        // Preserve and filter data
        preserve
        
        if `is_numeric' {
            qui keep if `by_var' == `g' & !missing(`by_var')
        }
        else {
            qui keep if `by_var' == "`g'" & !missing(`by_var')
        }
        
        // Check observation count
        qui count
        local nobs = r(N)
        
        if `nobs' == 0 {
            di as text "[pte] warning: no observations for group `g', skipping"
            restore
            continue
        }
        
        di as text "[pte]   `label' (N=`nobs')..."
        
        // Save each subgraph as a real .gph file so graph combine consumes
        // file paths instead of mistaking tempfile stems for memory graph names.
        tempfile tf_`i'
        local graph_file `"`tf_`i''.gph'"'
        
        // Call graph subprogram
        local subcmd "_pte_graph_`selected_type'"
        
        capture noisily `subcmd', `title_opt' `pass_options'
        local subrc = _rc
        
        if `subrc' {
            if missing(`first_subrc') {
                local first_subrc = `subrc'
            }
            di as text "[pte] warning: failed to generate subgraph for `label' (rc=`subrc')"
            restore
            continue
        }

        if "`preserved_type'" == "" {
            local preserved_type `"`r(type)'"'
        }

        // Preserve subtype-specific r() payloads when by() degenerates to a
        // single public subgroup. In that case the public wrapper should not
        // discard the worker's own returned contract.
        if `n_groups' == 1 {
            return add
        }
        
        // Save subgraph to a .gph tempfile for the later combine step.
        qui graph save `"`graph_file'"', replace
        local graph_files `"`graph_files' "`graph_file'""'
        if `is_numeric' {
            local groups_plotted "`groups_plotted' `g'"
        }
        else {
            local groups_plotted `"`groups_plotted' `"`g'"'"'
        }
        local ++n_plotted
        
        // Save individual graph if saveall specified (Task 8)
        if "`saveall'" != "" {
            // Clean filename
            local clean_label = subinstr("`label'", " ", "_", .)
            local clean_label = subinstr("`clean_label'", "'", "", .)
            local clean_label = subinstr("`clean_label'", "&", "and", .)
            local clean_label = subinstr("`clean_label'", "/", "_", .)
            local clean_label = subinstr("`clean_label'", ".", "", .)
            local clean_label = lower("`clean_label'")
            
            qui graph save "`saveall'_`clean_label'.gph", replace
            di as text "[pte]   saved: `saveall'_`clean_label'.gph"
        }
        
        restore
    }

    // Public by() advertises one graph per requested group. If any subgroup
    // worker fails after the wrapper has already accepted the group level,
    // returning rc=0 with a partial artifact would silently drop that
    // subgroup from the requested output bundle.
    if !missing(`first_subrc') {
        exit `first_subrc'
    }
    
    // Check subgraph count
    if `n_plotted' == 0 {
        di as error "[pte] no valid subgraphs could be created"
        exit 2000
    }
    
    // =========================================================
    // 6. Layout calculation (Task 9)
    // =========================================================
    
    if "`combine'" != "" & `n_plotted' > 1 {
        if `cols' == 0 & `rows' == 0 {
            local cols = ceil(sqrt(`n_plotted'))
            local rows = ceil(`n_plotted' / `cols')
        }
        else if `cols' == 0 {
            local cols = ceil(`n_plotted' / `rows')
        }
        else if `rows' == 0 {
            local rows = ceil(`n_plotted' / `cols')
        }
    }
    
    // =========================================================
    // 7. Execute graph combine (Task 10)
    // =========================================================
    
    local export_file ""
    local save_gph ""

    if "`combine'" != "" & `n_plotted' > 1 {
        // Build combine command
        local combine_cmd "graph combine"
        foreach f of local graph_files {
            local combine_cmd `"`combine_cmd' `f'"'
        }
        
        // Add layout
        local combine_cmd "`combine_cmd', cols(`cols')"
        
        // Common axes (default: enabled)
        if "`noxcommon'" == "" {
            local combine_cmd "`combine_cmd' xcommon"
        }
        if "`noycommon'" == "" {
            local combine_cmd "`combine_cmd' ycommon"
        }
        
        // Subgraph margin
        if "`imargin'" != "" {
            local combine_cmd "`combine_cmd' imargin(`imargin')"
        }
        
        // Overall title
        if "`title'" != "" {
            local combine_cmd `"`combine_cmd' title(`"`title'"')"'
        }
        
        // Scheme
        if "`scheme'" != "" {
            local combine_cmd "`combine_cmd' scheme(`scheme')"
        }
        
        // Execute (Task 11 - combine execution)
        di as text "[pte] combining `n_plotted' subgraphs (`cols' x `rows')..."
        `combine_cmd'
        
        // Save combined graph (Task 11)
        if "`save'" != "" {
            if !regexm("`save'", "\.gph$") {
                local save_gph "`save'.gph"
            }
            else {
                local save_gph "`save'"
            }
            
            qui graph save "`save_gph'", replace
            di as text "[pte] combined graph saved: `save_gph'"
        }

        // Export should work even when the caller does not also request save().
        if "`export'" != "" {
            local export_target ""

            // Preserve the historical save()+export(png) shorthand while also
            // honoring direct export filenames like export("path/file.png").
            if "`save'" != "" & !regexm("`export'", "[/\\]") & !regexm("`export'", "\.[A-Za-z0-9]+$") {
                local export_target = subinstr("`save_gph'", ".gph", ".`export'", 1)
            }
            else {
                local export_target "`export'"
            }

            qui graph export "`export_target'", ///
                width(`width') height(`height') replace
            di as text "[pte] combined graph exported: `export_target'"
            local export_file "`export_target'"
        }
    }
    else {
        // A single filename cannot represent multiple subgroup graphs unless
        // the wrapper first combines them into one public artifact.
        if `n_plotted' > 1 & ("`save'" != "" | "`export'" != "") {
            di as error "[pte] save()/export() require combine when by() yields multiple subgroup graphs"
            di as error "[pte] Use combine with save()/export(), or use saveall() for per-group .gph files"
            exit 198
        }

        if "`save'" != "" {
            if !regexm("`save'", "\.gph$") {
                local save_gph "`save'.gph"
            }
            else {
                local save_gph "`save'"
            }

            qui graph save "`save_gph'", replace
            di as text "[pte] graph saved: `save_gph'"
        }

        if "`export'" != "" {
            local export_target ""
            if "`save'" != "" & !regexm("`export'", "[/\\]") & !regexm("`export'", "\.[A-Za-z0-9]+$") {
                local export_target = subinstr("`save_gph'", ".gph", ".`export'", 1)
            }
            else {
                local export_target "`export'"
            }

            qui graph export "`export_target'", ///
                width(`width') height(`height') replace
            di as text "[pte] graph exported: `export_target'"
            local export_file "`export_target'"
        }
    }
    
    // =========================================================
    // 8. Return values (Task 12)
    // =========================================================
    
    return local by_var "`by_var'"
    return scalar n_groups = `n_groups'
    return local groups "`groups'"
    return scalar n_combined = `n_plotted'
    return local groups_plotted "`groups_plotted'"
    return local graph_type "`selected_type'"
    if `"`preserved_type'"' != "" {
        return local type `"`preserved_type'"'
    }
    
    if "`combine'" != "" & `n_plotted' > 1 {
        return scalar cols = `cols'
        return scalar rows = `rows'
    }
    
    if "`save'" != "" {
        return local save_file "`save_gph'"
    }
    if "`export_file'" != "" {
        return local export_file "`export_file'"
    }
    
    if "`saveall'" != "" {
        return local saveall_prefix "`saveall'"
    }
    
    // =========================================================
    // 9. Display summary (Task 13)
    // =========================================================
    
    di as text ""
    di as text "{bf:Industry-Specific Charts}"
    di as text "{hline 50}"
    di as text "Graph type:      `selected_type'"
    di as text "By variable:     `by_var'"
    di as text "Groups found:    `n_groups'"
    di as text "Groups plotted:  `n_plotted'"
    
    if "`combine'" != "" & `n_plotted' > 1 {
        di as text "Layout:          `cols' cols x `rows' rows"
    }
    
    if "`save'" != "" {
        di as text "Combined graph:  `save_gph'"
    }
    
    if "`saveall'" != "" {
        di as text "Individual:      `saveall'_*.gph"
    }
    
    di as text "{hline 50}"
    
end
