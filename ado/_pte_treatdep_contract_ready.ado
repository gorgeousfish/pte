*! _pte_treatdep_contract_ready.ado
*! Verify that the official treatdependent Mata companion objects are loaded.

version 14.0
capture program drop _pte_treatdep_contract_ready
program define _pte_treatdep_contract_ready, rclass
    version 14.0

    local ready = 1
    local missing ""

    // The official DO implementation loads facf1()/facf2(), while the PTE
    // patch refreshes opt_mata()/facf3(). Treatdependent is runnable only
    // when the full post-patch companion set is present.
    foreach fn in facf1 facf2 facf3 opt_mata {
        capture mata: mata describe `fn'()
        if _rc != 0 {
            local ready = 0
            local missing "`missing' `fn'()"
        }
    }

    return scalar ready = `ready'
    return local missing = strtrim("`missing'")
end
