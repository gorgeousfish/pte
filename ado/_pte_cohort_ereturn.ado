*! _pte_cohort_ereturn.ado
*! Store cohort analysis results into e() return system

version 14.0
capture program drop _pte_cohort_ereturn
program define _pte_cohort_ereturn, eclass
    version 14.0

    // -----------------------------------------------------------------------
    // Syntax parsing
    // -----------------------------------------------------------------------
    syntax ,                                        ///
        att_cohort(name)                            ///
        att_cohort_se(name)                         ///
        att_pool(name)                              ///
        att_pool_se(name)                           ///
        cohort_list(name)                           ///
        cohort_sizes(name)                          ///
        attperiods(name)                            ///
        matchstrategy(string)                       ///
        [                                           ///
            het_Q(name)                             ///
            het_Q_p(name)                           ///
            het_I2(name)                            ///
            het_Q_df(name)                          ///
            het_Q_G(name)                           ///
            ci_cohort_l(name)                       ///
            ci_cohort_u(name)                       ///
            ci_pool_l(name)                         ///
            ci_pool_u(name)                         ///
            nboot(integer 0)                        ///
            boot_failed(integer 0)                  ///
            boot_mode(string)                       ///
            matchexpr(string)                       ///
            cmdline(string)                         ///
            NODisplay                               ///
        ]

    // -----------------------------------------------------------------------
    // Extract dimensions: G = number of cohorts, L_plus_1 = number of periods
    // -----------------------------------------------------------------------
    local G = rowsof(`att_cohort')
    local L_plus_1 = colsof(`att_cohort')

    // -----------------------------------------------------------------------
    // Step 1: Input validation (Task 2, Task 12)
    // Error codes: E-3011 (empty ATT), E-3013 (dimension mismatch),
    //              E-3015 (all bootstrap failed), E-3016 (negative SE)
    // -----------------------------------------------------------------------

    // E-3011: No ATT estimates available
    if `G' == 0 {
        di as error "{bf:pte error E-3011}: No ATT estimates available"
        exit 3011
    }

    // E-3013: Matrix dimension mismatch - att_cohort_se
    if rowsof(`att_cohort_se') != `G' | colsof(`att_cohort_se') != `L_plus_1' {
        di as error "{bf:pte error E-3013}: att_cohort_se dimension mismatch" ///
            " (expected `G' x `L_plus_1')"
        exit 3013
    }

    // E-3013: Matrix dimension mismatch - att_pool
    if rowsof(`att_pool') != 1 | colsof(`att_pool') != `L_plus_1' {
        di as error "{bf:pte error E-3013}: att_pool dimension mismatch" ///
            " (expected 1 x `L_plus_1')"
        exit 3013
    }

    // E-3013: Matrix dimension mismatch - att_pool_se
    if rowsof(`att_pool_se') != 1 | colsof(`att_pool_se') != `L_plus_1' {
        di as error "{bf:pte error E-3013}: att_pool_se dimension mismatch" ///
            " (expected 1 x `L_plus_1')"
        exit 3013
    }

    // E-3013: Matrix dimension mismatch - cohort_list
    if rowsof(`cohort_list') != `G' | colsof(`cohort_list') != 1 {
        di as error "{bf:pte error E-3013}: cohort_list dimension mismatch" ///
            " (expected `G' x 1)"
        exit 3013
    }

    // E-3013: Matrix dimension mismatch - cohort_sizes
    if rowsof(`cohort_sizes') != `G' | colsof(`cohort_sizes') != 1 {
        di as error "{bf:pte error E-3013}: cohort_sizes dimension mismatch" ///
            " (expected `G' x 1)"
        exit 3013
    }

    // E-3013: Matrix dimension mismatch - attperiods
    if rowsof(`attperiods') != 1 | colsof(`attperiods') != `L_plus_1' {
        di as error "{bf:pte error E-3013}: attperiods dimension mismatch" ///
            " (expected 1 x `L_plus_1')"
        exit 3013
    }

    // Cohort labels become public row labels and must therefore be exact
    // integer cohort identifiers rather than rounded display values.
    mata: st_numscalar("__pte_cohort_list_int_ok",                    ///
        allof((floor(st_matrix("`cohort_list'")) :==                  ///
                st_matrix("`cohort_list'")) :|                        ///
            missing(st_matrix("`cohort_list'")), 1))
    if scalar(__pte_cohort_list_int_ok) == 0 {
        di as error "{bf:pte error E-3013}: cohort_list must contain integer cohort identifiers"
        scalar drop __pte_cohort_list_int_ok
        exit 3013
    }
    capture scalar drop __pte_cohort_list_int_ok

    // E-3016: Negative SE values
    mata: st_numscalar("__pte_se_ok",                                   ///
        allof((st_matrix("`att_cohort_se'") :>= 0) :|                   ///
            missing(st_matrix("`att_cohort_se'")), 1)                  ///
        & allof((st_matrix("`att_pool_se'") :>= 0) :|                   ///
            missing(st_matrix("`att_pool_se'")), 1))
    if scalar(__pte_se_ok) == 0 {
        di as error "{bf:pte error E-3016}: Negative SE values detected"
        scalar drop __pte_se_ok
        exit 3016
    }
    capture scalar drop __pte_se_ok

    // E-3015: All bootstrap iterations failed
    if `nboot' > 0 & `boot_failed' >= `nboot' {
        di as error "{bf:pte error E-3015}: All `nboot' bootstrap" ///
            " iterations failed"
        exit 3015
    }

    // Confidence intervals are a bundled bootstrap payload. A half-open
    // family is not a valid public contract and must fail-close regardless of
    // whether nboot() metadata is supplied by the caller.
    local ci_inputs = 0
    foreach _pte_ci_opt in ci_cohort_l ci_cohort_u ci_pool_l ci_pool_u {
        if `"``_pte_ci_opt''"' != "" {
            local ++ci_inputs
        }
    }
    local has_ci_family = (`ci_inputs' > 0)
    if `has_ci_family' & `ci_inputs' < 4 {
        di as error "{bf:pte error E-3013}: confidence interval payload requires ci_cohort_l(), ci_cohort_u(), ci_pool_l(), and ci_pool_u() together"
        exit 3013
    }

    // Validate CI matrix dimensions if provided
    if "`ci_cohort_l'" != "" {
        if rowsof(`ci_cohort_l') != `G' | colsof(`ci_cohort_l') != `L_plus_1' {
            di as error "{bf:pte error E-3013}: ci_cohort_l dimension mismatch"
            exit 3013
        }
    }
    if "`ci_cohort_u'" != "" {
        if rowsof(`ci_cohort_u') != `G' | colsof(`ci_cohort_u') != `L_plus_1' {
            di as error "{bf:pte error E-3013}: ci_cohort_u dimension mismatch"
            exit 3013
        }
    }
    if "`ci_pool_l'" != "" {
        if rowsof(`ci_pool_l') != 1 | colsof(`ci_pool_l') != `L_plus_1' {
            di as error "{bf:pte error E-3013}: ci_pool_l dimension mismatch"
            exit 3013
        }
    }
    if "`ci_pool_u'" != "" {
        if rowsof(`ci_pool_u') != 1 | colsof(`ci_pool_u') != `L_plus_1' {
            di as error "{bf:pte error E-3013}: ci_pool_u dimension mismatch"
            exit 3013
        }
    }
    if "`ci_cohort_l'" != "" & "`ci_cohort_u'" != "" & "`ci_pool_l'" != "" & "`ci_pool_u'" != "" {
        mata: st_numscalar("__pte_ci_pair_ok",                         ///
            allof(((missing(st_matrix("`ci_cohort_l'")) :&             ///
                    missing(st_matrix("`ci_cohort_u'"))) :|            ///
                ((!missing(st_matrix("`ci_cohort_l'"))) :&             ///
                 (!missing(st_matrix("`ci_cohort_u'"))) :&             ///
                 (st_matrix("`ci_cohort_l'") :<=                       ///
                    st_matrix("`ci_cohort_u'")))), 1)                  ///
            & allof(((missing(st_matrix("`ci_pool_l'")) :&             ///
                    missing(st_matrix("`ci_pool_u'"))) :|              ///
                ((!missing(st_matrix("`ci_pool_l'"))) :&               ///
                 (!missing(st_matrix("`ci_pool_u'"))) :&               ///
                 (st_matrix("`ci_pool_l'") :<=                         ///
                    st_matrix("`ci_pool_u'")))), 1))
        if scalar(__pte_ci_pair_ok) == 0 {
            di as error "{bf:pte error E-3013}: CI payload contains half-open or reversed bounds"
            scalar drop __pte_ci_pair_ok
            exit 3013
        }
        capture scalar drop __pte_ci_pair_ok
    }
    if "`het_Q_df'" != "" {
        if rowsof(`het_Q_df') != 1 | colsof(`het_Q_df') != `L_plus_1' {
            di as error "{bf:pte error E-3013}: het_Q_df dimension mismatch"
            exit 3013
        }
        mata: st_numscalar("__pte_qdf_range_ok",                      ///
            allof(((st_matrix("`het_Q_df'") :>= 0) :&                ///
                    (floor(st_matrix("`het_Q_df'")) :==              ///
                        st_matrix("`het_Q_df'"))) :|                 ///
                missing(st_matrix("`het_Q_df'")), 1))
        if scalar(__pte_qdf_range_ok) == 0 {
            di as error "{bf:pte error E-3013}: het_Q_df must contain nonnegative integers or missing values"
            scalar drop __pte_qdf_range_ok
            exit 3013
        }
        capture scalar drop __pte_qdf_range_ok
    }
    if "`het_Q_G'" != "" {
        if rowsof(`het_Q_G') != 1 | colsof(`het_Q_G') != `L_plus_1' {
            di as error "{bf:pte error E-3013}: het_Q_G dimension mismatch"
            exit 3013
        }
        mata: st_numscalar("__pte_qg_range_ok",                       ///
            allof(((st_matrix("`het_Q_G'") :>= 0) :&                 ///
                    (floor(st_matrix("`het_Q_G'")) :==               ///
                        st_matrix("`het_Q_G'"))) :|                  ///
                missing(st_matrix("`het_Q_G'")), 1))
        if scalar(__pte_qg_range_ok) == 0 {
            di as error "{bf:pte error E-3013}: het_Q_G must contain nonnegative integers or missing values"
            scalar drop __pte_qg_range_ok
            exit 3013
        }
        capture scalar drop __pte_qg_range_ok
    }
    if "`het_Q'" != "" {
        if rowsof(`het_Q') != 1 | colsof(`het_Q') != `L_plus_1' {
            di as error "{bf:pte error E-3013}: het_Q dimension mismatch"
            exit 3013
        }
        mata: st_numscalar("__pte_q_range_ok",                        ///
            allof((st_matrix("`het_Q'") :>= 0) :|                     ///
                missing(st_matrix("`het_Q'")), 1))
        if scalar(__pte_q_range_ok) == 0 {
            di as error "{bf:pte error E-3013}: het_Q contains impossible Q statistics"
            scalar drop __pte_q_range_ok
            exit 3013
        }
        capture scalar drop __pte_q_range_ok
    }
    if "`het_Q_p'" != "" {
        if rowsof(`het_Q_p') != 1 | colsof(`het_Q_p') != `L_plus_1' {
            di as error "{bf:pte error E-3013}: het_Q_p dimension mismatch"
            exit 3013
        }
        mata: st_numscalar("__pte_qp_range_ok",                       ///
            allof((((st_matrix("`het_Q_p'") :>= 0) :&                 ///
                    (st_matrix("`het_Q_p'") :<= 1)) :|                ///
                missing(st_matrix("`het_Q_p'"))), 1))
        if scalar(__pte_qp_range_ok) == 0 {
            di as error "{bf:pte error E-3013}: het_Q_p contains impossible p-values"
            scalar drop __pte_qp_range_ok
            exit 3013
        }
        capture scalar drop __pte_qp_range_ok
    }
    if "`het_I2'" != "" {
        if rowsof(`het_I2') != 1 | colsof(`het_I2') != `L_plus_1' {
            di as error "{bf:pte error E-3013}: het_I2 dimension mismatch"
            exit 3013
        }
        mata: st_numscalar("__pte_i2_range_ok",                       ///
            allof((((st_matrix("`het_I2'") :>= 0) :&                  ///
                    (st_matrix("`het_I2'") :<= 100)) :|               ///
                missing(st_matrix("`het_I2'"))), 1))
        if scalar(__pte_i2_range_ok) == 0 {
            di as error "{bf:pte error E-3013}: het_I2 contains impossible I-squared values"
            scalar drop __pte_i2_range_ok
            exit 3013
        }
        capture scalar drop __pte_i2_range_ok
    }
    if "`het_Q_df'" != "" & "`het_Q_G'" != "" {
        mata: st_numscalar("__pte_qdfg_pair_ok",                      ///
            allof(((missing(st_matrix("`het_Q_df'")) :|              ///
                    missing(st_matrix("`het_Q_G'"))) :|              ///
                ((st_matrix("`het_Q_G'") :-                         ///
                    st_matrix("`het_Q_df'")) :== 1)), 1))
        if scalar(__pte_qdfg_pair_ok) == 0 {
            di as error "{bf:pte error E-3013}: het_Q_df and het_Q_G are inconsistent (expected G = df + 1)"
            scalar drop __pte_qdfg_pair_ok
            exit 3013
        }
        capture scalar drop __pte_qdfg_pair_ok
    }

    // -----------------------------------------------------------------------
    // Step 2: Set matrix row/column names (Task 3)
    // Row names = cohort years from cohort_list
    // Col names follow the exact stored event-time support in attperiods()
    // -----------------------------------------------------------------------

    // Build row names from cohort_list
    local row_names ""
    forvalues g = 1/`G' {
        local yr = `cohort_list'[`g', 1]
        local yr_int = string(`yr', "%10.0f")
        local yr_int = strtrim("`yr_int'")
        local row_names `row_names' `yr_int'
    }

    // Build exact-support column names from attperiods().
    local col_names ""
    local b_colnames ""
    local display_periods ""
    forvalues l = 1/`L_plus_1' {
        local period = `attperiods'[1, `l']
        local period_str = trim(string(`period', "%21.0g"))
        local col_names `col_names' nt`period_str'
        local b_colnames `b_colnames' ATT_`period_str'
        local display_periods `display_periods' `period_str'
    }

    // Apply row/column names to all G x (L+1) matrices
    foreach mat in att_cohort att_cohort_se {
        matrix rownames ``mat'' = `row_names'
        matrix colnames ``mat'' = `col_names'
    }

    // Apply column names to 1 x (L+1) matrices
    foreach mat in att_pool att_pool_se {
        matrix colnames ``mat'' = `col_names'
    }

    // Apply names to CI matrices if provided
    if "`ci_cohort_l'" != "" {
        matrix rownames `ci_cohort_l' = `row_names'
        matrix colnames `ci_cohort_l' = `col_names'
    }
    if "`ci_cohort_u'" != "" {
        matrix rownames `ci_cohort_u' = `row_names'
        matrix colnames `ci_cohort_u' = `col_names'
    }
    if "`ci_pool_l'" != "" {
        matrix colnames `ci_pool_l' = `col_names'
    }
    if "`ci_pool_u'" != "" {
        matrix colnames `ci_pool_u' = `col_names'
    }

    // Apply names to Q matrices if provided
    if "`het_Q'" != "" {
        matrix colnames `het_Q' = `col_names'
    }
    if "`het_Q_p'" != "" {
        matrix colnames `het_Q_p' = `col_names'
    }
    if "`het_I2'" != "" {
        matrix colnames `het_I2' = `col_names'
    }
    if "`het_Q_df'" != "" {
        matrix colnames `het_Q_df' = `col_names'
    }
    if "`het_Q_G'" != "" {
        matrix colnames `het_Q_G' = `col_names'
    }

    // -----------------------------------------------------------------------
    // Step 3: Save all input matrices to tempnames (before ereturn post
    // clears everything). ereturn matrix MOVES the source, so we must
    // copy to tempnames that survive ereturn post.
    // -----------------------------------------------------------------------
    tempname t_att_c t_att_c_se t_att_p t_att_p_se
    tempname t_cohort_l t_cohort_s t_attp
    matrix `t_att_c'    = `att_cohort'
    matrix `t_att_c_se' = `att_cohort_se'
    matrix `t_att_p'    = `att_pool'
    matrix `t_att_p_se' = `att_pool_se'
    matrix `t_cohort_l' = `cohort_list'
    matrix `t_cohort_s' = `cohort_sizes'
    matrix `t_attp'     = `attperiods'

    // Save Q matrices if provided
    tempname t_het_Q t_het_Qp t_het_I2 t_het_Qdf t_het_QG
    if "`het_Q'" != "" {
        matrix `t_het_Q'  = `het_Q'
        if "`het_Q_p'" != "" {
            matrix `t_het_Qp' = `het_Q_p'
        }
        else {
            matrix `t_het_Qp' = J(1, `L_plus_1', .)
        }
        if "`het_I2'" != "" {
            matrix `t_het_I2' = `het_I2'
        }
        else {
            matrix `t_het_I2' = J(1, `L_plus_1', .)
        }
        if "`het_Q_df'" != "" {
            matrix `t_het_Qdf' = `het_Q_df'
        }
        else {
            matrix `t_het_Qdf' = J(1, `L_plus_1', `G' - 1)
        }
        if "`het_Q_G'" != "" {
            matrix `t_het_QG' = `het_Q_G'
        }
        else {
            matrix `t_het_QG' = J(1, `L_plus_1', `G')
        }
        matrix colnames `t_het_Qp' = `col_names'
        matrix colnames `t_het_I2' = `col_names'
        matrix colnames `t_het_Qdf' = `col_names'
        matrix colnames `t_het_QG' = `col_names'
    }

    // Save CI matrices if provided
    tempname t_ci_cl t_ci_cu t_ci_pl t_ci_pu
    if `has_ci_family' {
        matrix `t_ci_cl' = `ci_cohort_l'
        matrix `t_ci_cu' = `ci_cohort_u'
        matrix `t_ci_pl' = `ci_pool_l'
        matrix `t_ci_pu' = `ci_pool_u'
    }

    // -----------------------------------------------------------------------
    // Step 4: Construct e(b) and e(V) for esttab/outreg2 compatibility
    // (Task 11) Ref: prodest.ado L553-590
    // e(b) = ATT_pool row vector with exact-support ATT labels from attperiods()
    // e(V) = diagonal matrix with the same exact-support ATT labels
    // -----------------------------------------------------------------------
    tempname b V
    matrix `b' = `t_att_p'

    // Clear equation label (critical for esttab display)
    mat coleq `b' = ""
    matrix colnames `b' = `b_colnames'

    // Construct diagonal V matrix: V[i,i] = SE[i]^2
    mata: st_matrix("`V'", diag(st_matrix("`t_att_p_se'"):^2))
    matrix rownames `V' = `b_colnames'
    matrix colnames `V' = `b_colnames'

    // -----------------------------------------------------------------------
    // Step 5: ereturn post b V — establishes the estimation framework
    // This clears all prior e() values. Everything else must be stored AFTER.
    // -----------------------------------------------------------------------
    ereturn post `b' `V', depname("ATT")

    // -----------------------------------------------------------------------
    // Step 6: Store core ATT matrices (Task 6b-6e)
    // Ref: Paper Section 4.3, Proposition 4.3
    // ATT_{g,l} = E[omega^1 - omega^0 | t = e_i + l]
    // -----------------------------------------------------------------------
    ereturn matrix att_cohort    = `t_att_c'
    ereturn matrix att_cohort_se = `t_att_c_se'
    ereturn matrix att_pool      = `t_att_p'
    ereturn matrix att_pool_se   = `t_att_p_se'

    // -----------------------------------------------------------------------
    // Step 7: Store cohort identifiers (Task 7)
    // -----------------------------------------------------------------------
    ereturn matrix cohort_list  = `t_cohort_l'
    ereturn matrix cohort_sizes = `t_cohort_s'
    ereturn scalar n_cohorts = `G'

    // -----------------------------------------------------------------------
    // Step 8: Store heterogeneity test results (Task 8)
    // Ref: Paper Appendix C.2
    // Q_l = sum_g w_g * (ATT_{g,l} - ATT_{pool,l})^2 ~ chi2(G-1)
    // -----------------------------------------------------------------------
    if `G' >= 2 & "`het_Q'" != "" {
        local q_df_scalar = .
        local q_G_scalar = .
        local q_df_consistent = 1
        local q_G_consistent = 1
        forvalues l = 1/`L_plus_1' {
            local q_df_l = el(`t_het_Qdf', 1, `l')
            local q_G_l = el(`t_het_QG', 1, `l')
            if `l' == 1 {
                local q_df_scalar = `q_df_l'
                local q_G_scalar = `q_G_l'
            }
            else {
                if missing(`q_df_l') | missing(`q_df_scalar') | `q_df_l' != `q_df_scalar' {
                    local q_df_consistent = 0
                }
                if missing(`q_G_l') | missing(`q_G_scalar') | `q_G_l' != `q_G_scalar' {
                    local q_G_consistent = 0
                }
            }
        }
        ereturn matrix cohort_het_Q = `t_het_Q'
        ereturn matrix cohort_het_p = `t_het_Qp'
        ereturn matrix cohort_het_I2 = `t_het_I2'
        ereturn matrix df_Q_period = `t_het_Qdf'
        ereturn matrix G_Q_period = `t_het_QG'
        if `q_df_consistent' & !missing(`q_df_scalar') {
            ereturn scalar df_Q = `q_df_scalar'
        }
        else {
            ereturn scalar df_Q = .
        }
        if `q_G_consistent' & !missing(`q_G_scalar') {
            ereturn scalar G_Q = `q_G_scalar'
        }
        else {
            ereturn scalar G_Q = .
        }
    }
    else {
        // Single cohort or Q not provided: store missing values
        tempname Q_miss Q_df_miss Q_G_miss
        matrix `Q_miss' = J(1, `L_plus_1', .)
        matrix colnames `Q_miss' = `col_names'
        ereturn matrix cohort_het_Q = `Q_miss'
        matrix `Q_miss' = J(1, `L_plus_1', .)
        matrix colnames `Q_miss' = `col_names'
        ereturn matrix cohort_het_p = `Q_miss'
        matrix `Q_miss' = J(1, `L_plus_1', .)
        matrix colnames `Q_miss' = `col_names'
        ereturn matrix cohort_het_I2 = `Q_miss'
        matrix `Q_df_miss' = J(1, `L_plus_1', .)
        matrix colnames `Q_df_miss' = `col_names'
        ereturn matrix df_Q_period = `Q_df_miss'
        matrix `Q_G_miss' = J(1, `L_plus_1', .)
        matrix colnames `Q_G_miss' = `col_names'
        ereturn matrix G_Q_period = `Q_G_miss'
        ereturn scalar df_Q = 0
        ereturn scalar G_Q = `G'
    }

    // -----------------------------------------------------------------------
    // Step 9: Store bootstrap results - conditional (Task 9)
    // Only stored when bootstrap was actually performed
    // -----------------------------------------------------------------------
    if `has_ci_family' {
        ereturn matrix att_cohort_ci_l = `t_ci_cl'
        ereturn matrix att_cohort_ci_u = `t_ci_cu'
        ereturn matrix att_pool_ci_l   = `t_ci_pl'
        ereturn matrix att_pool_ci_u   = `t_ci_pu'
    }
    if `nboot' > 0 {
        ereturn scalar nboot = `nboot'
        ereturn scalar boot_failed = `boot_failed'
        ereturn local boot_mode "`boot_mode'"
    }

    // -----------------------------------------------------------------------
    // Step 10: Store meta info (Task 10)
    // -----------------------------------------------------------------------
    ereturn matrix attperiods = `t_attp'
    ereturn local matchstrategy "`matchstrategy'"
    if "`matchstrategy'" == "custom" & "`matchexpr'" != "" {
        ereturn local matchexpr "`matchexpr'"
    }
    ereturn local cmd "pte"
    ereturn local cmdline `"`cmdline'"'

    // -----------------------------------------------------------------------
    // Step 11: Formatted display output (Task 13-15)
    // Skip if nodisplay option specified
    // -----------------------------------------------------------------------
    if "`nodisplay'" == "" {

        // --- Table header (Task 13) ---
        di as text ""
        di as text "{hline 72}"
        di as text "{bf:Cohort-specific ATT estimates}"
        di as text "{hline 72}"

        // Column headers
        di as text %15s " " _continue
        forvalues l = 1/`L_plus_1' {
            local period_str : word `l' of `display_periods'
            di as text %12s "nt=`period_str'" _continue
        }
        di ""
        di as text "{hline 72}"

        // --- Cohort rows (Task 14) ---
        tempname ATT_disp SE_disp
        matrix `ATT_disp' = e(att_cohort)
        matrix `SE_disp'  = e(att_cohort_se)

        forvalues g = 1/`G' {
            // Cohort year label
            local yr : word `g' of `row_names'
            di as text %15s "Cohort `yr'" _continue

            // ATT values with significance stars
            forvalues l = 1/`L_plus_1' {
                local att_val = `ATT_disp'[`g', `l']
                local se_val  = `SE_disp'[`g', `l']

                // Significance stars based on t-statistic
                local stars ""
                if `se_val' > 0 & `se_val' < . {
                    local t_stat = abs(`att_val' / `se_val')
                    if `t_stat' > 2.576      local stars "***"
                    else if `t_stat' > 1.960 local stars "**"
                    else if `t_stat' > 1.645 local stars "*"
                }

                di as result %9.4f `att_val' as text %-3s "`stars'" _continue
            }
            di ""

            // SE row in parentheses
            di as text %15s " " _continue
            forvalues l = 1/`L_plus_1' {
                local se_val = `SE_disp'[`g', `l']
                di as text "(" %7.4f `se_val' ")" _col(`=15 + `l' * 12') _continue
            }
            di ""
        }

        // --- Pooled row and Q-test (Task 15) ---
        di as text "{hline 72}"

        tempname ATT_pool_disp SE_pool_disp
        matrix `ATT_pool_disp' = e(att_pool)
        matrix `SE_pool_disp'  = e(att_pool_se)

        // Pooled ATT row
        di as text %15s "Pooled" _continue
        forvalues l = 1/`L_plus_1' {
            local att_val = `ATT_pool_disp'[1, `l']
            local se_val  = `SE_pool_disp'[1, `l']

            local stars ""
            if `se_val' > 0 & `se_val' < . {
                local t_stat = abs(`att_val' / `se_val')
                if `t_stat' > 2.576      local stars "***"
                else if `t_stat' > 1.960 local stars "**"
                else if `t_stat' > 1.645 local stars "*"
            }

            di as result %9.4f `att_val' as text %-3s "`stars'" _continue
        }
        di ""

        // Pooled SE row
        di as text %15s " " _continue
        forvalues l = 1/`L_plus_1' {
            local se_val = `SE_pool_disp'[1, `l']
            di as text "(" %7.4f `se_val' ")" _col(`=15 + `l' * 12') _continue
        }
        di ""

        // Q-test p-values (only if G >= 2)
        mata: st_numscalar("__pte_qtest_has_p", any(st_matrix("e(cohort_het_p)") :< .))
        if `G' >= 2 & scalar(__pte_qtest_has_p) {
            tempname Q_p_disp
            matrix `Q_p_disp' = e(cohort_het_p)

            di ""
            di as text %15s "Q-test p" _continue
            forvalues l = 1/`L_plus_1' {
                local p_val = `Q_p_disp'[1, `l']
                if `p_val' < . {
                    di as text %12.4f `p_val' _continue
                }
                else {
                    di as text %12s "." _continue
                }
            }
            di ""
        }
        capture scalar drop __pte_qtest_has_p

        // Footer
        di as text "{hline 72}"
        di as text "* p<0.10, ** p<0.05, *** p<0.01"
        di as text "Match strategy: " as result "`matchstrategy'"
        if `nboot' > 0 {
            di as text "Bootstrap: " as result "`nboot' replications"  ///
                as text " (" as result `boot_failed' as text " failed)"
        }
        di as text "Cohorts: " as result `G'                           ///
            as text "  Periods: " as result `L_plus_1'
    }

end
