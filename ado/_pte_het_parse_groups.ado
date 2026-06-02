*! _pte_het_parse_groups.ado
*! Parse grouping variable for heterogeneity analysis
*! Identifies unique group values, labels, and handles missing/string variables

version 14.0
capture program drop _pte_het_parse_groups
program define _pte_het_parse_groups, rclass
    version 14.0
    
    // =========================================================================
    // Syntax: accepts a single variable name
    // =========================================================================
    syntax varname [, GENerate(name)]
    
    local groupvar "`varlist'"
    
    // =========================================================================
    // Step 1: Confirm variable exists in current dataset
    // =========================================================================
    confirm variable `groupvar'
    
    // =========================================================================
    // Step 2: Detect variable type (numeric vs string)
    // =========================================================================
    local is_string = 0
    local byvar_use "`groupvar'"
    local group_tokens ""
    
    capture confirm numeric variable `groupvar'
    if _rc {
        // String variable: encode to numeric using a caller-owned variable
        // so the mapped grouping id survives after this helper returns.
        local is_string = 1
        if "`generate'" == "" {
            display as error "_pte_het_parse_groups: generate() is required for string grouping variables"
            exit 198
        }
        capture confirm new variable `generate'
        if _rc {
            display as error "_pte_het_parse_groups: generate(`generate') must name a new variable"
            exit 110
        }
        quietly levelsof `groupvar' if !missing(`groupvar'), local(group_tokens)
        encode `groupvar', generate(`generate')
        local byvar_use "`generate'"
        display as text "Note: string variable `groupvar' encoded to numeric for analysis"
    }
    
    // =========================================================================
    // Step 3: Handle missing values - count and warn
    // =========================================================================
    quietly count if missing(`byvar_use')
    local n_missing = r(N)
    
    if `n_missing' > 0 {
        display as text "Warning: `n_missing' observations with missing values" ///
            " in `groupvar' will be excluded from heterogeneity analysis"
    }
    
    // =========================================================================
    // Step 4: Get unique group values using levelsof (excluding missing)
    // =========================================================================
    quietly levelsof `byvar_use' if !missing(`byvar_use'), local(group_list)
    if `"`group_tokens'"' == "" {
        local group_tokens "`group_list'"
    }
    if !`is_string' {
        local group_tokens : list retokenize group_tokens
    }
    
    // Count number of groups
    local n_groups : word count `group_list'
    
    // =========================================================================
    // Step 5: Validate minimum group count (need >= 2 for heterogeneity)
    // =========================================================================
    if `n_groups' < 2 {
        display as error "heterogeneity analysis requires at least 2 groups;" ///
            " variable `groupvar' has only `n_groups' group(s)"
        exit 498
    }
    
    // =========================================================================
    // Step 6: Retrieve value labels (if any)
    // =========================================================================
    local group_labels ""
    
    // Check if the variable has a value label attached
    local vallbl : value label `byvar_use'
    
    if "`vallbl'" != "" {
        // Variable has value labels: retrieve label for each group value
        foreach g of local group_list {
            local lbl : label `vallbl' `g'
            local lbl_clean = subinstr(`"`lbl'"', " ", "_", .)
            local lbl_clean = subinstr(`"`lbl_clean'"', `"""', "", .)
            local group_labels "`group_labels' `lbl_clean'"
        }
    }
    else {
        // No value labels: use numeric values as labels
        local group_labels "`group_list'"
    }
    
    // =========================================================================
    // Step 7: Display summary
    // =========================================================================
    display as text ""
    display as text "Grouping variable: `groupvar'"
    display as text "  Number of groups: `n_groups'"
    if `n_missing' > 0 {
        display as text "  Missing values:   `n_missing'"
    }
    if `is_string' {
        display as text "  Type: string (encoded to numeric)"
    }
    else {
        display as text "  Type: numeric"
    }
    
    // =========================================================================
    // Step 8: Return results
    // =========================================================================
    return local group_list    "`group_list'"
    return local group_labels  `"`group_labels'"'
    return local group_tokens  `"`group_tokens'"'
    return local byvar_use     "`byvar_use'"
    return scalar n_groups   = `n_groups'
    return scalar n_missing  = `n_missing'
    return scalar is_string  = `is_string'
    
end
