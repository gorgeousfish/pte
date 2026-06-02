*! _pte_winsorize_restore.ado
*! Failure rollback helper for _pte_winsorize

version 14.0
capture program drop _pte_winsorize_restore
program define _pte_winsorize_restore
    version 14.0
    syntax, ESTname(name) HASEST(integer)

    if `hasest' {
        capture estimates restore `estname'
        capture estimates drop `estname'
    }
    else {
        capture ereturn clear
    }
end
