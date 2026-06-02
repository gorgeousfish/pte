*! _pte_progress_init.ado

version 14.0
capture program drop _pte_progress_init
program define _pte_progress_init, rclass
    version 14.0
    
    syntax, Total(integer) ///
        [Desc(string)]     ///
        [Milestone(integer 50)] ///
        [Style(string)]    ///
        [NOLOG]
    
    // Parameter validation
    if `total' <= 0 {
        di as error "total() must be a positive integer"
        exit 198
    }
    
    if `milestone' <= 0 {
        local milestone = 50
    }
    
    // Default values
    if "`desc'" == "" {
        local desc "Processing"
    }
    
    if "`style'" == "" {
        local style "dots"
    }
    
    // Validate style option
    if !inlist("`style'", "dots", "pct", "bar", "minimal") {
        di as text "Note: Unknown style '`style'', using 'dots'"
        local style "dots"
    }
    
    // Initialize global state
    global PTE_PROGRESS_TOTAL = `total'
    global PTE_PROGRESS_CURRENT = 0
    global PTE_PROGRESS_DESC "`desc'"
    global PTE_PROGRESS_MILESTONE = `milestone'
    global PTE_PROGRESS_STYLE "`style'"
    global PTE_PROGRESS_NOLOG "`nolog'"
    global PTE_PROGRESS_FAILED = 0
    global PTE_PROGRESS_START = clock("$S_DATE $S_TIME", "DMYhms")
    
    // Display initial info
    if "`nolog'" == "" {
        if "`style'" == "dots" {
            di as text "`desc': " _continue
        }
        else if "`style'" == "pct" {
            di as text "`desc': " as result "0 / `total'" as text " (0%)"
        }
        else if "`style'" == "bar" {
            di as text "[" as text "--------------------" as text "] 0%"
        }
        // minimal: no initial display
    }
    
    // Return values
    return scalar total = `total'
end
