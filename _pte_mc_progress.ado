*! _pte_mc_progress.ado
*! MC and Bootstrap progress display for pte package
*! Implements progress indicators consistent with replication code

version 14.0
capture program drop _pte_mc_progress
program define _pte_mc_progress
    version 14.0
    syntax, level(string) current(integer) total(integer)
    
    // =========================================================================
    // MC outer loop progress (level = "mc")
    // Display iteration number every 10, dot otherwise
    // =========================================================================
    if "`level'" == "mc" {
        if mod(`current', 10) == 0 {
            noisily display as text " `current'" _continue
        }
        else {
            noisily display as text "." _continue
        }
        // Newline at end of all iterations
        if `current' == `total' {
            noisily display as text ""
        }
    }
    
    // =========================================================================
    // Bootstrap start banner (level = "boot_start")
    // Consistent with replication code L175
    // =========================================================================
    else if "`level'" == "boot_start" {
        noisily display as text "Start bootstrapping:"
    }
    
    // =========================================================================
    // Bootstrap iteration progress (level = "boot")
    // Display iteration number every 50, dot otherwise
    // Consistent with replication code L178-183
    // =========================================================================
    else if "`level'" == "boot" {
        if mod(`current', 50) == 0 {
            noisily display as text "`current'" _continue
        }
        else {
            noisily display as text "." _continue
        }
        // Newline at end of all bootstrap iterations
        if `current' == `total' {
            noisily display as text ""
        }
    }
    
    // =========================================================================
    // MC completion summary (level = "mc_done")
    // =========================================================================
    else if "`level'" == "mc_done" {
        noisily display as text ""
        noisily display as text "MC simulation complete: " ///
            as result `total' as text " iterations"
    }
    
end
