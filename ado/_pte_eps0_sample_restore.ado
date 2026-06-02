*! _pte_eps0_sample_restore.ado
*! Restore the caller dataset and estimation state after _pte_eps0_sample exits early.

version 14.0
capture program drop _pte_eps0_sample_restore
program define _pte_eps0_sample_restore
    version 14.0
    syntax, DATAfile(string) ESTname(name) HASEST(integer)

    // Roll back the saved data first, then either reinstate the previous
    // estimate or clear e() so no half-built eps0 bridge leaks outward.
    capture quietly use `"`datafile'"', clear
    if `hasest' {
        capture estimates restore `estname'
        capture estimates drop `estname'
    }
    else {
        capture ereturn clear
    }
end
