*! pte_esttab_att.ado
*! Convert ATT results to esttab-compatible e(b)/e(V) format
*!
*! After running pte with bootstrap, use this command to repost e(b) and e(V)
*! so that esttab/estout can display ATT results with standard errors.
*!
*! Usage:
*!   pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) bootstrap(200)
*!   pte_esttab_att
*!   esttab, se

version 14.0
capture program drop pte_esttab_att
program define pte_esttab_att, eclass
    version 14.0

    if trim(`"`0'"') != "" {
        di as error "{bf:pte_esttab_att}: no arguments or options are allowed"
        di as error "Usage: {bf:pte_esttab_att}"
        exit 198
    }

    // --- Validate preconditions ---
    if "`e(cmd)'" != "pte" {
        di as error "{bf:pte_esttab_att}: requires pte estimation results"
        di as error "Run {bf:pte} first, then call {bf:pte_esttab_att}"
        exit 301
    }

    // Check ATT was computed under either the matrix or scalar contract
    capture confirm matrix e(att)
    local has_att_matrix = (_rc == 0)

    capture confirm scalar e(ATT_avg)
    local has_att_avg = (_rc == 0)

    capture confirm scalar e(att)
    local has_att_scalar = (_rc == 0)

    if !`has_att_matrix' & !`has_att_avg' & !`has_att_scalar' {
        di as error "{bf:pte_esttab_att}: ATT results not found in e()"
        di as error "Expected {bf:e(att)} matrix, {bf:e(ATT_avg)} scalar, or legacy {bf:e(att)} scalar"
        di as error "Make sure pte was run without {bf:noatt} option"
        exit 301
    }

    // Grouped public ATT results publish pooled e(att) alongside grouped
    // payloads. This adapter only knows how to flatten one pooled ATT path
    // into e(b)/e(V), so accepting grouped results would silently discard
    // cross-group heterogeneity from e(att_by)/e(att_by_point).
    local _pte_grouped_by ""
    capture local _pte_grouped_by = e(by)
    if _rc == 0 & `"`_pte_grouped_by'"' == "." {
        local _pte_grouped_by ""
    }
    quietly _pte_has_grouped_att_payload
    local _pte_has_grouped_att = r(has_grouped_att)
    local _pte_grouped_payloads `"`r(grouped_payloads)'"'
    if `_pte_has_grouped_att' {
        di as error "{bf:pte_esttab_att}: grouped ATT results are not supported"
        if `"`_pte_grouped_by'"' != "" {
            di as error "Current e() results were produced with by()/industry() and contain group-specific ATT paths."
        }
        else {
            di as error "Current e() results still contain grouped ATT payloads even though route metadata are incomplete."
        }
        if `"`_pte_grouped_payloads'"' != "" di as error "Detected grouped payload(s): `macval(_pte_grouped_payloads)'"
        di as error "Reposting pooled e(att) here would silently drop grouped heterogeneity."
        di as error "Re-run pooled pte results before pte_esttab_att, or export grouped matrices manually."
        exit 198
    }

    tempname att_mat att_table_mat att_se_mat
    if `has_att_matrix' {
        matrix `att_mat' = e(att)
    }

    capture confirm matrix e(att_table)
    local has_att_table = (_rc == 0)
    if `has_att_table' {
        matrix `att_table_mat' = e(att_table)
    }

    capture confirm matrix e(att_se)
    local has_att_se_matrix = (_rc == 0)
    if `has_att_se_matrix' {
        matrix `att_se_mat' = e(att_se)
    }

    // --- Determine dynamic ATT support ---
    local has_attperiods_matrix = 0
    tempname attperiods_mat
    capture confirm matrix e(attperiods)
    if _rc == 0 {
        local has_attperiods_matrix = 1
        matrix `attperiods_mat' = e(attperiods)
    }

    local nperiods = .
    local periodlist ""
    local colnames ""
    if `has_attperiods_matrix' {
        local dyncols = colsof(`attperiods_mat')
        if `has_att_matrix' {
            local dyncols = colsof(`att_mat') - 1
        }
        else if `has_att_table' {
            local dyncols = rowsof(`att_table_mat')
        }
        else if `has_att_se_matrix' {
            local dyncols = colsof(`att_se_mat') - 1
        }

        quietly _pte_attperiods_support `attperiods_mat' `dyncols' "pte_esttab_att"
        local nperiods = r(nperiods)
        local periodlist `"`r(periodlist)'"'
        if `has_att_matrix' {
            local _pte_att_colnames : colnames `att_mat'
            forvalues i = 1/`nperiods' {
                local expected_period : word `i' of `periodlist'
                local actual_name : word `i' of `_pte_att_colnames'
                local actual_period = .
                if regexm(`"`actual_name'"', "(-?[0-9]+)$") {
                    local actual_period = real(regexs(1))
                }
                else if regexm(`"`actual_name'"', "^[-]?[0-9]+$") {
                    local actual_period = real(`"`actual_name'"')
                }
                if missing(`actual_period') | `actual_period' != `expected_period' {
                    di as error "{bf:pte_esttab_att}: e(att) dynamic column identities drift from e(attperiods)"
                    di as error "Expected event time `expected_period' in dynamic column `i', found column name `actual_name'."
                    exit 198
                }
            }
        }
        if `has_att_se_matrix' {
            local _pte_att_se_colnames : colnames `att_se_mat'
            forvalues i = 1/`nperiods' {
                local expected_period : word `i' of `periodlist'
                local actual_name : word `i' of `_pte_att_se_colnames'
                local actual_period = .
                if regexm(`"`actual_name'"', "(-?[0-9]+)$") {
                    local actual_period = real(regexs(1))
                }
                else if regexm(`"`actual_name'"', "^[-]?[0-9]+$") {
                    local actual_period = real(`"`actual_name'"')
                }
                if missing(`actual_period') | `actual_period' != `expected_period' {
                    di as error "{bf:pte_esttab_att}: e(att_se) dynamic column identities drift from e(attperiods)"
                    di as error "Expected event time `expected_period' in dynamic column `i', found column name `actual_name'."
                    exit 198
                }
            }
        }
        if `has_att_table' {
            forvalues i = 1/`nperiods' {
                local expected_period : word `i' of `periodlist'
                local actual_period = `att_table_mat'[`i', 1]
                if missing(`actual_period') {
                    di as error "{bf:pte_esttab_att}: e(att_table) row `i' is missing its event-time identity"
                    di as error "Expected event time `expected_period' in column 1."
                    exit 198
                }
                if floor(`actual_period') != `actual_period' {
                    di as error "{bf:pte_esttab_att}: e(att_table) must store integer event times in column 1"
                    di as error "Expected event time `expected_period' in row `i', found `actual_period'."
                    exit 198
                }
                if `actual_period' != `expected_period' {
                    di as error "{bf:pte_esttab_att}: e(att_table) dynamic row identities drift from e(attperiods)"
                    di as error "Expected event time `expected_period' in row `i', found `actual_period'."
                    exit 198
                }
            }
        }
        foreach period_token of local periodlist {
            local colnames "`colnames' ATT_s`period_token'"
        }
    }
    else {
        capture confirm scalar e(attperiods_max)
        if _rc == 0 {
            local attperiods = e(attperiods_max)
        }
        else {
            capture confirm scalar e(attperiods)
            if _rc == 0 {
                local attperiods = e(attperiods)
            }
            else {
                di as error "{bf:pte_esttab_att}: e(attperiods) support not found in e()"
                di as error "Expected matrix {bf:e(attperiods)} or legacy scalar {bf:e(attperiods_max)}"
                exit 301
            }
        }
        local nperiods = `attperiods' + 1
        forvalues s = 0/`attperiods' {
            local periodlist "`periodlist' `s'"
            local colnames "`colnames' ATT_s`s'"
        }
    }
    local has_bootstrap = (e(bootstrap) > 0)

    // --- Build coefficient vector and SE vector ---
    local ncoef = `nperiods' + 1
    local colnames "`colnames' ATT_avg"

    tempname __b __V
    matrix `__b' = J(1, `ncoef', .)
    matrix `__V' = J(`ncoef', `ncoef', 0)

    if `has_att_matrix' {
        if rowsof(`att_mat') != 1 | colsof(`att_mat') != `ncoef' {
            di as error "{bf:pte_esttab_att}: e(att) must be a 1 x `ncoef' row vector aligned with the stored dynamic support"
            exit 503
        }
    }

    if `has_att_table' {
        if rowsof(`att_table_mat') < `nperiods' | colsof(`att_table_mat') < 5 {
            di as error "{bf:pte_esttab_att}: e(att_table) must have at least `nperiods' rows and 5 columns"
            exit 503
        }
    }

    if `has_att_se_matrix' {
        if rowsof(`att_se_mat') != 1 | colsof(`att_se_mat') != `ncoef' {
            di as error "{bf:pte_esttab_att}: e(att_se) must be a 1 x `ncoef' row vector aligned with the stored dynamic support"
            exit 503
        }
    }

    // --- Construct e(b) ---
    forvalues i = 1/`nperiods' {
        local col = `i'
        local period_token : word `i' of `periodlist'
        if `has_att_matrix' {
            matrix `__b'[1, `col'] = `att_mat'[1, `col']
        }
        else if `has_att_table' {
            matrix `__b'[1, `col'] = `att_table_mat'[`i', 2]
        }
        else {
            tempname att_scalar
            capture scalar `att_scalar' = e(att_`period_token')
            if !_rc & !missing(`att_scalar') {
                matrix `__b'[1, `col'] = `att_scalar'
            }
        }
    }

    // Overall ATT in last column
    local col = `ncoef'
    if `has_att_avg' {
        matrix `__b'[1, `col'] = e(ATT_avg)
    }
    else if `has_att_matrix' {
        matrix `__b'[1, `col'] = `att_mat'[1, `col']
    }
    else {
        matrix `__b'[1, `col'] = e(att)
    }

    matrix colnames `__b' = `colnames'
    matrix coleq `__b' = ""

    // --- Construct e(V) ---
    // Diagonal variance matrix from bootstrap SE or point SE
    local att_se_is_vector = 0
    if `has_att_se_matrix' {
        local att_se_is_vector = 1
    }

    if `has_bootstrap' {
        if `att_se_is_vector' {
            forvalues col = 1/`ncoef' {
                local se_val = `att_se_mat'[1, `col']
                if !missing(`se_val') {
                    matrix `__V'[`col', `col'] = `se_val'^2
                }
            }
        }
        else {
            forvalues i = 1/`nperiods' {
                local col = `i'
                local period_token : word `i' of `periodlist'
                tempname bs_scalar
                capture scalar `bs_scalar' = e(bs_se_`period_token')
                if !_rc & !missing(`bs_scalar') {
                    matrix `__V'[`col', `col'] = `bs_scalar'^2
                }
            }
            // Legacy bootstrap aliases store the overall ATT SE separately.
            local col = `ncoef'
            capture local se_val = e(bs_se)
            if !_rc & !missing(`se_val') {
                matrix `__V'[`col', `col'] = `se_val'^2
            }
        }
    }
    else {
        if `att_se_is_vector' {
            forvalues col = 1/`ncoef' {
                local se_val = `att_se_mat'[1, `col']
                if !missing(`se_val') {
                    matrix `__V'[`col', `col'] = `se_val'^2
                }
            }
        }
        else if `has_att_table' {
            forvalues i = 1/`nperiods' {
                local row = `i'
                local col = `i'
                local se_val = `att_table_mat'[`row', 5]
                if !missing(`se_val') {
                    matrix `__V'[`col', `col'] = `se_val'^2
                }
            }
        }

        local col = `ncoef'
        if !`att_se_is_vector' {
            capture local se_val = e(att_se)
            if !_rc & !missing(`se_val') {
                matrix `__V'[`col', `col'] = `se_val'^2
            }
        }
    }

    matrix colnames `__V' = `colnames'
    matrix rownames `__V' = `colnames'
    matrix coleq `__V' = ""
    matrix roweq `__V' = ""

    // --- Post new estimation result ---
    capture confirm scalar e(N)
    local has_N = (_rc == 0)
    if `has_N' {
        local N = e(N)
    }

    ereturn clear
    ereturn post `__b' `__V'
    if `has_N' {
        ereturn scalar N = `N'
    }

    // Update cmd to indicate ATT mode
    ereturn local cmd "pte_att"
    ereturn local title "PTE: Average Treatment Effects on Treated"

    // --- Display ---
    di ""
    di as text "ATT results converted to esttab format."
    di as text "Periods: `periodlist', plus overall average."
    di as text ""
    di as text "Use: {bf:esttab, se} or {bf:estimates table}"
end
