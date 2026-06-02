*! _pte_graph_attperiods_contract.ado
*! Resolve and validate stored dynamic period support for graph consumers.

version 14.0
capture program drop _pte_graph_attperiods_contract
program define _pte_graph_attperiods_contract, rclass
    version 14.0

    syntax, DYNCOLS(integer) [CONTEXT(string)]

    local context `"`context'"'
    if `"`context'"' == "" {
        local context "dynamic graph"
    }

    if `dyncols' < 1 {
        di as error "`context': dynamic period support must contain at least one column."
        exit 198
    }

    tempname PERIODS
    capture confirm matrix e(attperiods)
    if _rc != 0 {
        di as error "`context': e(attperiods) not found."
        di as error "`context': dynamic graph consumers require the exact stored event-time support and must not infer 0..L-1 from matrix width."
        exit 198
    }

    matrix `PERIODS' = e(attperiods)
    quietly _pte_attperiods_support `PERIODS' `dyncols' `"`context'"'

    tempname RETURN_PERIODS
    matrix `RETURN_PERIODS' = r(periods)
    return matrix periods = `RETURN_PERIODS'
    return scalar used_stored = 1
    return scalar nperiods = r(nperiods)
    return scalar minperiod = r(minperiod)
    return scalar maxperiod = r(maxperiod)
    return local periodlist `"`r(periodlist)'"'
end
