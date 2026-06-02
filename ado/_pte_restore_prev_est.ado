*! _pte_restore_prev_est.ado
*! Restore the caller's previous e() bundle after a failed rerun.

version 14.0
capture program drop _pte_restore_prev_est
program define _pte_restore_prev_est
    version 14.0
    syntax, ESTname(name) HASEST(integer) [OMEGABACKup(name) HASOMEGA(integer 0)]

    capture confirm variable omega, exact
    if _rc == 0 {
        capture drop omega
    }
    if `hasomega' {
        capture clonevar omega = `omegabackup'
    }

    if `hasest' {
        capture estimates restore `estname'
        capture estimates drop `estname'
    }
    else {
        capture ereturn clear
    }
end
