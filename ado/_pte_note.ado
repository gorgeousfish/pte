*! _pte_note.ado
*! Note output for pte package (verbose mode only)

version 14.0
capture program drop _pte_note
program define _pte_note
    version 14.0
    args msg verbose
    
    // Only output in verbose mode
    if "`verbose'" != "" {
        di as text "[pte] Note: `msg'"
    }
end
