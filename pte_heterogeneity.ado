*! pte_heterogeneity.ado
*! Heterogeneity analysis for pte package
*! Analyzes treatment effect heterogeneity across discrete groups (e.g., industry)

version 14.0
capture program drop pte_heterogeneity
program define pte_heterogeneity, eclass
    version 14.0
    local pte_cmdline `"pte_heterogeneity`0'"'
    
    // =========================================================================
    // Syntax parsing
    // =========================================================================
    syntax , BY(name) [test] [NOCONTribution] [Level(cilevel)] ///
             [TOLerance(real 1e-6)]

    capture confirm variable `by', exact
    if _rc != 0 {
        di as error "pte_heterogeneity: variable `by' not found"
        di as error "  by() must match an existing grouping variable exactly"
        exit 111
    }
    
    // =========================================================================
    // Default values
    // =========================================================================
    if "`level'" == "" local level = 95
    if `tolerance' <= 0 {
        di as error "tolerance() must be positive"
        exit 198
    }
    local by_label : variable label `by'
    if `"`by_label'"' == "" {
        local by_label "`by'"
    }
    local heterogeneity_title `"`by_label'-level Treatment Effects on Productivity"'

    // Store option flags as locals for downstream modules
    local do_test      = ("`test'" != "")
    local no_contrib   = ("`nocontribution'" != "")
    // =========================================================================
    // Temporary names
    // =========================================================================
    tempname att_matrix se_vector contribution ci_matrix
    tempname Q_stat Q_pvalue I2
    tempname group_info att_temp boot_matrix
    tempname att_total se_total n_total
    local valid_group_positions ""
    local valid_group_tokens ""
    
    // =========================================================================
    // Step 1: Validate prerequisites (pte has been run, by-variable exists, etc.)
    // =========================================================================
    _pte_het_validate, by(`by')
    
    // =========================================================================
    // Step 2: Parse grouping variable and identify unique groups
    // =========================================================================
    tempvar _pte_het_by_id
    capture confirm numeric variable `by'
    if _rc {
        _pte_het_parse_groups `by', generate(`_pte_het_by_id')
    }
    else {
        _pte_het_parse_groups `by'
    }
    local group_list "`r(group_list)'"
    local group_labels `"`r(group_labels)'"'
    local group_tokens `"`r(group_tokens)'"'
    local byvar_use "`r(byvar_use)'"
    local n_groups = r(n_groups)
    local by_is_string = (`"`byvar_use'"' != "`by'")
    capture confirm variable _pte_treat, exact
    if _rc != 0 {
        di as error "pte_heterogeneity requires the exact treated-support bridge _pte_treat"
        di as error "  re-run {bf:pte} on the current dataset before heterogeneity analysis"
        exit 111
    }
    _pte_validate_internal_state _pte_treat binary ///
        "pte_heterogeneity requires _pte_treat to remain the certified binary treated-support bridge."
    local treated_condition " & _pte_treat == 1"
    local treat_opt "treatvar(_pte_treat)"
    tempname attperiods
    tempvar supported_tt

    capture confirm matrix e(attperiods)
    if _rc != 0 {
        di as error "pte_heterogeneity requires e(attperiods)"
        di as error "  re-run {bf:pte} on the current dataset before heterogeneity analysis"
        exit 198
    }
    matrix `attperiods' = e(attperiods)
    local attperiods_cols = colsof(`attperiods')
    quietly _pte_attperiods_support `attperiods' `attperiods_cols' ///
        "pte_heterogeneity"
    local supported_periods `"`r(periodlist)'"'
    quietly gen int `supported_tt' = -1
    foreach ell of numlist `supported_periods' {
        quietly replace `supported_tt' = _pte_nt if _pte_nt == `ell'
    }
    local support_condition "`supported_tt' >= 0"

    quietly count if !missing(_pte_tt) & `support_condition'`treated_condition' & missing(`byvar_use')
    local total_missing_by_valid = r(N)
    if `total_missing_by_valid' > 0 {
        di as error "[pte] pte_heterogeneity requires by(`by') to be nonmissing on the exact supported treated TT sample"
        di as error "[pte] Found `total_missing_by_valid' supported treated TT observation(s) with missing by()."
        di as error "[pte] Fill the subgroup labels or repair the current dataset before replaying Table 2 heterogeneity."
        exit 198
    }
    
    // =========================================================================
    // Step 3: Compute group-specific ATT
    //   - Recompute from _pte_tt on the exact stored ATT support
    //   - Returns G x 3 matrix (ATT, SD, N) and total scalars
    // =========================================================================
    _pte_het_group_att, byvar(`byvar_use') groups(`group_list') ///
        ttvar(_pte_tt) ntvar(`supported_tt') `treat_opt'
    
    matrix `att_matrix' = r(att_matrix)
    local total_att = r(total_att)
    local total_sd  = r(total_sd)
    local total_n   = r(total_n)
    local total_se  = .

    // Keep only groups that actually contribute to the post-treatment TT
    // sample. The paper/DO Table 2 contract is defined on the exact stored ATT
    // support, so groups with N=0 must be excluded before downstream SE/test
    // logic.
    tempname att_matrix_valid
    local valid_group_list ""
    local valid_group_labels ""
    local valid_n_groups = 0
    local group_list_work `"`group_list'"'
    local group_labels_work `"`group_labels'"'
    local group_tokens_work `"`group_tokens'"'
    forvalues g = 1/`n_groups' {
        gettoken group_value group_list_work : group_list_work, quotes
        gettoken group_label group_labels_work : group_labels_work, quotes
        gettoken group_token group_tokens_work : group_tokens_work, quotes
        local group_n = `att_matrix'[`g', 3]
        if !missing(`group_n') & `group_n' > 0 {
            local ++valid_n_groups
            if `valid_n_groups' == 1 {
                matrix `att_matrix_valid' = `att_matrix'[`g', 1...]
            }
            else {
                matrix `att_matrix_valid' = `att_matrix_valid' \ `att_matrix'[`g', 1...]
            }

            local valid_group_list "`valid_group_list' `group_value'"
            local valid_group_positions "`valid_group_positions' `g'"
            local valid_group_labels `"`valid_group_labels' `"`group_label'"'"'
            if `by_is_string' {
                local current_group_token `"`group_token'"'
            }
            else {
                local current_group_token "`group_value'"
            }
            local _pte_valid_group_token_`valid_n_groups' `"`current_group_token'"'
            local valid_group_tokens `"`valid_group_tokens' `"`current_group_token'"'"'
        }
    }
    local valid_group_tokens = trim(`"`valid_group_tokens'"')

    if `valid_n_groups' < 2 {
        di as error "heterogeneity analysis requires at least 2 groups with valid TT observations on the exact stored ATT support"
        exit 498
    }

    matrix `att_matrix' = `att_matrix_valid'
    local group_list "`valid_group_list'"
    local group_labels `"`valid_group_labels'"'
    local n_groups = `valid_n_groups'
    if `by_is_string' {
        quietly levelsof `by' if !missing(_pte_tt) & `support_condition'`treated_condition' & !missing(`by'), ///
            local(valid_group_tokens)
        local group_labels `"`valid_group_tokens'"'
    }
    else {
        local valid_group_tokens = trim(`"`valid_group_list'"')
    }

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
    if `has_grouped_boot_contract' & `"`stored_groups'"' == "" {
        di as error "[pte] grouped bootstrap heterogeneity requires e(groups)"
        di as error "[pte] grouped bootstrap columns are indexed by the estimation-time group order."
        di as error "[pte] Re-run grouped pte before pte_heterogeneity so the exact group mapping is available."
        exit 198
    }
    if `has_grouped_boot_contract' & `"`stored_by'"' == "" {
        di as error "[pte] grouped bootstrap heterogeneity requires e(by)"
        di as error "[pte] grouped bootstrap columns are indexed by the estimation-time grouping variable and exact group order."
        di as error "[pte] Re-run grouped pte before pte_heterogeneity so the grouped route metadata are available."
        exit 198
    }
    if `has_grouped_boot_contract' & `"`stored_by'"' != "`by'" {
        di as error "[pte] grouped bootstrap heterogeneity was estimated with e(by)=`stored_by', not by(`by')"
        di as error "[pte] grouped bootstrap ATT draws cannot be remapped under a different grouping variable."
        di as error "[pte] Re-run grouped pte with by(`by') or call pte_heterogeneity with by(`stored_by')."
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
                        di as error "[pte] grouped bootstrap heterogeneity requires e(groups) to contain unique route tokens"
                        di as error "[pte] Stored e(groups) repeats the same route token at positions `_pte_left' and `_pte_right', so grouped bootstrap columns no longer have a one-to-one route."
                        di as error "[pte] Re-run grouped pte before pte_heterogeneity so e(groups) stays unique and position-identifying."
                        exit 198
                    }
                }
            }
        }
    }
    local boot_keep_positions ""
    local valid_token_idx = 0
    foreach keep_pos of numlist `valid_group_positions' {
        local ++valid_token_idx
        if `"`stored_groups'"' == "" {
            local boot_keep_positions "`boot_keep_positions' `keep_pos'"
            continue
        }
        if `by_is_string' {
            local stored_pos = 0
            local _pte_stored_idx = 0
            local _pte_stored_groups_work `"`stored_groups'"'
            while `"`_pte_stored_groups_work'"' != "" {
                gettoken _pte_stored_token _pte_stored_groups_work : _pte_stored_groups_work, quotes
                if `"`_pte_stored_token'"' == "" {
                    continue
                }
                local ++_pte_stored_idx
                if `"`_pte_stored_token'"' == `"`_pte_valid_group_token_`valid_token_idx''"' {
                    local stored_pos = `_pte_stored_idx'
                    continue, break
                }
            }
        }
        else {
            local stored_pos : list posof `"`_pte_valid_group_token_`valid_token_idx''"' in stored_groups
        }
        if `stored_pos' < 1 {
            local missing_token `"`_pte_valid_group_token_`valid_token_idx''"'
            di as error `"[pte] grouped result token `missing_token' is missing from the stored e(groups) contract"'
            di as error "[pte] grouped bootstrap heterogeneity cannot remap retained Table 2 groups without an exact one-to-one stored route."
            exit 198
        }
        local boot_keep_positions "`boot_keep_positions' `stored_pos'"
    }

    // The Total-row SE should follow the live pte overall ATT contract
    // whenever that bundle is available; otherwise fall back to the pooled
    // TT standard error so standalone helper contexts remain usable.
    local has_live_att_se = 0
    capture confirm matrix e(att_se)
    if !_rc & `total_missing_by_valid' == 0 {
        local has_live_att_se = 1
        tempname att_se_live
        matrix `att_se_live' = e(att_se)
        tempname attperiods_live_check
        matrix `attperiods_live_check' = e(attperiods)
        local total_se_col = colsof(`att_se_live')
        quietly _pte_dynamic_colstripe_contract `att_se_live' `attperiods_live_check' ///
            `attperiods_cols' "pte_heterogeneity total SE replay" "e(att_se)"
        if `total_se_col' <= `attperiods_cols' {
            di as error "[pte] pte_heterogeneity requires the pooled ATT_avg standard error when live e(att_se) is posted."
            di as error "[pte] The live pooled ATT inference bundle is incomplete: e(att_se) has `total_se_col' column(s) for `attperiods_cols' supported event time(s)."
            di as error "[pte] Re-run pte so the pooled ATT_avg inference bundle remains complete, or drop the stale live e(att_se) helper state before replaying Table 2."
            exit 198
        }
        if `total_se_col' >= 1 {
            local total_se = `att_se_live'[1, `total_se_col']
        }
        if missing(`total_se') {
            di as error "[pte] pte_heterogeneity requires the pooled ATT_avg standard error when live e(att_se) is posted."
            di as error "[pte] The live pooled ATT inference bundle is incomplete: e(att_se)[1, `total_se_col'] is missing."
            di as error "[pte] Re-run pte so the pooled ATT_avg inference bundle remains complete, or drop the stale live e(att_se) helper state before replaying Table 2."
            exit 198
        }
    }
    if !`has_live_att_se' & missing(`total_se') {
        if `total_n' > 0 {
            local total_se = `total_sd' / sqrt(`total_n')
        }
    }
    
    // =========================================================================
    // Step 4: Compute Bootstrap standard errors
    //   - Inherit grouped bootstrap ATT draws via the shared bridge helper
    //     (e(att_boot_bygroup) when present, otherwise rebuilt from e(att_boot_g#))
    //   - SE_g = sd(boot_samples[.,g])
    // =========================================================================
    _pte_het_bootstrap_se, n_groups(`n_groups') keep(`boot_keep_positions')
    tempname se_vector
    matrix `se_vector' = r(se_vector)
    local nboot = r(nboot)
    local se_method "`r(method)'"
    local nboot_opt ""
    if "`nboot'" != "" {
        if !missing(`nboot') & `nboot' > 0 {
            local nboot_opt "nboot(`nboot')"
        }
    }
    
    // =========================================================================
    // Step 5: Compute contribution rates (unless nocontribution specified)
    //   - Contribution_g = (n_g / N) * ATT_g / |ATT_total| * 100
    //   - Warn if |ATT_total| < tolerance
    // =========================================================================
    local contrib_valid = 0
    local emit_contrib = !`no_contrib'
    local total_contrib = .
    if !`no_contrib' {
        _pte_het_contribution, att_matrix(`att_matrix') ///
            total_att(`total_att') total_n(`total_n') ///
            tolerance(`tolerance')
        matrix `contribution' = r(contribution)
        local contrib_valid = r(is_valid)
        if `contrib_valid' {
            local total_contrib = cond(`total_att' > 0, 100, -100)
        }
    }
    
    // =========================================================================
    // Step 6: Compute confidence intervals
    //   - Normal-based: ATT_g +/- z_{alpha/2} * SE_g
    // =========================================================================
    _pte_het_ci, att_matrix(`att_matrix') se_vector(`se_vector') level(`level')
    matrix `ci_matrix' = r(ci_matrix)
    
    // =========================================================================
    // Step 7: Heterogeneity test (optional, if test specified)
    // =========================================================================
    local Q_val = .
    local Q_p_val = .
    local I2_val = .
    local df_val = .
    if `do_test' {
        _pte_het_test_interface, att_matrix(`att_matrix') ///
            se_vector(`se_vector') n_groups(`n_groups') level(`level')
        local Q_val = r(Q_stat)
        local Q_p_val = r(Q_pvalue)
        local I2_val = r(I2)
        local df_val = r(df)
    }
    
    // =========================================================================
    // Step 8: Build result matrices
    //   - att_by_group: (G+1) x 4 matrix [ATT, SE, Contribution(%), N]
    //   - Row labels: group values + "Total"
    // =========================================================================
    if `emit_contrib' {
        _pte_het_matrix, attmat(`att_matrix') sevec(`se_vector') ///
            contrib(`contribution') ///
            totatt(`total_att') totse(`total_se') totn(`total_n') ///
            labels(`"`group_labels'"')
    }
    else {
        _pte_het_matrix, attmat(`att_matrix') sevec(`se_vector') ///
            totatt(`total_att') totse(`total_se') totn(`total_n') ///
            labels(`"`group_labels'"')
    }
    tempname result_matrix
    matrix `result_matrix' = r(result)
    capture matrix drop _pte_het_result_display
    matrix _pte_het_result_display = `result_matrix'
    local rownames "`r(rownames)'"
    
    local test_opts ""
    if `do_test' {
        local test_opts "tested(1) q_stat(`Q_val') q_pvalue(`Q_p_val') i2(`I2_val') df(`df_val')"
    }

    // =========================================================================
    // Step 9: Store e() return values
    // =========================================================================
    if `emit_contrib' {
        _pte_het_ereturn, result(`result_matrix') se(`se_vector') ///
            contrib(`contribution') ci(`ci_matrix') ///
            byvar(`by') labels(`"`group_labels'"') n_groups(`n_groups') ///
            grouptokens(`"`valid_group_tokens'"') level(`level') `nboot_opt' ///
            cmdline(`"`pte_cmdline'"') ///
            bootkeep(`boot_keep_positions') ///
            `test_opts'
    }
    else {
        _pte_het_ereturn, result(`result_matrix') se(`se_vector') ///
            ci(`ci_matrix') ///
            byvar(`by') labels(`"`group_labels'"') n_groups(`n_groups') ///
            grouptokens(`"`valid_group_tokens'"') level(`level') `nboot_opt' ///
            cmdline(`"`pte_cmdline'"') ///
            bootkeep(`boot_keep_positions') ///
            `test_opts'
    }

    // =========================================================================
    // Step 10: Formatted output display (Table 2 format)
    // =========================================================================
    if `do_test' {
        _pte_het_output, matrix(_pte_het_result_display) labels(`"`group_labels'"') ///
            level(`level') byvar(`by') test `nboot_opt'
    }
    else {
        _pte_het_output, matrix(_pte_het_result_display) labels(`"`group_labels'"') ///
            level(`level') byvar(`by') `nboot_opt'
    }
    capture matrix drop _pte_het_result_display
    
end
