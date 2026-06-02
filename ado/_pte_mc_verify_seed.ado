*! _pte_mc_verify_seed.ado
*! Seed verification utility for pte Monte Carlo simulations
*! Verifies that the same seed produces identical random number sequences

version 14.0
capture program drop _pte_mc_verify_seed
program define _pte_mc_verify_seed, rclass
    version 14.0
    syntax, seed(integer) [verbose]

    // =========================================================================
    // 0. Initialize
    // =========================================================================
    local n_test = 10
    local verified = 0

    if "`verbose'" != "" {
        di as text ""
        di as text "Seed verification: testing determinism for seed = " ///
            as result `seed'
        di as text "  Generating `n_test' random draws per pass..."
    }

    // =========================================================================
    // 1. First pass: set seed and generate random numbers into Mata vector
    // =========================================================================
    set seed `seed'

    tempname vec1 vec2
    matrix `vec1' = J(1, `n_test', 0)
    forvalues i = 1/`n_test' {
        matrix `vec1'[1, `i'] = rnormal()
    }

    if "`verbose'" != "" {
        di as text "  Pass 1 complete."
    }

    // =========================================================================
    // 2. Second pass: reset same seed and generate again
    // =========================================================================
    set seed `seed'

    matrix `vec2' = J(1, `n_test', 0)
    forvalues i = 1/`n_test' {
        matrix `vec2'[1, `i'] = rnormal()
    }

    if "`verbose'" != "" {
        di as text "  Pass 2 complete."
    }

    // =========================================================================
    // 3. Compare the two sequences element by element
    // =========================================================================
    local verified = 1
    forvalues i = 1/`n_test' {
        if `vec1'[1, `i'] != `vec2'[1, `i'] {
            local verified = 0
            if "`verbose'" != "" {
                di as error "  MISMATCH at draw `i': " ///
                    as result %18.0g `vec1'[1, `i'] ///
                    as error " vs " ///
                    as result %18.0g `vec2'[1, `i']
            }
        }
    }

    if "`verbose'" != "" {
        if `verified' {
            di as text "  All `n_test' draws matched."
        }
        else {
            di as error "  Sequences differ — seed is NOT deterministic."
        }
    }

    // =========================================================================
    // 4. Report output
    // =========================================================================
    di as text ""
    di as text "Seed verification:"
    di as text "  Seed: " as result `seed'
    di as text "  Deterministic: " as result cond(`verified', "Yes", "No")
    di as text "  Status: " as result cond(`verified', "PASS", "FAIL")

    // =========================================================================
    // 5. Return results
    // =========================================================================
    return scalar verified = `verified'
    return scalar seed = `seed'
    return scalar n_test = `n_test'

end
