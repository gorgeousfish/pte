*! _pte_restore_xtset_contract.ado
*! Restore the caller's xtset contract after temporary panel-state changes.

version 14.0
capture program drop _pte_restore_xtset_contract
program define _pte_restore_xtset_contract
    version 14.0

    syntax , HADXTSET(integer) [PANEL(string) TIME(string) DELTA(string)]

    if `hadxtset' {
        if `"`panel'"' == "" {
            di as error "_pte_restore_xtset_contract: panel() is required when hadxtset(1)"
            exit 198
        }

        local time_clean = strtrim(`"`time'"')
        if `"`time_clean'"' == "" {
            capture quietly xtset `panel'
            exit
        }

        local delta_opt ""
        local delta_clean = strtrim(`"`delta'"')
        if `"`delta_clean'"' != "" {
            local delta_opt "delta(`delta_clean')"
        }
        capture quietly xtset `panel' `time_clean', `delta_opt'
    }
    else {
        capture quietly xtset, clear
    }
end
