*! Top-level loader for source-loading an installed treatdependent ado file.

version 14.0

capture mata: mata describe facf1()
local pte_need_seed = (_rc != 0)
capture mata: mata describe facf2()
if _rc != 0 local pte_need_seed = 1
capture mata: mata describe facf3()
if _rc != 0 local pte_need_seed = 1
capture mata: mata describe opt_mata()
if _rc != 0 local pte_need_seed = 1

if `pte_need_seed' {
    capture quietly findfile _pte_treatdep_seed_placeholders.do
    if _rc == 0 {
        include `"`r(fn)'"'
    }
}

include `"$PTE_TREATDEP_SOURCE_FILE"'
