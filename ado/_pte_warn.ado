*! _pte_warn.ado
*! Warning output for pte package (non-fatal)

version 14.0
capture program drop _pte_warn
program define _pte_warn
    version 14.0
    args msg
    
    // Output warning message (non-fatal, uses text color)
    di as text "[pte] Warning: `msg'"
end
