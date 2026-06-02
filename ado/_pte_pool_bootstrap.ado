*! _pte_pool_bootstrap.ado
*! Re-appends all industry data per iteration, recomputes pooled ATT
*! SE = standard deviation of bootstrap ATT estimates

version 14.0
program define _pte_pool_bootstrap, rclass
    version 14.0
    syntax, groups(string) tempdir(string) bootstrap(integer) attperiods(integer)
    
    local L = `attperiods'
    local B = `bootstrap'
    
    // ─────────────────────────────────────────────────────────────
    // Step 1: Check if TT_mean_trim exists (from first boot file)
    // ─────────────────────────────────────────────────────────────
    local first_grp : word 1 of `groups'
    preserve
    capture use "`tempdir'/tt_`first_grp'_boot1.dta", clear
    if _rc {
        restore
        di as error "Bootstrap file not found: `tempdir'/tt_`first_grp'_boot1.dta"
        exit 601
    }
    capture confirm variable TT_mean_trim
    local has_trim = (_rc == 0)
    restore
    
    // ─────────────────────────────────────────────────────────────
    // Step 2: Initialize bootstrap result matrices
    // ─────────────────────────────────────────────────────────────
    tempname ATT_boot_pool ATT_boot_pool_trim
    matrix `ATT_boot_pool' = J(`B', `L'+2, .)
    if `has_trim' {
        matrix `ATT_boot_pool_trim' = J(`B', `L'+2, .)
    }
    
    // ─────────────────────────────────────────────────────────────
    // Step 3: Bootstrap iterations
    // ─────────────────────────────────────────────────────────────
    local n_failed = 0
    di as text "Computing pooled Bootstrap SE..."
    
    forvalues b = 1/`B' {
        // Progress display
        if mod(`b', 50) == 0 {
            di as text "`b'" _continue
        }
        else if mod(`b', 10) == 0 {
            di as text "." _continue
        }
        
        // Attempt merge and compute (skip on failure)
        capture {
            // Merge all industry data for this iteration
            local first_grp : word 1 of `groups'
            use "`tempdir'/tt_`first_grp'_boot`b'.dta", clear
            capture confirm variable TT_mean
            if _rc {
                exit _rc
            }
            quietly count if nt >= 0 & nt <= `L' & !missing(TT_mean)
            if r(N) == 0 {
                exit 2000
            }
            if `has_trim' {
                capture confirm variable TT_mean_trim
                if _rc {
                    exit _rc
                }
                quietly count if nt >= 0 & nt <= `L' & !missing(TT_mean_trim)
                if r(N) == 0 {
                    exit 2000
                }
            }
            foreach grp of local groups {
                if "`grp'" != "`first_grp'" {
                    capture confirm file "`tempdir'/tt_`grp'_boot`b'.dta"
                    if _rc {
                        exit _rc
                    }
                    preserve
                    capture quietly use "`tempdir'/tt_`grp'_boot`b'.dta", clear
                    local _pte_tt_rc = _rc
                    local _pte_tt_n = 0
                    local _pte_trim_n = 0
                    if `_pte_tt_rc' == 0 {
                        capture confirm variable TT_mean
                        local _pte_tt_rc = _rc
                        if `_pte_tt_rc' == 0 {
                            capture quietly count if nt >= 0 & nt <= `L' & !missing(TT_mean)
                            local _pte_tt_rc = _rc
                            if `_pte_tt_rc' == 0 {
                                local _pte_tt_n = r(N)
                            }
                        }
                        if `_pte_tt_rc' == 0 & `has_trim' {
                            capture confirm variable TT_mean_trim
                            local _pte_tt_rc = _rc
                            if `_pte_tt_rc' == 0 {
                                capture quietly count if nt >= 0 & nt <= `L' & !missing(TT_mean_trim)
                                local _pte_tt_rc = _rc
                                if `_pte_tt_rc' == 0 {
                                    local _pte_trim_n = r(N)
                                }
                            }
                        }
                    }
                    restore
                    if `_pte_tt_rc' != 0 {
                        exit `_pte_tt_rc'
                    }
                    if `_pte_tt_n' == 0 {
                        exit 2000
                    }
                    if `has_trim' & `_pte_trim_n' == 0 {
                        exit 2000
                    }
                    append using "`tempdir'/tt_`grp'_boot`b'.dta", force
                }
            }
            
            // Compute pooled ATT by nt (explicit loop)
            forvalues ell = 0/`L' {
                quietly count if nt == `ell' & !missing(TT_mean)
                if r(N) > 0 {
                    quietly summarize TT_mean if nt == `ell', meanonly
                    matrix `ATT_boot_pool'[`b', `ell'+1] = r(mean)
                    
                    if `has_trim' {
                        quietly summarize TT_mean_trim if nt == `ell', meanonly
                        matrix `ATT_boot_pool_trim'[`b', `ell'+1] = r(mean)
                    }
                }
            }
            
            // ATT_avg
            quietly summarize TT_mean if nt >= 0 & nt <= `L', meanonly
            matrix `ATT_boot_pool'[`b', `L'+2] = r(mean)
            
            if `has_trim' {
                quietly summarize TT_mean_trim if nt >= 0 & nt <= `L', meanonly
                matrix `ATT_boot_pool_trim'[`b', `L'+2] = r(mean)
            }
        }
        if _rc {
            local n_failed = `n_failed' + 1
        }
    }
    di as text ""
    
    // Report failed iterations
    if `n_failed' > 0 {
        di as text "Warning: `n_failed' out of `B' Bootstrap iterations failed"
    }
    
    // Check minimum valid iterations
    local n_valid = `B' - `n_failed'
    if `n_valid' < 2 {
        di as error "Only `n_valid' valid Bootstrap iterations (minimum 2 required)"
        exit 3003
    }
    
    // ─────────────────────────────────────────────────────────────
    // Step 4: Compute Bootstrap SE via Mata
    // ─────────────────────────────────────────────────────────────
    tempname ATT_SE_pool ATT_SE_pool_trim
    local boot_mat_name `ATT_boot_pool'
    local se_mat_name `ATT_SE_pool'
    mata: _ATT_boot = st_matrix("`boot_mat_name'"); ///
        _SE = J(1, cols(_ATT_boot), .); ///
        for (_j = 1; _j <= cols(_ATT_boot); _j++) { ///
            _valid = select(_ATT_boot[., _j], _ATT_boot[., _j] :< .); ///
            if (rows(_valid) > 1) _SE[1, _j] = sqrt(variance(_valid)); ///
        } ///
        st_matrix("`se_mat_name'", _SE)
    
    if `has_trim' {
        local boot_trim_name `ATT_boot_pool_trim'
        local se_trim_name `ATT_SE_pool_trim'
        mata: _ATT_boot_t = st_matrix("`boot_trim_name'"); ///
            _SE_t = J(1, cols(_ATT_boot_t), .); ///
            for (_j = 1; _j <= cols(_ATT_boot_t); _j++) { ///
                _valid_t = select(_ATT_boot_t[., _j], _ATT_boot_t[., _j] :< .); ///
                if (rows(_valid_t) > 1) _SE_t[1, _j] = sqrt(variance(_valid_t)); ///
            } ///
            st_matrix("`se_trim_name'", _SE_t)
    }
    
    // Set column names
    local colnames ""
    forvalues ell = 0/`L' {
        local colnames "`colnames' `ell'"
    }
    local colnames "`colnames' avg"
    matrix colnames `ATT_SE_pool' = `colnames'
    if `has_trim' {
        matrix colnames `ATT_SE_pool_trim' = `colnames'
    }
    
    // ─────────────────────────────────────────────────────────────
    // Step 5: Return results
    // ─────────────────────────────────────────────────────────────
    return matrix att_se_pool = `ATT_SE_pool'
    return matrix att_boot_pool = `ATT_boot_pool'
    if `has_trim' {
        return matrix att_se_pool_trim = `ATT_SE_pool_trim'
        return matrix att_boot_pool_trim = `ATT_boot_pool_trim'
    }
    return scalar n_failed = `n_failed'
    return scalar n_valid = `n_valid'
end
