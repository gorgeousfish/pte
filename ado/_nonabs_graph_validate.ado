*! Validation subroutine for _pte_graph_att_nonabs

version 14.0
program define _nonabs_graph_validate, rclass
    version 14.0
    
    syntax , CI(string) [LEvel(integer 95) ABSorbing ATTDIFF]
    
    * Check pte command was run
    if !inlist("`e(cmd)'", "pte", "_pte_bootstrap_nonabs") {
        di as error "Error: Run {bf:pte} command first."
        exit 198
    }
    
    * Check treatment type
    local _pte_trt_type = lower("`e(trt_type)'")
    if "`_pte_trt_type'" == "" {
        local _pte_trt_type = lower("`e(treatment_type)'")
    }
    if "`_pte_trt_type'" == "" & "`e(cmd)'" == "_pte_bootstrap_nonabs" {
        capture confirm matrix e(att_plus)
        local _pte_has_att_plus = (_rc == 0)
        capture confirm matrix e(att_minus)
        local _pte_has_att_minus = (_rc == 0)
        if `_pte_has_att_plus' & `_pte_has_att_minus' {
            local _pte_trt_type "nonabsorbing"
        }
        else if `_pte_has_att_plus' | `_pte_has_att_minus' {
            local _pte_nonabs_one_sided_side "ATT- only"
            if `_pte_has_att_plus' {
                local _pte_nonabs_one_sided_side "ATT+ only"
            }
            di as error "Error: one-sided nonabsorbing helper bundle detected (`_pte_nonabs_one_sided_side')."
            di as error "Direct nonabsorbing ATT graphs require both e(att_plus) and e(att_minus)."
            di as error "This helper bundle is not an absorbing e(att) result and cannot be graphed by _pte_graph_att_nonabs."
            exit 198
        }
    }

    if !inlist("`_pte_trt_type'", "non-absorbing", "nonabsorbing") & "`absorbing'" == "" {
        di as error "Error: Data is from absorbing treatment."
        di as error "Use {bf:pte_graph, att} for absorbing treatment results."
        exit 198
    }
    
    * Validate level()
    if `level' < 10 | `level' > 99 {
        di as error "Error: level() must be between 10 and 99."
        exit 198
    }
    
    * Validate ci() option
    if !inlist("`ci'", "area", "rcap", "rspike", "none") {
        di as error "Error: ci() must be area, rcap, rspike, or none."
        exit 198
    }
    
    * Check required matrices (error if missing)
    foreach mat in att_plus att_minus {
        capture confirm matrix e(`mat')
        if _rc != 0 {
            di as error "Error: Matrix e(`mat') not found."
            di as error "Ensure {bf:pte} was run with {bf:nonabsorbing} option."
            exit 111
        }
    }
    
    * Check optional SE matrices (warn and degrade if missing)
    local has_se 1
    foreach mat in att_plus_se att_minus_se {
        capture confirm matrix e(`mat')
        if _rc != 0 {
            if "`attdiff'" == "" {
                di as text "Warning: e(`mat') not found. ATT+ / ATT- CI will not be displayed."
            }
            else {
                di as text "Warning: e(`mat') not found. Side ATT CI is unavailable; attdiff CI will use dedicated difference payload if posted."
            }
            local has_se 0
        }
    }
    
    * Check dimension consistency
    local nr_plus = rowsof(e(att_plus))
    local nr_minus = rowsof(e(att_minus))
    if `nr_plus' != `nr_minus' {
        di as error "Error: ATT+ and ATT- dimensions mismatch"
        di as error "  ATT+ has `nr_plus' rows, ATT- has `nr_minus' rows"
        exit 459
    }

    * Explicit nt support, when posted in column 4, must be shared across
    * ATT+ and ATT- so downstream graphs can preserve the producer horizon.
    local nc_plus = colsof(e(att_plus))
    local nc_minus = colsof(e(att_minus))
    local plus_shape_class = inlist(`nc_plus', 1, 4)
    local minus_shape_class = inlist(`nc_minus', 1, 4)
    if !`plus_shape_class' | !`minus_shape_class' {
        di as error "Error: Non-absorbing ATT payloads must be either pure ATT vectors or exact canonical [ATT, SD, N, nt] matrices."
        di as error "  Partial 2- or 3-column payloads and orphan extra columns are not supported."
        exit 198
    }
    local has_nt = 0
    local plus_has_nt = (`nc_plus' == 4)
    local minus_has_nt = (`nc_minus' == 4)
    if `plus_has_nt' != `minus_has_nt' {
        di as error "Error: ATT+ and ATT- must either both publish explicit nt support or both omit it."
        exit 198
    }
    if `plus_has_nt' & `minus_has_nt' {
        local plus_cnames : colnames e(att_plus)
        local minus_cnames : colnames e(att_minus)
        local plus_rnames : rownames e(att_plus)
        local minus_rnames : rownames e(att_minus)
        local plus_cnames : list retokenize plus_cnames
        local minus_cnames : list retokenize minus_cnames
        local plus_rnames : list retokenize plus_rnames
        local minus_rnames : list retokenize minus_rnames
        local plus_cnames = lower("`plus_cnames'")
        local minus_cnames = lower("`minus_cnames'")
        if "`plus_cnames'" != "att_plus sd n nt" {
            di as error "Error: e(att_plus) must use the exact canonical column order [ATT_plus, SD, N, nt]."
            exit 198
        }
        if "`minus_cnames'" != "att_minus sd n nt" {
            di as error "Error: e(att_minus) must use the exact canonical column order [ATT_minus, SD, N, nt]."
            exit 198
        }
        local prev_nt = .
        forvalues i = 1/`nr_plus' {
            if e(att_plus)[`i', 4] != e(att_minus)[`i', 4] {
                di as error "Error: ATT+ and ATT- must share the same nt support."
                exit 198
            }
            local nt_val = e(att_plus)[`i', 4]
            local expected_rname = lower("nt`nt_val'")
            local plus_rname_i : word `i' of `plus_rnames'
            local minus_rname_i : word `i' of `minus_rnames'
            local plus_rname_i = lower("`plus_rname_i'")
            local minus_rname_i = lower("`minus_rname_i'")
            if "`plus_rname_i'" == "" | "`minus_rname_i'" == "" {
                di as error "Error: canonical non-absorbing ATT payloads must publish rownames that match the nt support."
                exit 198
            }
            if "`plus_rname_i'" != "`expected_rname'" | "`minus_rname_i'" != "`expected_rname'" {
                di as error "Error: canonical non-absorbing ATT payload rownames must match the posted nt support row by row."
                exit 198
            }
            if `i' > 1 & `nt_val' <= `prev_nt' {
                di as error "Error: canonical non-absorbing nt support must be strictly increasing and unique."
                exit 198
            }
            local prev_nt = `nt_val'
        }
        local has_nt = 1
    }
    local allow_explicit_side_support = `has_nt'
    local fallback_nt_support ""
    if !`allow_explicit_side_support' {
        forvalues i = 0/`=`nr_plus' - 1' {
            local fallback_nt_support "`fallback_nt_support' nt`i'"
        }
        local fallback_nt_support = strtrim("`fallback_nt_support'")
        foreach mat in att_plus att_minus {
            local main_row_support : rownames e(`mat')
            local main_row_support = strtrim("`main_row_support'")
            local main_row_tokens : word count `main_row_support'
            local main_row_is_nt = (`main_row_tokens' == `nr_plus')
            if `main_row_is_nt' {
                forvalues i = 1/`main_row_tokens' {
                    local main_row_tok : word `i' of `main_row_support'
                    if !regexm(lower("`main_row_tok'"), "^nt-?[0-9]+$") {
                        local main_row_is_nt = 0
                    }
                }
            }
            if `main_row_is_nt' & "`main_row_support'" != "`fallback_nt_support'" {
                di as error "Error: 1-column non-absorbing ATT payloads cannot publish explicit nt rownames unless they match the fallback dense route implied by row order."
                exit 198
            }
        }
    }

    * Helper bootstrap draw matrices, when posted, are part of the same
    * non-absorbing horizon contract used by attdiff replay.
    local has_boot_plus = 0
    local has_boot_minus = 0
    capture confirm matrix e(att_plus_boot)
    if _rc == 0 local has_boot_plus = 1
    capture confirm matrix e(att_minus_boot)
    if _rc == 0 local has_boot_minus = 1
    if `has_boot_plus' | `has_boot_minus' {
        if `has_boot_plus' != `has_boot_minus' {
            di as error "Error: helper bootstrap draw matrices for ATT+ and ATT- must be posted as a matched pair."
            exit 198
        }

        local plus_boot_cols = colsof(e(att_plus_boot))
        local minus_boot_cols = colsof(e(att_minus_boot))
        if `plus_boot_cols' != `nr_plus' | `minus_boot_cols' != `nr_minus' {
            di as error "Error: helper bootstrap draw matrices must match the ATT horizon width."
            exit 198
        }

        local plus_boot_cnames : colnames e(att_plus_boot)
        local minus_boot_cnames : colnames e(att_minus_boot)
        if !`allow_explicit_side_support' {
            foreach boot_support in plus_boot_cnames minus_boot_cnames {
                local orphan_boot_support = strtrim("``boot_support''")
                local orphan_boot_tokens : word count `orphan_boot_support'
                local orphan_boot_is_nt = (`orphan_boot_tokens' == `nr_plus')
                if `orphan_boot_is_nt' {
                    forvalues i = 1/`orphan_boot_tokens' {
                        local orphan_boot_tok : word `i' of `orphan_boot_support'
                        if !regexm(lower("`orphan_boot_tok'"), "^nt-?[0-9]+$") {
                            local orphan_boot_is_nt = 0
                        }
                    }
                }
                if `orphan_boot_is_nt' & "`orphan_boot_support'" != "`fallback_nt_support'" {
                    di as error "Error: helper bootstrap draw matrices cannot publish explicit nt support unless e(att_plus)/e(att_minus) do so canonically."
                    exit 198
                }
            }
        }

        if `has_nt' {
            if "`plus_boot_cnames'" == "" | "`minus_boot_cnames'" == "" {
                di as error "Error: helper bootstrap draw matrices must publish explicit nt colnames."
                exit 198
            }
            if "`plus_boot_cnames'" != "`minus_boot_cnames'" {
                di as error "Error: helper bootstrap draw matrices must share the same nt colnames."
                exit 198
            }
            local expected_boot_cnames ""
            forvalues i = 1/`nr_plus' {
                local nt_val = e(att_plus)[`i', 4]
                local expected_boot_cnames "`expected_boot_cnames' nt`nt_val'"
            }
            local expected_boot_cnames = strtrim("`expected_boot_cnames'")
            if "`plus_boot_cnames'" != "`expected_boot_cnames'" {
                di as error "Error: helper bootstrap draw matrices must align with the canonical nt support posted in e(att_plus)/e(att_minus)."
                exit 198
            }
        }
    }
    
    * Check SE dimensions if available
    if `has_se' {
        local nr_se_p = rowsof(e(att_plus_se))
        local nr_se_m = rowsof(e(att_minus_se))
        local nc_se_p = colsof(e(att_plus_se))
        local nc_se_m = colsof(e(att_minus_se))
        local plus_shape_ok = (`nr_se_p' == `nr_plus' & `nc_se_p' == 1) | ///
            (`nr_se_p' == 1 & `nc_se_p' == `nr_plus')
        local minus_shape_ok = (`nr_se_m' == `nr_minus' & `nc_se_m' == 1) | ///
            (`nr_se_m' == 1 & `nc_se_m' == `nr_minus')
        if !`plus_shape_ok' | !`minus_shape_ok' {
            di as text "Warning: SE matrix dimensions mismatch. CI disabled."
            local has_se 0
        }
        else if !`allow_explicit_side_support' {
            foreach mat in att_plus_se att_minus_se {
                local nr_side = rowsof(e(`mat'))
                local nc_side = colsof(e(`mat'))
                local side_support ""
                if `nr_side' == 1 & `nc_side' == `nr_plus' {
                    local side_support : colnames e(`mat')
                }
                else {
                    local side_support : rownames e(`mat')
                }
                local side_support = strtrim("`side_support'")
                if "`side_support'" == "" {
                    di as error "Error: side SE matrices must publish explicit nt support labels when the main ATT payload posts canonical nt support."
                    exit 198
                }
                local side_tokens : word count `side_support'
                local side_is_nt = (`side_tokens' == `nr_plus')
                if `side_is_nt' {
                    forvalues i = 1/`side_tokens' {
                        local side_tok : word `i' of `side_support'
                        if !regexm(lower("`side_tok'"), "^nt-?[0-9]+$") {
                            local side_is_nt = 0
                        }
                    }
                }
                if `side_is_nt' & "`side_support'" != "`fallback_nt_support'" {
                    di as error "Error: side SE matrices cannot publish explicit nt support unless e(att_plus)/e(att_minus) do so canonically."
                    exit 198
                }
            }
        }
        else {
            local expected_se_support ""
            forvalues i = 1/`nr_plus' {
                local nt_val = e(att_plus)[`i', 4]
                local expected_se_support "`expected_se_support' nt`nt_val'"
            }
            local expected_se_support = strtrim("`expected_se_support'")
            foreach mat in att_plus_se att_minus_se {
                local nr_side = rowsof(e(`mat'))
                local nc_side = colsof(e(`mat'))
                local side_support ""
                if `nr_side' == 1 & `nc_side' == `nr_plus' {
                    local side_support : colnames e(`mat')
                }
                else {
                    local side_support : rownames e(`mat')
                }
                local side_support = strtrim("`side_support'")
                if "`side_support'" == "" {
                    di as error "Error: side SE matrices must publish explicit nt support labels when the main ATT payload posts canonical nt support."
                    exit 198
                }
                if "`side_support'" != "`expected_se_support'" {
                    di as error "Error: side SE matrices must align with the canonical nt support posted in e(att_plus)/e(att_minus)."
                    exit 198
                }
            }
        }
    }

    * Bootstrap CI matrices, when present, must be published as matched
    * pairs for both ATT+ and ATT- and must cover the plotted horizon.
    local has_ci_plus_lo = 0
    local has_ci_plus_hi = 0
    local has_ci_minus_lo = 0
    local has_ci_minus_hi = 0
    capture confirm matrix e(att_plus_ci_lower)
    if _rc == 0 local has_ci_plus_lo = 1
    capture confirm matrix e(att_plus_ci_upper)
    if _rc == 0 local has_ci_plus_hi = 1
    capture confirm matrix e(att_minus_ci_lower)
    if _rc == 0 local has_ci_minus_lo = 1
    capture confirm matrix e(att_minus_ci_upper)
    if _rc == 0 local has_ci_minus_hi = 1

    local any_boot_ci = `has_ci_plus_lo' | `has_ci_plus_hi' | `has_ci_minus_lo' | `has_ci_minus_hi'
    local has_boot_ci = 0
    if `any_boot_ci' {
        if `has_ci_plus_lo' != `has_ci_plus_hi' {
            di as error "Error: e(att_plus_ci_lower) and e(att_plus_ci_upper) must be posted as a matched pair."
            exit 198
        }
        if `has_ci_minus_lo' != `has_ci_minus_hi' {
            di as error "Error: e(att_minus_ci_lower) and e(att_minus_ci_upper) must be posted as a matched pair."
            exit 198
        }
        if !(`has_ci_plus_lo' & `has_ci_plus_hi' & `has_ci_minus_lo' & `has_ci_minus_hi') {
            di as error "Error: Non-absorbing bootstrap CI payload must cover both ATT+ and ATT-."
            exit 198
        }

        local nr_ci_p_lo = rowsof(e(att_plus_ci_lower))
        local nc_ci_p_lo = colsof(e(att_plus_ci_lower))
        local nr_ci_p_hi = rowsof(e(att_plus_ci_upper))
        local nc_ci_p_hi = colsof(e(att_plus_ci_upper))
        local nr_ci_m_lo = rowsof(e(att_minus_ci_lower))
        local nc_ci_m_lo = colsof(e(att_minus_ci_lower))
        local nr_ci_m_hi = rowsof(e(att_minus_ci_upper))
        local nc_ci_m_hi = colsof(e(att_minus_ci_upper))

        local plus_ci_shape_ok = ///
            ((`nr_ci_p_lo' == `nr_plus' & `nc_ci_p_lo' == 1) | (`nr_ci_p_lo' == 1 & `nc_ci_p_lo' == `nr_plus')) & ///
            ((`nr_ci_p_hi' == `nr_plus' & `nc_ci_p_hi' == 1) | (`nr_ci_p_hi' == 1 & `nc_ci_p_hi' == `nr_plus'))
        local minus_ci_shape_ok = ///
            ((`nr_ci_m_lo' == `nr_minus' & `nc_ci_m_lo' == 1) | (`nr_ci_m_lo' == 1 & `nc_ci_m_lo' == `nr_minus')) & ///
            ((`nr_ci_m_hi' == `nr_minus' & `nc_ci_m_hi' == 1) | (`nr_ci_m_hi' == 1 & `nc_ci_m_hi' == `nr_minus'))
        if !`plus_ci_shape_ok' | !`minus_ci_shape_ok' {
            di as error "Error: bootstrap CI matrix dimensions must match ATT+ and ATT- horizons."
            exit 198
        }
        if !`allow_explicit_side_support' {
            foreach mat in att_plus_ci_lower att_plus_ci_upper att_minus_ci_lower att_minus_ci_upper {
                local nr_ci = rowsof(e(`mat'))
                local nc_ci = colsof(e(`mat'))
                local ci_support ""
                if `nr_ci' == 1 & `nc_ci' == `nr_plus' {
                    local ci_support : colnames e(`mat')
                }
                else {
                    local ci_support : rownames e(`mat')
                }
                local ci_support = strtrim("`ci_support'")
                local ci_tokens : word count `ci_support'
                local ci_is_nt = (`ci_tokens' == `nr_plus')
                if `ci_is_nt' {
                    forvalues i = 1/`ci_tokens' {
                        local ci_tok : word `i' of `ci_support'
                        if !regexm(lower("`ci_tok'"), "^nt-?[0-9]+$") {
                            local ci_is_nt = 0
                        }
                    }
                }
                if `ci_is_nt' & "`ci_support'" != "`fallback_nt_support'" {
                    di as error "Error: bootstrap CI matrices cannot publish explicit nt support unless e(att_plus)/e(att_minus) do so canonically."
                    exit 198
                }
            }
        }
        if `has_nt' {
            local expected_ci_support ""
            forvalues i = 1/`nr_plus' {
                local nt_val = e(att_plus)[`i', 4]
                local expected_ci_support "`expected_ci_support' nt`nt_val'"
            }
            local expected_ci_support = strtrim("`expected_ci_support'")

            foreach mat in att_plus_ci_lower att_plus_ci_upper att_minus_ci_lower att_minus_ci_upper {
                local nr_ci = rowsof(e(`mat'))
                local nc_ci = colsof(e(`mat'))
                local ci_support ""
                if `nr_ci' == 1 & `nc_ci' == `nr_plus' {
                    local ci_support : colnames e(`mat')
                }
                else {
                    local ci_support : rownames e(`mat')
                }
                local ci_support = strtrim("`ci_support'")
                if "`ci_support'" == "" {
                    di as error "Error: bootstrap CI matrices must publish explicit nt support labels when the main ATT payload posts canonical nt support."
                    exit 198
                }
                if "`ci_support'" != "`expected_ci_support'" {
                    di as error "Error: bootstrap CI matrices must align with the canonical nt support posted in e(att_plus)/e(att_minus)."
                    exit 198
                }
            }
        }
        local has_boot_ci = 1
    }

    * Direct difference bootstrap SE payload, when consumed by attdiff, must
    * also honor the canonical nt support posted by the main ATT payload.
    if "`attdiff'" != "" {
        capture confirm matrix e(att_diff_se_boot)
        if _rc == 0 {
            local nr_diff_se = rowsof(e(att_diff_se_boot))
            local nc_diff_se = colsof(e(att_diff_se_boot))
            local diff_se_shape_ok = ///
                (`nr_diff_se' == `nr_plus' & `nc_diff_se' == 1) | ///
                (`nr_diff_se' == 1 & `nc_diff_se' == `nr_plus')
            if !`diff_se_shape_ok' {
                di as error "Error: e(att_diff_se_boot) must match the ATT horizon as an N x 1 or 1 x N vector."
                exit 198
            }
            if !`allow_explicit_side_support' {
                local diff_se_support ""
                if `nr_diff_se' == 1 & `nc_diff_se' == `nr_plus' {
                    local diff_se_support : colnames e(att_diff_se_boot)
                }
                else {
                    local diff_se_support : rownames e(att_diff_se_boot)
                }
                local diff_se_support = strtrim("`diff_se_support'")
                local diff_tokens : word count `diff_se_support'
                local diff_is_nt = (`diff_tokens' == `nr_plus')
                if `diff_is_nt' {
                    forvalues i = 1/`diff_tokens' {
                        local diff_tok : word `i' of `diff_se_support'
                        if !regexm(lower("`diff_tok'"), "^nt-?[0-9]+$") {
                            local diff_is_nt = 0
                        }
                    }
                }
                if `diff_is_nt' & "`diff_se_support'" != "`fallback_nt_support'" {
                    di as error "Error: e(att_diff_se_boot) cannot publish explicit nt support unless e(att_plus)/e(att_minus) do so canonically."
                    exit 198
                }
            }

            if `has_nt' {
                local expected_diff_support ""
                forvalues i = 1/`nr_plus' {
                    local nt_val = e(att_plus)[`i', 4]
                    local expected_diff_support "`expected_diff_support' nt`nt_val'"
                }
                local expected_diff_support = strtrim("`expected_diff_support'")

                local diff_se_support ""
                if `nr_diff_se' == 1 & `nc_diff_se' == `nr_plus' {
                    local diff_se_support : colnames e(att_diff_se_boot)
                }
                else {
                    local diff_se_support : rownames e(att_diff_se_boot)
                }
                local diff_se_support = strtrim("`diff_se_support'")
                if "`diff_se_support'" == "" {
                    di as error "Error: e(att_diff_se_boot) must publish explicit nt support labels when the main ATT payload posts canonical nt support."
                    exit 198
                }
                if "`diff_se_support'" != "`expected_diff_support'" {
                    di as error "Error: e(att_diff_se_boot) must align with the canonical nt support posted in e(att_plus)/e(att_minus)."
                    exit 198
                }
            }
        }
    }
    
    return scalar has_se = `has_se'
    return scalar has_boot_ci = `has_boot_ci'
    return scalar has_nt = `has_nt'
    
end
