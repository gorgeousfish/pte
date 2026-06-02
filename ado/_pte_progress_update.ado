*! _pte_progress_update.ado

version 14.0
capture program drop _pte_progress_update
program define _pte_progress_update
    version 14.0
    
    syntax, Current(integer) [FAILED]
    
    // Check initialization state
    if "$PTE_PROGRESS_TOTAL" == "" {
        di as error "Progress system not initialized"
        exit 198
    }
    
    // Update state
    global PTE_PROGRESS_CURRENT = `current'
    if "`failed'" != "" {
        global PTE_PROGRESS_FAILED = $PTE_PROGRESS_FAILED + 1
    }
    
    // Check suppression flag
    if "$PTE_PROGRESS_NOLOG" != "" {
        exit
    }
    
    // Get global state
    local total = $PTE_PROGRESS_TOTAL
    local milestone = $PTE_PROGRESS_MILESTONE
    local style "$PTE_PROGRESS_STYLE"
    local desc "$PTE_PROGRESS_DESC"
    
    // Calculate percentage
    local pct = round(100 * `current' / `total', 1)
    
    // Calculate ETA
    local elapsed = (clock("$S_DATE $S_TIME", "DMYhms") - $PTE_PROGRESS_START) / 1000
    if `current' > 0 {
        local eta = `elapsed' * (`total' - `current') / `current'
        _pte_format_time `eta'
        local eta_str "`s(formatted)'"
    }
    else {
        local eta_str "..."
    }
    
    // Frequency limiting: pct/bar styles only update on percentage change
    local should_display = 1
    if inlist("`style'", "pct", "bar") & `total' > 100 {
        local prev_pct_int = floor(100 * (`current' - 1) / `total')
        local curr_pct_int = floor(100 * `current' / `total')
        local should_display = (`curr_pct_int' > `prev_pct_int') | (`current' == `total')
    }
    
    // Display based on style
    if "`style'" == "dots" {
        if "`failed'" != "" {
            noi di as error "x" _continue
        }
        else if mod(`current', `milestone') == 0 {
            noi di as result "`current'" _continue
        }
        else {
            noi di as text "." _continue
        }
    }
    else if "`style'" == "pct" {
        if `should_display' {
            noi di _char(13) as text "`desc': " as result "`current' / `total'" ///
               as text " (`pct'%) - ETA: " as result "`eta_str'" _continue
        }
    }
    else if "`style'" == "bar" {
        if `should_display' {
            local bar_width = 20
            local filled = floor(`pct' * `bar_width' / 100)
            local empty = `bar_width' - `filled'
            // Build progress bar string
            local bar_filled ""
            local bar_empty ""
            forval i = 1/`filled' {
                local bar_filled "`bar_filled'#"
            }
            if `empty' > 0 {
                forval i = 1/`empty' {
                    local bar_empty "`bar_empty'-"
                }
            }
            noi di _char(13) as text "[" as result "`bar_filled'" ///
                as text "`bar_empty'" as text "] `pct'%" _continue
        }
    }
    else if "`style'" == "minimal" {
        if mod(`current', `milestone') == 0 {
            noi di as result "`current' " _continue
        }
    }
end
