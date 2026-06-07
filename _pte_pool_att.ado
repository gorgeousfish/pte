*! _pte_pool_att.ado
*! Merges industry TT data, computes firm-level pooled ATT
*! Includes parameter validation (IMP-006)

version 14.0
program define _pte_pool_att, eclass
    version 14.0
    syntax, groups(string) tempdir(string) attperiods(integer) ///
            [bootstrap(integer 0)]
    
    // ─────────────────────────────────────────────────────────────
    // IMP-006: Parameter validation
    // ─────────────────────────────────────────────────────────────
    if `attperiods' < 0 {
        di as error "attperiods must be >= 0"
        exit 198
    }
    if `bootstrap' < 0 {
        di as error "bootstrap must be >= 0"
        exit 198
    }
    if `"`groups'"' == "" {
        di as error "groups must be non-empty"
        exit 198
    }
    
    // Verify data files exist
    foreach grp of local groups {
        capture confirm file "`tempdir'/tt_`grp'.dta"
        if _rc {
            di as error "Data file not found: `tempdir'/tt_`grp'.dta"
            exit 601
        }
    }
    
    // ─────────────────────────────────────────────────────────────
    // Step 1: Merge all industry data
    // ─────────────────────────────────────────────────────────────
    _pte_pool_merge_data, groups(`groups') tempdir(`tempdir')
    
    // Save merged data for bootstrap use
    tempfile pooled_data
    quietly save `pooled_data', replace
    
    // ─────────────────────────────────────────────────────────────
    // Step 2: Compute pooled ATT (includes ATT_avg)
    // ─────────────────────────────────────────────────────────────
    _pte_pool_compute_att, attperiods(`attperiods')
    
    // Capture return values before they are cleared
    tempname ATT_pool ATT_pool_trim ATT_sd N_pool
    matrix `ATT_pool' = r(att_pool)
    matrix `ATT_sd' = r(att_sd)
    matrix `N_pool' = r(N_pool)
    local N_total = r(N_total)
    
    capture matrix `ATT_pool_trim' = r(att_pool_trim)
    local has_trim = (_rc == 0)
    
    tempname ATT_sd_trim
    if `has_trim' {
        matrix `ATT_sd_trim' = r(att_sd_trim)
    }
    
    // ─────────────────────────────────────────────────────────────
    // Step 3: Bootstrap SE (if requested)
    // ─────────────────────────────────────────────────────────────
    tempname ATT_SE_pool ATT_SE_pool_trim ATT_SE_pool_alias ATT_SE_pool_trim_alias
    if `bootstrap' > 0 {
        _pte_pool_bootstrap, groups(`groups') tempdir(`tempdir') ///
            bootstrap(`bootstrap') attperiods(`attperiods')
        
        matrix `ATT_SE_pool' = r(att_se_pool)
        matrix `ATT_SE_pool_alias' = `ATT_SE_pool'
        if `has_trim' {
            capture matrix `ATT_SE_pool_trim' = r(att_se_pool_trim)
            capture matrix `ATT_SE_pool_trim_alias' = `ATT_SE_pool_trim'
        }
    }
    
    // ─────────────────────────────────────────────────────────────
    // Step 4: Store e() return values
    // ─────────────────────────────────────────────────────────────
    ereturn clear
    
    // Matrices
    ereturn matrix att_pool = `ATT_pool'
    ereturn matrix att_sd_pool = `ATT_sd'
    ereturn matrix N_pool = `N_pool'
    
    if `has_trim' {
        ereturn matrix att_pool_trim = `ATT_pool_trim'
        ereturn matrix att_sd_pool_trim = `ATT_sd_trim'
    }
    
    if `bootstrap' > 0 {
        ereturn matrix att_pool_se = `ATT_SE_pool'
        ereturn matrix att_se_pool = `ATT_SE_pool_alias'
        if `has_trim' {
            capture ereturn matrix att_pool_se_trim = `ATT_SE_pool_trim'
            capture ereturn matrix att_se_pool_trim = `ATT_SE_pool_trim_alias'
        }
    }
    
    // Scalars
    ereturn scalar N_total_pool = `N_total'
    ereturn scalar attperiods = `attperiods'
    ereturn scalar bootstrap = `bootstrap'
    ereturn scalar n_groups = `: word count `groups''
    
    // Macros
    ereturn local groups "`groups'"
    ereturn local cmd "_pte_pool_att"
    
    // ─────────────────────────────────────────────────────────────
    // Step 5: Display results table
    // ─────────────────────────────────────────────────────────────
    local L = `attperiods'
    local n_grps : word count `groups'
    
    di as text ""
    di as text "{hline 60}"
    di as text "  Pooled ATT Estimation Results"
    di as text "  (Firm-level Average, NOT Industry-weighted)"
    di as text "{hline 60}"
    di as text "  Industries pooled:  " as result `n_grps'
    di as text "  Total treated firms:" as result %8.0f `N_total'
    di as text "  Periods analyzed:   " as result "0 to `L'"
    di as text "{hline 60}"
    
    // Header row
    di as text "  {ralign 8:Period}" _col(20) "{ralign 10:ATT_pool}" ///
        _col(32) "{ralign 10:SE}" _col(44) "{ralign 10:N}"
    di as text "  {hline 50}"
    
    // Per-period rows
    forvalues ell = 0/`L' {
        local att_val = e(att_pool)[1, `ell'+1]
        local n_val = e(N_pool)[1, `ell'+1]
        
        if `bootstrap' > 0 {
            local se_val = e(att_pool_se)[1, `ell'+1]
            di as text "  {ralign 8:`ell'}" _col(20) as result %10.4f `att_val' ///
                _col(32) as result %10.4f `se_val' ///
                _col(44) as result %10.0f `n_val'
        }
        else {
            di as text "  {ralign 8:`ell'}" _col(20) as result %10.4f `att_val' ///
                _col(32) as text "         ." ///
                _col(44) as result %10.0f `n_val'
        }
    }
    
    di as text "  {hline 50}"
    
    // ATT_avg row
    local att_avg = e(att_pool)[1, `L'+2]
    if `bootstrap' > 0 {
        local se_avg = e(att_pool_se)[1, `L'+2]
        di as text "  {ralign 8:avg}" _col(20) as result %10.4f `att_avg' ///
            _col(32) as result %10.4f `se_avg' ///
            _col(44) as result %10.0f `N_total'
    }
    else {
        di as text "  {ralign 8:avg}" _col(20) as result %10.4f `att_avg' ///
            _col(32) as text "         ." ///
            _col(44) as result %10.0f `N_total'
    }
    
    di as text "{hline 60}"
end
