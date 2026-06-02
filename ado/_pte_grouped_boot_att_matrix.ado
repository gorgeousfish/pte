*! _pte_grouped_boot_att_matrix.ado
*! Recover grouped bootstrap ATT draws from e()

version 14.0
capture program drop _pte_grouped_boot_att_matrix
program define _pte_grouped_boot_att_matrix, rclass
    version 14.0

    syntax [, KEEP(numlist integer min=1) ATTPERIOD(integer 2147483647)]

    tempname boot_mat first_group group_draws periods
    local use_attperiod = (`attperiod' != 2147483647)
    local selected_col = .

    local ngroups = 0
    local grouped_labels `"`e(groups)'"'
    if `"`grouped_labels'"' != "" & `"`grouped_labels'"' != "." {
        local ngroups : word count `grouped_labels'
    }

    capture local ngroups_macro = e(ngroups)
    if `ngroups' < 1 & ///
        "`ngroups_macro'" != "" & "`ngroups_macro'" != "." {
        local ngroups = `ngroups_macro'
    }
    capture local n_groups_macro = e(n_groups)
    if `ngroups' < 1 & ///
        "`n_groups_macro'" != "" & "`n_groups_macro'" != "." {
        local ngroups = `n_groups_macro'
    }

    capture confirm matrix e(att_boot_bygroup)
    local has_boot_bygroup = (_rc == 0)
    if !`use_attperiod' & `has_boot_bygroup' {
        matrix `boot_mat' = e(att_boot_bygroup)
        local pooled_cols = colsof(`boot_mat')
        if `ngroups' > 0 & `pooled_cols' != `ngroups' {
            di as error "[pte] pooled grouped bootstrap sidecar e(att_boot_bygroup) must have exactly one column per stored group token"
            di as error "[pte] Stored e(groups) count is `ngroups', but colsof(e(att_boot_bygroup)) = `pooled_cols'."
            di as error "[pte] Re-run grouped pte or repost a synchronized pooled grouped-bootstrap shell before replaying heterogeneity."
            exit 198
        }
        local pooled_boot_cnames : colnames `boot_mat'
        if `"`pooled_boot_cnames'"' != "" {
            local canonical_short ""
            local canonical_long ""
            forvalues g = 1/`pooled_cols' {
                local canonical_short "`canonical_short' g`g'"
                local canonical_long "`canonical_long' group`g'"
            }
            local canonical_short = trim(`"`canonical_short'"')
            local canonical_long = trim(`"`canonical_long'"')
            if `"`pooled_boot_cnames'"' != `"`canonical_short'"' & ///
                `"`pooled_boot_cnames'"' != `"`canonical_long'"' {
                di as error "[pte] pooled grouped bootstrap sidecar e(att_boot_bygroup) must preserve canonical grouped column order"
                di as error `"[pte] Expected column names `"`canonical_short'"' (or legacy alias `"`canonical_long'"'), got `"`pooled_boot_cnames'"'."'
                di as error "[pte] Re-run grouped pte or repost e(att_boot_bygroup) without reordering or renaming grouped bootstrap columns."
                exit 198
            }
        }
        local source "att_boot_bygroup"
    }
    else {

        if `ngroups' < 1 {
            forvalues g = 1/999 {
                capture confirm matrix e(att_boot_g`g')
                if _rc {
                    continue, break
                }
                local ngroups = `g'
            }
        }

        if `ngroups' < 1 {
            exit 111
        }

        local use_trim = 0
        local notrimeps_flag ""
        capture local notrimeps_flag `"`e(notrimeps)'"'
        if _rc != 0 | `"`notrimeps_flag'"' == "." {
            local notrimeps_flag ""
        }
        if `"`notrimeps_flag'"' == "" {
            capture confirm matrix e(att_trim_boot_g1)
            if _rc == 0 {
                matrix `first_group' = e(att_trim_boot_g1)
                local use_trim = 1
            }
        }
        if `use_trim' == 0 {
            capture confirm matrix e(att_boot_g1)
            if _rc {
                if `use_attperiod' & `has_boot_bygroup' {
                    di as error "[pte] nt()-specific grouped bootstrap replay cannot use pooled e(att_boot_bygroup) sidecars."
                    di as error "[pte] Re-run grouped pte so period-specific e(att_boot_g#) / e(att_trim_boot_g#) draws remain available."
                    exit 198
                }
                exit 111
            }
            matrix `first_group' = e(att_boot_g1)
        }

        local nboot = rowsof(`first_group')
        local lastcol = colsof(`first_group')
        if `nboot' < 1 | `lastcol' < 1 {
            exit 503
        }

        if `use_attperiod' {
            capture confirm matrix e(attperiods)
            if _rc {
                di as error "[pte] nt()-specific grouped bootstrap replay requires e(attperiods)."
                di as error "[pte] Re-run grouped pte so event-time support is stored alongside grouped bootstrap draws."
                exit 198
            }
            matrix `periods' = e(attperiods)
            local dyncols = `lastcol' - 1
            quietly _pte_attperiods_support `periods' `dyncols' ///
                "pte_graph, heterogeneity grouped bootstrap replay"
            matrix `periods' = r(periods)
            local _pte_first_src = cond(`use_trim', "e(att_trim_boot_g1)", "e(att_boot_g1)")
            quietly _pte_dynamic_colstripe_contract `first_group' `periods' `dyncols' ///
                "pte_graph, heterogeneity grouped bootstrap replay" ///
                "`_pte_first_src'"
            local selected_col = 0
            forvalues j = 1/`=colsof(`periods')' {
                if `periods'[1, `j'] == `attperiod' {
                    local selected_col = `j'
                    continue, break
                }
            }
            if `selected_col' < 1 {
                di as error "[pte] requested nt(`attperiod') is not part of the stored e(attperiods) support."
                exit 198
            }
        }

        matrix `boot_mat' = J(`nboot', `ngroups', .)
        local colnames ""
        forvalues g = 1/`ngroups' {
            if `use_trim' {
                capture confirm matrix e(att_trim_boot_g`g')
                if _rc {
                    di as error "[pte] grouped bootstrap trim draw matrix e(att_trim_boot_g`g') not found"
                    exit 111
                }
                matrix `group_draws' = e(att_trim_boot_g`g')
            }
            else {
                capture confirm matrix e(att_boot_g`g')
                if _rc {
                    exit 111
                }
                matrix `group_draws' = e(att_boot_g`g')
            }
            if rowsof(`group_draws') != `nboot' {
                di as error "[pte] grouped bootstrap ATT draws have inconsistent replication counts"
                local _pte_src = cond(`use_trim', "att_trim_boot_g`g'", "att_boot_g`g'")
                di as error "[pte] Expected rowsof(e(`_pte_src')) = `nboot', got " rowsof(`group_draws')
                exit 503
            }
            if colsof(`group_draws') < 1 {
                local _pte_src = cond(`use_trim', "att_trim_boot_g`g'", "att_boot_g`g'")
                di as error "[pte] grouped bootstrap ATT draw matrix e(`_pte_src') is empty"
                exit 503
            }
            local lastcol = colsof(`group_draws')
            local draw_col = `lastcol'
            if `use_attperiod' {
                if `lastcol' != colsof(`first_group') {
                    di as error "[pte] grouped bootstrap ATT draw matrices have inconsistent column counts"
                    local _pte_src = cond(`use_trim', "att_trim_boot_g`g'", "att_boot_g`g'")
                    di as error "[pte] Expected colsof(e(`_pte_src')) = " colsof(`first_group') ", got " `lastcol'
                    exit 503
                }
                local _pte_src = cond(`use_trim', "e(att_trim_boot_g`g')", "e(att_boot_g`g')")
                quietly _pte_dynamic_colstripe_contract `group_draws' `periods' `dyncols' ///
                    "pte_graph, heterogeneity grouped bootstrap replay" ///
                    "`_pte_src'"
                local draw_col = `selected_col'
            }
            forvalues b = 1/`nboot' {
                matrix `boot_mat'[`b', `g'] = el(`group_draws', `b', `draw_col')
            }
            local colnames "`colnames' group`g'"
        }
        matrix colnames `boot_mat' = `colnames'
        if `use_attperiod' {
            local source = cond(`use_trim', "att_trim_boot_g[nt=`attperiod']", "att_boot_g[nt=`attperiod']")
        }
        else {
            local source = cond(`use_trim', "att_trim_boot_g", "att_boot_g")
        }
    }

    if "`keep'" != "" {
        local _pte_keep_work "`keep'"
        local _pte_keep_idx = 0
        while "`_pte_keep_work'" != "" {
            gettoken _pte_keep_src _pte_keep_work : _pte_keep_work
            if "`_pte_keep_src'" == "" {
                continue
            }
            local ++_pte_keep_idx
            local _pte_keep_token_`_pte_keep_idx' "`_pte_keep_src'"
        }
        if `_pte_keep_idx' > 1 {
            forvalues _pte_left = 1/`=`_pte_keep_idx' - 1' {
                forvalues _pte_right = `=`_pte_left' + 1'/`_pte_keep_idx' {
                    if "`_pte_keep_token_`_pte_left''" == "`_pte_keep_token_`_pte_right''" {
                        local _pte_keep_repeat "`_pte_keep_token_`_pte_left''"
                        di as error "[pte] grouped bootstrap keep() must contain unique column positions"
                        di as error `"[pte] keep() repeats grouped bootstrap column `"`_pte_keep_repeat'"', which would clone one stored draw column under multiple groups."'
                        di as error "[pte] Recompute the grouped route so each retained group maps to exactly one bootstrap column."
                        exit 198
                    }
                }
            }
        }
        local keep_count : word count `keep'
        tempname selected
        matrix `selected' = J(rowsof(`boot_mat'), `keep_count', .)
        local colnames ""
        local keep_j = 0
        foreach src of numlist `keep' {
            local ++keep_j
            if `src' > colsof(`boot_mat') {
                di as error "[pte] requested grouped bootstrap column `src' exceeds available columns " colsof(`boot_mat')
                exit 503
            }
            forvalues b = 1/`=rowsof(`boot_mat')' {
                matrix `selected'[`b', `keep_j'] = `boot_mat'[`b', `src']
            }
            local colnames "`colnames' group`src'"
        }
        matrix colnames `selected' = `colnames'
        matrix `boot_mat' = `selected'
    }

    local nboot_out = rowsof(`boot_mat')
    local ngroups_out = colsof(`boot_mat')
    return matrix boot_mat = `boot_mat'
    return scalar nboot = `nboot_out'
    return scalar ngroups = `ngroups_out'
    return local source "`source'"
end
