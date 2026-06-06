*! _pte_cf_inference.ado
*! Computes bootstrap inference statistics from pre-computed bootstrap matrices:
*! - Standard errors (SD of bootstrap distribution)
*! - Percentile confidence intervals
*! - Two-sided p-values: p = 2 * min(P(>=0), P(<=0)), capped at 1
*! - Wald joint test: H0: Delta_0 = ... = Delta_L = 0
*! Can be called standalone with bootstrap matrices or as part of
*! _pte_bootstrap_cf pipeline.

version 14.0
capture program drop _pte_cf_inference
program define _pte_cf_inference, eclass
    version 14.0
    syntax, bs_att(name) bs_ate(name) bs_delta(name) ///
        att_point(name) ate_point(name) ///
        [level(integer 95) ///
         attperiods(integer 4) ///
         breps(integer 100) ///
         n_success(integer 0) ///
         NODISplay]

    // ================================================================
    // Step 0: Input validation
    // ================================================================
    if `level' < 10 | `level' > 99 {
        di as error "[pte] Error: level must be between 10 and 99"
        exit 198
    }

    // Validate matrix dimensions
    local nperiods = `attperiods' + 1
    local ncols = `nperiods' + 1   // periods 0..L + pooled

    // Check bootstrap matrix dimensions
    capture confirm matrix `bs_att'
    if _rc != 0 {
        di as error "[pte] Error: bootstrap ATT matrix not found"
        exit 198
    }
    local bs_rows = rowsof(`bs_att')
    local bs_cols = colsof(`bs_att')
    if `bs_cols' != `ncols' {
        di as error "[pte] Error: bs_att has `bs_cols' columns, expected `ncols'"
        exit 503
    }

    capture confirm matrix `bs_ate'
    if _rc != 0 {
        di as error "[pte] Error: bootstrap ATE^count matrix not found"
        exit 198
    }
    local bs_ate_rows = rowsof(`bs_ate')
    local bs_ate_cols = colsof(`bs_ate')
    if `bs_ate_rows' != `bs_rows' | `bs_ate_cols' != `ncols' {
        di as error "[pte] Error: bs_ate has `bs_ate_rows' x `bs_ate_cols', expected `bs_rows' x `ncols'"
        exit 503
    }

    capture confirm matrix `bs_delta'
    if _rc != 0 {
        di as error "[pte] Error: bootstrap Delta matrix not found"
        exit 198
    }
    local bs_delta_rows = rowsof(`bs_delta')
    local bs_delta_cols = colsof(`bs_delta')
    if `bs_delta_rows' != `bs_rows' | `bs_delta_cols' != `ncols' {
        di as error "[pte] Error: bs_delta has `bs_delta_rows' x `bs_delta_cols', expected `bs_rows' x `ncols'"
        exit 503
    }

    capture confirm matrix `att_point'
    if _rc != 0 {
        di as error "[pte] Error: ATT point-estimate matrix not found"
        exit 198
    }
    if rowsof(`att_point') != 1 | colsof(`att_point') != `ncols' {
        di as error "[pte] Error: att_point must be a 1 x `ncols' row vector"
        exit 503
    }

    capture confirm matrix `ate_point'
    if _rc != 0 {
        di as error "[pte] Error: ATE^count point-estimate matrix not found"
        exit 198
    }
    if rowsof(`ate_point') != 1 | colsof(`ate_point') != `ncols' {
        di as error "[pte] Error: ate_point must be a 1 x `ncols' row vector"
        exit 503
    }

    // Use n_success if provided, otherwise infer successful bootstrap draws
    // from the pooled Delta column. In the bootstrap pipeline, a draw counts
    // as successful only when ATT and ATE^count both complete, which is
    // exactly when the pooled Delta entry is available.
    if `n_success' == 0 {
        local n_success = 0
        forvalues bb = 1/`bs_rows' {
            local _delta_ok = `bs_delta'[`bb', `ncols']
            if !missing(`_delta_ok') {
                local ++n_success
            }
        }
    }
    if `n_success' < 2 {
        di as error "[pte] Error: fewer than 2 successful bootstrap iterations"
        exit 2000
    }

    // ================================================================
    // Step 1: Initialize result matrices
    // ================================================================
    local alpha = (100 - `level') / 200
    // Percentile points (in percent) for the _pctile-based CI bounds, matching
    // the official replication DOs (egen pctile(), p(.)).
    local p_lo = 100 * `alpha'
    local p_hi = 100 * (1 - `alpha')

    tempname se_att ci_lo_att ci_hi_att pval_att
    tempname se_ate ci_lo_ate ci_hi_ate pval_ate
    tempname se_delta ci_lo_delta ci_hi_delta pval_delta

    matrix `se_att' = J(1, `ncols', .)
    matrix `ci_lo_att' = J(1, `ncols', .)
    matrix `ci_hi_att' = J(1, `ncols', .)
    matrix `pval_att' = J(1, `ncols', .)

    matrix `se_ate' = J(1, `ncols', .)
    matrix `ci_lo_ate' = J(1, `ncols', .)
    matrix `ci_hi_ate' = J(1, `ncols', .)
    matrix `pval_ate' = J(1, `ncols', .)

    matrix `se_delta' = J(1, `ncols', .)
    matrix `ci_lo_delta' = J(1, `ncols', .)
    matrix `ci_hi_delta' = J(1, `ncols', .)
    matrix `pval_delta' = J(1, `ncols', .)

    // ================================================================
    // Step 2: Load bootstrap results into temporary dataset
    // ================================================================
    preserve
    clear
    quietly set obs `bs_rows'

    forvalues j = 1/`ncols' {
        quietly gen double _att`j' = .
        quietly gen double _ate`j' = .
        quietly gen double _delta`j' = .
        forvalues bb = 1/`bs_rows' {
            local va = `bs_att'[`bb', `j']
            local vc = `bs_ate'[`bb', `j']
            local vd = `bs_delta'[`bb', `j']
            if !missing(`va') {
                quietly replace _att`j' = `va' in `bb'
            }
            if !missing(`vc') {
                quietly replace _ate`j' = `vc' in `bb'
            }
            if !missing(`vd') {
                quietly replace _delta`j' = `vd' in `bb'
            }
        }
    }

    // ================================================================
    // Step 3: Compute SE, percentile CI, and p-values for each column
    // ================================================================
    forvalues j = 1/`ncols' {

        // --- ATT ---
        quietly summarize _att`j'
        if r(N) >= 2 {
            matrix `se_att'[1, `j'] = r(sd)

            // Percentile CI: use _pctile so the bounds match the official
            // replication DOs (egen pctile(), p(.)) exactly.
            quietly count if !missing(_att`j')
            local nv = r(N)
            quietly _pctile _att`j' if !missing(_att`j'), percentiles(`p_lo' `p_hi')
            matrix `ci_lo_att'[1, `j'] = r(r1)
            matrix `ci_hi_att'[1, `j'] = r(r2)

            // Count zero mass on both tails so a degenerate null distribution
            // does not spuriously reject at p = 0.
            quietly count if _att`j' >= 0 & !missing(_att`j')
            local n_nonneg = r(N)
            quietly count if _att`j' <= 0 & !missing(_att`j')
            local n_nonpos = r(N)
            local prop_nonneg = `n_nonneg' / `nv'
            local prop_nonpos = `n_nonpos' / `nv'
            local pv = min(1, 2 * min(`prop_nonneg', `prop_nonpos'))
            matrix `pval_att'[1, `j'] = `pv'
        }

        // --- ATE^count ---
        quietly summarize _ate`j'
        if r(N) >= 2 {
            matrix `se_ate'[1, `j'] = r(sd)

            quietly count if !missing(_ate`j')
            local nv = r(N)
            quietly _pctile _ate`j' if !missing(_ate`j'), percentiles(`p_lo' `p_hi')
            matrix `ci_lo_ate'[1, `j'] = r(r1)
            matrix `ci_hi_ate'[1, `j'] = r(r2)

            quietly count if _ate`j' >= 0 & !missing(_ate`j')
            local n_nonneg = r(N)
            quietly count if _ate`j' <= 0 & !missing(_ate`j')
            local n_nonpos = r(N)
            local prop_nonneg = `n_nonneg' / `nv'
            local prop_nonpos = `n_nonpos' / `nv'
            local pv = min(1, 2 * min(`prop_nonneg', `prop_nonpos'))
            matrix `pval_ate'[1, `j'] = `pv'
        }

        // --- Delta = ATT - ATE^count ---
        quietly summarize _delta`j'
        if r(N) >= 2 {
            matrix `se_delta'[1, `j'] = r(sd)

            quietly count if !missing(_delta`j')
            local nv = r(N)
            quietly _pctile _delta`j' if !missing(_delta`j'), percentiles(`p_lo' `p_hi')
            matrix `ci_lo_delta'[1, `j'] = r(r1)
            matrix `ci_hi_delta'[1, `j'] = r(r2)

            quietly count if _delta`j' >= 0 & !missing(_delta`j')
            local n_nonneg = r(N)
            quietly count if _delta`j' <= 0 & !missing(_delta`j')
            local n_nonpos = r(N)
            local prop_nonneg = `n_nonneg' / `nv'
            local prop_nonpos = `n_nonpos' / `nv'
            local pv = min(1, 2 * min(`prop_nonneg', `prop_nonpos'))
            matrix `pval_delta'[1, `j'] = `pv'
        }
    }

    // ================================================================
    // Step 4: Wald joint test
    // H0: Delta_0 = Delta_1 = ... = Delta_L = 0
    // Wald = Delta' * V^{-1} * Delta ~ chi2(L+1)
    // ================================================================
    local wald_joint = .
    local wald_pval = .
    local wald_df = `nperiods'

    if `nperiods' >= 1 {
        // Build Delta point estimate vector (exclude pooled column)
        tempname delta_vec V_boot V_boot_inv wald_mat
        matrix `delta_vec' = J(`nperiods', 1, 0)
        forvalues i = 1/`nperiods' {
            local _att_i = `att_point'[1, `i']
            local _ate_i = `ate_point'[1, `i']
            if !missing(`_att_i') & !missing(`_ate_i') {
                matrix `delta_vec'[`i', 1] = `_att_i' - `_ate_i'
            }
        }

        // Variance-covariance matrix from bootstrap delta columns
        // Keep only period-specific delta columns (exclude pooled)
        capture {
            tempvar _pte_wald_rowmiss
            keep _delta1-_delta`nperiods'
            quietly egen `_pte_wald_rowmiss' = rowmiss(_delta1-_delta`nperiods')
            quietly count if `_pte_wald_rowmiss' == 0
            local n_wald = r(N)
            if `n_wald' >= 2 {
                quietly keep if `_pte_wald_rowmiss' == 0
                drop `_pte_wald_rowmiss'
                mat accum `V_boot' = _delta*, deviations noconstant
                mat `V_boot' = `V_boot' / (`n_wald' - 1)

                // Check invertibility
                local det_v = det(`V_boot')
                if `det_v' > 1e-10 {
                    mat `V_boot_inv' = inv(`V_boot')
                }
                else {
                    // Use Mata generalized inverse for near-singular case
                    if "`nodisplay'" == "" {
                        di as text "  Note: Variance matrix near-singular, using generalized inverse"
                    }
                    mata: st_matrix("`V_boot_inv'", pinv(st_matrix("`V_boot'")))
                }

                // Wald = Delta' * V^{-1} * Delta
                mat `wald_mat' = `delta_vec'' * `V_boot_inv' * `delta_vec'
                local wald_joint = `wald_mat'[1, 1]
                local wald_pval = 1 - chi2(`wald_df', `wald_joint')
            }
        }
        if _rc != 0 {
            if "`nodisplay'" == "" {
                di as text "  Note: Wald test computation failed (rc=" _rc ")"
            }
            local wald_joint = .
            local wald_pval = .
        }
    }

    restore

    // Shared comparison consumers treat e(attperiods) as the exact realized
    // dynamic support. Keep only periods where both ATT and ATE^count are
    // identified, rather than reposting the originally requested 0..L horizon.
    local _pte_sparse_support_cols ""
    local _pte_sparse_support_periods ""
    forvalues s = 0/`attperiods' {
        local _pte_source_col = `s' + 1
        if !missing(`att_point'[1, `_pte_source_col']) & ///
            !missing(`ate_point'[1, `_pte_source_col']) {
            local _pte_sparse_support_cols ///
                "`_pte_sparse_support_cols' `_pte_source_col'"
            local _pte_sparse_support_periods ///
                "`_pte_sparse_support_periods' `s'"
        }
    }
    local _pte_sparse_support_cols : list retokenize _pte_sparse_support_cols
    local _pte_sparse_support_periods : list retokenize _pte_sparse_support_periods
    local _pte_sparse_nperiods : word count `_pte_sparse_support_cols'
    if `_pte_sparse_nperiods' < 1 {
        di as error "[pte] Error: no common nonmissing dynamic ATT/ATE^count periods remain"
        exit 2000
    }
    local _pte_sparse_ncols = `_pte_sparse_nperiods' + 1
    local wald_df = `_pte_sparse_nperiods'

    // ================================================================
    // Step 5: Display results table
    // ================================================================
    if "`nodisplay'" == "" {
        di as text ""
        di as text "{hline 70}"
        di as text "Counterfactual Inference Results (`level'% CI, `n_success' reps)"
        di as text "{hline 70}"

        // --- ATT results ---
        di as text ""
        di as text "  ATT (Average Treatment Effect on the Treated):"
        di as text "  " _col(5) "ell" _col(14) "ATT" _col(26) "BS_SE" _col(38) "[`level'% CI]" _col(62) "p-val"
        di as text "  {hline 62}"
        local _pte_display_idx = 0
        foreach s of local _pte_sparse_support_periods {
            local ++_pte_display_idx
            local col : word `_pte_display_idx' of `_pte_sparse_support_cols'
            local att_pt = `att_point'[1, `col']
            local bse = `se_att'[1, `col']
            local cil = `ci_lo_att'[1, `col']
            local cih = `ci_hi_att'[1, `col']
            local pv = `pval_att'[1, `col']
            if !missing(`att_pt') & !missing(`bse') {
                di as text "  " _col(5) %3.0f `s' _col(11) as result %10.4f `att_pt' _col(23) as result %8.4f `bse' _col(33) as text "[" as result %7.4f `cil' as text "," as result %7.4f `cih' as text "]" _col(58) as result %6.4f `pv'
            }
        }
        // Pooled row
        local att_pooled = `att_point'[1, `ncols']
        local bse_p = `se_att'[1, `ncols']
        local cil_p = `ci_lo_att'[1, `ncols']
        local cih_p = `ci_hi_att'[1, `ncols']
        local pv_p = `pval_att'[1, `ncols']
        di as text "  {hline 62}"
        di as text "  " _col(5) "All" _col(11) as result %10.4f `att_pooled' _col(23) as result %8.4f `bse_p' _col(33) as text "[" as result %7.4f `cil_p' as text "," as result %7.4f `cih_p' as text "]" _col(58) as result %6.4f `pv_p'

        // --- ATE^count results ---
        di as text ""
        di as text "  ATE^count (Counterfactual Average Treatment Effect):"
        di as text "  " _col(5) "ell" _col(14) "ATE_cf" _col(26) "BS_SE" _col(38) "[`level'% CI]" _col(62) "p-val"
        di as text "  {hline 62}"
        local _pte_display_idx = 0
        foreach s of local _pte_sparse_support_periods {
            local ++_pte_display_idx
            local col : word `_pte_display_idx' of `_pte_sparse_support_cols'
            local ate_pt = `ate_point'[1, `col']
            local bse = `se_ate'[1, `col']
            local cil = `ci_lo_ate'[1, `col']
            local cih = `ci_hi_ate'[1, `col']
            local pv = `pval_ate'[1, `col']
            if !missing(`ate_pt') & !missing(`bse') {
                di as text "  " _col(5) %3.0f `s' _col(11) as result %10.4f `ate_pt' _col(23) as result %8.4f `bse' _col(33) as text "[" as result %7.4f `cil' as text "," as result %7.4f `cih' as text "]" _col(58) as result %6.4f `pv'
            }
        }
        local ate_pooled = `ate_point'[1, `ncols']
        local bse_p = `se_ate'[1, `ncols']
        local cil_p = `ci_lo_ate'[1, `ncols']
        local cih_p = `ci_hi_ate'[1, `ncols']
        local pv_p = `pval_ate'[1, `ncols']
        di as text "  {hline 62}"
        di as text "  " _col(5) "All" _col(11) as result %10.4f `ate_pooled' _col(23) as result %8.4f `bse_p' _col(33) as text "[" as result %7.4f `cil_p' as text "," as result %7.4f `cih_p' as text "]" _col(58) as result %6.4f `pv_p'

        // --- Delta = ATT - ATE^count ---
        di as text ""
        di as text "  Delta = ATT - ATE^count (Difference Test):"
        di as text "  " _col(5) "ell" _col(14) "Delta" _col(26) "BS_SE" _col(38) "[`level'% CI]" _col(62) "p-val"
        di as text "  {hline 62}"
        local _pte_display_idx = 0
        foreach s of local _pte_sparse_support_periods {
            local ++_pte_display_idx
            local col : word `_pte_display_idx' of `_pte_sparse_support_cols'
            local att_pt = `att_point'[1, `col']
            local ate_pt = `ate_point'[1, `col']
            local delta_pt = .
            if !missing(`att_pt') & !missing(`ate_pt') {
                local delta_pt = `att_pt' - `ate_pt'
            }
            local bse = `se_delta'[1, `col']
            local cil = `ci_lo_delta'[1, `col']
            local cih = `ci_hi_delta'[1, `col']
            local pv = `pval_delta'[1, `col']
            if !missing(`delta_pt') & !missing(`bse') {
                di as text "  " _col(5) %3.0f `s' _col(11) as result %10.4f `delta_pt' _col(23) as result %8.4f `bse' _col(33) as text "[" as result %7.4f `cil' as text "," as result %7.4f `cih' as text "]" _col(58) as result %6.4f `pv'
            }
        }
        local att_pooled = `att_point'[1, `ncols']
        local ate_pooled = `ate_point'[1, `ncols']
        local delta_pooled = .
        if !missing(`att_pooled') & !missing(`ate_pooled') {
            local delta_pooled = `att_pooled' - `ate_pooled'
        }
        local bse_p = `se_delta'[1, `ncols']
        local cil_p = `ci_lo_delta'[1, `ncols']
        local cih_p = `ci_hi_delta'[1, `ncols']
        local pv_p = `pval_delta'[1, `ncols']
        di as text "  {hline 62}"
        di as text "  " _col(5) "All" _col(11) as result %10.4f `delta_pooled' _col(23) as result %8.4f `bse_p' _col(33) as text "[" as result %7.4f `cil_p' as text "," as result %7.4f `cih_p' as text "]" _col(58) as result %6.4f `pv_p'

        // --- Wald joint test ---
        di as text ""
        if !missing(`wald_joint') {
            di as text "  Wald joint test: H0: Delta_0 = ... = Delta_L = 0"
            di as text "    Wald statistic = " as result %10.4f `wald_joint'
            di as text "    df             = " as result `wald_df'
            di as text "    p-value        = " as result %8.4f `wald_pval'
        }
        else {
            di as text "  Wald joint test: not computed"
        }
        di as text "{hline 70}"
    }

    // ================================================================
    // Step 6: Store e() return values
    // ================================================================
    ereturn clear

    // --- Scalar returns ---
    tempname att_mat ate_mat attperiods_vec attperiods_mat
    tempname se_att_out ci_lo_att_out ci_hi_att_out pval_att_out
    tempname se_ate_out ci_lo_ate_out ci_hi_ate_out pval_ate_out
    tempname se_delta_out ci_lo_delta_out ci_hi_delta_out pval_delta_out
    matrix `att_mat' = J(1, `_pte_sparse_ncols', .)
    matrix `ate_mat' = J(1, `_pte_sparse_ncols', .)
    matrix `attperiods_vec' = J(1, `_pte_sparse_nperiods', .)
    matrix `se_att_out' = J(1, `_pte_sparse_ncols', .)
    matrix `ci_lo_att_out' = J(1, `_pte_sparse_ncols', .)
    matrix `ci_hi_att_out' = J(1, `_pte_sparse_ncols', .)
    matrix `pval_att_out' = J(1, `_pte_sparse_ncols', .)
    matrix `se_ate_out' = J(1, `_pte_sparse_ncols', .)
    matrix `ci_lo_ate_out' = J(1, `_pte_sparse_ncols', .)
    matrix `ci_hi_ate_out' = J(1, `_pte_sparse_ncols', .)
    matrix `pval_ate_out' = J(1, `_pte_sparse_ncols', .)
    matrix `se_delta_out' = J(1, `_pte_sparse_ncols', .)
    matrix `ci_lo_delta_out' = J(1, `_pte_sparse_ncols', .)
    matrix `ci_hi_delta_out' = J(1, `_pte_sparse_ncols', .)
    matrix `pval_delta_out' = J(1, `_pte_sparse_ncols', .)
    local att_colnames ""
    local ate_colnames ""
    local delta_colnames ""
    local ap_colnames ""
    local _pte_store_idx = 0
    foreach s of local _pte_sparse_support_periods {
        local ++_pte_store_idx
        local col : word `_pte_store_idx' of `_pte_sparse_support_cols'
        local _att_pt = `att_point'[1, `col']
        local _ate_pt = `ate_point'[1, `col']
        matrix `att_mat'[1, `_pte_store_idx'] = `_att_pt'
        matrix `ate_mat'[1, `_pte_store_idx'] = `_ate_pt'
        matrix `attperiods_vec'[1, `_pte_store_idx'] = `s'
        matrix `se_att_out'[1, `_pte_store_idx'] = `se_att'[1, `col']
        matrix `ci_lo_att_out'[1, `_pte_store_idx'] = `ci_lo_att'[1, `col']
        matrix `ci_hi_att_out'[1, `_pte_store_idx'] = `ci_hi_att'[1, `col']
        matrix `pval_att_out'[1, `_pte_store_idx'] = `pval_att'[1, `col']
        matrix `se_ate_out'[1, `_pte_store_idx'] = `se_ate'[1, `col']
        matrix `ci_lo_ate_out'[1, `_pte_store_idx'] = `ci_lo_ate'[1, `col']
        matrix `ci_hi_ate_out'[1, `_pte_store_idx'] = `ci_hi_ate'[1, `col']
        matrix `pval_ate_out'[1, `_pte_store_idx'] = `pval_ate'[1, `col']
        matrix `se_delta_out'[1, `_pte_store_idx'] = `se_delta'[1, `col']
        matrix `ci_lo_delta_out'[1, `_pte_store_idx'] = `ci_lo_delta'[1, `col']
        matrix `ci_hi_delta_out'[1, `_pte_store_idx'] = `ci_hi_delta'[1, `col']
        matrix `pval_delta_out'[1, `_pte_store_idx'] = `pval_delta'[1, `col']
        local att_colnames "`att_colnames' att_`s'"
        local ate_colnames "`ate_colnames' ate_count_`s'"
        local delta_colnames "`delta_colnames' delta_`s'"
        local ap_colnames "`ap_colnames' `s'"
    }
    matrix `att_mat'[1, `_pte_sparse_ncols'] = `att_point'[1, `ncols']
    matrix `ate_mat'[1, `_pte_sparse_ncols'] = `ate_point'[1, `ncols']
    matrix `se_att_out'[1, `_pte_sparse_ncols'] = `se_att'[1, `ncols']
    matrix `ci_lo_att_out'[1, `_pte_sparse_ncols'] = `ci_lo_att'[1, `ncols']
    matrix `ci_hi_att_out'[1, `_pte_sparse_ncols'] = `ci_hi_att'[1, `ncols']
    matrix `pval_att_out'[1, `_pte_sparse_ncols'] = `pval_att'[1, `ncols']
    matrix `se_ate_out'[1, `_pte_sparse_ncols'] = `se_ate'[1, `ncols']
    matrix `ci_lo_ate_out'[1, `_pte_sparse_ncols'] = `ci_lo_ate'[1, `ncols']
    matrix `ci_hi_ate_out'[1, `_pte_sparse_ncols'] = `ci_hi_ate'[1, `ncols']
    matrix `pval_ate_out'[1, `_pte_sparse_ncols'] = `pval_ate'[1, `ncols']
    matrix `se_delta_out'[1, `_pte_sparse_ncols'] = `se_delta'[1, `ncols']
    matrix `ci_lo_delta_out'[1, `_pte_sparse_ncols'] = `ci_lo_delta'[1, `ncols']
    matrix `ci_hi_delta_out'[1, `_pte_sparse_ncols'] = `ci_hi_delta'[1, `ncols']
    matrix `pval_delta_out'[1, `_pte_sparse_ncols'] = `pval_delta'[1, `ncols']
    matrix colnames `att_mat' = `att_colnames' ATT_avg
    matrix colnames `ate_mat' = `ate_colnames' ATE_count_avg
    matrix rownames `att_mat' = ATT
    matrix rownames `ate_mat' = ATE_count
    matrix colnames `se_att_out' = `att_colnames' ATT_avg
    matrix colnames `ci_lo_att_out' = `att_colnames' ATT_avg
    matrix colnames `ci_hi_att_out' = `att_colnames' ATT_avg
    matrix colnames `pval_att_out' = `att_colnames' ATT_avg
    matrix rownames `se_att_out' = ATT
    matrix rownames `ci_lo_att_out' = ATT
    matrix rownames `ci_hi_att_out' = ATT
    matrix rownames `pval_att_out' = ATT
    matrix colnames `se_ate_out' = `ate_colnames' ATE_count_avg
    matrix colnames `ci_lo_ate_out' = `ate_colnames' ATE_count_avg
    matrix colnames `ci_hi_ate_out' = `ate_colnames' ATE_count_avg
    matrix colnames `pval_ate_out' = `ate_colnames' ATE_count_avg
    matrix rownames `se_ate_out' = ATE_count
    matrix rownames `ci_lo_ate_out' = ATE_count
    matrix rownames `ci_hi_ate_out' = ATE_count
    matrix rownames `pval_ate_out' = ATE_count
    matrix colnames `se_delta_out' = `delta_colnames' delta_avg
    matrix colnames `ci_lo_delta_out' = `delta_colnames' delta_avg
    matrix colnames `ci_hi_delta_out' = `delta_colnames' delta_avg
    matrix colnames `pval_delta_out' = `delta_colnames' delta_avg
    matrix rownames `se_delta_out' = Delta
    matrix rownames `ci_lo_delta_out' = Delta
    matrix rownames `ci_hi_delta_out' = Delta
    matrix rownames `pval_delta_out' = Delta
    matrix colnames `attperiods_vec' = `ap_colnames'
    matrix rownames `attperiods_vec' = period
    matrix `attperiods_mat' = `attperiods_vec'

    ereturn scalar ATT_avg = `att_point'[1, `ncols']
    foreach s of local _pte_sparse_support_periods {
        local col = `s' + 1
        if !missing(`att_point'[1, `col']) {
            ereturn scalar att_`s' = `att_point'[1, `col']
        }
    }

    ereturn scalar ate_count_avg = `ate_point'[1, `ncols']
    foreach s of local _pte_sparse_support_periods {
        local col = `s' + 1
        if !missing(`ate_point'[1, `col']) {
            ereturn scalar ate_count_`s' = `ate_point'[1, `col']
        }
    }

    local delta_pooled_val = .
    if !missing(`att_point'[1, `ncols']) & !missing(`ate_point'[1, `ncols']) {
        local delta_pooled_val = `att_point'[1, `ncols'] - `ate_point'[1, `ncols']
    }
    ereturn scalar delta = `delta_pooled_val'
    foreach s of local _pte_sparse_support_periods {
        local col = `s' + 1
        local _delta_pt = .
        if !missing(`att_point'[1, `col']) & !missing(`ate_point'[1, `col']) {
            local _delta_pt = `att_point'[1, `col'] - `ate_point'[1, `col']
        }
        ereturn scalar delta_`s' = `_delta_pt'
    }

    ereturn scalar wald_joint = `wald_joint'
    ereturn scalar wald_pval = `wald_pval'
    ereturn scalar wald_df = `wald_df'
    ereturn scalar level = `level'
    ereturn scalar n_success = `n_success'
    ereturn scalar bootstrap = `breps'
    ereturn scalar breps = `breps'
    ereturn scalar nboot = `breps'
    ereturn scalar attperiods_max = `attperiods'

    // --- Matrix returns: Point estimates and support ---
    ereturn matrix attperiods = `attperiods_mat'
    ereturn matrix attperiods_vec = `attperiods_vec'
    ereturn matrix att = `att_mat'
    ereturn matrix ate_count = `ate_mat'

    // --- Matrix returns: SE ---
    ereturn matrix att_se = `se_att_out'
    ereturn matrix ate_count_se = `se_ate_out'
    ereturn matrix delta_se = `se_delta_out'

    // --- Matrix returns: CI ---
    ereturn matrix att_lb = `ci_lo_att_out'
    ereturn matrix att_ub = `ci_hi_att_out'
    ereturn matrix ate_count_lb = `ci_lo_ate_out'
    ereturn matrix ate_count_ub = `ci_hi_ate_out'
    ereturn matrix delta_lb = `ci_lo_delta_out'
    ereturn matrix delta_ub = `ci_hi_delta_out'

    // --- Matrix returns: p-values ---
    ereturn matrix att_pval = `pval_att_out'
    ereturn matrix ate_count_pval = `pval_ate_out'
    ereturn matrix delta_pval = `pval_delta_out'

    // --- Local returns ---
    ereturn local cmd "_pte_cf_inference"
    ereturn local title "PTE Counterfactual Inference Statistics"

end
