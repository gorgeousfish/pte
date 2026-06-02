*! _pte_attperiods_support.ado
*! Validate semantic integrity of stored ATT event-time support.

version 14.0
capture program drop _pte_attperiods_support
program define _pte_attperiods_support, rclass
    version 14.0

    args matname dyncols context

    if `"`context'"' == "" {
        local context "attperiods support"
    }

    if `dyncols' < 1 {
        di as error "`context': dynamic period support must contain at least one column."
        exit 198
    }

    if rowsof(`matname') != 1 {
        di as error "`context': e(attperiods) must be a row vector."
        exit 198
    }

    local stored_cols = colsof(`matname')
    if `stored_cols' != `dyncols' {
        di as error "`context': dynamic result columns drift from e(attperiods)."
        di as error "`context': expected `stored_cols' dynamic columns from e(attperiods), found `dyncols'."
        exit 198
    }

    local periodlist ""
    local minperiod = .
    local maxperiod = .
    local prevperiod = .

    forvalues i = 1/`dyncols' {
        local period_i = `matname'[1, `i']
        if missing(`period_i') {
            di as error "`context': e(attperiods) must not contain missing event-time support."
            exit 198
        }
        if floor(`period_i') != `period_i' {
            di as error "`context': e(attperiods) must contain integer event-time support."
            di as error "`context': ATT horizons are indexed by discrete event time ell and cannot be fractional."
            exit 198
        }
        if `period_i' < 0 {
            di as error "`context': e(attperiods) must contain nonnegative event-time support."
            di as error "`context': ATT horizons are indexed by discrete event time ell >= 0 and cannot be negative."
            exit 198
        }
        if `i' > 1 & `period_i' <= `prevperiod' {
            di as error "`context': e(attperiods) must be strictly increasing without duplicates."
            exit 198
        }

        local period_str = trim(string(`period_i', "%21.0g"))
        local periodlist "`periodlist' `period_str'"
        local prevperiod = `period_i'

        if missing(`minperiod') | `period_i' < `minperiod' {
            local minperiod = `period_i'
        }
        if missing(`maxperiod') | `period_i' > `maxperiod' {
            local maxperiod = `period_i'
        }
    }

    return matrix periods = `matname'
    return scalar nperiods = `dyncols'
    return scalar minperiod = `minperiod'
    return scalar maxperiod = `maxperiod'
    return local periodlist : list retokenize periodlist
end
