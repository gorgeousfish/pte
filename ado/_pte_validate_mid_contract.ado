*! _pte_validate_mid_contract.ado
*! Validate that the live transition indicator matches the current treatment law.

version 14.0
capture program drop _pte_validate_mid_contract
program define _pte_validate_mid_contract, rclass sortpreserve
    version 14.0

    syntax, MIDVAR(name) TREATment(name) PANELVAR(name) TIMEVAR(name) TOUSE(name) ///
        [CONTEXT(string)]

    if "`context'" == "" {
        local context "current omega recovery step"
    }

    capture confirm variable `midvar', exact
    if _rc != 0 {
        di as error "[pte] Error: transition indicator '`midvar'' not found"
        exit 111
    }
    capture confirm numeric variable `midvar'
    if _rc != 0 {
        di as error "[pte] Error: transition indicator '`midvar'' must be numeric"
        exit 111
    }
    capture confirm variable `treatment', exact
    if _rc != 0 {
        di as error "[pte] Error: treatment variable '`treatment'' not found"
        exit 111
    }
    capture confirm numeric variable `treatment'
    if _rc != 0 {
        di as error "[pte] Error: treatment variable '`treatment'' must be numeric"
        exit 111
    }
    capture confirm variable `panelvar', exact
    if _rc != 0 {
        di as error "[pte] Error: panel variable '`panelvar'' not found"
        exit 111
    }
    capture confirm variable `timevar', exact
    if _rc != 0 {
        di as error "[pte] Error: time variable '`timevar'' not found"
        exit 111
    }
    capture confirm variable `touse', exact
    if _rc != 0 {
        di as error "[pte] Error: touse variable '`touse'' not found"
        exit 111
    }
    capture confirm numeric variable `touse'
    if _rc != 0 {
        di as error "[pte] Error: touse variable '`touse'' must be numeric"
        exit 111
    }

    tempvar _pte_mid_expected _pte_mid_defined _pte_mid_first _pte_mid_mismatch
    quietly sort `panelvar' `timevar'
    quietly by `panelvar' (`timevar'): gen byte `_pte_mid_first' = (_n == 1)
    quietly by `panelvar' (`timevar'): gen byte `_pte_mid_defined' = ///
        (`touse' != 0 & !missing(`touse') & L.`touse' != 0 & !missing(L.`touse') ///
        & !missing(`treatment', L.`treatment'))
    quietly gen double `_pte_mid_expected' = . 
    quietly replace `_pte_mid_expected' = (`treatment' != L.`treatment') if `_pte_mid_defined'

    quietly gen byte `_pte_mid_mismatch' = 0
    quietly replace `_pte_mid_mismatch' = 1 if ///
        (`touse' != 0 & !missing(`touse')) & !missing(`_pte_mid_expected') & ///
        `midvar' != `_pte_mid_expected'

    quietly count if `_pte_mid_mismatch' == 1
    local n_mismatch = r(N)
    return scalar n_mismatch = `n_mismatch'

    if `n_mismatch' > 0 {
        di as error "[pte] Error: transition indicator '`midvar'' does not match treatment(`treatment') in `context'"
        di as error "[pte]        Theorem 3.1 requires transition periods to be defined from the same D_t path"
        di as error "[pte]        Re-run _pte_transition or pte_setup using treatment(`treatment') on the current sample"
        exit 498
    }
end
