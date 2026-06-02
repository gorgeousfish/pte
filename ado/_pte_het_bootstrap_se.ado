*! _pte_het_bootstrap_se.ado
*! Calculate Bootstrap SE for group ATT
*! Inherits Bootstrap samples from pte main command grouped ATT draw payloads

version 14.0
capture program drop _pte_het_bootstrap_se
program define _pte_het_bootstrap_se, rclass
    version 14.0
    syntax , N_groups(integer) [KEEP(numlist integer min=1)]
    
    tempname se_vector boot_samples
    matrix `se_vector' = J(`n_groups', 1, .)
    
    // ================================================================
    // Step 1: Check if grouped bootstrap ATT draws exist in e()
    // ================================================================
    capture noisily _pte_grouped_boot_att_matrix, keep(`keep')
    if _rc != 0 {
        if _rc == 198 {
            exit 198
        }
        // Bootstrap sample matrix not available, try fallback
        local boot_available = 0
    }
    else {
        matrix `boot_samples' = r(boot_mat)
        local boot_available = 1
        local B = rowsof(`boot_samples')
        local G = colsof(`boot_samples')
        
        // Step 2: Validate dimensions (B x G)
        if `G' != `n_groups' {
            di as error "Bootstrap sample columns (`G') != number of groups (`n_groups')"
            exit 459
        }
        
        mata: st_numscalar("r(_pte_boot_nonmissing)", ///
            rows(select(vec(st_matrix("`boot_samples'")), ///
            vec(st_matrix("`boot_samples'")) :< .)))
        if r(_pte_boot_nonmissing) == 0 {
            local boot_available = 0
        }
        else {
            di as text "Using grouped bootstrap ATT draws from pte main command (`B' replications)"
        }
    }
    
    // ================================================================
    // Step 3: Compute column-wise standard deviation (core SE algorithm)
    //   SE_g = sd(boot_samples[., g])
    //   Mata variance() on a column vector returns a 1x1 matrix
    // ================================================================
    if `boot_available' == 1 {
        forv g = 1/`G' {
            mata: valid_draws = select(st_matrix("`boot_samples'")[., `g'], st_matrix("`boot_samples'")[., `g'] :< .); st_numscalar("r(sd_g)", rows(valid_draws) > 1 ? sqrt(variance(valid_draws)) : .)
            matrix `se_vector'[`g', 1] = r(sd_g)
        }
        
        return matrix se_vector = `se_vector'
        return scalar nboot = `B'
        return local method "inherited"
        exit
    }
    
    // ================================================================
    // Step 4: Fallback - inherit SE from summary statistics
    //   Try live stored-result contract e(att_by_group_se)
    // ================================================================
    capture matrix `se_vector' = e(att_by_group_se)
    local fallback_allowed = ("`e(cmd)'" != "pte_heterogeneity")
    if _rc == 0 & matmissing(`se_vector') == 0 & `fallback_allowed' {
        local se_rows = rowsof(`se_vector')
        local se_rows_ok = 1
        if "`keep'" != "" {
            local keep_count : word count `keep'
            local max_keep = 0
            foreach src of numlist `keep' {
                if `src' > `max_keep' local max_keep = `src'
            }
            if `se_rows' < `max_keep' {
                local se_rows_ok = 0
            }
            tempname se_selected
            matrix `se_selected' = J(`keep_count', 1, .)
            local keep_j = 0
            foreach src of numlist `keep' {
                local ++keep_j
                matrix `se_selected'[`keep_j', 1] = `se_vector'[`src', 1]
            }
            matrix `se_vector' = `se_selected'
        }
        else if `se_rows' != `n_groups' {
            local se_rows_ok = 0
        }

        if !`se_rows_ok' {
            di as error "Stored e(att_by_group_se) does not match requested group layout"
            exit 459
        }
        di as text "Using SE from pte main command e(att_by_group_se)"
        return matrix se_vector = `se_vector'
        return scalar nboot = e(nboot)
        return local method "inherited_se"
        exit
    }
    
    // ================================================================
    // Step 5: No Bootstrap samples available - error out
    // ================================================================
    di as error "Bootstrap samples not available from pte main command"
    di as error "Please rerun pte with bootstrap() option, e.g.:"
    di as error "    pte ..., bootstrap(500) by(industry)"
    exit 459
    
end
