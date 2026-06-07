*! _pte_has_grouped_beta_payload.ado
*! Detect grouped bootstrap coefficient payloads lingering in e()

version 14.0
capture program drop _pte_has_grouped_beta_payload
program define _pte_has_grouped_beta_payload, rclass
    version 14.0

    local has_grouped_beta = 0
    local grouped_payloads ""
    local group_count = 0

    local groups `"`e(groups)'"'
    if `"`groups'"' != "" & `"`groups'"' != "." {
        local group_count : word count `groups'
    }
    if `group_count' < 1 {
        capture local ngroups = e(ngroups)
        if _rc == 0 & `"`ngroups'"' != "" & `"`ngroups'"' != "." {
            local group_count = `ngroups'
        }
    }
    if `group_count' < 1 {
        capture local n_groups = e(n_groups)
        if _rc == 0 & `"`n_groups'"' != "" & `"`n_groups'"' != "." {
            local group_count = `n_groups'
        }
    }
    if `group_count' < 1 {
        forvalues g = 1/999 {
            local found_group = 0
            foreach prefix in beta_boot_g beta_se_g {
                capture confirm matrix e(`prefix'`g')
                if _rc == 0 local found_group = 1
            }
            if `found_group' {
                local group_count = `g'
            }
            else if `group_count' > 0 {
                continue, break
            }
        }
    }

    if `group_count' > 0 {
        forvalues g = 1/`group_count' {
            foreach prefix in beta_boot_g beta_se_g {
                capture confirm matrix e(`prefix'`g')
                if _rc == 0 {
                    local has_grouped_beta = 1
                    local grouped_payloads "`grouped_payloads' `prefix'`g'"
                }
            }
        }
    }

    return scalar has_grouped_beta = `has_grouped_beta'
    return local grouped_payloads : list uniq grouped_payloads
end
