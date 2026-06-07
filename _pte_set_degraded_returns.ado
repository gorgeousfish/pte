*! _pte_set_degraded_returns.ado
*! Maps e(att) -> e(att_switchin), creates empty e(att_switchout)

version 14.0
// _pte_set_degraded_returns: Remap returns to interface
// att_switchin = (L+2)x3 [period, ATT, N_firms] from e(att)
// att_switchout = (L+2)x3 all missing (no exit events)

program define _pte_set_degraded_returns, eclass
    version 14.0
    
    syntax, ATTperiods(integer) Nentry(integer) [Verbose]
    
    // ═══════════════════════════════════════════════════════════════
    // Step 1: Save e(att) BEFORE any ereturn (ereturn clears e())
    // ═══════════════════════════════════════════════════════════════
    tempname att_raw
    matrix `att_raw' = e(att)
    local L = `attperiods'
    local nrows = `L' + 2       // L+2 rows: nt0...ntL + Avg
    
    // ═══════════════════════════════════════════════════════════════
    // Step 2: Set treatment type flag (this clears previous e())
    // ═══════════════════════════════════════════════════════════════
    ereturn local trt_type "absorbing"
    
    // ═══════════════════════════════════════════════════════════════
    // Step 3: Build att_switchin = (L+2)x3 [period, ATT, N_firms]
    //   Compatible with output interface
    // ═══════════════════════════════════════════════════════════════
    tempname att_switchin
    matrix `att_switchin' = J(`nrows', 3, .)
    forvalues i = 1/`nrows' {
        matrix `att_switchin'[`i', 1] = `i' - 1            // period: 0,1,...,L,L+1(Avg)
        matrix `att_switchin'[`i', 2] = `att_raw'[1, `i']  // ATT value
        matrix `att_switchin'[`i', 3] = `nentry'            // N_firms (same for all periods)
    }
    
    // Row/column names
    local rnames ""
    forvalues i = 0/`L' {
        local rnames "`rnames' nt`i'"
    }
    local rnames "`rnames' Avg"
    matrix rownames `att_switchin' = `rnames'
    matrix colnames `att_switchin' = period ATT N_firms
    ereturn matrix att_switchin = `att_switchin'
    
    // ═══════════════════════════════════════════════════════════════
    // Step 4: Build att_switchout = (L+2)x3 all missing
    // ═══════════════════════════════════════════════════════════════
    tempname att_switchout
    matrix `att_switchout' = J(`nrows', 3, .)
    matrix rownames `att_switchout' = `rnames'
    matrix colnames `att_switchout' = period ATT N_firms
    ereturn matrix att_switchout = `att_switchout'
    
    // ═══════════════════════════════════════════════════════════════
    // Step 5: Extended sample counts and flags
    // ═══════════════════════════════════════════════════════════════
    ereturn scalar n_switchin = `nentry'
    ereturn scalar n_switchout = 0
    ereturn scalar absorbing = 1
    
    // ═══════════════════════════════════════════════════════════════
    // Step 6: Display mapping summary
    // ═══════════════════════════════════════════════════════════════
    di as text _n "Return values mapped to non-absorbing interface:"
    di as text "  e(trt_type) = " as result "absorbing"
    di as text "  e(att_switchin): (`nrows'x3) " as result "(mapped from e(att))"
    di as text "  e(att_switchout): (`nrows'x3) " as result "(all missing)"
    di as text "  e(n_switchin) = " as result %8.0f e(n_switchin)
    di as text "  e(n_switchout) = " as result "0"
    di as text "  e(absorbing) = " as result "1"
    
    if "`verbose'" != "" {
        di as text _n "[debug] _pte_set_degraded_returns: " ///
            "L=`L', nrows=`nrows', nentry=`nentry'"
    }
end
