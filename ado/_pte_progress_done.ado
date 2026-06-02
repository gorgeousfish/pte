*! _pte_progress_done.ado

version 14.0
capture program drop _pte_progress_done
program define _pte_progress_done, rclass
    version 14.0
    
    syntax [, Message(string)]
    
    // Get final state (with safe defaults if not initialized)
    if "$PTE_PROGRESS_TOTAL" == "" {
        capture macro drop PTE_PROGRESS_*
        // Not initialized - return silently
        return scalar elapsed = 0
        return scalar total = 0
        return scalar completed = 0
        return scalar failed = 0
        exit
    }
    
    local total = $PTE_PROGRESS_TOTAL
    local current = $PTE_PROGRESS_CURRENT
    local failed = $PTE_PROGRESS_FAILED
    local desc "$PTE_PROGRESS_DESC"
    local nolog "$PTE_PROGRESS_NOLOG"
    
    // Calculate total elapsed time
    local elapsed = (clock("$S_DATE $S_TIME", "DMYhms") - $PTE_PROGRESS_START) / 1000
    
    // Format elapsed time
    _pte_format_time `elapsed'
    local elapsed_str "`s(formatted)'"
    
    // Display completion info
    if "`nolog'" == "" {
        di as text ""
        if `"`message'"' != "" {
            di as text `"`message'"'
        }
        else if `failed' > 0 {
            di as text "`desc': Complete with " as error "`failed'" ///
                as text " failures (" as result "`elapsed_str'" as text ")"
        }
        else {
            di as text "`desc': Complete (" as result "`elapsed_str'" as text ")"
        }
    }
    
    // Return values
    return scalar elapsed = `elapsed'
    return scalar total = `total'
    return scalar completed = `current'
    return scalar failed = `failed'
    
    // Clean up global state
    capture macro drop PTE_PROGRESS_*
end
