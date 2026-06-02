*! _pte_has_grouped_replay_state.ado
*! Detect grouped replay payloads lingering in e()

version 14.0
capture program drop _pte_has_grouped_replay_state
program define _pte_has_grouped_replay_state, rclass
    version 14.0

    quietly _pte_has_grouped_att_payload
    local has_grouped_replay = r(has_grouped_att)
    local grouped_payloads `"`r(grouped_payloads)'"'

    foreach _pte_mat in b_by rho_by sigma_by N_by N_firms_by {
        capture confirm matrix e(`_pte_mat')
        if _rc == 0 {
            local has_grouped_replay = 1
            local grouped_payloads "`grouped_payloads' `_pte_mat'"
        }
    }

    return scalar has_grouped_replay = `has_grouped_replay'
    return local grouped_payloads : list uniq grouped_payloads
end
