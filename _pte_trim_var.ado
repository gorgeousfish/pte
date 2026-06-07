*! _pte_trim_var.ado
*! Deterministic 1%-99% trim helper for public diagnostic workers.

version 14.0
capture program drop _pte_trim_var
program define _pte_trim_var, rclass
    version 14.0

    syntax varname(numeric) [if]

    marksample touse, novarlist

    quietly count if `touse' & !missing(`varlist')
    local n_input = r(N)
    if r(N) == 0 {
        return scalar N_input = 0
        return scalar N_trimmed = 0
        return scalar p1 = .
        return scalar p99 = .
        exit
    }

    quietly _pctile `varlist' if `touse' & !missing(`varlist'), p(1 99)
    local p1 = r(r1)
    local p99 = r(r2)

    quietly count if `touse' & !missing(`varlist') ///
        & (`varlist' < `p1' | `varlist' > `p99')
    local n_trimmed = r(N)

    quietly replace `varlist' = . if `touse' ///
        & (`varlist' < `p1' | `varlist' > `p99')

    return scalar N_input = `n_input'
    return scalar N_trimmed = `n_trimmed'
    return scalar p1 = `p1'
    return scalar p99 = `p99'
end
