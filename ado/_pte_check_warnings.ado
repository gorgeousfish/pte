*! _pte_check_warnings.ado
*! Post-ereturn warning detection for pte
*!
*! Checks e(V) for non-positive diagonal elements and non-positive-semi-definiteness.
*! Accumulates warnings in e(warnings) macro.
*!
*! Usage (internal, after ereturn post):
*!   _pte_check_warnings

version 14.0
capture program drop _pte_check_warnings
program define _pte_check_warnings, eclass
    version 14.0

    local warnings ""

    // 1. Check V diagonal elements are non-negative
    tempname V_check
    matrix `V_check' = e(V)
    local K = rowsof(`V_check')

    forvalues k = 1/`K' {
        if `V_check'[`k', `k'] < 0 {
            local vname : word `k' of `: colnames `V_check''
            di as text "{bf:pte warning W-4001}: Non-positive variance for parameter '`vname'' (position `k')"
            local warnings "`warnings' W-4001"
        }
    }

    // 2. Check positive semi-definiteness via minimum eigenvalue
    tempname __min_eigen
    mata {
        _V_tmp = st_matrix("`V_check'")
        _eig_vals = eigenvalues(_V_tmp)
        _min_eig = min(Re(_eig_vals))
        st_numscalar("`__min_eigen'", _min_eig)
    }

    if `__min_eigen' < -1e-10 {
        di as text "{bf:pte warning W-4002}: V matrix is not positive semi-definite"
        di as text "  Minimum eigenvalue: " %12.6e `__min_eigen'
        local warnings "`warnings' W-4002"
    }

    // 3. Store warnings in e()
    if "`warnings'" != "" {
        local warnings = strtrim("`warnings'")
        ereturn local warnings "`warnings'"
    }
end
