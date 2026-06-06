*! _pte_has_grouped_att_payload.ado
*! Detect grouped ATT payloads lingering in e()

version 14.0
capture program drop _pte_has_grouped_att_payload
program define _pte_has_grouped_att_payload, rclass
    version 14.0

    local has_grouped_att = 0
    local grouped_payloads ""

    foreach _pte_mat in ///
        att_by att_by_point att_pool att_pool_trim att_pool_raw ///
        att_N ///
        att_mean_pool att_mean_pool_trim ///
        att_se_pool att_se_pool_trim ///
        att_ci_lower_pool att_ci_upper_pool ///
        att_ci_lower_trim att_ci_upper_trim ///
        att_boot_all att_boot_trim att_boot_bygroup {
        capture confirm matrix e(`_pte_mat')
        if _rc == 0 {
            local has_grouped_att = 1
            local grouped_payloads "`grouped_payloads' `_pte_mat'"
        }
    }

    local _pte_group_count = 0
    local _pte_groups `"`e(groups)'"'
    if `"`_pte_groups'"' != "" & `"`_pte_groups'"' != "." {
        local _pte_group_count : word count `_pte_groups'
    }
    if `_pte_group_count' < 1 {
        capture local _pte_ngroups = e(ngroups)
        if _rc == 0 & "`_pte_ngroups'" != "." & "`_pte_ngroups'" != "" {
            local _pte_group_count = `_pte_ngroups'
        }
    }
    if `_pte_group_count' < 1 {
        capture local _pte_n_groups = e(n_groups)
        if _rc == 0 & "`_pte_n_groups'" != "." & "`_pte_n_groups'" != "" {
            local _pte_group_count = `_pte_n_groups'
        }
    }
    if `_pte_group_count' < 1 {
        forvalues _pte_g = 1/999 {
            local _pte_found_group = 0
            foreach _pte_prefix in att_boot_g att_trim_boot_g att_se_g {
                capture confirm matrix e(`_pte_prefix'`_pte_g')
                if _rc == 0 local _pte_found_group = 1
            }
            if `_pte_found_group' {
                local _pte_group_count = `_pte_g'
            }
            else if `_pte_group_count' > 0 {
                continue, break
            }
        }
    }

    if `_pte_group_count' > 0 {
        forvalues _pte_g = 1/`_pte_group_count' {
            foreach _pte_prefix in att_boot_g att_trim_boot_g att_se_g {
                capture confirm matrix e(`_pte_prefix'`_pte_g')
                if _rc == 0 {
                    local has_grouped_att = 1
                    local grouped_payloads "`grouped_payloads' `_pte_prefix'`_pte_g'"
                }
            }
        }
    }

    return scalar has_grouped_att = `has_grouped_att'
    return local grouped_payloads : list uniq grouped_payloads
end
