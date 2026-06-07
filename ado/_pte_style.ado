*! _pte_style.ado
*! Style management for pte_graph

version 14.0
program define _pte_style, rclass
    version 14.0
    
    syntax , TYPE(string) ///
        [PReset(string)] ///
        [SCHeme(string)] ///
        [LColor(string)] ///
        [LWidth(string)] ///
        [LPattern(string)] ///
        [MSymbol(string)] ///
        [MSize(string)] ///
        [MColor(string)] ///
        [MFColor(string)] ///
        [TItle(string)] ///
        [XTItle(string)] ///
        [YTItle(string)] ///
        [SUBtitle(string)] ///
        [NOTE(string)] ///
        [LEGend(string)] ///
        [LEGENDPos(integer -1)] ///
        [LEGENDCols(integer -1)] ///
        [LEGENDRing(integer -1)] ///
        [NOLEGend] ///
        [XLine(string)] ///
        [YLine(string)] ///
        [REFLine(real -999)] ///
        [NOREFLine] ///
        [BGColor(string)] ///
        [GRID] ///
        [NOGRID] ///
        [GRIDStyle(string)] ///
        [ALpha(integer 100)]
    
    // =========================================================================
    // Step 1: Validate user inputs
    // =========================================================================
    
    if "`scheme'" != "" | "`lwidth'" != "" | "`lpattern'" != "" | ///
       "`msymbol'" != "" | "`msize'" != "" | `alpha' != 100 | ///
       "`preset'" != "" {
        _pte_style_validate, ///
            scheme(`scheme') lwidth(`lwidth') lpattern(`lpattern') ///
            msymbol(`msymbol') msize(`msize') alpha(`alpha') ///
            preset(`preset')
    }
    
    // =========================================================================
    // Step 2: Get defaults for this graph type
    // =========================================================================
    
    _pte_style_defaults `type'
    
    local def_scheme    "`r(scheme)'"
    local def_title     `"`r(title)'"'
    local def_xtitle    `"`r(xtitle)'"'
    local def_ytitle    `"`r(ytitle)'"'
    local def_legend    `"`r(legend)'"'
    local def_refline   `"`r(refline)'"'
    local def_bgcolor   "`r(bgcolor)'"
    local def_lcolor    "`r(lcolor)'"
    local def_lwidth    "`r(lwidth)'"
    local def_lpattern  "`r(lpattern)'"
    local def_msymbol   "`r(msymbol)'"
    local def_msize     "`r(msize)'"
    local def_mcolor    "`r(mcolor)'"
    
    // Capture type-specific defaults (period/group styles)
    forvalues i = 0/4 {
        foreach prop in lc lw lp ms {
            local def_`prop'_`i' "`r(`prop'_`i')'"
        }
    }
    foreach grp in treated control nolag linear cubic low medium high {
        foreach prop in lc lw lp ms {
            local def_`prop'_`grp' "`r(`prop'_`grp')'"
        }
    }
    
    // =========================================================================
    // Step 3: Apply preset if specified
    // =========================================================================
    
    if "`preset'" != "" {
        _pte_style_preset `preset'
        
        local pre_scheme "`r(scheme)'"
        local pre_lw_mult "`r(lw_mult)'"
        local pre_msize_mult "`r(msize_mult)'"
        local pre_nogrid "`r(nogrid)'"
        
        // Preset overrides defaults (but user overrides preset)
        if "`pre_scheme'" != "" & "`scheme'" == "" {
            local scheme "`pre_scheme'"
        }
    }
    
    // =========================================================================
    // Step 4: Merge: user > preset > defaults
    // =========================================================================
    
    // Save current scheme
    local save_scheme "`c(scheme)'"
    
    // Final scheme
    local final_scheme = cond("`scheme'" != "", "`scheme'", "`def_scheme'")
    if "`final_scheme'" == "" local final_scheme "s1color"
    quietly set scheme `final_scheme'
    
    // Final text elements
    if `"`title'"' == ""    local title    `"`def_title'"'
    if `"`xtitle'"' == ""   local xtitle   `"`def_xtitle'"'
    if `"`ytitle'"' == ""   local ytitle   `"`def_ytitle'"'
    if `"`legend'"' == ""   local legend   `"`def_legend'"'
    if `"`refline'"' == "" & `refline' == -999 & "`norefline'" == "" {
        local final_refline `"`def_refline'"'
    }
    else if "`norefline'" != "" {
        local final_refline ""
    }
    else {
        local final_refline `"`refline'"'
    }
    
    // Final line styles
    local final_lcolor   = cond("`lcolor'" != "", "`lcolor'", "`def_lcolor'")
    local final_lwidth   = cond("`lwidth'" != "", "`lwidth'", "`def_lwidth'")
    local final_lpattern = cond("`lpattern'" != "", "`lpattern'", "`def_lpattern'")
    
    // Final marker styles
    local final_msymbol  = cond("`msymbol'" != "", "`msymbol'", "`def_msymbol'")
    local final_msize    = cond("`msize'" != "", "`msize'", "`def_msize'")
    local final_mcolor   = cond("`mcolor'" != "", "`mcolor'", "`def_mcolor'")
    local final_mfcolor  = cond("`mfcolor'" != "", "`mfcolor'", "")
    
    // Final background
    local final_bgcolor  = cond("`bgcolor'" != "", "`bgcolor'", "`def_bgcolor'")
    
    // Grid handling
    local final_grid "grid"
    if "`nogrid'" != "" local final_grid "nogrid"
    
    // Alpha handling (Stata 15+ only)
    local final_alpha = `alpha'
    
    // Restore scheme
    quietly set scheme `save_scheme'
    
    // =========================================================================
    // Step 5: Return all final values
    // =========================================================================
    
    return local type "`type'"
    return local scheme "`final_scheme'"
    return local save_scheme "`save_scheme'"
    
    return local title     `"`title'"'
    return local xtitle    `"`xtitle'"'
    return local ytitle    `"`ytitle'"'
    return local subtitle  `"`subtitle'"'
    return local note      `"`note'"'
    return local legend    `"`legend'"'
    return local refline   `"`final_refline'"'
    
    return local lcolor    "`final_lcolor'"
    return local lwidth    "`final_lwidth'"
    return local lpattern  "`final_lpattern'"
    return local msymbol   "`final_msymbol'"
    return local msize     "`final_msize'"
    return local mcolor    "`final_mcolor'"
    return local mfcolor   "`final_mfcolor'"
    return local bgcolor   "`final_bgcolor'"
    return local grid      "`final_grid'"
    return local gridstyle "`gridstyle'"
    return scalar alpha    = `final_alpha'
    
    if "`nolegend'" != "" {
        return local nolegend "nolegend"
    }
    if `legendpos' != -1 {
        return scalar legendpos = `legendpos'
    }
    if `legendcols' != -1 {
        return scalar legendcols = `legendcols'
    }
    if `legendring' != -1 {
        return scalar legendring = `legendring'
    }
    
    // Pass through type-specific defaults
    forvalues i = 0/4 {
        foreach prop in lc lw lp ms {
            if "`def_`prop'_`i''" != "" {
                return local `prop'_`i' "`def_`prop'_`i''"
            }
        }
    }
    foreach grp in treated control nolag linear cubic low medium high {
        foreach prop in lc lw lp ms {
            if "`def_`prop'_`grp''" != "" {
                return local `prop'_`grp' "`def_`prop'_`grp''"
            }
        }
    }
    
end
