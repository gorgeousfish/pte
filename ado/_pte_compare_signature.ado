*! _pte_compare_signature.ado
*! Compute a deterministic compare-input fingerprint.

version 14.0
capture program drop _pte_compare_signature
program define _pte_compare_signature, rclass sortpreserve
    version 14.0

    syntax , PANELVAR(name) TIMEVAR(name) TREATment(name) ///
        DEPVAR(name) FREE(name) STATE(name) PROXY(name) ///
        [CONTROLS(varlist)]

    foreach _pte_sig_var in `panelvar' `timevar' `treatment' `depvar' `free' `state' `proxy' {
        capture confirm variable `_pte_sig_var', exact
        if _rc != 0 {
            di as error "_pte_compare_signature: variable `_pte_sig_var' not found"
            exit 111
        }
    }

    local _pte_sig_vars `panelvar' `timevar' `treatment' `depvar' `free' `state' `proxy'
    if `"`controls'"' != "" {
        foreach _pte_ctrl of varlist `controls' {
            capture confirm variable `_pte_ctrl', exact
            if _rc != 0 {
                di as error "_pte_compare_signature: control variable `_pte_ctrl' not found"
                exit 111
            }
        }
        local _pte_sig_vars `_pte_sig_vars' `controls'
    }

    quietly sort `panelvar' `timevar'
    quietly _datasignature `_pte_sig_vars'

    return local signature "`r(datasignature)'"
    return local vars "`_pte_sig_vars'"
end
