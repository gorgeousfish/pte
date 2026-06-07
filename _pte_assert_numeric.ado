*! _pte_assert_numeric.ado
*! Numeric assertion with tolerance

version 14.0
capture program drop _pte_assert_numeric
program define _pte_assert_numeric
    version 14.0
    syntax, actual(real) expected(real) [tol(real 1e-6) type(string) msg(string)]
    
    // Default comparison type: relative difference
    if "`type'" == "" local type "reldif"
    
    // Calculate difference based on type
    if "`type'" == "reldif" {
        local diff = reldif(`actual', `expected')
        local diff_label "reldif"
    }
    else if "`type'" == "absdif" {
        local diff = abs(`actual' - `expected')
        local diff_label "absdif"
    }
    else {
        di as error "[_pte_assert_numeric] Invalid type: `type' (valid: reldif, absdif)"
        exit 198
    }
    
    // Check assertion
    if `diff' >= `tol' {
        di as error "[ASSERT FAIL] `msg'"
        di as error "  actual   = " %18.12g `actual'
        di as error "  expected = " %18.12g `expected'
        di as error "  `diff_label' = " %12.6e `diff' " >= tol = " %12.6e `tol'
        exit 9
    }
    else {
        di as result "[ASSERT PASS] `msg' (`diff_label'=" %9.2e `diff' ")"
    }
end
