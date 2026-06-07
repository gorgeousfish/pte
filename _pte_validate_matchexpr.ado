*! _pte_validate_matchexpr.ado
*! Custom matching expression validation

version 14.0
capture program drop _pte_validate_matchexpr
program define _pte_validate_matchexpr, rclass
    version 14.0
    
    syntax , expr(string)
    
    // ================================================================
    // Task 1-2: Safety check - detect dangerous keywords
    // ================================================================
    
    local dangerous "drop clear erase rm delete save use merge append replace"
    local expr_lower = lower(`"`expr'"')
    
    foreach word of local dangerous {
        local pos = strpos("`expr_lower'", "`word'")
        if `pos' > 0 {
            local len = strlen("`word'")
            
            // Check preceding character (word boundary)
            local prev_ok = 1
            if `pos' > 1 {
                local prev_char = substr("`expr_lower'", `pos'-1, 1)
                if regexm("`prev_char'", "[a-z_]") {
                    local prev_ok = 0
                }
            }
            
            // Check following character (word boundary)
            local next_ok = 1
            local next_pos = `pos' + `len'
            if `next_pos' <= strlen("`expr_lower'") {
                local next_char = substr("`expr_lower'", `next_pos', 1)
                if regexm("`next_char'", "[a-z_0-9]") {
                    local next_ok = 0
                }
            }
            
            if `prev_ok' & `next_ok' {
                di as error "{bf:pte error E-3018}: matchexpr contains forbidden keyword '`word''"
                di as error "  matchexpr should be a boolean condition, not a command"
                exit 198
            }
        }
    }
    
    // ================================================================
    // Task 3: Syntax validation using cap gen byte
    // ================================================================
    
    tempvar _test_matchexpr
    cap gen byte `_test_matchexpr' = (`expr')
    
    if _rc != 0 {
        di as error "{bf:pte error E-3019}: matchexpr syntax error"
        di as error "  Expression: `expr'"
        di as error "  Stata error code: " _rc
        exit 198
    }
    
    // ================================================================
    // Task 4: Existence check and sample size warnings
    // ================================================================
    
    qui count if `_test_matchexpr' == 1
    local N_match = r(N)
    
    // No observations match
    if `N_match' == 0 {
        di as error "{bf:pte error E-3012}: matchexpr matches no observations"
        di as error "  Expression: `expr'"
        exit 3012
    }
    
    // Sample size warnings
    if `N_match' < 10 {
        di as text "{bf:Warning W-3016}: matchexpr matches only `N_match' observations (< 10)"
    }
    else if `N_match' < 30 {
        di as text "{bf:Warning W-3010}: matchexpr matches only `N_match' observations (< 30)"
        di as text "  Consider relaxing the matching condition"
    }
    
    // Report validation result
    di as text "matchexpr validated: `expr'"
    di as text "  Matching observations: `N_match'"
    
    // Return values
    return scalar N_match = `N_match'
    return scalar valid = 1
    
end
