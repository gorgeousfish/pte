*! _pte_graph_heterogeneity.ado
*! Heterogeneity Analysis Graph (Table 2 visualization)
*! Generates horizontal bar chart of ATT by subgroups with CIs

version 14.0
program define _pte_graph_heterogeneity, rclass
    version 14.0
    
    syntax , BY(varname) [NTALL NT(integer -999) LEVEL(integer 95)] ///
             [TItle(string) XTItle(string) YTItle(string)] ///
             [SCHeme(string) SAVE(string) EXPORT(string)] ///
             [HORizontal SORT(string) SHOWcontrib] ///
             [WIDTH(integer 800) HEIGHT(integer 600)]
    
    // =========================================================================
    // T02b: ntall filtering logic
    // =========================================================================
    
    // Mutual exclusivity check (T02c)
    if "`ntall'" != "" & `nt' != -999 {
        di as error "pte: ntall and nt() are mutually exclusive"
        exit 198
    }
    
    // =========================================================================
    // T03: Prerequisite checks
    // =========================================================================
    
    capture confirm variable _pte_tt, exact
    if _rc {
        di as error "pte: variable _pte_tt not found"
        di as error "  run {bf:pte} estimation before using heterogeneity graph"
        exit 111
    }

    _pte_validate_internal_state _pte_tt numeric ///
        "pte_graph, heterogeneity requires _pte_tt to remain the numeric firm-level TT bridge."
    
    capture confirm variable _pte_nt, exact
    if _rc {
        di as error "pte: variable _pte_nt not found"
        di as error "  run {bf:pte} estimation before using heterogeneity graph"
        exit 111
    }

    _pte_validate_internal_state _pte_nt integer ///
        "pte_graph, heterogeneity requires _pte_nt to remain the integer event-time bridge."

    capture confirm variable _pte_treat, exact
    if _rc {
        di as error "pte: variable _pte_treat not found"
        di as error "  pte_graph, heterogeneity requires the exact treated-support bridge from pte"
        exit 111
    }
    _pte_validate_internal_state _pte_treat binary ///
        "pte_graph, heterogeneity requires _pte_treat to remain the binary treated-support bridge."
    local treated_condition " & _pte_treat == 1"
    tempname attperiods
    tempvar supported_tt

    capture confirm matrix e(attperiods)
    if _rc {
        di as error "pte_graph, heterogeneity requires e(attperiods)"
        di as error "pte_graph, heterogeneity consumes only the exact stored ATT event-time support."
        exit 198
    }
    matrix `attperiods' = e(attperiods)
    local attperiods_cols = colsof(`attperiods')
    quietly _pte_attperiods_support `attperiods' `attperiods_cols' ///
        "pte_graph, heterogeneity"
    local supported_periods `"`r(periodlist)'"'
    quietly gen byte `supported_tt' = 0
    foreach ell of numlist `supported_periods' {
        quietly replace `supported_tt' = 1 if _pte_nt == `ell'
    }

    // Build nt_condition local from the exact stored ATT support
    local use_ntall = 0
    if `nt' != -999 {
        local nt_supported = 0
        foreach ell of numlist `supported_periods' {
            if `ell' == `nt' {
                local nt_supported = 1
                continue, break
            }
        }
        if !`nt_supported' {
            di as error "[pte] requested nt(`nt') is not part of the stored e(attperiods) support."
            exit 198
        }
        local nt_condition "`supported_tt' == 1 & _pte_nt == `nt'"
        di as text "Filtering: nt = `nt'"
    }
    else {
        local nt_condition "`supported_tt' == 1"
        local use_ntall = 1
        di as text "Filtering: exact stored ATT support (`supported_periods')"
    }

    quietly count if `nt_condition' & !missing(_pte_tt)`treated_condition' & missing(`by')
    local total_missing_by_valid = r(N)
    if `total_missing_by_valid' > 0 {
        di as error "[pte] pte_graph, heterogeneity requires by(`by') to be nonmissing on the exact supported treated TT sample"
        di as error "[pte] Found `total_missing_by_valid' supported treated TT observation(s) with missing by()."
        di as error "[pte] Fill the subgroup labels or repair the current dataset before replaying the Table 2 graph."
        exit 198
    }
    
    capture confirm variable `by'
    if _rc {
        di as error "pte: variable `by' not found"
        exit 111
    }

    local by_is_numeric = 0
    tempvar by_group_id
    capture confirm numeric variable `by'
    if _rc == 0 {
        local by_is_numeric = 1
        quietly _pte_het_parse_groups `by'
    }
    else {
        quietly _pte_het_parse_groups `by', generate(`by_group_id')
    }
    local full_group_values "`r(group_list)'"
    local by_calc "`r(byvar_use)'"
    
    quietly count if `nt_condition' & !missing(_pte_tt)`treated_condition' & !missing(`by')
    if r(N) == 0 {
        di as error "pte: no valid observations satisfying `nt_condition'"
        exit 2000
    }
    
    // =========================================================================
    // T04: Group identification
    // =========================================================================
    
    quietly levelsof `by_calc' if `nt_condition' & !missing(_pte_tt)`treated_condition' & !missing(`by_calc'), local(group_values)
    local n_groups : word count `group_values'
    
    if `n_groups' == 0 {
        di as error "pte: no groups found for variable `by'"
        exit 2000
    }
    
    if `n_groups' > 50 {
        di as text "{bf:Warning}: `n_groups' groups detected for `by'. Plot may be crowded."
    }

    local group_values_token_work `"`group_values'"'
    local _pte_token_fill_i = 0
    while `"`group_values_token_work'"' != "" {
        gettoken gval_token group_values_token_work : group_values_token_work, quotes
        if `"`gval_token'"' == "" {
            continue
        }
        local ++_pte_token_fill_i
        if `by_is_numeric' {
            local _pte_graph_group_token_`_pte_token_fill_i' `"`gval_token'"'
        }
        else {
            local _pte_graph_group_token_`_pte_token_fill_i' ""
            quietly levelsof `by' if `nt_condition' & !missing(_pte_tt)`treated_condition' & ///
                !missing(`by') & `by_calc' == `gval_token', ///
                local(_pte_graph_group_token_`_pte_token_fill_i')
        }
    }
    
    // Get value labels if they exist
    local bylabel : value label `by'
    local keep_positions ""
    local has_grouped_boot_contract = 0
    capture confirm matrix e(att_boot_bygroup)
    if !_rc local has_grouped_boot_contract = 1
    if !`has_grouped_boot_contract' {
        capture confirm matrix e(boot_att_by)
        if !_rc local has_grouped_boot_contract = 1
    }
    if !`has_grouped_boot_contract' {
        capture confirm matrix e(att_boot_g1)
        if !_rc local has_grouped_boot_contract = 1
    }
    if !`has_grouped_boot_contract' {
        capture confirm matrix e(att_trim_boot_g1)
        if !_rc local has_grouped_boot_contract = 1
    }
    local stored_groups ""
    capture local stored_groups `"`e(groups)'"'
    if _rc != 0 | `"`stored_groups'"' == "." {
        local stored_groups ""
    }
    local stored_by ""
    capture local stored_by = e(by)
    if _rc != 0 | `"`stored_by'"' == "." {
        local stored_by ""
    }
    local stored_cmd ""
    capture local stored_cmd = e(cmd)
    if _rc != 0 | `"`stored_cmd'"' == "." {
        local stored_cmd ""
    }
    if `has_grouped_boot_contract' & `"`stored_groups'"' == "" {
        di as error "[pte] grouped bootstrap heterogeneity graph requires e(groups)"
        di as error "[pte] grouped bootstrap columns are indexed by the estimation-time group order."
        di as error "[pte] Re-run grouped pte or pte_heterogeneity so the exact group mapping is available."
        exit 198
    }
    if `has_grouped_boot_contract' & `"`stored_by'"' == "" {
        di as error "[pte] grouped bootstrap heterogeneity graph requires e(by)"
        di as error "[pte] grouped bootstrap columns are indexed by the estimation-time grouping variable and exact group order."
        di as error "[pte] Re-run grouped pte or pte_heterogeneity so the grouped route metadata are available."
        exit 198
    }
    if `has_grouped_boot_contract' & `"`stored_by'"' != "`by'" {
        di as error "[pte] grouped bootstrap heterogeneity graph was estimated with e(by)=`stored_by', not by(`by')"
        di as error "[pte] grouped bootstrap ATT draws cannot be remapped under a different grouping variable."
        di as error "[pte] Re-run grouped pte with by(`by') or call pte_graph, heterogeneity by(`stored_by')."
        exit 198
    }
    if `has_grouped_boot_contract' & `"`stored_groups'"' != "" {
        local _pte_stored_group_count 0
        local _pte_stored_groups_work `"`stored_groups'"'
        while `"`_pte_stored_groups_work'"' != "" {
            gettoken _pte_stored_token _pte_stored_groups_work : _pte_stored_groups_work, quotes
            if `"`_pte_stored_token'"' == "" {
                continue
            }
            local ++_pte_stored_group_count
            local _pte_stored_group_token_`_pte_stored_group_count' `"`_pte_stored_token'"'
        }
        if `_pte_stored_group_count' > 1 {
            forvalues _pte_left = 1/`=`_pte_stored_group_count' - 1' {
                forvalues _pte_right = `=`_pte_left' + 1'/`_pte_stored_group_count' {
                    if `"`_pte_stored_group_token_`_pte_left''"' == `"`_pte_stored_group_token_`_pte_right''"' {
                        di as error "[pte] grouped bootstrap heterogeneity graph requires e(groups) to contain unique route tokens"
                        di as error "[pte] Stored e(groups) repeats the same route token at positions `_pte_left' and `_pte_right', so grouped bootstrap columns no longer have a one-to-one route."
                        di as error "[pte] Re-run grouped pte or pte_heterogeneity so e(groups) stays unique and position-identifying."
                        exit 198
                    }
                }
            }
        }
    }
    if `has_grouped_boot_contract' & `"`stored_cmd'"' == "pte_heterogeneity" {
        if `_pte_stored_group_count' != `n_groups' {
            di as error "[pte] pooled pte_heterogeneity repost requires e(groups) to match the live grouped support exactly"
            di as error "[pte] Stored e(groups) count (`_pte_stored_group_count') differs from the live grouped support count (`n_groups')."
            di as error "[pte] Re-run pte_heterogeneity so the reposted grouped route matches the current grouped Table 2 support exactly."
            exit 198
        }

        local _pte_stored_groups_work `"`stored_groups'"'
        forvalues current_idx = 1/`n_groups' {
            gettoken _pte_stored_token _pte_stored_groups_work : _pte_stored_groups_work, quotes
            if `"`_pte_stored_token'"' == "" {
                di as error "[pte] pooled pte_heterogeneity repost requires a complete exact e(groups) token list"
                di as error "[pte] Re-run pte_heterogeneity so grouped bootstrap columns remain aligned with the reposted group order."
                exit 198
            }
            if `"`_pte_stored_token'"' != `"`_pte_graph_group_token_`current_idx''"' {
                di as error "[pte] pooled pte_heterogeneity repost requires e(groups) to match the live grouped support exactly"
                di as error "[pte] Stored e(groups) token order disagrees with the live grouped support at position `current_idx'."
                di as error "[pte] Grouped bootstrap pooled reposts cannot be remapped positionally once pte_heterogeneity has already fixed the grouped route."
                exit 198
            }
            local keep_positions "`keep_positions' `current_idx'"
        }
        if trim(`"`_pte_stored_groups_work'"') != "" {
            di as error "[pte] pooled pte_heterogeneity repost requires e(groups) to match the live grouped support exactly"
            di as error "[pte] Stored e(groups) contains extra grouped tokens beyond the live grouped Table 2 support."
            di as error "[pte] Re-run pte_heterogeneity so the reposted grouped route stays synchronized with the pooled bootstrap sidecars."
            exit 198
        }
    }
    else {
    forvalues current_idx = 1/`n_groups' {
        if `"`stored_groups'"' == "" {
            local keep_positions "`keep_positions' `current_idx'"
            continue
        }
        if `by_is_numeric' {
            local stored_pos : list posof `"`_pte_graph_group_token_`current_idx''"' in stored_groups
        }
        else {
            local stored_pos = 0
            local _pte_stored_idx = 0
            local _pte_stored_groups_work `"`stored_groups'"'
            while `"`_pte_stored_groups_work'"' != "" {
                gettoken _pte_stored_token _pte_stored_groups_work : _pte_stored_groups_work, quotes
                if `"`_pte_stored_token'"' == "" {
                    continue
                }
                local ++_pte_stored_idx
                if `"`_pte_stored_token'"' == `"`_pte_graph_group_token_`current_idx''"' {
                    local stored_pos = `_pte_stored_idx'
                    continue, break
                }
            }
        }
        if `stored_pos' < 1 {
            di as error "[pte] grouped result token `_pte_graph_group_token_`current_idx'' is missing from the stored e(groups) contract"
            exit 459
        }
        local keep_positions "`keep_positions' `stored_pos'"
    }
    }
    
    // Build group_labels list
    local group_labels ""
    local gi = 0
    local group_values_work `"`group_values'"'
    while `"`group_values_work'"' != "" {
        gettoken gval group_values_work : group_values_work, quotes
        if `"`gval'"' == "" {
            continue
        }
        local gi = `gi' + 1
        if `by_is_numeric' & "`bylabel'" != "" {
            local lbl : label `bylabel' `gval'
            local _pte_graph_group_token_`gi' `"`gval'"'
        }
        else if `by_is_numeric' {
            local lbl `"`gval'"'
            local _pte_graph_group_token_`gi' `"`gval'"'
        }
        else {
            local lbl ""
            quietly levelsof `by' if `nt_condition' & !missing(_pte_tt)`treated_condition' & ///
                !missing(`by') & `by_calc' == `gval', local(lbl)
            local _pte_graph_group_token_`gi' `"`lbl'"'
        }
        local group_labels `"`group_labels' `"`lbl'"'"'
        local glabel_`gi' `"`lbl'"'
    }
    
    // =========================================================================
    // T05a: Total ATT calculation
    // =========================================================================
    
    quietly summarize _pte_tt if `nt_condition' & !missing(`by')`treated_condition', meanonly
    local att_total = r(mean)
    local n_total = r(N)
    
    // SD for total (need non-meanonly for sd)
    quietly summarize _pte_tt if `nt_condition' & !missing(`by')`treated_condition'
    local sd_total = r(sd)
    local se_total = .
    
    // =========================================================================
    // T05b: Per-group ATT loop
    // =========================================================================
    
    local gi = 0
    local group_values_work `"`group_values'"'
    while `"`group_values_work'"' != "" {
        gettoken gval group_values_work : group_values_work, quotes
        if `"`gval'"' == "" {
            continue
        }
        local gi = `gi' + 1
        quietly summarize _pte_tt if `nt_condition' & `by_calc' == `gval'`treated_condition'
        local att_`gi' = r(mean)
        local sd_`gi' = r(sd)
        local n_`gi' = r(N)
    }
    
    // =========================================================================
    // T06: SE calculation (Bootstrap SE priority)
    // =========================================================================
    
    local se_method "A"
    local grouped_boot_rc = 0
    local has_grouped_draws = 0
    capture confirm matrix e(att_boot_g1)
    if !_rc local has_grouped_draws = 1
    if !`has_grouped_draws' {
        capture confirm matrix e(att_trim_boot_g1)
        if !_rc local has_grouped_draws = 1
    }
    local has_pooled_boot_repost = 0
    capture confirm matrix e(att_boot_bygroup)
    if !_rc local has_pooled_boot_repost = 1
    if !`has_pooled_boot_repost' {
        capture confirm matrix e(boot_att_by)
        if !_rc local has_pooled_boot_repost = 1
    }

    // Match the live heterogeneity table contract when bootstrap draws are
    // available from the main pte run.
    if `nt' != -999 {
        capture noisily _pte_grouped_boot_att_matrix, keep(`keep_positions') attperiod(`nt')
    }
    else {
        capture noisily _pte_grouped_boot_att_matrix, keep(`keep_positions')
    }
    local grouped_boot_rc = _rc
    if !_rc {
        local se_method "B"
        tempname boot_mat
        matrix `boot_mat' = r(boot_mat)
    }
    else {
        if `grouped_boot_rc' == 198 & `has_pooled_boot_repost' {
            exit 198
        }
        if `nt' != -999 & `has_pooled_boot_repost' & !`has_grouped_draws' {
            di as error "[pte] pte_graph, heterogeneity nt(`nt') cannot replay pooled e(att_boot_bygroup) / e(boot_att_by) sidecars."
            di as error "[pte] Those reposts only summarize pooled Table 2 heterogeneity. Re-run grouped pte so period-specific e(att_boot_g#) draws remain live."
            exit 198
        }
        if `nt' != -999 & `has_grouped_draws' {
            exit `grouped_boot_rc'
        }
        // Backward-compatible fallback for older helper payloads that already
        // store summary SEs by group.
        capture confirm matrix e(boot_att_by)
        if !_rc {
            local se_method "C"
            tempname boot_mat
            matrix `boot_mat' = e(boot_att_by)
        }
    }
    
    if "`se_method'" == "B" {
        local G = colsof(`boot_mat')
        if `G' != `n_groups' {
            di as error "pte: grouped bootstrap draw columns (`G') do not match retained groups (`n_groups')"
            exit 459
        }
        // Method B: derive group SEs from bootstrap draws, mirroring
        // _pte_het_bootstrap_se.
        local gi = 0
        local group_values_work `"`group_values'"'
        while `"`group_values_work'"' != "" {
            gettoken gval group_values_work : group_values_work, quotes
            if `"`gval'"' == "" {
                continue
            }
            local gi = `gi' + 1
            mata: valid_draws = select(st_matrix("`boot_mat'")[., `gi'], ///
                st_matrix("`boot_mat'")[., `gi'] :< .); ///
                st_numscalar("r(sd_g)", rows(valid_draws) > 1 ? sqrt(variance(valid_draws)) : .)
            local se_`gi' = r(sd_g)
            if missing(`se_`gi'') & `n_`gi'' >= 2 {
                local se_`gi' = `sd_`gi'' / sqrt(`n_`gi'')
            }
        }
        local has_live_att_se = 0
        capture confirm matrix e(att_se)
        if !_rc & `total_missing_by_valid' == 0 {
            local has_live_att_se = 1
            tempname att_se_mat
            matrix `att_se_mat' = e(att_se)
            local att_se_col = colsof(`att_se_mat')
            if `nt' != -999 {
                capture confirm matrix e(attperiods)
                if _rc {
                    di as error "[pte] nt()-specific heterogeneity total SE replay requires e(attperiods)."
                    exit 198
                }
                tempname attperiods
                matrix `attperiods' = e(attperiods)
                local att_dyncols = `att_se_col' - 1
                quietly _pte_attperiods_support `attperiods' `att_dyncols' ///
                    "pte_graph, heterogeneity total SE replay"
                matrix `attperiods' = r(periods)
                quietly _pte_dynamic_colstripe_contract `att_se_mat' `attperiods' `att_dyncols' ///
                    "pte_graph, heterogeneity total SE replay" "e(att_se)"
                local total_se_idx = 0
                forvalues j = 1/`=colsof(`attperiods')' {
                    if `attperiods'[1, `j'] == `nt' {
                        local total_se_idx = `j'
                        continue, break
                    }
                }
                if `total_se_idx' < 1 {
                    di as error "[pte] requested nt(`nt') is not part of the stored e(attperiods) support."
                    exit 198
                }
                local se_total = `att_se_mat'[1, `total_se_idx']
                if missing(`se_total') {
                    di as error "[pte] pte_graph, heterogeneity nt(`nt') requires the live ATT standard error for that supported period."
                    di as error "[pte] The live e(att_se) bundle is incomplete at the stored support position for nt(`nt')."
                    di as error "[pte] Re-run pte so the supported ATT inference bundle remains complete before graph replay."
                    exit 198
                }
            }
            else if `att_se_col' >= 1 {
                local se_total = `att_se_mat'[1, `att_se_col']
                if missing(`se_total') {
                    di as error "[pte] pte_graph, heterogeneity requires the pooled ATT_avg standard error when live e(att_se) is posted."
                    di as error "[pte] The live pooled ATT inference bundle is incomplete: e(att_se)[1, `att_se_col'] is missing."
                    di as error "[pte] Re-run pte so the pooled ATT_avg inference bundle remains complete, or drop the stale live e(att_se) helper state before replaying the Table 2 graph."
                    exit 198
                }
            }
        }
        if !`has_live_att_se' & missing(`se_total') & `n_total' >= 2 {
            local se_total = `sd_total' / sqrt(`n_total')
        }
    }
    else if "`se_method'" == "C" {
        local _pte_legacy_total_se = .
        local _pte_legacy_total_row = .
        if `"_pte_stored_group_count'"' != "" & `_pte_stored_group_count' >= 1 {
            local _pte_legacy_total_row = `_pte_stored_group_count' + 1
        }
        if `"_pte_legacy_total_row'"' != "." & `"_pte_legacy_total_row'"' != "" {
            if rowsof(`boot_mat') >= `_pte_legacy_total_row' {
                capture local _pte_legacy_total_se = `boot_mat'[`_pte_legacy_total_row', 2]
            }
        }
        if "`keep_positions'" != "" {
            local keep_count : word count `keep_positions'
            tempname boot_selected
            matrix `boot_selected' = J(`keep_count', colsof(`boot_mat'), .)
            local keep_j = 0
            foreach src of numlist `keep_positions' {
                local ++keep_j
                if `src' > rowsof(`boot_mat') {
                    di as error "pte: requested legacy grouped summary row `src' exceeds available rows " rowsof(`boot_mat')
                    exit 503
                }
                forvalues c = 1/`=colsof(`boot_mat')' {
                    matrix `boot_selected'[`keep_j', `c'] = `boot_mat'[`src', `c']
                }
            }
            matrix `boot_mat' = `boot_selected'
        }
        // Method C: extract SEs from an older summary matrix layout.
        local gi = 0
        local group_values_work `"`group_values'"'
        while `"`group_values_work'"' != "" {
            gettoken gval group_values_work : group_values_work, quotes
            if `"`gval'"' == "" {
                continue
            }
            local gi = `gi' + 1
            capture local se_`gi' = `boot_mat'[`gi', 2]
            if _rc & `n_`gi'' >= 2 {
                local se_`gi' = `sd_`gi'' / sqrt(`n_`gi'')
            }
        }
        local has_live_att_se = 0
        capture confirm matrix e(att_se)
        if !_rc & `total_missing_by_valid' == 0 {
            local has_live_att_se = 1
            tempname att_se_mat
            matrix `att_se_mat' = e(att_se)
            local att_se_col = colsof(`att_se_mat')
            if `att_se_col' >= 1 {
                local se_total = `att_se_mat'[1, `att_se_col']
            }
            if missing(`se_total') {
                di as error "[pte] pte_graph, heterogeneity requires the pooled ATT_avg standard error when live e(att_se) is posted."
                di as error "[pte] The live pooled ATT inference bundle is incomplete: e(att_se)[1, `att_se_col'] is missing."
                di as error "[pte] Re-run pte so the pooled ATT_avg inference bundle remains complete, or drop the stale live e(att_se) helper state before replaying the Table 2 graph."
                exit 198
            }
        }
        if !`has_live_att_se' & missing(`se_total') & !missing(`_pte_legacy_total_se') {
            local se_total = `_pte_legacy_total_se'
        }
        if missing(`se_total') & `n_total' >= 2 {
            local se_total = `sd_total' / sqrt(`n_total')
        }
    }
    else {
        // Method A fallback: SE = sd / sqrt(n)
        local gi = 0
        local group_values_work `"`group_values'"'
        while `"`group_values_work'"' != "" {
            gettoken gval group_values_work : group_values_work, quotes
            if `"`gval'"' == "" {
                continue
            }
            local gi = `gi' + 1
            if `n_`gi'' >= 2 {
                local se_`gi' = `sd_`gi'' / sqrt(`n_`gi'')
            }
            else {
                local se_`gi' = .
            }
        }
        if `n_total' >= 2 {
            local se_total = `sd_total' / sqrt(`n_total')
        }
        else {
            local se_total = .
        }
    }
    
    // =========================================================================
    // T07: CI calculation
    // =========================================================================
    
    // Validate confidence level
    if `level' < 10 | `level' > 99 {
        di as error "pte: level() must be between 10 and 99"
        exit 198
    }
    
    local alpha = 1 - `level' / 100
    local z = invnormal(1 - `alpha' / 2)
    
    // Per-group CIs
    local gi = 0
    foreach gval of local group_values {
        local gi = `gi' + 1
        if !missing(`se_`gi'') {
            local ci_lower_`gi' = `att_`gi'' - `z' * `se_`gi''
            local ci_upper_`gi' = `att_`gi'' + `z' * `se_`gi''
        }
        else {
            local ci_lower_`gi' = .
            local ci_upper_`gi' = .
        }
    }
    
    // Total CIs
    if !missing(`se_total') {
        local ci_lower_total = `att_total' - `z' * `se_total'
        local ci_upper_total = `att_total' + `z' * `se_total'
    }
    else {
        local ci_lower_total = .
        local ci_upper_total = .
    }
    
    // =========================================================================
    // T08: Contribution rate calculation
    // =========================================================================
    
    // Match the public Table 2 contract used by pte_heterogeneity:
    // contribution signs follow group ATT, with the pooled ATT entering only
    // through its magnitude in the denominator.
    local att_total_abs = abs(`att_total')
    local contrib_warn = 0
    if `att_total_abs' < 1e-8 {
        di as text "{bf:Warning}: total ATT is near zero (`att_total'). Contribution rates may be unreliable."
        local contrib_warn = 1
    }
    else if `att_total_abs' <= 1e-6 {
        di as text "{bf:Warning}: total ATT is near zero (`att_total'). Contribution rates are reported but may be unreliable."
    }
    
    local contrib_sum = 0
    local gi = 0
    foreach gval of local group_values {
        local gi = `gi' + 1
        if `contrib_warn' == 0 {
            local contrib_`gi' = (`n_`gi'' / `n_total') * `att_`gi'' / `att_total_abs' * 100
        }
        else {
            local contrib_`gi' = .
        }
        if !missing(`contrib_`gi'') {
            local contrib_sum = `contrib_sum' + `contrib_`gi''
        }
    }
    
    // Verify sum approximately equals sign(att_total) * 100%
    if `contrib_warn' == 0 {
        local expected_contrib_sum = cond(`att_total' > 0, 100, -100)
        local contrib_check = abs(`contrib_sum' - `expected_contrib_sum')
        if `contrib_check' > 1e-8 {
            di as text "{bf:Note}: contribution sum = " %9.4f `contrib_sum' ///
                "% (expected " %9.4f `expected_contrib_sum' "%)"
        }
    }
    
    // =========================================================================
    // T09: Plot data preparation
    // =========================================================================
    
    preserve
    clear
    
    quietly set obs `n_groups'
    
    quietly gen int group_id = .
    quietly gen double att = .
    quietly gen double se = .
    quietly gen double ci_lower = .
    quietly gen double ci_upper = .
    quietly gen double n_obs = .
    quietly gen double contrib = .
    quietly gen str80 group_label = ""
    
    // Fill from stored locals
    local gi = 0
    foreach gval of local group_values {
        local gi = `gi' + 1
        quietly replace group_id = `gi' in `gi'
        quietly replace att = `att_`gi'' in `gi'
        quietly replace se = `se_`gi'' in `gi'
        quietly replace ci_lower = `ci_lower_`gi'' in `gi'
        quietly replace ci_upper = `ci_upper_`gi'' in `gi'
        quietly replace n_obs = `n_`gi'' in `gi'
        quietly replace contrib = `contrib_`gi'' in `gi'
        quietly replace group_label = `"`glabel_`gi''"' in `gi'
    }
    
    // =========================================================================
    // T10: Sort functionality
    // =========================================================================
    
    if `"`sort'"' == "mean" {
        gsort -att
    }
    else if `"`sort'"' == "n" {
        gsort -n_obs
    }
    else {
        // Default: sort by group label (alphabetical)
        sort group_label
    }
    
    // Generate order variable for Y-axis positioning
    quietly gen int order = _n
    
    // Apply value labels to order variable for Y-axis display
    forvalues i = 1/`n_groups' {
        local lbl_i = group_label[`i']
        label define order_lbl `i' `"`lbl_i'"', add
    }
    label values order order_lbl
    
    // =========================================================================
    // T11-T13: Build graph command
    // =========================================================================
    
    // Set defaults
    if `"`title'"' == "" local title "Heterogeneity Analysis"
    if `"`xtitle'"' == "" local xtitle "ATT"
    if `"`ytitle'"' == "" local ytitle ""
    if "`scheme'" == "" local scheme "s1color"
    
    // Build twoway command
    // T11: Bar chart (horizontal)
    local graph_cmd "twoway"
    local graph_cmd "`graph_cmd' (bar att order, horizontal color(navy%70) barwidth(0.6))"
    
    // T12: Error bars (horizontal rcap)
    local graph_cmd "`graph_cmd' (rcap ci_lower ci_upper order, horizontal lcolor(black))"
    
    // T13: Reference line, labels, titles
    // Zero reference line
    local graph_cmd "`graph_cmd', xline(0, lcolor(black) lpattern(solid))"
    
    // Y-axis labels: show group names
    local graph_cmd "`graph_cmd' ylabel(1/`n_groups', valuelabel angle(0) labsize(small))"
    
    // Axis titles
    local graph_cmd `"`graph_cmd' xtitle(`"`xtitle'"')"'
    local graph_cmd `"`graph_cmd' ytitle(`"`ytitle'"')"'
    
    // Title
    local graph_cmd `"`graph_cmd' title(`"`title'"')"'
    
    // Note with CI level info
    local graph_cmd `"`graph_cmd' note("`level'% confidence intervals")"'
    
    // Legend off, scheme
    local graph_cmd "`graph_cmd' legend(off) scheme(`scheme')"
    
    // Execute graph command
    `graph_cmd'
    
    // =========================================================================
    // T14: Save and export
    // =========================================================================
    
    if "`save'" != "" {
        if !regexm("`save'", "\.gph$") {
            local save "`save'.gph"
        }
        graph save "`save'", replace
        di as text "graph saved to `save'"
    }
    
    if "`export'" != "" {
        graph export "`export'", width(`width') height(`height') replace
        di as text "graph exported to `export'"
    }
    
    // =========================================================================
    // Restore BEFORE setting return values
    // =========================================================================
    
    restore
    
    // =========================================================================
    // T15: r() return values (AFTER restore)
    // =========================================================================
    
    // Create (K+1) x 4 matrix following the public table contract:
    // ATT, SE, Contribution, N
    local nrows = `n_groups' + 1
    tempname att_by_mat
    matrix `att_by_mat' = J(`nrows', 4, .)
    matrix colnames `att_by_mat' = ATT SE Contribution N
    
    // Build row names
    local rownames ""
    local gi = 0
    foreach gval of local group_values {
        local gi = `gi' + 1
        // Fill group rows
        matrix `att_by_mat'[`gi', 1] = `att_`gi''
        if !missing(`se_`gi'') {
            matrix `att_by_mat'[`gi', 2] = `se_`gi''
        }
        if !missing(`contrib_`gi'') {
            matrix `att_by_mat'[`gi', 3] = `contrib_`gi''
        }
        matrix `att_by_mat'[`gi', 4] = `n_`gi''
        // Sanitize label for matrix row name (replace spaces with underscores)
        local rlbl `glabel_`gi''
        local rlbl : subinstr local rlbl " " "_", all
        local rlbl : subinstr local rlbl "." "_", all
        if strlen("`rlbl'") > 32 {
            local rlbl = substr("`rlbl'", 1, 32)
        }
        local rownames `"`rownames' `rlbl'"'
    }
    
    // Fill Total row
    matrix `att_by_mat'[`nrows', 1] = `att_total'
    if !missing(`se_total') {
        matrix `att_by_mat'[`nrows', 2] = `se_total'
    }
    if `contrib_warn' == 0 {
        matrix `att_by_mat'[`nrows', 3] = cond(`att_total' > 0, 100, -100)
    }
    matrix `att_by_mat'[`nrows', 4] = `n_total'
    local rownames `"`rownames' Total"'
    
    matrix rownames `att_by_mat' = `rownames'
    
    // Return matrix
    return matrix att_by = `att_by_mat'
    
    // Return scalars
    return scalar att_total = `att_total'
    if !missing(`se_total') {
        return scalar se_total = `se_total'
    }
    else {
        return scalar se_total = .
    }
    return scalar n_total = `n_total'
    return scalar n_groups = `n_groups'
    return scalar ntall = `use_ntall'
    if `nt' != -999 {
        return scalar nt = `nt'
    }
    else {
        return scalar nt = .
    }
    return scalar level = `level'
    
    // Return locals
    return local by "`by'"
    return local group_labels `"`group_labels'"'
    return local type "heterogeneity"
    return local graph_type "heterogeneity"
    if "`save'" != "" {
        return local filename "`save'"
    }
    if "`export'" != "" {
        return local filename "`export'"
    }
    
    // =========================================================================
    // T16: Summary display
    // =========================================================================
    
    di as text ""
    di as text "{bf:Heterogeneity Analysis by `by'}"
    di as text "{hline 70}"
    
    // Table header
    if "`showcontrib'" != "" {
        di as text "{col 3}Group{col 28}ATT{col 40}SE{col 50}Contrib(%){col 63}N"
    }
    else {
        di as text "{col 3}Group{col 28}ATT{col 40}SE{col 52}N"
    }
    di as text "{hline 70}"
    
    // Per-group rows
    local gi = 0
    foreach gval of local group_values {
        local gi = `gi' + 1
        local lbl `glabel_`gi''
        
        // Truncate label if too long for display
        if strlen("`lbl'") > 24 {
            local lbl = substr("`lbl'", 1, 21) + "..."
        }
        
        if "`showcontrib'" != "" & !missing(`contrib_`gi'') {
            di as text "{col 3}`lbl'" ///
                       "{col 26}" %9.4f `att_`gi'' ///
                       "{col 38}" %8.4f `se_`gi'' ///
                       "{col 49}" %10.2f `contrib_`gi'' ///
                       "{col 62}" %8.0fc `n_`gi''
        }
        else {
            di as text "{col 3}`lbl'" ///
                       "{col 26}" %9.4f `att_`gi'' ///
                       "{col 38}" %8.4f `se_`gi'' ///
                       "{col 49}" %8.0fc `n_`gi''
        }
    }
    
    // Total row
    di as text "{hline 70}"
    if "`showcontrib'" != "" & `contrib_warn' == 0 {
        di as text "{col 3}{bf:Total}" ///
                   "{col 26}" %9.4f `att_total' ///
                   "{col 38}" %8.4f `se_total' ///
                   "{col 49}" %10.2f cond(`att_total' > 0, 100, -100) ///
                   "{col 62}" %8.0fc `n_total'
    }
    else {
        di as text "{col 3}{bf:Total}" ///
                   "{col 26}" %9.4f `att_total' ///
                   "{col 38}" %8.4f `se_total' ///
                   "{col 49}" %8.0fc `n_total'
    }
    di as text "{hline 70}"
    
    // Note about contribution formula
    if "`showcontrib'" != "" {
        di as text "Contribution: C_i = (n_i/N) * ATT_i / |ATT_total| * 100"
    }
    
end
