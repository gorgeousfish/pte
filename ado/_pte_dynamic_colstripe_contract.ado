*! _pte_dynamic_colstripe_contract.ado
*! Validate dynamic matrix column identities against exact stored event-time support.

version 14.0
capture program drop _pte_dynamic_colstripe_contract
program define _pte_dynamic_colstripe_contract
    version 14.0

    args matname supportname dyncols context surfacename

    if `"`context'"' == "" {
        local context "dynamic support contract"
    }
    if `"`surfacename'"' == "" {
        local surfacename "dynamic result"
    }

    if `dyncols' < 1 {
        di as error "`context': dynamic period support must contain at least one column."
        exit 198
    }

    local mat_cols = colsof(`matname')
    if `mat_cols' < `dyncols' {
        di as error "`context': `surfacename' does not cover the declared dynamic support."
        di as error "`context': expected at least `dyncols' dynamic columns, found `mat_cols'."
        exit 198
    }

    local colnames : colnames `matname'
    local cname_count : word count `colnames'
    if `cname_count' < `dyncols' {
        di as error "`context': `surfacename' is missing dynamic column identities."
        di as error "`context': expected `dyncols' dynamic column names, found `cname_count'."
        exit 198
    }

    forvalues j = 1/`dyncols' {
        local expected_period = `supportname'[1, `j']
        local expected_str = trim(string(`expected_period', "%21.0g"))
        local actual_name : word `j' of `colnames'
        local actual_period = .

        if regexm(`"`actual_name'"', "(-?[0-9]+)$") {
            local actual_period = real(regexs(1))
        }
        else if regexm(`"`actual_name'"', "^[-]?[0-9]+$") {
            local actual_period = real(`"`actual_name'"')
        }

        if missing(`actual_period') {
            di as error "`context': `surfacename' dynamic column identities drift from e(attperiods)."
            di as error "`context': expected event time `expected_str' in dynamic column `j', found column name `actual_name'."
            exit 198
        }

        if `actual_period' != `expected_period' {
            di as error "`context': `surfacename' dynamic column identities drift from e(attperiods)."
            di as error "`context': expected event time `expected_str' in dynamic column `j', found column name `actual_name'."
            exit 198
        }
    }
end
