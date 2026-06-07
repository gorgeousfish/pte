*! _pte_treatdep_interact.ado
*! This module generates treatment interaction terms for treatment-dependent
*! production function estimation. It creates lnl_tp = lnl × D and lnk_tp = lnk × D
*! for use with endopolyprodest.

version 14.0
capture program drop _pte_treatdep_interact
program define _pte_treatdep_interact, rclass
    version 14.0
    
    // ═══════════════════════════════════════════════════════════════════════
    // Syntax parsing
    // ═══════════════════════════════════════════════════════════════════════
    syntax, FREE(name) STATE(name) TREATMENT(name) ///
        [PFUNC(string) SUFFIX(string) NOCLEAN]
    
    // ═══════════════════════════════════════════════════════════════════════
    // Default values
    // ═══════════════════════════════════════════════════════════════════════
    if "`pfunc'" == "" {
        local pfunc "cd"
    }
    if "`suffix'" == "" {
        local suffix "tp"
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Input validation
    // ═══════════════════════════════════════════════════════════════════════
    
    // Preserve the literal option tokens until the exact-name checks.
    // Using syntax varname here would silently expand lnl -> lnl_shadow
    // before the helper can enforce that treatment-dependent interactions are
    // built from the exact realized l_t, k_t, and D_t state variables.

    // Validate input variables exist exactly
    foreach var in `free' `state' `treatment' {
        capture confirm variable `var', exact
        if _rc {
            di as error "Error: Variable `var' not found"
            exit 111
        }
    }
    
    // Validate variables are numeric
    foreach var in `free' `state' `treatment' {
        capture confirm numeric variable `var'
        if _rc {
            di as error "Error: Variable `var' must be numeric"
            exit 109
        }
    }
    
    // Validate treatment is binary (0/1)
    quietly {
        count if !inlist(`treatment', 0, 1, .)
        if r(N) > 0 {
            noisily di as error "Error: Treatment variable must be binary (0/1)"
            noisily di as error "Found " r(N) " non-binary values in `treatment'"
            exit 198
        }
    }
    
    // Validate treatment is not all missing
    quietly {
        count if !missing(`treatment')
        if r(N) == 0 {
            noisily di as error "Error: Treatment variable is all missing"
            exit 416
        }
    }
    
    // Validate pfunc parameter
    if !inlist("`pfunc'", "cd", "translog") {
        di as error "Error: pfunc must be 'cd' or 'translog'"
        exit 198
    }
    
    // Validate suffix is a valid Stata name component
    capture confirm name `free'_`suffix'
    if _rc {
        di as error "Error: suffix '`suffix'' creates invalid variable name"
        exit 198
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Variable cleanup or conflict check
    // ═══════════════════════════════════════════════════════════════════════
    local free_interact "`free'_`suffix'"
    local state_interact "`state'_`suffix'"
    
    if "`noclean'" == "" {
        // Clean mode: drop existing variables
        capture drop `free_interact'
        capture drop `state_interact'
    }
    else {
        // No-clean mode: error if variables exist
        capture confirm variable `free_interact'
        if _rc == 0 {
            di as error "Error: Variable `free_interact' already exists (use without noclean to overwrite)"
            exit 110
        }
        capture confirm variable `state_interact'
        if _rc == 0 {
            di as error "Error: Variable `state_interact' already exists (use without noclean to overwrite)"
            exit 110
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Generate interaction terms
    // Paper formula: lnl_tp = ln(L) × D, lnk_tp = ln(K) × D
    // ═══════════════════════════════════════════════════════════════════════
    
    // Generate labor interaction: lnl_tp = lnl × D
    quietly gen double `free_interact' = `free' * `treatment'
    label variable `free_interact' "Log labor × Treatment (`free' × `treatment')"
    
    // Generate capital interaction: lnk_tp = lnk × D
    quietly gen double `state_interact' = `state' * `treatment'
    label variable `state_interact' "Log capital × Treatment (`state' × `treatment')"
    
    // ═══════════════════════════════════════════════════════════════════════
    // Construct parameter lists for endopolyprodest
    // ═══════════════════════════════════════════════════════════════════════
    local free_vars "`free' `free_interact'"
    local state_vars "`state' `state_interact'"
    local interact_vars "`free_interact' `state_interact'"
    local n_interact = 2
    
    // ═══════════════════════════════════════════════════════════════════════
    // Statistics
    // ═══════════════════════════════════════════════════════════════════════
    quietly {
        count if `treatment' == 0 & !missing(`free')
        local n_untreated = r(N)
        count if `treatment' == 1 & !missing(`free')
        local n_treated = r(N)
        count if missing(`treatment') | missing(`free')
        local n_missing = r(N)
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // Display output
    // ═══════════════════════════════════════════════════════════════════════
    di as text ""
    di as text "{hline 70}"
    di as text "Treatment Interaction Generation"
    di as text "{hline 70}"
    di as text "  Production function:     " as result "`pfunc'"
    di as text "  Treatment variable:      " as result "`treatment'"
    di as text "  Interaction suffix:      " as result "_`suffix'"
    di as text "  Generated variables:     " as result "`n_interact'"
    di as text "    - " as result "`free_interact'" as text " = `free' × `treatment'"
    di as text "    - " as result "`state_interact'" as text " = `state' × `treatment'"
    di as text "{hline 70}"
    di as text "  Observations:"
    di as text "    Untreated (D=0):       " as result %10.0fc `n_untreated'
    di as text "    Treated (D=1):         " as result %10.0fc `n_treated'
    di as text "    Missing:               " as result %10.0fc `n_missing'
    di as text "{hline 70}"
    di as text "  Parameter lists for endopolyprodest:"
    di as text "    free():                " as result "`free_vars'"
    di as text "    state():               " as result "`state_vars'"
    di as text "{hline 70}"
    di as text ""
    
    // ═══════════════════════════════════════════════════════════════════════
    // Return values
    // ═══════════════════════════════════════════════════════════════════════
    return local free_vars "`free_vars'"
    return local state_vars "`state_vars'"
    return local interact_vars "`interact_vars'"
    return scalar n_interact = `n_interact'
    return scalar n_free = wordcount("`free_vars'")
    return scalar n_state = wordcount("`state_vars'")
    return local treatment_var "`treatment'"
    return local pfunc "`pfunc'"
    return local suffix "`suffix'"
    return scalar n_untreated = `n_untreated'
    return scalar n_treated = `n_treated'
    
end
