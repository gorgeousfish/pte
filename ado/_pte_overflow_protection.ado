*! _pte_overflow_protection.ado
*! Overflow protection for numerical stability
*! Detects and handles NaN/Inf/overflow in Stata variables.
*! Wraps Mata pte_safe_poly() and pte_safe_evolution() for Stata-level use.
*! Replication code has NO overflow protection (pte improvement)

version 14.0
program define _pte_overflow_protection, rclass
    version 14.0
    
    syntax varlist(numeric), [bound(real 1e10) replace Verbose]
    
    // -----------------------------------------------------------------------
    // Initialize counters
    // -----------------------------------------------------------------------
    local total_bounded = 0
    local total_replaced = 0
    local verbose_flag = ("`verbose'" != "")
    
    foreach var of local varlist {
        local n_bounded = 0
        local n_replaced = 0
        
        // -------------------------------------------------------------------
        // Check 1: Count missing values (NaN/Inf in Stata are stored as .)
        // -------------------------------------------------------------------
        quietly count if missing(`var')
        local n_miss_before = r(N)
        
        // -------------------------------------------------------------------
        // Check 2: Detect values exceeding bound
        // -------------------------------------------------------------------
        quietly count if !missing(`var') & abs(`var') > `bound'
        local n_bounded = r(N)
        
        // -------------------------------------------------------------------
        // Check 3: Detect non-finite values (. .a .b etc.)
        // Stata stores Inf as missing, so check for extreme values near limit
        // -------------------------------------------------------------------
        quietly count if !missing(`var') & abs(`var') > 8.988e+307
        local n_nearinf = r(N)
        local n_replaced = `n_nearinf'
        
        if `verbose_flag' & (`n_bounded' > 0 | `n_replaced' > 0) {
            display as text "  `var': " ///
                `n_bounded' " values > bound(" %9.1e `bound' "), " ///
                `n_replaced' " near-Inf values"
        }
        
        // -------------------------------------------------------------------
        // Apply corrections if replace option specified
        // -------------------------------------------------------------------
        if "`replace'" != "" {
            // Replace near-Inf with missing
            if `n_nearinf' > 0 {
                quietly replace `var' = . if abs(`var') > 8.988e+307
            }
            
            // Truncate values exceeding bound to ±bound
            if `n_bounded' > 0 {
                quietly replace `var' = `bound' ///
                    if !missing(`var') & `var' > `bound'
                quietly replace `var' = -`bound' ///
                    if !missing(`var') & `var' < -`bound'
            }
        }
        
        local total_bounded = `total_bounded' + `n_bounded'
        local total_replaced = `total_replaced' + `n_replaced'
    }
    
    // -----------------------------------------------------------------------
    // Return results
    // -----------------------------------------------------------------------
    return scalar n_bounded = `total_bounded'
    return scalar n_replaced = `total_replaced'
    return scalar bound = `bound'
    
    if `verbose_flag' {
        display as text "  Overflow protection: " ///
            `total_bounded' " bounded, " ///
            `total_replaced' " replaced"
    }
end
