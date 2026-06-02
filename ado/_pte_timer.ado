*! _pte_timer.ado

version 14.0
capture program drop _pte_timer
program define _pte_timer, rclass
    version 14.0
    
    syntax anything(name=action), Name(string)
    
    // Normalize action name
    local action = lower("`action'")
    
    // Build global macro names using local variables
    local gname_start "PTE_TIMER_`name'_START"
    local gname_running "PTE_TIMER_`name'_RUNNING"
    
    if "`action'" == "start" {
        // Start timer
        global `gname_start' = clock("$S_DATE $S_TIME", "DMYhms")
        global `gname_running' = 1
    }
    else if "`action'" == "elapsed" {
        // Get elapsed time
        if "${`gname_running'}" != "1" {
            di as error "Timer '`name'' is not running"
            exit 198
        }
        local elapsed = clock("$S_DATE $S_TIME", "DMYhms") - ${`gname_start'}
        return scalar elapsed_ms = `elapsed'
    }
    else if "`action'" == "stop" {
        // Stop timer
        if "${`gname_running'}" != "1" {
            di as error "Timer '`name'' is not running"
            exit 198
        }
        local total = clock("$S_DATE $S_TIME", "DMYhms") - ${`gname_start'}
        return scalar total_ms = `total'
        // Clean up
        capture macro drop PTE_TIMER_`name'_*
    }
    else if "`action'" == "reset" {
        // Reset timer
        capture macro drop PTE_TIMER_`name'_*
    }
    else {
        di as error "Unknown action: '`action''"
        di as error "Valid actions: start, elapsed, stop, reset"
        exit 198
    }
end
