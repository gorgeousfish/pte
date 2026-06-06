*! _pte_nonabs_ereturn.ado
*! Stores ATT+/ATT- results in e(), formats output tables,
*! and constructs esttab-compatible b/V matrices.

version 14.0
capture program drop _pte_nonabs_ereturn
program define _pte_nonabs_ereturn, eclass
    version 14.0

    syntax, ///
        ATTswitchin(name) ///
        ATTswitchinse(name) ///
        ATTswitchout(name) ///
        ATTswitchoutse(name) ///
        Nswitchin(integer) ///
        Nswitchout(integer) ///
        ATTperiods(name) ///
        PERSISTperiods(integer) ///
        [SIGMAeps0(real 0) ///
         SIGMAeps1(real 0) ///
         SIGMAeps0trim(real 0) ///
         SIGMAeps1trim(real 0) ///
         Ntotal(integer 0) ///
         NBoot(integer 0) ///
         BOOTfailed(integer 0) ///
         CIswitchinl(name) ///
         CIswitchinu(name) ///
         CIswitchoutl(name) ///
         CIswitchoutu(name) ///
         TOUSE(name) ///
         CMDline(string) ///
         Verbose]

    if "`touse'" != "" {
        capture confirm variable `touse', exact
        if _rc {
            di as error "{bf:pte error}: touse variable '`touse'' not found"
            exit 111
        }
    }

    // ================================================================
    // Task 2: Input matrix dimension validation
    // Error codes: E-3024 (dimension mismatch), E-3025 (negative SE),
    //              E-3021 (empty ATT+), E-3023 (no entry events),
    //              E-3026 (all bootstrap failed)
    // ================================================================
    local L_plus_2 = rowsof(`attswitchin')
    local L_plus_1 = colsof(`attperiods')

    if `L_plus_2' != `L_plus_1' + 1 {
        di as error "{bf:pte error E-3024}: Matrix dimension mismatch"
        di as error "  att_switchin rows: `L_plus_2', expected: " ///
            `L_plus_1' + 1
        exit 3024
    }

    if colsof(`attswitchin') != 3 {
        di as error "{bf:pte error E-3024}: att_switchin must have 3 columns"
        exit 3024
    }

    if colsof(`attswitchout') != 3 {
        di as error "{bf:pte error E-3024}: att_switchout must have 3 columns"
        exit 3024
    }

    if rowsof(`attswitchinse') != `L_plus_2' {
        di as error "{bf:pte error E-3024}: att_switchin_se row mismatch"
        exit 3024
    }

    // E-3025: Negative SE values (ATT+)
    mata: st_numscalar("__pte_se_plus_ok",                             ///
        allof(st_matrix("`attswitchinse'") :>= 0, 1))
    if scalar(__pte_se_plus_ok) == 0 {
        di as error "{bf:pte error E-3025}: Negative SE values detected"
        scalar drop __pte_se_plus_ok
        exit 3025
    }
    capture scalar drop __pte_se_plus_ok

    // ================================================================
    // Task 3: Absorbing detection logic
    // ================================================================
    local absorbing_flag = (`nswitchout' == 0)

    if `absorbing_flag' {
        local treatment_type "absorbing"
        if "`verbose'" != "" {
            di as text "{bf:Note}: No exit events detected, treatment is absorbing"
        }
    }
    else {
        local treatment_type "nonabsorbing"
    }

    if !`absorbing_flag' {
        // E-3025: Negative SE values (ATT-)
        mata: st_numscalar("__pte_se_minus_ok",                        ///
            allof(st_matrix("`attswitchoutse'") :>= 0, 1))
        if scalar(__pte_se_minus_ok) == 0 {
            di as error "{bf:pte error E-3025}: Negative SE values detected"
            scalar drop __pte_se_minus_ok
            exit 3025
        }
        capture scalar drop __pte_se_minus_ok
    }

    // ================================================================
    // Task 4: TT sign consistency diagnostic
    // ================================================================
    if !`absorbing_flag' {
        local att_plus_0 = `attswitchin'[1, 2]
        local att_minus_0 = `attswitchout'[1, 2]

        if sign(`att_plus_0') != sign(`att_minus_0') & ///
           `att_plus_0' != 0 & `att_minus_0' != 0 {
            di as text ""
            di as text "{bf:pte warning W-3027}: " ///
                "ATT+ and ATT- have opposite signs at nt=0"
            di as text "  ATT+[nt=0] = " as result %9.4f `att_plus_0'
            di as text "  ATT-[nt=0] = " as result %9.4f `att_minus_0'
            di as text "  This may indicate asymmetric treatment effects"
        }
    }

    // ================================================================
    // Task 5: Set matrix row/column names
    // ================================================================
    local row_names ""
    forv l = 0/`=`L_plus_1'-1' {
        local row_names "`row_names' nt`l'"
    }
    local row_names "`row_names' Avg"

    local col_names "period ATT N_firms"
    local se_col "SE"

    matrix rownames `attswitchin' = `row_names'
    matrix colnames `attswitchin' = `col_names'
    matrix rownames `attswitchinse' = `row_names'
    matrix colnames `attswitchinse' = `se_col'

    if !`absorbing_flag' {
        matrix rownames `attswitchout' = `row_names'
        matrix colnames `attswitchout' = `col_names'
        matrix rownames `attswitchoutse' = `row_names'
        matrix colnames `attswitchoutse' = `se_col'
    }

    // ================================================================
    // Task 14: Error handling (pre-post checks)
    // ================================================================
    if rowsof(`attswitchin') == 0 {
        di as error "{bf:pte error E-3021}: No ATT+ estimates available"
        exit 3021
    }

    if `nswitchin' == 0 {
        di as error "{bf:pte error E-3023}: No entry events detected"
        exit 3023
    }

    if `nboot' > 0 & `bootfailed' == `nboot' {
        di as error "{bf:pte error E-3026}: All bootstrap iterations failed"
        exit 3026
    }

    // ================================================================
    // Task 12-13: Construct esttab-compatible b/V matrices
    // Must be done BEFORE ereturn post
    // ================================================================
    tempname b V

    if `absorbing_flag' {
        // Task 12: Absorbing case — ATT+ only
        tempname se_plus
        local _m = `L_plus_1'
        mata: st_matrix(st_local("b"), st_matrix(st_local("attswitchin"))[1..`_m', 2]')
        mata: st_matrix(st_local("se_plus"), st_matrix(st_local("attswitchinse"))[1..`_m', 1])
        mata: st_matrix(st_local("V"), diag(st_matrix(st_local("se_plus")):^2))

        // Column names: ATT_plus_0, ATT_plus_1, ...
        local b_colnames ""
        forv l = 0/`=`_m'-1' {
            local b_colnames "`b_colnames' ATT_plus_`l'"
        }
        matrix colnames `b' = `b_colnames'
        matrix rownames `V' = `b_colnames'
        matrix colnames `V' = `b_colnames'
    }
    else {
        // Task 13: Non-absorbing case — ATT+ and ATT- concatenated
        local _m = `L_plus_1'
        // Build b vector: concatenate ATT+ and ATT- period estimates
        tempname b_plus b_minus
        mata: st_matrix(st_local("b_plus"), st_matrix(st_local("attswitchin"))[1..`_m', 2]')
        mata: st_matrix(st_local("b_minus"), st_matrix(st_local("attswitchout"))[1..`_m', 2]')
        matrix `b' = `b_plus', `b_minus'

        // Build V matrix: block diagonal of SE^2
        tempname se_p se_m V_plus V_minus
        mata: st_matrix(st_local("se_p"), st_matrix(st_local("attswitchinse"))[1..`_m', 1])
        mata: st_matrix(st_local("se_m"), st_matrix(st_local("attswitchoutse"))[1..`_m', 1])
        mata: st_matrix(st_local("V_plus"), diag(st_matrix(st_local("se_p")):^2))
        mata: st_matrix(st_local("V_minus"), diag(st_matrix(st_local("se_m")):^2))

        // Assemble block diagonal V
        matrix `V' = J(2*`_m', 2*`_m', 0)
        forv i = 1/`_m' {
            matrix `V'[`i', `i'] = `V_plus'[`i', `i']
            local j = `i' + `_m'
            matrix `V'[`j', `j'] = `V_minus'[`i', `i']
        }

        // Column names: ATT_plus_0, ..., ATT_minus_0, ...
        local b_colnames ""
        forv l = 0/`=`_m'-1' {
            local b_colnames "`b_colnames' ATT_plus_`l'"
        }
        forv l = 0/`=`_m'-1' {
            local b_colnames "`b_colnames' ATT_minus_`l'"
        }
        matrix colnames `b' = `b_colnames'
        matrix rownames `V' = `b_colnames'
        matrix colnames `V' = `b_colnames'
    }

    // ================================================================
    // Task 6: ereturn post — establish eclass framework
    // ================================================================
    if "`touse'" != "" {
        ereturn post `b' `V', esample(`touse')
    }
    else {
        ereturn post `b' `V'
    }

    // ================================================================
    // Task 6 (cont): Store ATT+ matrices
    // ================================================================
    ereturn matrix att_switchin = `attswitchin'
    ereturn matrix att_switchin_se = `attswitchinse'

    // ================================================================
    // Task 7: Store ATT- matrices (conditional)
    // ================================================================
    if !`absorbing_flag' {
        ereturn matrix att_switchout = `attswitchout'
        ereturn matrix att_switchout_se = `attswitchoutse'
    }
    else {
        // Create missing-value matrices for absorbing case
        tempname missing_att missing_se
        matrix `missing_att' = J(`L_plus_2', 3, .)
        matrix `missing_se' = J(`L_plus_2', 1, .)
        matrix rownames `missing_att' = `row_names'
        matrix colnames `missing_att' = `col_names'
        matrix rownames `missing_se' = `row_names'
        matrix colnames `missing_se' = `se_col'
        ereturn matrix att_switchout = `missing_att'
        ereturn matrix att_switchout_se = `missing_se'
    }

    // ================================================================
    // Task 8: Store graph-compatible ATT aliases
    // ================================================================
    local n_graph_rows = `L_plus_2' - 1
    local graph_row_names ""
    forv l = 0/`=`n_graph_rows'-1' {
        local graph_row_names "`graph_row_names' nt`l'"
    }

    tempname att_switchin_src att_switchout_src att_switchin_se_src att_switchout_se_src
    matrix `att_switchin_src' = e(att_switchin)
    matrix `att_switchout_src' = e(att_switchout)
    matrix `att_switchin_se_src' = e(att_switchin_se)
    matrix `att_switchout_se_src' = e(att_switchout_se)

    tempname att_plus_alias att_minus_alias att_plus_se_alias att_minus_se_alias
    matrix `att_plus_alias' = J(`n_graph_rows', 4, .)
    matrix `att_minus_alias' = J(`n_graph_rows', 4, .)
    matrix `att_plus_se_alias' = J(`n_graph_rows', 1, .)
    matrix `att_minus_se_alias' = J(`n_graph_rows', 1, .)

    forv row = 1/`n_graph_rows' {
        local nt_plus = el(`att_switchin_src', `row', 1)
        if missing(`nt_plus') {
            local nt_plus = `row' - 1
        }
        matrix `att_plus_alias'[`row', 1] = `att_switchin_src'[`row', 2]
        matrix `att_plus_alias'[`row', 2] = `att_switchin_se_src'[`row', 1]
        matrix `att_plus_alias'[`row', 3] = `att_switchin_src'[`row', 3]
        matrix `att_plus_alias'[`row', 4] = `nt_plus'
        matrix `att_plus_se_alias'[`row', 1] = `att_switchin_se_src'[`row', 1]

        local nt_minus = el(`att_switchout_src', `row', 1)
        if missing(`nt_minus') {
            local nt_minus = `row' - 1
        }
        matrix `att_minus_alias'[`row', 1] = `att_switchout_src'[`row', 2]
        matrix `att_minus_alias'[`row', 2] = `att_switchout_se_src'[`row', 1]
        matrix `att_minus_alias'[`row', 3] = `att_switchout_src'[`row', 3]
        matrix `att_minus_alias'[`row', 4] = `nt_minus'
        matrix `att_minus_se_alias'[`row', 1] = `att_switchout_se_src'[`row', 1]
    }

    matrix rownames `att_plus_alias' = `graph_row_names'
    matrix colnames `att_plus_alias' = ATT_plus SD N nt
    matrix rownames `att_minus_alias' = `graph_row_names'
    matrix colnames `att_minus_alias' = ATT_minus SD N nt
    matrix rownames `att_plus_se_alias' = `graph_row_names'
    matrix colnames `att_plus_se_alias' = SE
    matrix rownames `att_minus_se_alias' = `graph_row_names'
    matrix colnames `att_minus_se_alias' = SE

    ereturn matrix att_plus = `att_plus_alias'
    ereturn matrix att_minus = `att_minus_alias'
    ereturn matrix att_plus_se = `att_plus_se_alias'
    ereturn matrix att_minus_se = `att_minus_se_alias'

    // ================================================================
    // Task 9: Store switching statistics
    // ================================================================
    ereturn scalar n_switchin = `nswitchin'
    ereturn scalar n_switchout = `nswitchout'
    ereturn scalar absorbing = `absorbing_flag'

    // ================================================================
    // Task 10: Store shock distribution parameters
    // ================================================================
    if `sigmaeps0' > 0 {
        ereturn scalar sigma_eps0 = `sigmaeps0'
    }
    if `sigmaeps0trim' > 0 {
        ereturn scalar sigma_eps0_trim = `sigmaeps0trim'
    }
    if !`absorbing_flag' {
        if `sigmaeps1' > 0 {
            ereturn scalar sigma_eps1 = `sigmaeps1'
        }
        if `sigmaeps1trim' > 0 {
            ereturn scalar sigma_eps1_trim = `sigmaeps1trim'
        }
    }

    // ================================================================
    // Task 11: Store bootstrap results (conditional)
    // ================================================================
    if `nboot' > 0 {
        ereturn scalar nboot = `nboot'
        ereturn scalar boot_failed = `bootfailed'

        if "`ciswitchinl'" != "" {
            ereturn matrix att_switchin_ci_l = `ciswitchinl'
            ereturn matrix att_switchin_ci_u = `ciswitchinu'
        }

        if !`absorbing_flag' & "`ciswitchoutl'" != "" {
            ereturn matrix att_switchout_ci_l = `ciswitchoutl'
            ereturn matrix att_switchout_ci_u = `ciswitchoutu'
        }
    }

    // ================================================================
    // Task 12: Store metadata
    // ================================================================
    ereturn matrix attperiods = `attperiods'
    ereturn scalar persistperiods = `persistperiods'
    ereturn local treatment_type "`treatment_type'"
    if `absorbing_flag' {
        ereturn local trt_type "absorbing"
    }
    else {
        ereturn local trt_type "non-absorbing"
    }
    ereturn local cmd "pte"
    if `"`cmdline'"' != "" {
        ereturn local cmdline `"`cmdline'"'
    }
    if `ntotal' > 0 {
        ereturn scalar N_total = `ntotal'
    }

    // ================================================================
    // Task 15: Display summary header
    // ================================================================
    di as text ""
    di as text "{hline 78}"
    if `absorbing_flag' {
        di as text "Treatment Effects (Absorbing Treatment Detected)"
    }
    else {
        di as text "Non-absorbing Treatment Effects"
    }
    di as text "{hline 78}"
    di as text "Treatment type:    " as result "`treatment_type'"
    di as text "Entry events (G=+1): " as result %6.0fc `nswitchin'
    di as text "Exit events  (G=-1): " as result %6.0fc `nswitchout'
    di as text "Persistence:         persistperiods(" ///
        as result `persistperiods' as text ")"
    di as text "{hline 78}"

    // ================================================================
    // Task 16-17: ATT+ table output
    // ================================================================
    local has_ci = (`nboot' > 0 & "`ciswitchinl'" != "")

    di as text ""
    di as text "{hline 78}"
    di as text "ATT+ (Entry Effects: Effect of entering treatment)"
    di as text "{hline 78}"

    // Retrieve stored matrices from e()
    tempname ATT_plus SE_plus
    matrix `ATT_plus' = e(att_switchin)
    matrix `SE_plus' = e(att_switchin_se)

    if `has_ci' {
        tempname CI_plus_l CI_plus_u
        matrix `CI_plus_l' = e(att_switchin_ci_l)
        matrix `CI_plus_u' = e(att_switchin_ci_u)
        di as text "      nt {c |}     ATT+    Boot. SE" ///
            "   [95% Conf. Interval]   Firms"
        di as text "{hline 9}{c +}{hline 68}"
    }
    else {
        di as text "      nt {c |}     ATT+          SE       Firms"
        di as text "{hline 9}{c +}{hline 40}"
    }

    // Task 17: Output each period row
    forv row = 1/`L_plus_2' {
        local att_val = `ATT_plus'[`row', 2]
        local se_val = `SE_plus'[`row', 1]
        local n_val = `ATT_plus'[`row', 3]

        // Significance stars
        local stars ""
        if `se_val' > 0 & `se_val' < . {
            local t_stat = abs(`att_val' / `se_val')
            if `t_stat' > 2.576 {
                local stars "***"
            }
            else if `t_stat' > 1.96 {
                local stars "** "
            }
            else if `t_stat' > 1.645 {
                local stars "*  "
            }
            else {
                local stars "   "
            }
        }
        else {
            local stars "   "
        }

        // Row label
        if `row' == `L_plus_2' {
            di as text "     Avg {c |}" _continue
        }
        else {
            local nt_label = `row' - 1
            di as text %8.0f `nt_label' " {c |}" _continue
        }

        // ATT, SE, CI, N
        di as result %10.6f `att_val' as text "`stars'" _continue
        di as result %12.6f `se_val' _continue

        if `has_ci' {
            local ci_l = `CI_plus_l'[`row', 1]
            local ci_u = `CI_plus_u'[`row', 1]
            di as result %11.6f `ci_l' %11.6f `ci_u' _continue
        }

        di as result %8.0fc `n_val'
    }

    if `has_ci' {
        di as text "{hline 9}{c +}{hline 68}"
    }
    else {
        di as text "{hline 9}{c +}{hline 40}"
    }

    // ================================================================
    // Task 18: ATT- table output (conditional)
    // ================================================================
    if !`absorbing_flag' {
        local has_ci_minus = (`nboot' > 0 & "`ciswitchoutl'" != "")

        tempname ATT_minus SE_minus
        matrix `ATT_minus' = e(att_switchout)
        matrix `SE_minus' = e(att_switchout_se)

        di as text ""
        di as text "{hline 78}"
        di as text "ATT- (Exit Switchers: Staying treated vs observed exit)"
        di as text "{hline 78}"

        if `has_ci_minus' {
            tempname CI_minus_l CI_minus_u
            matrix `CI_minus_l' = e(att_switchout_ci_l)
            matrix `CI_minus_u' = e(att_switchout_ci_u)
            di as text "      nt {c |}     ATT-    Boot. SE" ///
                "   [95% Conf. Interval]   Firms"
            di as text "{hline 9}{c +}{hline 68}"
        }
        else {
            di as text "      nt {c |}     ATT-          SE       Firms"
            di as text "{hline 9}{c +}{hline 40}"
        }

        forv row = 1/`L_plus_2' {
            local att_val = `ATT_minus'[`row', 2]
            local se_val = `SE_minus'[`row', 1]
            local n_val = `ATT_minus'[`row', 3]

            // Significance stars
            local stars ""
            if `se_val' > 0 & `se_val' < . {
                local t_stat = abs(`att_val' / `se_val')
                if `t_stat' > 2.576 {
                    local stars "***"
                }
                else if `t_stat' > 1.96 {
                    local stars "** "
                }
                else if `t_stat' > 1.645 {
                    local stars "*  "
                }
                else {
                    local stars "   "
                }
            }
            else {
                local stars "   "
            }

            // Row label
            if `row' == `L_plus_2' {
                di as text "     Avg {c |}" _continue
            }
            else {
                local nt_label = `row' - 1
                di as text %8.0f `nt_label' " {c |}" _continue
            }

            di as result %10.6f `att_val' as text "`stars'" _continue
            di as result %12.6f `se_val' _continue

            if `has_ci_minus' {
                local ci_l = `CI_minus_l'[`row', 1]
                local ci_u = `CI_minus_u'[`row', 1]
                di as result %11.6f `ci_l' %11.6f `ci_u' _continue
            }

            di as result %8.0fc `n_val'
        }

        if `has_ci_minus' {
            di as text "{hline 9}{c +}{hline 68}"
        }
        else {
            di as text "{hline 9}{c +}{hline 40}"
        }
    }

    // ================================================================
    // Task 19: Absorbing degradation message
    // ================================================================
    if `absorbing_flag' {
        di as text ""
        di as text "{bf:Note}: No exit events detected in sample"
        di as text "  Results equivalent to standard pte without" ///
            " nonabsorbing option"
        di as text "  ATT- is set to missing"
        di as text "  Consider using standard pte command for" ///
            " absorbing treatments"
    }

    // ================================================================
    // Task 20: Footnotes and metadata display
    // ================================================================
    di as text ""
    di as text "* p<0.10, ** p<0.05, *** p<0.01"
    if `nboot' > 0 {
        di as text "Bootstrap replications: " as result e(nboot)
        if `bootfailed' > 0 {
            di as text "Failed iterations: " as result `bootfailed'
        }
    }
    di as text ""

end
