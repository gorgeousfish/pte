*! _pte_style_validate.ado
*! Style validation for pte_graph

version 14.0
program define _pte_style_validate
    version 14.0
    
    syntax , [SCHeme(string) LColor(string) LWidth(string) LPattern(string) ///
              MSymbol(string) MSize(string) Alpha(integer -1) Preset(string) ///
              Legendpos(integer -1)]
    
    // Scheme validation
    if "`scheme'" != "" {
        local current_scheme "`c(scheme)'"
        capture set scheme `scheme'
        if _rc {
            di as error "pte_graph error: invalid scheme '{bf:`scheme'}'"
            di as error "use {bf:graph query, schemes} to see available schemes"
            exit 198
        }
        quietly set scheme `current_scheme'
    }
    
    // Line width validation
    if "`lwidth'" != "" {
        local valid_lw "none vvthin vthin thin medthin medium medthick thick vthick vvthick"
        local is_keyword = 0
        foreach k of local valid_lw {
            if "`lwidth'" == "`k'" {
                local is_keyword = 1
                continue, break
            }
        }
        if !`is_keyword' {
            capture confirm number `lwidth'
            if _rc {
                di as error "pte_graph error: invalid lwidth '{bf:`lwidth'}'"
                di as error "lwidth must be positive number or keyword (thin, medium, thick, ...)"
                exit 198
            }
            if `lwidth' <= 0 {
                di as error "pte_graph error: lwidth must be positive"
                di as error "received: `lwidth'"
                exit 198
            }
        }
    }
    
    // Line pattern validation
    if "`lpattern'" != "" {
        local valid_lp "solid dash dot dash_dot shortdash longdash shortdash_dot longdash_dot blank"
        local lp_valid = 0
        foreach p of local valid_lp {
            if "`lpattern'" == "`p'" {
                local lp_valid = 1
                continue, break
            }
        }
        if !`lp_valid' {
            di as error "pte_graph error: invalid line pattern '{bf:`lpattern'}'"
            di as error "valid patterns: solid, dash, dot, dash_dot, shortdash, longdash, blank"
            exit 198
        }
    }
    
    // Marker symbol validation
    if "`msymbol'" != "" {
        local valid_ms "O Oh o oh D Dh d dh T Th t th S Sh s sh + X x p P i none"
        local ms_valid = 0
        foreach s of local valid_ms {
            if "`msymbol'" == "`s'" {
                local ms_valid = 1
                continue, break
            }
        }
        if !`ms_valid' {
            di as error "pte_graph error: invalid marker symbol '{bf:`msymbol'}'"
            di as error "valid symbols: O, Oh, T, Th, D, Dh, S, Sh, X, +, p, i, none"
            exit 198
        }
    }
    
    // Marker size validation
    if "`msize'" != "" {
        local valid_ms_keys "vtiny tiny vsmall small medsmall medium medlarge large vlarge huge vhuge"
        local is_keyword = 0
        foreach k of local valid_ms_keys {
            if "`msize'" == "`k'" {
                local is_keyword = 1
                continue, break
            }
        }
        if !`is_keyword' {
            capture confirm number `msize'
            if _rc {
                di as error "pte_graph error: invalid msize '{bf:`msize'}'"
                di as error "msize must be positive number or keyword (tiny, small, medium, large, ...)"
                exit 198
            }
            if `msize' <= 0 {
                di as error "pte_graph error: msize must be positive"
                exit 198
            }
        }
    }
    
    // Alpha validation
    if `alpha' != -1 {
        if `alpha' < 0 | `alpha' > 100 {
            di as error "pte_graph error: alpha must be integer between 0 and 100"
            di as error "received: `alpha'"
            exit 198
        }
    }
    
    // Preset validation
    if "`preset'" != "" {
        local valid_presets "paper presentation grayscale colorblind minimal"
        local preset_valid = 0
        foreach p of local valid_presets {
            if "`preset'" == "`p'" {
                local preset_valid = 1
                continue, break
            }
        }
        if !`preset_valid' {
            di as error "pte_graph error: invalid preset '{bf:`preset'}'"
            di as error "valid presets: paper, presentation, grayscale, colorblind, minimal"
            exit 198
        }
    }
    
    // Legend position validation
    if `legendpos' != -1 {
        if `legendpos' < 0 | `legendpos' > 12 {
            di as error "pte_graph error: legendpos must be integer between 0 and 12"
            di as error "received: `legendpos'"
            di as error "(0=center, 1-12=clock positions)"
            exit 198
        }
    }
    
end
