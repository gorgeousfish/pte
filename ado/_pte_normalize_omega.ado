*! _pte_normalize_omega.ado
*! Normalize productivity by industry mean
*! Internal helper for pte_graph

version 14.0
program define _pte_normalize_omega
    version 14.0
    
    // Confirm required variables exist
    capture confirm variable _pte_omega
    if _rc {
        di as error "variable _pte_omega not found"
        exit 111
    }
    
    capture confirm variable _pte_industry
    if _rc {
        di as error "variable _pte_industry not found"
        exit 111
    }
    
    // Drop old normalized variable if exists (idempotent)
    capture drop _pte_omega_norm
    
    // Initialize normalized variable
    qui gen double _pte_omega_norm = .
    
    // Get industry list and check boundaries
    qui levelsof _pte_industry, local(industries)
    local n_industries : word count `industries'
    
    if `n_industries' == 0 {
        di as error "Error: No valid industries found in _pte_industry"
        exit 2000
    }
    if `n_industries' == 1 {
        di as text "{bf:Warning}: Only 1 industry found. Normalization will result in zero-mean productivity."
    }
    if `n_industries' > 100 {
        di as text "{bf:Warning}: Large number of industries (`n_industries'). Verify _pte_industry coding."
    }
    
    // Normalize by industry (use all non-missing obs for mean calculation)
    local skipped_industries ""
    foreach ind of local industries {
        qui count if _pte_industry == `ind' & !missing(_pte_omega)
        local n_obs = r(N)
        if `n_obs' == 0 {
            local skipped_industries "`skipped_industries' `ind'"
            continue
        }
        qui sum _pte_omega if _pte_industry == `ind' & !missing(_pte_omega), meanonly
        qui replace _pte_omega_norm = _pte_omega - r(mean) if _pte_industry == `ind'
    }
    
    if "`skipped_industries'" != "" {
        di as text "{bf:Warning}: Industries with no valid observations (skipped):`skipped_industries'"
    }
    
    // Label variable
    label variable _pte_omega_norm "Normalized productivity (industry-demeaned)"
    
    // Verify normalization correctness
    foreach ind of local industries {
        qui sum _pte_omega_norm if _pte_industry == `ind' & !missing(_pte_omega_norm), meanonly
        if r(N) == 0 {
            continue
        }
        if abs(r(mean)) > 1e-10 {
            di as error "Normalization error: industry `ind' mean = " r(mean)
            exit 499
        }
    }
    
end
