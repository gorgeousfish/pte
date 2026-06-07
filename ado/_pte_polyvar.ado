*! _pte_polyvar.ado
*! Build the stage-1 polynomial basis used to approximate Phi(k,l,m),
*! including the mixed lag instrument required by the translog moments.

version 14.0
capture program drop _pte_polyvar
program define _pte_polyvar, rclass
    version 14.0

    // The interface names map to the economic roles used downstream:
    // free = labor, proxy = materials, state = capital.
    syntax, FREE(name) PROXY(name) STATE(name) ///
        [PFUNC(string) POLY(integer 3) GENLAG NOCLEAN]

    // CD is the baseline stage-1 approximation unless translog is requested.
    if "`pfunc'" == "" {
        local pfunc "cd"
    }

    // Fail fast so callers never create a partial polynomial bundle.
    foreach var in `free' `proxy' `state' {
        capture confirm variable `var', exact
        if _rc {
            di as error "{bf:_pte_polyvar}: variable {bf:`var'} not found"
            exit 111
        }
    }

    // Every generated basis term must remain numeric and double precision.
    foreach var in `free' `proxy' `state' {
        capture confirm numeric variable `var'
        if _rc {
            di as error "{bf:_pte_polyvar}: variable {bf:`var'} is not numeric"
            exit 109
        }
    }

    // All-missing inputs would silently propagate missing values to every term.
    foreach var in `free' `proxy' `state' {
        qui count if !mi(`var')
        if r(N) == 0 {
            di as error "{bf:_pte_polyvar}: variable {bf:`var'} has all missing values"
            exit 2000
        }
    }

    // Restrict the interface to the polynomial orders supported by the paper
    // and the matching GMM moment builders.
    if !inlist(`poly', 1, 2, 3) {
        di as error "{bf:_pte_polyvar}: poly must be 1, 2, or 3 (specified: `poly')"
        exit 198
    }

    if !inlist("`pfunc'", "cd", "translog") {
        di as error "{bf:_pte_polyvar}: pfunc must be 'cd' or 'translog' (specified: `pfunc')"
        exit 198
    }

    // Lag generation relies on the active panel declaration because the
    // instrument set uses time ordering, not observation ordering.
    if "`genlag'" != "" {
        capture _xt, trequired
        if _rc {
            di as error "{bf:_pte_polyvar}: data not xtset"
            di as error "genlag option requires panel data structure."
            di as error "Please run: xtset panelvar timevar"
            exit 459
        }
    }

    // The default behavior refreshes the full generated bundle so callers do
    // not accidentally mix stale basis terms with a new specification.
    if "`noclean'" == "" {
        // Drop term-by-term so a partially existing bundle never aborts cleanup.
        foreach _v in l1 m1 k1 l2 m2 k2 l3 m3 k3 ///
            l1m1 l1k1 m1k1 l1m2 l1k2 m1k2 m1l2 k1l2 k1m2 k1l1m1 {
            cap drop `_v'
        }

        // Keep lag cleanup aligned with the requested feature set.
        if "`genlag'" != "" {
            foreach _v in `free'_lag `proxy'_lag `state'_lag ///
                l2_lag k2_lag l1k_lag {
                cap drop `_v'
            }
        }
    }

    // The first-order aliases give later stages stable names regardless of the
    // original variable names chosen by the user.
    qui gen double l1 = `free'
    qui gen double m1 = `proxy'
    qui gen double k1 = `state'
    local polyvars "l1 m1 k1"

    label variable l1 "Log labor (first order)"
    label variable m1 "Log materials (first order)"
    label variable k1 "Log capital (first order)"

    // Quadratic terms match the second-order basis used by both the stage-1
    // proxy regression and the translog moment matrices.
    if `poly' >= 2 {
        qui gen double l2 = `free'^2
        qui gen double m2 = `proxy'^2
        qui gen double k2 = `state'^2
        local polyvars "`polyvars' l2 m2 k2"

        label variable l2 "Log labor squared"
        label variable m2 "Log materials squared"
        label variable k2 "Log capital squared"

        // Cross products stay explicit because later code selects subsets by name.
        qui gen double l1m1 = `free' * `proxy'
        qui gen double l1k1 = `free' * `state'
        qui gen double m1k1 = `proxy' * `state'
        local polyvars "`polyvars' l1m1 l1k1 m1k1"

        label variable l1m1 "Log labor × Log materials"
        label variable l1k1 "Log labor × Log capital"
        label variable m1k1 "Log materials × Log capital"
    }

    // The cubic basis is generated for both CD and translog requests so the
    // staging layer can decide which terms enter each regression.
    if `poly' == 3 {
        qui gen double l3 = `free'^3
        qui gen double m3 = `proxy'^3
        qui gen double k3 = `state'^3
        local polyvars "`polyvars' l3 m3 k3"

        label variable l3 "Log labor cubed"
        label variable m3 "Log materials cubed"
        label variable k3 "Log capital cubed"

        // These terms mirror the DO-file polynomial expansion exactly.
        qui gen double l1m2 = `free' * `proxy'^2
        qui gen double l1k2 = `free' * `state'^2
        qui gen double m1k2 = `proxy' * `state'^2

        label variable l1m2 "Log labor × Log materials²"
        label variable l1k2 "Log labor × Log capital²"
        label variable m1k2 "Log materials × Log capital²"

        qui gen double m1l2 = `proxy' * `free'^2
        qui gen double k1l2 = `state' * `free'^2
        qui gen double k1m2 = `state' * `proxy'^2

        label variable m1l2 "Log materials × Log labor²"
        label variable k1l2 "Log capital × Log labor²"
        label variable k1m2 "Log capital × Log materials²"

        qui gen double k1l1m1 = `state' * `free' * `proxy'

        label variable k1l1m1 "Log capital × Log labor × Log materials"

        local polyvars "`polyvars' l1m2 l1k2 m1k2 m1l2 k1l2 k1m2 k1l1m1"
    }

    // The lag bundle is only needed for panels and must stay synchronized with
    // the chosen polynomial order because the instrument list changes with poly.
    local lagvars ""
    local n_lagvars 0

    if "`genlag'" != "" {
        // Raw lagged inputs are shared by CD and translog moment conditions.
        qui gen double `free'_lag = L.`free'
        qui gen double `proxy'_lag = L.`proxy'
        qui gen double `state'_lag = L.`state'
        local lagvars "`free'_lag `proxy'_lag `state'_lag"
        local n_lagvars 3

        label variable `free'_lag "Lagged `free'"
        label variable `proxy'_lag "Lagged `proxy'"
        label variable `state'_lag "Lagged `state'"

        if `poly' >= 2 {
            qui gen double l2_lag = L.l2
            qui gen double k2_lag = L.k2

            label variable l2_lag "Lagged log labor squared"
            label variable k2_lag "Lagged log capital squared"

            // This mixed lag follows Assumption 2.2 in the paper and the DO
            // files: labor is lagged, but capital enters at time t because it
            // is predetermined at t-1. Using L.l1k1 would shift capital twice
            // and would no longer reproduce the intended translog instrument.
            qui gen double l1k_lag = L.`free' * `state'

            label variable l1k_lag "Lagged log labor × Current log capital"

            local lagvars "`lagvars' l2_lag k2_lag l1k_lag"
            local n_lagvars 6
        }
    }

    // Expose bundle sizes so callers can assert the expected basis dimension.
    local n_polyvars : word count `polyvars'

    // The summary is informational only; the canonical contract is returned in r().
    di as text ""
    di as text "{hline 60}"
    di as text "Polynomial Variable Generation"
    di as text "{hline 60}"
    di as text _col(3) "Production function:" _col(40) as result "`pfunc'"
    di as text _col(3) "Polynomial degree:" _col(40) as result `poly'
    di as text _col(3) "Polynomial variables:" _col(40) as result `n_polyvars'
    if "`genlag'" != "" {
        di as text _col(3) "Lag variables:" _col(40) as result `n_lagvars'
    }
    di as text "{hline 60}"
    di as text ""

    // Return both names and counts because downstream code checks the bundle
    // shape before building stage-1 regressions and GMM matrices.
    return local polyvars "`polyvars'"
    return scalar n_polyvars = `n_polyvars'
    return local pfunc "`pfunc'"
    return scalar poly = `poly'

    if "`genlag'" != "" {
        return local lagvars "`lagvars'"
        return scalar n_lagvars = `n_lagvars'
    }

end
