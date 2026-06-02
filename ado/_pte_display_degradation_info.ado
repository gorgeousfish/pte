*! _pte_display_degradation_info.ado
*! Shows absorbing treatment detection status and algorithm choice

version 14.0
// _pte_display_degradation_info: Inform user about absorbing degradation
// Called when nonabsorbing option is specified but data is absorbing

program define _pte_display_degradation_info
    version 14.0
    
    syntax, Nentry(integer) [Verbose]
    
    // ═══════════════════════════════════════════════════════════════
    // Main information display
    // ═══════════════════════════════════════════════════════════════
    di as text _n "{hline 70}"
    di as text "Non-absorbing Treatment Option Enabled"
    di as text "{hline 70}"
    
    di as text "Treatment type detected: " as result "Absorbing (irreversible)"
    di as text "  Entry events (0->1): " as result %8.0f `nentry'
    di as text "  Exit events (1->0):  " as result "0"
    
    di as text _n "Interpretation:"
    di as text "  No firms exit treatment once adopted."
    di as text "  This is consistent with absorbing treatment assumption."
    
    di as text _n "Algorithm:"
    di as text "  Using standard pte estimation"
    di as text "  ATT(-) (exit effects) is undefined."
    di as text "  ATT(+) (entry effects) equals standard ATT."
    
    di as text "{hline 70}" _n
    
    // ═══════════════════════════════════════════════════════════════
    // Verbose debug output
    // ═══════════════════════════════════════════════════════════════
    if "`verbose'" != "" {
        di as text "[debug] _pte_display_degradation_info: " ///
            "nentry=`nentry', degrading to standard pipeline"
    }
end
