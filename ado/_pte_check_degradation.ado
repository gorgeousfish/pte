*! _pte_check_degradation.ado
*! Absorbing degradation detection (rclass)
*! Pure decision function: checks if nexit == 0 => absorbing treatment

version 14.0
// _pte_check_degradation: Determine if treatment is absorbing
// Called by orchestrator _pte_main.ado after _pte_detect_treatment_type
// Returns r(absorbing), r(trt_type), r(nexit), r(nentry)

program define _pte_check_degradation, rclass
    version 14.0
    
    syntax, Nexit(integer) Nentry(integer) [Verbose]
    
    // ═══════════════════════════════════════════════════════════════
    // Core logic: absorbing iff nexit == 0
    // ═══════════════════════════════════════════════════════════════
    if `nexit' == 0 {
        return scalar absorbing = 1
        return local trt_type "absorbing"
        
        if "`verbose'" != "" {
            di as text "[debug] _pte_check_degradation: " ///
                "nexit=0 => absorbing treatment detected"
        }
    }
    else {
        return scalar absorbing = 0
        return local trt_type "non-absorbing"
        
        if "`verbose'" != "" {
            di as text "[debug] _pte_check_degradation: " ///
                "nexit=`nexit' => non-absorbing treatment"
        }
    }
    
    // Pass through counts
    return scalar nexit = `nexit'
    return scalar nentry = `nentry'
end
