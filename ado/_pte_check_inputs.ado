*! _pte_check_inputs.ado
*! Pre-ereturn-post validation for pte
*!
*! Validates b/V matrices, touse variable, and observation count
*! before ereturn post to catch errors early with clear messages.
*!
*! Usage (internal):
*!   _pte_check_inputs `__b' `__V' `touse' `nobs'

version 14.0
capture program drop _pte_check_inputs
program define _pte_check_inputs
    version 14.0
    args b V touse nobs

    // 1. Validate touse variable exists
    capture confirm variable `touse'
    if _rc {
        di as error "{bf:pte error E-4009}: touse variable '`touse'' not found"
        exit 3009
    }

    // 2. Validate nobs > 0
    if `nobs' <= 0 {
        di as error "{bf:pte error E-4003}: No observations (nobs = `nobs')"
        exit 3003
    }

    // 3. Validate b/V dimension consistency
    local b_cols = colsof(`b')
    local V_rows = rowsof(`V')
    local V_cols = colsof(`V')

    if `b_cols' != `V_rows' | `b_cols' != `V_cols' {
        di as error "{bf:pte error E-4002}: Dimension mismatch between b and V"
        di as error "  e(b) columns: `b_cols'"
        di as error "  e(V) dimensions: `V_rows' x `V_cols'"
        exit 3002
    }

    // 4. Validate V has no missing values
    forvalues i = 1/`V_rows' {
        forvalues j = 1/`V_cols' {
            if missing(`V'[`i', `j']) {
                di as error "{bf:pte error E-4001}: V matrix contains missing values"
                di as error "  Missing at position [`i', `j']"
                exit 3001
            }
        }
    }
end
