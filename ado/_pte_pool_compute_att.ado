*! _pte_pool_compute_att.ado
*! Uses explicit loop (not tabstat by) to avoid nt gap misalignment
*! Includes ATT_avg calculation (IMP-003)

version 14.0
program define _pte_pool_compute_att, rclass
    version 14.0
    syntax, attperiods(integer)
    
    local L = `attperiods'
    
    // ─────────────────────────────────────────────────────────────
    // Step 1: Initialize matrices
    // ─────────────────────────────────────────────────────────────
    tempname ATT_pool ATT_pool_trim ATT_sd ATT_sd_trim N_pool
    matrix `ATT_pool' = J(1, `L'+2, .)
    matrix `ATT_sd' = J(1, `L'+2, .)
    matrix `N_pool' = J(1, `L'+1, .)
    
    // Check if TT_mean_trim exists
    capture confirm variable TT_mean_trim
    local has_trim = (_rc == 0)
    if `has_trim' {
        matrix `ATT_pool_trim' = J(1, `L'+2, .)
        matrix `ATT_sd_trim' = J(1, `L'+2, .)
    }
    
    // ─────────────────────────────────────────────────────────────
    // Step 2: Explicit loop by nt (safe against nt gaps)
    // ─────────────────────────────────────────────────────────────
    forvalues ell = 0/`L' {
        quietly count if nt == `ell' & !missing(TT_mean)
        local n_ell = r(N)
        
        if `n_ell' > 0 {
            quietly summarize TT_mean if nt == `ell'
            matrix `ATT_pool'[1, `ell'+1] = r(mean)
            matrix `ATT_sd'[1, `ell'+1] = r(sd)
            matrix `N_pool'[1, `ell'+1] = r(N)
            
            if `has_trim' {
                quietly summarize TT_mean_trim if nt == `ell'
                matrix `ATT_pool_trim'[1, `ell'+1] = r(mean)
                matrix `ATT_sd_trim'[1, `ell'+1] = r(sd)
            }
        }
        else {
            // No observations for this period
            matrix `ATT_pool'[1, `ell'+1] = .
            matrix `ATT_sd'[1, `ell'+1] = .
            matrix `N_pool'[1, `ell'+1] = 0
            
            if `has_trim' {
                matrix `ATT_pool_trim'[1, `ell'+1] = .
                matrix `ATT_sd_trim'[1, `ell'+1] = .
            }
            
            di as text "Warning: No observations for nt = `ell'"
        }
    }
    
    // ─────────────────────────────────────────────────────────────
    // Step 3: ATT_avg = simple mean across all firms (IMP-003)
    // ─────────────────────────────────────────────────────────────
    quietly summarize TT_mean if nt >= 0 & nt <= `L'
    matrix `ATT_pool'[1, `L'+2] = r(mean)
    matrix `ATT_sd'[1, `L'+2] = r(sd)
    local N_total = r(N)
    
    if `has_trim' {
        quietly summarize TT_mean_trim if nt >= 0 & nt <= `L'
        matrix `ATT_pool_trim'[1, `L'+2] = r(mean)
        matrix `ATT_sd_trim'[1, `L'+2] = r(sd)
    }
    
    // ─────────────────────────────────────────────────────────────
    // Step 4: Set column names
    // ─────────────────────────────────────────────────────────────
    local colnames ""
    forvalues ell = 0/`L' {
        local colnames "`colnames' `ell'"
    }
    local colnames "`colnames' avg"
    matrix colnames `ATT_pool' = `colnames'
    matrix colnames `ATT_sd' = `colnames'
    
    local n_colnames ""
    forvalues ell = 0/`L' {
        local n_colnames "`n_colnames' `ell'"
    }
    matrix colnames `N_pool' = `n_colnames'
    
    if `has_trim' {
        matrix colnames `ATT_pool_trim' = `colnames'
        matrix colnames `ATT_sd_trim' = `colnames'
    }
    
    // ─────────────────────────────────────────────────────────────
    // Step 5: Return results
    // ─────────────────────────────────────────────────────────────
    return matrix att_pool = `ATT_pool'
    return matrix att_sd = `ATT_sd'
    return matrix N_pool = `N_pool'
    return scalar N_total = `N_total'
    
    if `has_trim' {
        return matrix att_pool_trim = `ATT_pool_trim'
        return matrix att_sd_trim = `ATT_sd_trim'
    }
end
