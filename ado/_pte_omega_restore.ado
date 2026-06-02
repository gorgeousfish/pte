*! _pte_omega_restore.ado
*! Roll back the saved estimation state after _pte_omega failures.

version 14.0
capture program drop _pte_omega_restore
program define _pte_omega_restore
    version 14.0
    syntax, ESTname(name) HASEST(integer)

    // Restore the preserved dataset first, then either reinstate the saved
    // e() result or clear e() so callers do not inherit half-built state.
    capture restore
    if `hasest' {
        capture estimates restore `estname'
        capture estimates drop `estname'
    }
    else {
        capture ereturn clear
    }
end
