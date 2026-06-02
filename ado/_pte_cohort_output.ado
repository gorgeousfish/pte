*! _pte_cohort_output.ado
*! Cohort analysis output and ereturn module
*! Stores cohort ATT results in e() and displays formatted output

version 14.0
capture program drop _pte_cohort_output
program define _pte_cohort_output, eclass
    version 14.0
    
    // ================================================================
    // T-009.1.1: Syntax parsing
    // ================================================================
    
    syntax , ///
        ATTcohort(string)    /// G x (L+1) cohort ATT matrix
        SEcohort(string)     /// G x (L+1) cohort SE matrix
        ATTpool(string)      /// 1 x (L+1) pooled ATT vector
        SEpool(string)       /// 1 x (L+1) pooled SE vector
        COHORTlist(string)   /// G x 1 cohort year vector
        COHORTsizes(string)  /// G x 1 cohort firm count vector
        [                    ///
        ATTPERIODS(string)   /// 1 x (L+1) exact event-time support (optional)
        Qmat(string)         /// 1 x (L+1) Q statistics (optional)
        Pmat(string)         /// 1 x (L+1) p-values (optional)
        I2mat(string)        /// 1 x (L+1) I-squared (optional)
        CIlo(string)         /// G x (L+1) CI lower (optional)
        CIhi(string)         /// G x (L+1) CI upper (optional)
        CIpoollo(string)     /// 1 x (L+1) pooled CI lower (optional)
        CIpoolhi(string)     /// 1 x (L+1) pooled CI upper (optional)
        IVWweights(string)   /// G x (L+1) IVW weights (optional)
        MATCHstrategy(string) /// matching strategy name
        Nobs(integer 0)      /// total observations
        Nfirms(integer 0)    /// total firms
        Level(integer 95)    /// confidence level
        CMDline(string)      /// original command line
        QUIET                /// suppress display
        ]
    
    // ================================================================
    // T-009.1.2: Input validation
    // ================================================================
    
    // Check required matrices exist
    cap confirm matrix `attcohort'
    if _rc != 0 {
        di as error "{bf:pte error E-009.01}: ATT cohort matrix not found"
        exit 498
    }
    
    cap confirm matrix `secohort'
    if _rc != 0 {
        di as error "{bf:pte error E-009.01}: SE cohort matrix not found"
        exit 498
    }
    
    cap confirm matrix `attpool'
    if _rc != 0 {
        di as error "{bf:pte error E-009.01}: ATT pool vector not found"
        exit 498
    }
    
    cap confirm matrix `sepool'
    if _rc != 0 {
        di as error "{bf:pte error E-009.01}: SE pool vector not found"
        exit 498
    }
    
    cap confirm matrix `cohortlist'
    if _rc != 0 {
        di as error "{bf:pte error E-009.01}: cohort list vector not found"
        exit 498
    }
    
    cap confirm matrix `cohortsizes'
    if _rc != 0 {
        di as error "{bf:pte error E-009.01}: cohort sizes vector not found"
        exit 498
    }
    
    // Dimension checks
    local G = rowsof(`attcohort')
    local Lp1 = colsof(`attcohort')
    
    if rowsof(`secohort') != `G' | colsof(`secohort') != `Lp1' {
        di as error "{bf:pte error E-009.02}: dimension mismatch between ATT and SE cohort matrices"
        exit 503
    }
    
    if rowsof(`attpool') != 1 | colsof(`attpool') != `Lp1' {
        di as error "{bf:pte error E-009.02}: ATT pool dimension mismatch"
        exit 503
    }

    if rowsof(`sepool') != 1 | colsof(`sepool') != `Lp1' {
        di as error "{bf:pte error E-009.02}: SE pool dimension mismatch"
        exit 503
    }
    
    if rowsof(`cohortlist') != `G' | colsof(`cohortlist') != 1 {
        di as error "{bf:pte error E-009.02}: cohort list dimension mismatch"
        exit 503
    }

    if rowsof(`cohortsizes') != `G' | colsof(`cohortsizes') != 1 {
        di as error "{bf:pte error E-009.02}: cohort sizes dimension mismatch"
        exit 503
    }

    // Cohort labels become public row and display labels. Fractional values
    // would be rounded into ambiguous labels, so reject them at entry.
    mata: st_numscalar("__pte_cohort_output_clist_int_ok",             ///
        allof((floor(st_matrix("`cohortlist'")) :==                    ///
                st_matrix("`cohortlist'")) :|                          ///
            missing(st_matrix("`cohortlist'")), 1))
    if scalar(__pte_cohort_output_clist_int_ok) == 0 {
        di as error "{bf:pte error E-009.02}: cohort list must contain integer cohort identifiers"
        scalar drop __pte_cohort_output_clist_int_ok
        exit 503
    }
    capture scalar drop __pte_cohort_output_clist_int_ok

    // Standard errors are scale parameters and must be nonnegative. A
    // negative value is an invalid public payload, not a value that can be
    // squared away inside e(V) or silently excluded from Q-valid counts.
    mata: st_numscalar("__pte_cohort_output_se_ok",                   ///
        allof((st_matrix("`secohort'") :>= 0) :|                      ///
            missing(st_matrix("`secohort'")), 1)                      ///
        & allof((st_matrix("`sepool'") :>= 0) :|                      ///
            missing(st_matrix("`sepool'")), 1))
    if scalar(__pte_cohort_output_se_ok) == 0 {
        di as error "{bf:pte error E-3016}: Negative SE values detected"
        scalar drop __pte_cohort_output_se_ok
        exit 3016
    }
    capture scalar drop __pte_cohort_output_se_ok

    // Confidence intervals are a bundled bootstrap payload. A partial family
    // would publish a half-open public surface, which downstream consumers
    // must reject instead of silently downgrading.
    local ci_inputs = 0
    foreach _pte_ci_opt in cilo cihi cipoollo cipoolhi {
        if `"``_pte_ci_opt''"' != "" {
            local ++ci_inputs
        }
    }
    local has_ci_family = (`ci_inputs' > 0)
    if `has_ci_family' & `ci_inputs' < 4 {
        di as error "{bf:pte error E-009.03}: confidence interval payload requires cilo(), cihi(), cipoollo(), and cipoolhi() together"
        exit 503
    }
    if `has_ci_family' {
        foreach _pte_ci_opt in cilo cihi cipoollo cipoolhi {
            cap confirm matrix ``_pte_ci_opt''
            if _rc != 0 {
                di as error "{bf:pte error E-009.01}: CI matrix ``_pte_ci_opt'' not found"
                exit 498
            }
        }
        if rowsof(`cilo') != `G' | colsof(`cilo') != `Lp1' {
            di as error "{bf:pte error E-009.02}: cohort lower CI dimension mismatch"
            exit 503
        }
        if rowsof(`cihi') != `G' | colsof(`cihi') != `Lp1' {
            di as error "{bf:pte error E-009.02}: cohort upper CI dimension mismatch"
            exit 503
        }
        if rowsof(`cipoollo') != 1 | colsof(`cipoollo') != `Lp1' {
            di as error "{bf:pte error E-009.02}: pooled lower CI dimension mismatch"
            exit 503
        }
        if rowsof(`cipoolhi') != 1 | colsof(`cipoolhi') != `Lp1' {
            di as error "{bf:pte error E-009.02}: pooled upper CI dimension mismatch"
            exit 503
        }

        // Confidence intervals are ordered pairs, not two unrelated payloads.
        // Each cell must be either fully missing on both sides or fully
        // observed with lower <= upper.
        mata: st_numscalar("__pte_cohort_output_ci_ok",                ///
            allof(((missing(st_matrix("`cilo'")) :&                    ///
                    missing(st_matrix("`cihi'"))) :|                   ///
                ((!missing(st_matrix("`cilo'"))) :&                    ///
                 (!missing(st_matrix("`cihi'"))) :&                    ///
                 (st_matrix("`cilo'") :<= st_matrix("`cihi'")))), 1)   ///
            & allof(((missing(st_matrix("`cipoollo'")) :&              ///
                    missing(st_matrix("`cipoolhi'"))) :|               ///
                ((!missing(st_matrix("`cipoollo'"))) :&                ///
                 (!missing(st_matrix("`cipoolhi'"))) :&                ///
                 (st_matrix("`cipoollo'") :<=                          ///
                    st_matrix("`cipoolhi'")))), 1))
        if scalar(__pte_cohort_output_ci_ok) == 0 {
            di as error "{bf:pte error E-009.03}: CI payload contains half-open or reversed bounds"
            scalar drop __pte_cohort_output_ci_ok
            exit 198
        }
        capture scalar drop __pte_cohort_output_ci_ok
    }

    // IVW weights are a cohort-by-period payload. They must align exactly
    // with the cohort ATT surface; otherwise downstream consumers observe
    // extra cohorts or duplicate event-time columns that are not estimands.
    if "`ivwweights'" != "" {
        cap confirm matrix `ivwweights'
        if _rc == 0 {
            if rowsof(`ivwweights') != `G' | colsof(`ivwweights') != `Lp1' {
                di as error "{bf:pte error E-009.02}: ivwweights dimension mismatch"
                exit 503
            }
        }
    }
    
    // ================================================================
    // Resolve exact event-time support before building labels.
    // Precedence:
    //   1) explicit attperiods()
    //   2) exact-support colnames carried by core ATT/SE matrices
    //   3) legacy fallback 0..L-1
    // Optional payloads are consumers of that support. They may be relabeled
    // onto the resolved support, but they must not define it.
    // Any disagreement across explicit support and labeled core matrices is a
    // contract error because the event-time index is part of the estimand.
    // ================================================================

    tempname attperiods_store
    matrix `attperiods_store' = J(1, `Lp1', .)

    local support_tokens ""
    local support_source "legacy"
    local has_qmat = 0
    local has_pmat = 0
    local has_i2mat = 0
    if "`qmat'" != "" {
        cap confirm matrix `qmat'
        if _rc == 0 {
            local has_qmat = 1
            if rowsof(`qmat') != 1 | colsof(`qmat') != `Lp1' {
                di as error "{bf:pte error E-009.02}: qmat dimension mismatch"
                exit 503
            }
        }
    }
    if `has_qmat' & "`pmat'" != "" {
        cap confirm matrix `pmat'
        if _rc == 0 {
            local has_pmat = 1
            if rowsof(`pmat') != 1 | colsof(`pmat') != `Lp1' {
                di as error "{bf:pte error E-009.02}: pmat dimension mismatch"
                exit 503
            }
        }
    }
    if `has_qmat' & "`i2mat'" != "" {
        cap confirm matrix `i2mat'
        if _rc == 0 {
            local has_i2mat = 1
            if rowsof(`i2mat') != 1 | colsof(`i2mat') != `Lp1' {
                di as error "{bf:pte error E-009.02}: i2mat dimension mismatch"
                exit 503
            }
        }
    }

    // Q-test payloads are public heterogeneity statistics. They must obey
    // the same mathematical support as the live test producer:
    // Q >= 0, p in [0,1], I2 in [0,100].
    if `has_qmat' {
        mata: st_numscalar("__pte_qmat_range_ok",                     ///
            allof((st_matrix("`qmat'") :>= 0) :|                      ///
                missing(st_matrix("`qmat'")), 1))
        if scalar(__pte_qmat_range_ok) == 0 {
            di as error "{bf:pte error E-009.02}: qmat contains impossible Q statistics"
            scalar drop __pte_qmat_range_ok
            exit 503
        }
        capture scalar drop __pte_qmat_range_ok
    }
    if `has_qmat' & `has_pmat' {
        mata: st_numscalar("__pte_pmat_range_ok",                     ///
            allof((((st_matrix("`pmat'") :>= 0) :&                    ///
                    (st_matrix("`pmat'") :<= 1)) :|                   ///
                missing(st_matrix("`pmat'"))), 1))
        if scalar(__pte_pmat_range_ok) == 0 {
            di as error "{bf:pte error E-009.02}: pmat contains impossible p-values"
            scalar drop __pte_pmat_range_ok
            exit 503
        }
        capture scalar drop __pte_pmat_range_ok
    }
    if `has_qmat' & `has_i2mat' {
        mata: st_numscalar("__pte_i2mat_range_ok",                    ///
            allof((((st_matrix("`i2mat'") :>= 0) :&                   ///
                    (st_matrix("`i2mat'") :<= 100)) :|                ///
                missing(st_matrix("`i2mat'"))), 1))
        if scalar(__pte_i2mat_range_ok) == 0 {
            di as error "{bf:pte error E-009.02}: i2mat contains impossible I-squared values"
            scalar drop __pte_i2mat_range_ok
            exit 503
        }
        capture scalar drop __pte_i2mat_range_ok
    }

    foreach _pte_support_mat in attcohort secohort attpool sepool {
        if `"``_pte_support_mat''"' != "" {
            cap confirm matrix ``_pte_support_mat''
            if _rc != 0 {
                continue
            }
            local _pte_cols : colnames ``_pte_support_mat''
            if `"`_pte_cols'"' != "" {
                local _pte_ncols : word count `_pte_cols'
                if `_pte_ncols' != `Lp1' {
                    di as error "{bf:pte error E-009.02}: `'_pte_support_mat'' colname count does not match matrix width"
                    exit 503
                }

                local _pte_tokens ""
                local _pte_parse_ok = 1
                forvalues l = 1/`Lp1' {
                    local _pte_tok : word `l' of `_pte_cols'
                    local _pte_period ""
                    if regexm(`"`_pte_tok'"', "^nt(-?[0-9.]+)$") {
                        local _pte_period = regexs(1)
                    }
                    else if regexm(`"`_pte_tok'"', "^ATT_(-?[0-9.]+)$") {
                        local _pte_period = regexs(1)
                    }
                    else {
                        local _pte_parse_ok = 0
                        continue, break
                    }
                    local _pte_tokens "`_pte_tokens' `_pte_period'"
                }
                local _pte_tokens = trim("`_pte_tokens'")

                if `_pte_parse_ok' {
                    if `"`support_tokens'"' == "" {
                        local support_tokens "`_pte_tokens'"
                        local support_source "colnames"
                    }
                    else if `"`_pte_tokens'"' != `"`support_tokens'"' {
                        di as error "{bf:pte error E-009.02}: exact event-time support disagrees across cohort output inputs"
                        exit 503
                    }
                }
            }
        }
    }

    if `"`attperiods'"' != "" {
        if rowsof(`attperiods') != 1 | colsof(`attperiods') != `Lp1' {
            di as error "{bf:pte error E-009.02}: attperiods dimension mismatch"
            exit 503
        }
        local _pte_explicit_tokens ""
        forvalues l = 1/`Lp1' {
            local _pte_period = `attperiods'[1, `l']
            local _pte_period_str = trim(string(`_pte_period', "%21.0g"))
            local _pte_explicit_tokens "`_pte_explicit_tokens' `_pte_period_str'"
            matrix `attperiods_store'[1, `l'] = `_pte_period'
        }
        local _pte_explicit_tokens = trim("`_pte_explicit_tokens'")
        if `"`support_tokens'"' != "" & `"`support_tokens'"' != `"`_pte_explicit_tokens'"' {
            di as error "{bf:pte error E-009.02}: attperiods() disagrees with exact-support matrix labels"
            exit 503
        }
        local support_tokens "`_pte_explicit_tokens'"
        local support_source "attperiods"
    }
    else if `"`support_tokens'"' != "" {
        forvalues l = 1/`Lp1' {
            local _pte_period : word `l' of `support_tokens'
            matrix `attperiods_store'[1, `l'] = real("`_pte_period'")
        }
    }
    else {
        local _pte_legacy_tokens ""
        forvalues l = 1/`Lp1' {
            local _pte_period = `l' - 1
            local _pte_legacy_tokens "`_pte_legacy_tokens' `_pte_period'"
            matrix `attperiods_store'[1, `l'] = `_pte_period'
        }
        local support_tokens = trim("`_pte_legacy_tokens'")
    }

    // Optional payload matrices consume exact-support metadata. They should
    // agree with an already resolved core support, but they must not be able
    // to define or block the legacy fallback path on their own.
    local support_from_core = ("`support_source'" != "legacy")
    if `support_from_core' {
        foreach _pte_optional_mat in qmat pmat i2mat cilo cihi cipoollo cipoolhi ivwweights {
            if `"``_pte_optional_mat''"' == "" {
                continue
            }
            if inlist("`_pte_optional_mat'", "pmat", "i2mat") & !`has_qmat' {
                continue
            }
            cap confirm matrix ``_pte_optional_mat''
            if _rc != 0 {
                continue
            }
            local _pte_opt_cols : colnames ``_pte_optional_mat''
            if `"`_pte_opt_cols'"' == "" {
                continue
            }
            local _pte_opt_ncols : word count `_pte_opt_cols'
            if `_pte_opt_ncols' != `Lp1' {
                di as error "{bf:pte error E-009.02}: `'_pte_optional_mat'' colname count does not match matrix width"
                exit 503
            }

            local _pte_opt_tokens ""
            local _pte_opt_parse_ok = 1
            forvalues l = 1/`Lp1' {
                local _pte_tok : word `l' of `_pte_opt_cols'
                local _pte_period ""
                if regexm(`"`_pte_tok'"', "^nt(-?[0-9.]+)$") {
                    local _pte_period = regexs(1)
                }
                else if regexm(`"`_pte_tok'"', "^ATT_(-?[0-9.]+)$") {
                    local _pte_period = regexs(1)
                }
                else {
                    local _pte_opt_parse_ok = 0
                    continue, break
                }
                local _pte_opt_tokens "`_pte_opt_tokens' `_pte_period'"
            }
            local _pte_opt_tokens = trim("`_pte_opt_tokens'")

            if `_pte_opt_parse_ok' & `"`_pte_opt_tokens'"' != `"`support_tokens'"' {
                di as error "{bf:pte error E-009.02}: exact event-time support disagrees across cohort output inputs"
                exit 503
            }
        }
    }

    local period_colnames ""
    local pooled_b_colnames ""
    forvalues l = 1/`Lp1' {
        local _pte_period : word `l' of `support_tokens'
        local period_colnames "`period_colnames' nt`_pte_period'"
        local pooled_b_colnames "`pooled_b_colnames' ATT_`_pte_period'"
    }
    local period_colnames = trim("`period_colnames'")
    local pooled_b_colnames = trim("`pooled_b_colnames'")
    matrix colnames `attperiods_store' = `period_colnames'
    matrix rownames `attperiods_store' = period

    // ================================================================
    // T-009.2.1 + T-009.2.2: Build b and V for esttab compatibility
    // Dense branch retains the legacy full vector. Sparse branch falls back
    // to the pooled-only e(b)/e(V) contract because ereturn post rejects
    // missing values in the coefficient vector.
    // ================================================================

    mata: st_numscalar("__pte_sparse_cohort_output", ///
        any(st_matrix("`attcohort'") :>= .) | any(st_matrix("`secohort'") :>= .))
    local sparse_contract = scalar(__pte_sparse_cohort_output)
    capture scalar drop __pte_sparse_cohort_output

    tempname b_vec V_diag
    if `sparse_contract' {
        matrix `b_vec' = `attpool'
        mata: st_matrix("`V_diag'", diag(st_matrix("`sepool'"):^2))
        local colnames "`pooled_b_colnames'"
    }
    else {
        local K = `G' * `Lp1' + `Lp1'
        matrix `b_vec' = J(1, `K', 0)
        matrix `V_diag' = J(`K', `K', 0)

        // Fill cohort ATTs into b vector
        local col = 1
        forvalues g = 1/`G' {
            forvalues l = 1/`Lp1' {
                matrix `b_vec'[1, `col'] = `attcohort'[`g', `l']
                local se_val = `secohort'[`g', `l']
                matrix `V_diag'[`col', `col'] = `se_val' * `se_val'
                local col = `col' + 1
            }
        }

        // Fill pooled ATTs into b vector
        forvalues l = 1/`Lp1' {
            matrix `b_vec'[1, `col'] = `attpool'[1, `l']
            local se_val = `sepool'[1, `l']
            matrix `V_diag'[`col', `col'] = `se_val' * `se_val'
            local col = `col' + 1
        }

        // ================================================================
        // T-009.1.3: Set column names for dense b and V
        // Format: c{year}_nt{period} for cohorts, pool_nt{period} for pooled
        // ================================================================
        local colnames ""
        forvalues g = 1/`G' {
            local cyear = `cohortlist'[`g', 1]
            local cyear_int = int(`cyear')
            forvalues l = 1/`Lp1' {
                local period : word `l' of `support_tokens'
                local colnames "`colnames' c`cyear_int'_nt`period'"
            }
        }
        forvalues l = 1/`Lp1' {
            local period : word `l' of `support_tokens'
            local colnames "`colnames' pool_nt`period'"
        }
    }

    matrix colnames `b_vec' = `colnames'
    matrix colnames `V_diag' = `colnames'
    matrix rownames `V_diag' = `colnames'
    
    // ================================================================
    // T-009.2.3: ereturn post (must come first)
    // ================================================================
    
    ereturn post `b_vec' `V_diag'
    
    // ================================================================
    // T-009.1.4: Store matrices in e()
    // ================================================================
    
    // Set row/col names on cohort matrices
    tempname att_c se_c att_p se_p clist csizes
    matrix `att_c' = `attcohort'
    matrix `se_c' = `secohort'
    matrix `att_p' = `attpool'
    matrix `se_p' = `sepool'
    matrix `clist' = `cohortlist'
    matrix `csizes' = `cohortsizes'
    
    // Set row names (cohort years)
    local rownames ""
    forvalues g = 1/`G' {
        local cyear = `cohortlist'[`g', 1]
        local cyear_int = int(`cyear')
        local rownames "`rownames' c`cyear_int'"
    }
    matrix rownames `att_c' = `rownames'
    matrix rownames `se_c' = `rownames'
    
    matrix colnames `att_c' = `period_colnames'
    matrix colnames `se_c' = `period_colnames'
    matrix colnames `att_p' = `period_colnames'
    matrix colnames `se_p' = `period_colnames'
    
    ereturn matrix att_cohort = `att_c'
    ereturn matrix att_cohort_se = `se_c'
    ereturn matrix att_pool = `att_p'
    ereturn matrix att_pool_se = `se_p'
    ereturn matrix cohort_list = `clist'
    ereturn matrix cohort_sizes = `csizes'
    ereturn matrix attperiods = `attperiods_store'
    
    // Optional heterogeneity matrices. Keep the public e() surface aligned
    // with _pte_cohort_ereturn: a no-q path still publishes exact-support
    // missing matrices instead of silently dropping the payload family.
    tempname q_df_store q_g_store
    local q_df_scalar = .
    local q_g_scalar = .
    local q_df_consistent = 1
    local q_g_consistent = 1
    if `has_qmat' {
        matrix `q_df_store' = J(1, `Lp1', .)
        matrix `q_g_store' = J(1, `Lp1', .)
        local q_any_valid = 0
        forvalues l = 1/`Lp1' {
            local n_valid = 0
            forvalues g = 1/`G' {
                local att_gl = `attcohort'[`g', `l']
                local se_gl = `secohort'[`g', `l']
                if `att_gl' < . & `se_gl' < . & `se_gl' > 0 {
                    local ++n_valid
                }
            }
            matrix `q_g_store'[1, `l'] = `n_valid'
            if `n_valid' >= 2 {
                local q_any_valid = 1
                local df_l = `n_valid' - 1
                matrix `q_df_store'[1, `l'] = `df_l'
                if `q_df_scalar' >= . {
                    local q_df_scalar = `df_l'
                    local q_g_scalar = `n_valid'
                }
                else {
                    if `df_l' != `q_df_scalar' local q_df_consistent = 0
                    if `n_valid' != `q_g_scalar' local q_g_consistent = 0
                }
            }
            else if `q_df_scalar' < . | `q_g_scalar' < . {
                local q_df_consistent = 0
                local q_g_consistent = 0
            }
        }
        matrix colnames `q_df_store' = `period_colnames'
        matrix colnames `q_g_store' = `period_colnames'
        ereturn matrix df_Q_period = `q_df_store'
        ereturn matrix G_Q_period = `q_g_store'
        if `q_any_valid' & `q_df_consistent' & `q_df_scalar' < . {
            ereturn scalar df_Q = `q_df_scalar'
        }
        else {
            ereturn scalar df_Q = .
        }
        if `q_any_valid' & `q_g_consistent' & `q_g_scalar' < . {
            ereturn scalar G_Q = `q_g_scalar'
        }
        else {
            ereturn scalar G_Q = .
        }
        tempname q_store
        matrix `q_store' = `qmat'
        matrix colnames `q_store' = `period_colnames'
        ereturn matrix cohort_het_Q = `q_store'
    }
    
    if `has_qmat' & `has_pmat' {
        tempname p_store
        matrix `p_store' = `pmat'
        matrix colnames `p_store' = `period_colnames'
        ereturn matrix cohort_het_p = `p_store'
    }
    else if `has_qmat' {
        tempname p_miss
        matrix `p_miss' = J(1, `Lp1', .)
        matrix colnames `p_miss' = `period_colnames'
        ereturn matrix cohort_het_p = `p_miss'
    }
    
    if `has_qmat' & `has_i2mat' {
        tempname i2_store
        matrix `i2_store' = `i2mat'
        matrix colnames `i2_store' = `period_colnames'
        ereturn matrix cohort_het_I2 = `i2_store'
    }
    else if `has_qmat' {
        tempname i2_miss
        matrix `i2_miss' = J(1, `Lp1', .)
        matrix colnames `i2_miss' = `period_colnames'
        ereturn matrix cohort_het_I2 = `i2_miss'
    }
    else {
        tempname q_miss p_miss i2_miss df_miss g_miss
        matrix `q_miss' = J(1, `Lp1', .)
        matrix colnames `q_miss' = `period_colnames'
        ereturn matrix cohort_het_Q = `q_miss'

        matrix `p_miss' = J(1, `Lp1', .)
        matrix colnames `p_miss' = `period_colnames'
        ereturn matrix cohort_het_p = `p_miss'

        matrix `i2_miss' = J(1, `Lp1', .)
        matrix colnames `i2_miss' = `period_colnames'
        ereturn matrix cohort_het_I2 = `i2_miss'

        matrix `df_miss' = J(1, `Lp1', .)
        matrix colnames `df_miss' = `period_colnames'
        ereturn matrix df_Q_period = `df_miss'

        matrix `g_miss' = J(1, `Lp1', .)
        matrix colnames `g_miss' = `period_colnames'
        ereturn matrix G_Q_period = `g_miss'

        ereturn scalar df_Q = 0
        ereturn scalar G_Q = `G'
    }
    
    if `has_ci_family' {
        tempname ci_lo_store ci_hi_store cip_lo cip_hi
        matrix `ci_lo_store' = `cilo'
        matrix rownames `ci_lo_store' = `rownames'
        matrix colnames `ci_lo_store' = `period_colnames'
        ereturn matrix att_cohort_ci_l = `ci_lo_store'

        matrix `ci_hi_store' = `cihi'
        matrix rownames `ci_hi_store' = `rownames'
        matrix colnames `ci_hi_store' = `period_colnames'
        ereturn matrix att_cohort_ci_u = `ci_hi_store'

        matrix `cip_lo' = `cipoollo'
        matrix colnames `cip_lo' = `period_colnames'
        ereturn matrix att_pool_ci_l = `cip_lo'

        matrix `cip_hi' = `cipoolhi'
        matrix colnames `cip_hi' = `period_colnames'
        ereturn matrix att_pool_ci_u = `cip_hi'
    }
    
    if "`ivwweights'" != "" {
        cap confirm matrix `ivwweights'
        if _rc == 0 {
            tempname ivw_store
            matrix `ivw_store' = `ivwweights'
            matrix rownames `ivw_store' = `rownames'
            matrix colnames `ivw_store' = `period_colnames'
            ereturn matrix ivw_weights = `ivw_store'
        }
    }
    
    // ================================================================
    // T-009.1.5: Store scalars
    // ================================================================
    
    ereturn scalar n_cohorts = `G'
    ereturn scalar n_periods = `Lp1'
    ereturn scalar level = `level'
    
    if `nobs' > 0 {
        ereturn scalar N = `nobs'
    }
    if `nfirms' > 0 {
        ereturn scalar N_g = `nfirms'
    }
    
    // ================================================================
    // T-009.1.6: Store macros
    // ================================================================
    
    ereturn local cmd "pte"
    ereturn local subcmd "cohort"
    ereturn local properties "b V"
    
    if "`matchstrategy'" != "" {
        ereturn local matchstrategy "`matchstrategy'"
    }
    else {
        ereturn local matchstrategy "notyettreated"
    }
    
    if `"`cmdline'"' != "" {
        ereturn local cmdline `"`cmdline'"'
    }
    
    // ================================================================
    // T-009.3.1 ~ T-009.3.5: Display formatted output
    // ================================================================
    
    if "`quiet'" != "" {
        exit
    }
    
    // --- Cohort summary ---
    di as text ""
    di as text "Cohort Analysis Summary"
    di as text "{hline 55}"
    di as text "  Number of cohorts:    " as result %5.0f `G'
    di as text "  Number of periods:    " as result %5.0f `Lp1'
    if `nobs' > 0 {
        di as text "  Total observations:   " as result %5.0f `nobs'
    }
    if `nfirms' > 0 {
        di as text "  Total firms:          " as result %5.0f `nfirms'
    }
    di as text "  Matching strategy:    " as result "`matchstrategy'"
    di as text ""
    
    // --- Cohort sizes ---
    di as text "  Cohort sizes:"
    forvalues g = 1/`G' {
        local cyear = `cohortlist'[`g', 1]
        local cyear_int = int(`cyear')
        local csize = `cohortsizes'[`g', 1]
        local csize_int = int(`csize')
        di as text "    Cohort `cyear_int': " as result %5.0f `csize_int' as text " firms"
    }
    
    // --- ATT table ---
    di as text ""
    di as text "{hline 70}"
    di as text "Cohort-specific ATT estimates"
    di as text "{hline 70}"
    
    // Column headers
    di as text _col(14) _continue
    forvalues l = 1/`Lp1' {
        local period : word `l' of `support_tokens'
        di as text %12s "nt`period'" _continue
    }
    di ""
    di as text "{hline 70}"
    
    // Cohort rows
    forvalues g = 1/`G' {
        local cyear = `cohortlist'[`g', 1]
        local cyear_int = int(`cyear')
        
        // ATT row
        di as text %12s "c`cyear_int'" "  " _continue
        forvalues l = 1/`Lp1' {
            local att_val = `attcohort'[`g', `l']
            local se_val = `secohort'[`g', `l']
            
            // Significance stars
            local stars ""
            if `se_val' > 0 & `se_val' < . {
                local tstat = abs(`att_val' / `se_val')
                if `tstat' > 2.576 {
                    local stars "***"
                }
                else if `tstat' > 1.960 {
                    local stars "**"
                }
                else if `tstat' > 1.645 {
                    local stars "*"
                }
            }
            
            if `att_val' < . {
                di as result %9.4f `att_val' as text "`stars'" _continue
            }
            else {
                di as text %12s "N/A" _continue
            }
        }
        di ""
        
        // SE row (in parentheses)
        di as text _col(14) _continue
        forvalues l = 1/`Lp1' {
            local se_val = `secohort'[`g', `l']
            if `se_val' < . {
                di as text "(" as result %7.4f `se_val' as text ")  " _continue
            }
            else {
                di as text %12s "" _continue
            }
        }
        di ""
    }
    
    // Separator
    di as text "{hline 70}"
    
    // Pooled row
    di as text %12s "Pooled" "  " _continue
    forvalues l = 1/`Lp1' {
        local att_val = `attpool'[1, `l']
        local se_val = `sepool'[1, `l']
        
        local stars ""
        if `se_val' > 0 & `se_val' < . {
            local tstat = abs(`att_val' / `se_val')
            if `tstat' > 2.576 {
                local stars "***"
            }
            else if `tstat' > 1.960 {
                local stars "**"
            }
            else if `tstat' > 1.645 {
                local stars "*"
            }
        }
        
        if `att_val' < . {
            di as result %9.4f `att_val' as text "`stars'" _continue
        }
        else {
            di as text %12s "N/A" _continue
        }
    }
    di ""
    
    // Pooled SE row
    di as text _col(14) _continue
    forvalues l = 1/`Lp1' {
        local se_val = `sepool'[1, `l']
        if `se_val' < . {
            di as text "(" as result %7.4f `se_val' as text ")  " _continue
        }
        else {
            di as text %12s "" _continue
        }
    }
    di ""
    
    di as text "{hline 70}"
    di as text "  *** p<0.01, ** p<0.05, * p<0.10"
    
    // --- Q-test output (optional) ---
    if `has_qmat' {
        cap confirm matrix e(cohort_het_p)
        if _rc == 0 {
            tempname qtest_p
            matrix `qtest_p' = e(cohort_het_p)
            di as text ""
            di as text "Q-test p-value" _col(14) _continue
            forvalues l = 1/`Lp1' {
                local p_val = .
                cap local p_val = el(`qtest_p', 1, `l')
                if `p_val' < . {
                    di as result %12.4f `p_val' _continue
                }
                else {
                    di as text %12s "." _continue
                }
            }
            di ""
        }
    }
    
end
