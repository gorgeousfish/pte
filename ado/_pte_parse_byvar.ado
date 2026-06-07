*! _pte_parse_byvar.ado
*! By-group variable parsing: detect type, enumerate groups, count samples, validate sizes

version 14.0
// Parse by-group variable: detect type, enumerate groups, count samples, validate sizes
program define _pte_parse_byvar, rclass
    version 14.0
    
    // =========================================================================
    // 1. Parse syntax
    // =========================================================================
    syntax varname [, Treatment(varname) MIN_obs(integer 100) ///
        MIN_treated(integer 50) MIN_control(integer 50) NOWarn]
    
    local byvar "`varlist'"
    
    // =========================================================================
    // 2. Validate parameters
    // =========================================================================
    if `min_obs' <= 0 {
        display as error "_pte_parse_byvar: min_obs must be positive"
        exit 198
    }
    if `min_treated' <= 0 {
        display as error "_pte_parse_byvar: min_treated must be positive"
        exit 198
    }
    if `min_control' <= 0 {
        display as error "_pte_parse_byvar: min_control must be positive"
        exit 198
    }
    
    // =========================================================================
    // 3. Confirm variables exist
    // =========================================================================
    confirm variable `byvar'
    if "`treatment'" != "" {
        confirm variable `treatment'
    }
    
    // =========================================================================
    // 4. Detect variable type (numeric vs string)
    // =========================================================================
    local vartype ""
    capture confirm numeric variable `byvar'
    if _rc == 0 {
        local vartype "numeric"
    }
    else {
        capture confirm string variable `byvar'
        if _rc == 0 {
            local vartype "string"
        }
        else {
            display as error "_pte_parse_byvar: `byvar' is neither numeric nor string"
            exit 111
        }
    }
    
    // =========================================================================
    // 5. Count missing values
    // =========================================================================
    if "`vartype'" == "numeric" {
        quietly count if missing(`byvar')
    }
    else {
        quietly count if `byvar' == ""
    }
    local n_missing = r(N)
    
    // Check all-missing
    if "`vartype'" == "numeric" {
        quietly count if !missing(`byvar')
    }
    else {
        quietly count if `byvar' != ""
    }
    if r(N) == 0 {
        display as error "_pte_parse_byvar: all values of `byvar' are missing"
        exit 2001
    }
    
    // =========================================================================
    // 6. Get unique group values via levelsof
    // =========================================================================
    // For string variables, do NOT use clean option (compound quotes handle spaces)
    if "`vartype'" == "numeric" {
        quietly levelsof `byvar', local(groups) clean
    }
    else {
        quietly levelsof `byvar', local(groups)
    }
    
    // Use r(r) for group count (NOT word count, which fails for strings with spaces)
    local n_groups = r(r)
    
    // =========================================================================
    // 7. Check single group (warning)
    // =========================================================================
    if `n_groups' == 1 {
        display as text "Warning: `byvar' has only 1 group; by-group analysis not meaningful"
    }
    
    // =========================================================================
    // 8. Initialize matrices
    // =========================================================================
    tempname mat_N mat_Nt mat_Nc
    matrix `mat_N' = J(`n_groups', 1, 0)
    matrix colnames `mat_N' = "N"
    
    if "`treatment'" != "" {
        matrix `mat_Nt' = J(`n_groups', 1, 0)
        matrix colnames `mat_Nt' = "N_treated"
        matrix `mat_Nc' = J(`n_groups', 1, 0)
        matrix colnames `mat_Nc' = "N_control"
    }
    
    // Use sequential row names (1, 2, 3...) to avoid space issues
    local rownames ""
    forvalues i = 1/`n_groups' {
        local rownames "`rownames' `i'"
    }
    matrix rownames `mat_N' = `rownames'
    if "`treatment'" != "" {
        matrix rownames `mat_Nt' = `rownames'
        matrix rownames `mat_Nc' = `rownames'
    }
    
    // =========================================================================
    // 9. Loop over groups: count total, treated, control
    // =========================================================================
    local warnings = 0
    local group_labels ""
    local idx = 0
    
    foreach grp of local groups {
        local idx = `idx' + 1
        
        // Count total observations in this group
        if "`vartype'" == "numeric" {
            quietly count if `byvar' == `grp'
        }
        else {
            // Use compound quotes for string comparison (handles spaces)
            quietly count if `byvar' == `"`grp'"'
        }
        local n_total = r(N)
        
        // Check empty group
        if `n_total' == 0 {
            display as error "_pte_parse_byvar: group `grp' has zero observations"
            exit 2000
        }
        
        matrix `mat_N'[`idx', 1] = `n_total'
        
        // Count treated and control if treatment variable specified
        if "`treatment'" != "" {
            if "`vartype'" == "numeric" {
                quietly count if `byvar' == `grp' & `treatment' == 1
            }
            else {
                quietly count if `byvar' == `"`grp'"' & `treatment' == 1
            }
            local n_treated = r(N)
            matrix `mat_Nt'[`idx', 1] = `n_treated'
            
            if "`vartype'" == "numeric" {
                quietly count if `byvar' == `grp' & `treatment' == 0
            }
            else {
                quietly count if `byvar' == `"`grp'"' & `treatment' == 0
            }
            local n_control = r(N)
            matrix `mat_Nc'[`idx', 1] = `n_control'
        }
        
        // Build group_labels mapping: "1=value1 2=value2 ..."
        local group_labels "`group_labels' `idx'=`grp'"
    }
    
    // Trim leading space
    local group_labels = strtrim("`group_labels'")
    
    // =========================================================================
    // 10. Warning logic (if nowarn not specified)
    // =========================================================================
    if "`nowarn'" == "" {
        local idx = 0
        foreach grp of local groups {
            local idx = `idx' + 1
            local n_total = `mat_N'[`idx', 1]
            
            // Check total obs vs min_obs
            if `n_total' < `min_obs' {
                display as text "Warning: group `grp' has `n_total' obs " ///
                    "(below min_obs=`min_obs')"
                local warnings = `warnings' + 1
            }
            
            // Check treated and control thresholds
            if "`treatment'" != "" {
                local n_treated = `mat_Nt'[`idx', 1]
                local n_control = `mat_Nc'[`idx', 1]
                
                if `n_treated' < `min_treated' {
                    display as text "Warning: group `grp' has `n_treated' " ///
                        "treated obs (below min_treated=`min_treated')"
                    local warnings = `warnings' + 1
                }
                if `n_control' < `min_control' {
                    display as text "Warning: group `grp' has `n_control' " ///
                        "control obs (below min_control=`min_control')"
                    local warnings = `warnings' + 1
                }
            }
        }
    }
    
    // =========================================================================
    // 11. Display summary table
    // =========================================================================
    display as text ""
    display as text "By-group variable: `byvar' (`vartype')"
    display as text "Number of groups:  `n_groups'"
    if `n_missing' > 0 {
        display as text "Missing values:    `n_missing'"
    }
    display as text ""
    display as text "{hline 60}"
    
    if "`treatment'" != "" {
        display as text %5s "Group" %15s "Value" %10s "N" %10s "Treated" %10s "Control"
    }
    else {
        display as text %5s "Group" %15s "Value" %10s "N"
    }
    display as text "{hline 60}"
    
    local idx = 0
    foreach grp of local groups {
        local idx = `idx' + 1
        local n_total = `mat_N'[`idx', 1]
        
        if "`treatment'" != "" {
            local n_treated = `mat_Nt'[`idx', 1]
            local n_control = `mat_Nc'[`idx', 1]
            display as result %5.0f `idx' %15s "`grp'" ///
                %10.0f `n_total' %10.0f `n_treated' %10.0f `n_control'
        }
        else {
            display as result %5.0f `idx' %15s "`grp'" %10.0f `n_total'
        }
    }
    display as text "{hline 60}"
    
    if `warnings' > 0 {
        display as text ""
        display as text "Total warnings: `warnings'"
    }
    
    // =========================================================================
    // 12. Set all return values
    // =========================================================================
    return local groups "`groups'"
    return scalar n_groups = `n_groups'
    return local vartype "`vartype'"
    return local group_labels "`group_labels'"
    return matrix N_by = `mat_N'
    
    if "`treatment'" != "" {
        return matrix N_treated_by = `mat_Nt'
        return matrix N_control_by = `mat_Nc'
    }
    
    return scalar n_missing = `n_missing'
    return scalar warnings = `warnings'
    return local byvar "`byvar'"
    
end
