*! _pte_mc_io.ado
*! MC Intermediate File I/O Management
*!
*! Programs:
*!   _pte_mc_save_sample   - Save intermediate MC bootstrap sample
*!   _pte_mc_load_sample   - Load intermediate MC bootstrap sample
*!   _pte_mc_check_resume  - Check resume point for interrupted MC runs
*!   _pte_mc_cleanup       - Clean up intermediate files

version 14.0
// =========================================================================
// Program 1: _pte_mc_save_sample
// Save current dataset as intermediate MC bootstrap sample
// =========================================================================
capture program drop _pte_mc_save_sample
program define _pte_mc_save_sample
    version 14.0
    syntax, m(integer) [path(string)]
    
    // Default path is current working directory
    if "`path'" == "" local path "."
    
    // Save current data as intermediate sample file
    qui save "`path'/mc_boot_sample`m'.dta", replace
    
    if "$PTE_VERBOSE" == "1" {
        display as text "  [IO] Saved intermediate sample: " ///
            as result "`path'/mc_boot_sample`m'.dta"
    }
end

// =========================================================================
// Program 2: _pte_mc_load_sample
// Load intermediate MC bootstrap sample
// =========================================================================
capture program drop _pte_mc_load_sample
program define _pte_mc_load_sample
    version 14.0
    syntax, m(integer) [path(string)]
    
    // Default path is current working directory
    if "`path'" == "" local path "."
    
    // Load intermediate sample file
    qui use "`path'/mc_boot_sample`m'.dta", clear
    
    if "$PTE_VERBOSE" == "1" {
        display as text "  [IO] Loaded intermediate sample: " ///
            as result "`path'/mc_boot_sample`m'.dta"
    }
end

// =========================================================================
// Program 3: _pte_mc_check_resume
// Check which MC iterations have completed intermediate files
// Returns r(last_completed) and r(n_completed)
// =========================================================================
capture program drop _pte_mc_check_resume
program define _pte_mc_check_resume, rclass
    version 14.0
    syntax, mc(integer) [path(string)]
    
    // Default path is current working directory
    if "`path'" == "" local path "."
    
    // Initialize counters
    local last_completed = 0
    local n_completed = 0
    
    // Iterate through all expected MC iterations
    forvalues m = 1/`mc' {
        capture confirm file "`path'/mc_boot_sample`m'.dta"
        if _rc == 0 {
            local last_completed = `m'
            local n_completed = `n_completed' + 1
        }
    }
    
    // Display resume information
    display as text ""
    display as text "{hline 50}"
    display as text "MC Resume Check"
    display as text "{hline 50}"
    display as text "  Total iterations:     " as result `mc'
    display as text "  Completed iterations: " as result `n_completed'
    display as text "  Last completed:       " as result `last_completed'
    if `n_completed' < `mc' {
        local next_iter = `last_completed' + 1
        display as text "  Resume from:          " as result `next_iter'
    }
    else {
        display as text "  Status:               " as result "All complete"
    }
    display as text "{hline 50}"
    
    // Return results
    return scalar last_completed = `last_completed'
    return scalar n_completed = `n_completed'
end


// =========================================================================
// Program 4: _pte_mc_cleanup
// Clean up intermediate MC bootstrap sample files
// =========================================================================
capture program drop _pte_mc_cleanup
program define _pte_mc_cleanup
    version 14.0
    syntax, mc(integer) [path(string) keep]
    
    // Default path is current working directory
    if "`path'" == "" local path "."
    
    // Count files found
    local n_found = 0
    local n_erased = 0
    
    // Iterate through all expected MC iterations
    forvalues m = 1/`mc' {
        capture confirm file "`path'/mc_boot_sample`m'.dta"
        if _rc == 0 {
            local n_found = `n_found' + 1
            if "`keep'" == "" {
                erase "`path'/mc_boot_sample`m'.dta"
                local n_erased = `n_erased' + 1
            }
        }
    }
    
    // Display cleanup report
    display as text ""
    display as text "{hline 50}"
    display as text "MC File Cleanup"
    display as text "{hline 50}"
    display as text "  Files found:   " as result `n_found'
    if "`keep'" != "" {
        display as text "  Action:        " as result "KEEP (dry run)"
        display as text "  Files erased:  " as result 0
    }
    else {
        display as text "  Action:        " as result "ERASE"
        display as text "  Files erased:  " as result `n_erased'
    }
    display as text "{hline 50}"
end
