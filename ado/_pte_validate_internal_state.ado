*! _pte_validate_internal_state.ado
*! Validate package-owned internal state contracts for public consumers.

version 14.0
capture program drop _pte_validate_internal_state
program define _pte_validate_internal_state
    version 14.0

    args varname statetype context

    local statetype = lower(strtrim(`"`statetype'"'))
    local context = strtrim(`"`context'"')
    if `"`context'"' == "" {
        local context "PTE postestimation consumers"
    }

    capture confirm variable `varname', exact
    if _rc {
        di as error "[pte] `varname' variable not found"
        di as error "[pte] `context'"
        di as error "[pte] Re-run pte to regenerate internal variables"
        exit 111
    }

    capture confirm numeric variable `varname', exact
    if _rc {
        di as error "[pte] `varname' must be numeric."
        di as error "[pte] `context'"
        di as error "[pte] Re-run pte to regenerate internal variables"
        exit 111
    }

    if "`statetype'" == "binary" {
        capture assert inlist(`varname', 0, 1) if !missing(`varname')
        if _rc {
            di as error "[pte] `varname' must be binary (0/1)."
            di as error "[pte] `context'"
            di as error "[pte] Re-run pte to regenerate internal variables"
            exit 450
        }
        exit
    }

    if "`statetype'" == "integer" {
        capture assert abs(`varname' - round(`varname')) <= 1e-10 if !missing(`varname')
        if _rc {
            di as error "[pte] `varname' must be integer-valued when nonmissing."
            di as error "[pte] `context'"
            di as error "[pte] Re-run pte to regenerate internal variables"
            exit 450
        }
        exit
    }

    if "`statetype'" == "numeric" {
        exit
    }

    di as error "[pte] Unsupported internal state contract type: `statetype'"
    exit 198
end
