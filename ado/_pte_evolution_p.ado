*! _pte_evolution_p.ado
*! Custom predict for _pte_evolution

version 14.0
capture program drop _pte_evolution_p
program define _pte_evolution_p
    version 14.0, missing

    local myopts "XB REsiduals"
    _pred_se "`myopts'" `0'
    if `s(done)' {
        exit
    }
    local vtyp `s(typ)'
    local varn `s(varn)'
    local 0 `"`s(rest)'"'

    syntax [if] [in] [, `myopts']
    local type "`xb'`residuals'"

    if "`type'" == "" {
        di as text "(option xb assumed; fitted values)"
        local type "xb"
    }

    marksample touse

    capture _xt, trequired
    if _rc {
        di as error "_pte_evolution prediction requires the current data to be xtset."
        exit 459
    }

    local panelvar `"`e(idvar)'"'
    if "`panelvar'" == "" {
        local panelvar `"`e(id)'"'
    }
    local timevar `"`e(timevar)'"'
    if "`timevar'" == "" {
        local timevar `"`e(time)'"'
    }

    if "`panelvar'" != "" & "`r(ivar)'" != "`panelvar'" {
        di as error "_pte_evolution prediction requires xtset panel variable `panelvar'."
        exit 459
    }
    if "`timevar'" != "" & "`r(tvar)'" != "`timevar'" {
        di as error "_pte_evolution prediction requires xtset time variable `timevar'."
        exit 459
    }

    capture confirm variable omega, exact
    if _rc {
        di as error "_pte_evolution prediction requires exact variable omega."
        exit 111
    }
    capture confirm numeric variable omega
    if _rc {
        di as error "_pte_evolution prediction requires numeric variable omega."
        exit 111
    }

    local treatment `"`e(treatment)'"'
    capture confirm variable `treatment', exact
    if _rc {
        di as error "_pte_evolution prediction requires treatment variable `treatment'."
        exit 111
    }
    capture confirm numeric variable `treatment'
    if _rc {
        di as error "_pte_evolution prediction requires numeric treatment variable `treatment'."
        exit 111
    }

    quietly gen `vtyp' `varn' = 0 if `touse'

    local ebnames : colnames e(b)
    foreach term of local ebnames {
        if "`term'" == "_cons" {
            quietly replace `varn' = `varn' + _b[_cons] if `touse'
        }
        else if "`term'" == "L.omega" {
            quietly replace `varn' = `varn' + _b[L.omega] * L.omega if `touse'
        }
        else if "`term'" == "L.omega2" {
            quietly replace `varn' = `varn' + _b[L.omega2] * (L.omega)^2 if `touse'
        }
        else if "`term'" == "L.omega3" {
            quietly replace `varn' = `varn' + _b[L.omega3] * (L.omega)^3 if `touse'
        }
        else if "`term'" == "L.omega4" {
            quietly replace `varn' = `varn' + _b[L.omega4] * (L.omega)^4 if `touse'
        }
        else if "`term'" == "L.omega_tp" {
            quietly replace `varn' = `varn' + _b[L.omega_tp] * L.omega * L.`treatment' if `touse'
        }
        else if "`term'" == "L.omega2_tp" {
            quietly replace `varn' = `varn' + _b[L.omega2_tp] * ((L.omega)^2) * L.`treatment' if `touse'
        }
        else if "`term'" == "L.omega3_tp" {
            quietly replace `varn' = `varn' + _b[L.omega3_tp] * ((L.omega)^3) * L.`treatment' if `touse'
        }
        else if "`term'" == "L.omega4_tp" {
            quietly replace `varn' = `varn' + _b[L.omega4_tp] * ((L.omega)^4) * L.`treatment' if `touse'
        }
        else if "`term'" == "L.`treatment'" {
            quietly replace `varn' = `varn' + _b[L.`treatment'] * L.`treatment' if `touse'
        }
    }

    if "`type'" == "residuals" {
        quietly replace `varn' = omega - `varn' if `touse'
        label variable `varn' "Residuals"
    }
    else {
        label variable `varn' "Linear prediction"
    }
end
