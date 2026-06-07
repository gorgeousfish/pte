*! _pte_het_ereturn.ado
*! Store e() return values for pte_heterogeneity

version 14.0
capture program drop _pte_het_ereturn
program define _pte_het_ereturn, eclass
    version 14.0
    syntax , RESULT(name) SE(name) [CONTRIB(name)] CI(name) ///
             BYvar(varname) LABELS(string) N_groups(integer) LEVEL(real) ///
             GROUPTOKENS(string) ///
             [NBOOT(string)] [TESTED(integer 0)] ///
             [Q_stat(real 0)] [Q_pvalue(real 0)] [I2(real 0)] [DF(real -1)] ///
             [BOOTKEEP(numlist integer min=1)] [CMDLINE(string)] ///
             [TITLE(string)]
    
    local G = `n_groups'
    local total_row = `G' + 1
    
    // Preserve bootstrap and overall-SE payloads used by immediate re-entry.
    tempname _pte_boot_bygroup _pte_att_se
    local _pte_has_boot_bygroup = 0
    local _pte_has_att_se = 0
    local _pte_has_attperiods = 0
    local _pte_supported_periods ""
    capture noisily _pte_grouped_boot_att_matrix, keep(`bootkeep')
    if !_rc {
        matrix `_pte_boot_bygroup' = r(boot_mat)
        local _pte_has_boot_bygroup = 1
    }
    capture confirm matrix e(att_se)
    if !_rc {
        matrix `_pte_att_se' = e(att_se)
        local _pte_has_att_se = 1
    }
    capture confirm matrix e(attperiods)
    if !_rc {
        tempname _pte_attperiods_in
        matrix `_pte_attperiods_in' = e(attperiods)
        local _pte_attperiods_cols = colsof(`_pte_attperiods_in')
        quietly _pte_attperiods_support `_pte_attperiods_in' `_pte_attperiods_cols' ///
            "pte_heterogeneity repost"
        local _pte_supported_periods `"`r(periodlist)'"'
        local _pte_has_attperiods = 1
    }

    // Build a coherent heterogeneity eclass baseline (b/V/sample) so stale
    // estimation objects from prior commands cannot leak into this contract.
    tempvar _pte_het_esample
    capture confirm variable _pte_tt, exact
    local _pte_has_tt = (_rc == 0)
    capture confirm variable _pte_nt, exact
    local _pte_has_nt = (_rc == 0)
    capture confirm variable _pte_treat, exact
    if _rc != 0 {
        di as error "_pte_het_ereturn requires the exact treated-support bridge _pte_treat"
        exit 111
    }
    _pte_validate_internal_state _pte_treat binary ///
        "_pte_het_ereturn requires _pte_treat to remain the certified binary treated-support bridge."
    if `_pte_has_tt' & `_pte_has_nt' & `_pte_has_attperiods' {
        quietly gen byte `_pte_het_esample' = 0
        foreach _pte_ell of numlist `_pte_supported_periods' {
            quietly replace `_pte_het_esample' = 1 if !missing(_pte_tt) & ///
                _pte_nt == `_pte_ell' & _pte_treat == 1 & !missing(`byvar')
        }
    }
    else if `_pte_has_tt' & `_pte_has_nt' {
        quietly gen byte `_pte_het_esample' = !missing(_pte_tt) & _pte_nt >= 0 & _pte_treat == 1 & !missing(`byvar')
    }
    else {
        quietly gen byte `_pte_het_esample' = !missing(`byvar') & _pte_treat == 1
    }

    tempname _pte_b _pte_V
    matrix `_pte_b' = J(1, `G' + 1, .)
    forvalues g = 1/`G' {
        matrix `_pte_b'[1, `g'] = `result'[`g', 1]
    }
    matrix `_pte_b'[1, `G' + 1] = `result'[`total_row', 1]

    matrix `_pte_V' = J(`G' + 1, `G' + 1, 0)
    forvalues g = 1/`G' {
        local _pte_se_g = `se'[`g', 1]
        local _pte_var_g = .
        if !missing(`_pte_se_g') {
            local _pte_var_g = (`_pte_se_g')^2
        }
        matrix `_pte_V'[`g', `g'] = `_pte_var_g'
    }
    local _pte_total_se = `result'[`total_row', 2]
    local _pte_total_var = .
    if !missing(`_pte_total_se') {
        local _pte_total_var = (`_pte_total_se')^2
    }
    matrix `_pte_V'[`G' + 1, `G' + 1] = `_pte_total_var'

    local _pte_colnames ""
    forvalues g = 1/`G' {
        local _pte_colnames "`_pte_colnames' g`g'"
    }
    local _pte_colnames "`_pte_colnames' total"
    matrix colnames `_pte_b' = `_pte_colnames'
    matrix colnames `_pte_V' = `_pte_colnames'
    matrix rownames `_pte_V' = `_pte_colnames'

    quietly ereturn clear
    quietly ereturn post `_pte_b' `_pte_V', esample(`_pte_het_esample')
    
    // ================================================================
    // Scalars
    // ================================================================
    ereturn scalar n_groups = `n_groups'
    ereturn scalar level = `level'
    if "`nboot'" != "" {
        capture confirm number `nboot'
        if _rc != 0 {
            di as error "nboot() must be numeric when specified"
            exit 198
        }
        local nboot_value = real("`nboot'")
        if !missing(`nboot_value') & `nboot_value' > 0 {
            ereturn scalar nboot = `nboot_value'
        }
    }
    
    // Total statistics from result matrix
    ereturn scalar total_att = `result'[`total_row', 1]
    ereturn scalar total_se = `result'[`total_row', 2]
    
    local ncol = colsof(`result')
    if `ncol' == 4 {
        ereturn scalar total_n = `result'[`total_row', 4]
    }
    else {
        ereturn scalar total_n = `result'[`total_row', 3]
    }
    
    // Test statistics (if available)
    if `tested' {
        ereturn scalar Q_stat = `q_stat'
        ereturn scalar Q_pvalue = `q_pvalue'
        ereturn scalar I2 = `i2'
        ereturn scalar df = `df'
    }
    
    // ================================================================
    // Macros
    // ================================================================
    if `"`cmdline'"' == "" {
        local cmdline "pte_heterogeneity, by(`byvar')"
    }
    if `"`title'"' == "" {
        local by_label : variable label `byvar'
        if `"`by_label'"' == "" {
            local by_label "`byvar'"
        }
        gettoken by_label_clean by_label_rest : by_label, quotes
        if `"`by_label_clean'"' != "" {
            local by_label `"`by_label_clean'"'
        }
        local title `"`by_label'-level Treatment Effects on Productivity"'
    }
    mata: st_local("title", subinstr(st_local("title"), char(96) + char(34), "", .))
    mata: st_local("title", subinstr(st_local("title"), char(34) + char(39), "", .))
    mata: st_local("title", subinstr(st_local("title"), char(34) + char(34), char(34), .))
    mata: st_local("cmdline", subinstr(st_local("cmdline"), char(96) + char(34), "", .))
    mata: st_local("cmdline", subinstr(st_local("cmdline"), char(34) + char(39), "", .))
    ereturn local cmd = "pte_heterogeneity"
    ereturn local cmdline `"`cmdline'"'
    ereturn local by = "`byvar'"
    ereturn local by_var = "`byvar'"
    ereturn local groups `"`grouptokens'"'
    ereturn local group_labels `"`labels'"'
    ereturn local title `"`title'"'
    
    // ================================================================
    // Matrices
    // ================================================================
    ereturn matrix att_by_group = `result'
    ereturn matrix att_by_group_se = `se'
    ereturn matrix att_by_group_ci = `ci'
    if `_pte_has_attperiods' {
        tempname _pte_attperiods_out
        local _pte_period_count : word count `_pte_supported_periods'
        matrix `_pte_attperiods_out' = J(1, `_pte_period_count', .)
        local _pte_attperiods_colnames ""
        local _pte_idx = 0
        foreach _pte_ell of numlist `_pte_supported_periods' {
            local ++_pte_idx
            matrix `_pte_attperiods_out'[1, `_pte_idx'] = `_pte_ell'
            local _pte_attperiods_colnames "`_pte_attperiods_colnames' nt`_pte_ell'"
        }
        matrix colnames `_pte_attperiods_out' = `_pte_attperiods_colnames'
        matrix rownames `_pte_attperiods_out' = period
        ereturn matrix attperiods = `_pte_attperiods_out'
    }
    if `_pte_has_boot_bygroup' {
        local _pte_boot_colnames ""
        forvalues _pte_g = 1/`G' {
            local _pte_boot_colnames "`_pte_boot_colnames' g`_pte_g'"
        }
        matrix colnames `_pte_boot_bygroup' = `_pte_boot_colnames'
        ereturn matrix att_boot_bygroup = `_pte_boot_bygroup'
    }
    if `_pte_has_att_se' {
        ereturn matrix att_se = `_pte_att_se'
    }
    
    if "`contrib'" != "" {
        ereturn matrix contribution = `contrib'
    }
    
    // ================================================================
    // Display stored results summary
    // ================================================================
    display as text ""
    display as text "Results stored in e():"
    display as text "  e(att_by_group)    - ATT matrix (" `G'+1 " x " `ncol' ")"
    display as text "  e(att_by_group_se) - SE vector (" `G' " x 1)"
    display as text "  e(att_by_group_ci) - CI matrix (" `G' " x 2)"
    if "`contrib'" != "" {
        display as text "  e(contribution)    - Contribution vector (" `G' " x 1)"
    }
    
end
