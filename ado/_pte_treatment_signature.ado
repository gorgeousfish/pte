*! _pte_treatment_signature.ado
*! Compute a deterministic panel/time/treatment-law fingerprint.

version 14.0
capture program drop _pte_treatment_signature
program define _pte_treatment_signature, rclass sortpreserve
    version 14.0

    syntax , PANELVAR(name) TIMEVAR(name) TREATment(name)

    capture confirm variable `panelvar', exact
    if _rc != 0 {
        di as error "_pte_treatment_signature: panel variable `panelvar' not found"
        exit 111
    }
    capture confirm variable `timevar', exact
    if _rc != 0 {
        di as error "_pte_treatment_signature: time variable `timevar' not found"
        exit 111
    }
    capture confirm variable `treatment', exact
    if _rc != 0 {
        di as error "_pte_treatment_signature: treatment variable `treatment' not found"
        exit 111
    }

    quietly sort `panelvar' `timevar'
    quietly _datasignature `panelvar' `timevar' `treatment'

    return local signature "`r(datasignature)'"
    return local panelvar "`panelvar'"
    return local timevar "`timevar'"
    return local treatment "`treatment'"
end
