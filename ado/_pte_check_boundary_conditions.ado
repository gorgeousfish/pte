*! _pte_check_boundary_conditions.ado
*! Boundary condition checks for treatment events
*! Validates nentry/nexit counts and issues warnings or errors

version 14.0
// _pte_check_boundary_conditions: Check edge cases before estimation
// BC-1: nentry=0 & nexit=0 => error 498 (no treatment variation)
// BC-2: nentry < 10 => warning (imprecise estimates)
// BC-3: Only 1 firm => warning (bootstrap unavailable)

program define _pte_check_boundary_conditions
    version 14.0
    
    syntax, ///
        Nentry(integer) ///
        Nexit(integer) ///
        PANELvar(varname) ///
        [TOUSE(varname numeric)]
    
    // ═══════════════════════════════════════════════════════════════
    // BC-1: No treatment variation at all
    // ═══════════════════════════════════════════════════════════════
    if `nentry' == 0 & `nexit' == 0 {
        di as error "pte: No treatment variation in the data"
        di as error "All observations have the same treatment status"
        exit 498
    }
    
    // ═══════════════════════════════════════════════════════════════
    // BC-2: Very few entry events
    // ═══════════════════════════════════════════════════════════════
    if `nentry' > 0 & `nentry' < 10 {
        di as text "{p 0 4 2}"
        di as text "Warning: Very few entry events (N=`nentry')."
        di as text "ATT estimates may be imprecise."
        di as text "{p_end}"
    }
    
    // ═══════════════════════════════════════════════════════════════
    // BC-3: Single firm in sample
    // ═══════════════════════════════════════════════════════════════
    if "`touse'" == "" {
        qui levelsof `panelvar', local(_pte_firms)
    }
    else {
        qui levelsof `panelvar' if `touse', local(_pte_firms)
    }
    local _pte_nfirms : word count `_pte_firms'
    if `_pte_nfirms' == 1 {
        di as text "{p 0 4 2}"
        di as text "Warning: Only 1 firm in the sample."
        di as text "Bootstrap inference not available."
        di as text "{p_end}"
    }
end
