*! _pte_style_preset.ado
*! Preset style configurations for pte_graph

version 14.0
program define _pte_style_preset, rclass
    version 14.0
    args preset
    
    // paper: Paper style (default)
    if "`preset'" == "paper" {
        return local scheme "s1color"
        return local lw_mult "1.0"
        return local msize_mult "1.0"
        return local description "Paper style (default) - matches Chen, Liao & Schurter (2026)"
    }
    
    // presentation: Presentation style
    else if "`preset'" == "presentation" {
        return local scheme "s2color"
        return local lw_mult "1.5"
        return local msize_mult "1.5"
        return local description "Presentation style - thicker lines, larger markers"
    }
    
    // grayscale: Grayscale style
    else if "`preset'" == "grayscale" {
        return local scheme "s1mono"
        return local lw_mult "1.0"
        return local msize_mult "1.0"
        
        return local color_treated "gs4"
        return local color_control "gs8"
        return local color_low "gs2"
        return local color_medium "gs5"
        return local color_high "gs8"
        return local color_period0 "black"
        return local color_period1 "gs4"
        return local color_period2 "gs6"
        return local color_period3 "gs8"
        return local color_period4 "gs10"
        
        return local description "Grayscale style - for black & white printing"
    }
    
    // colorblind: Colorblind-safe style
    else if "`preset'" == "colorblind" {
        return local scheme "s1color"
        return local lw_mult "1.0"
        return local msize_mult "1.0"
        
        // Wong (2011) colorblind-safe palette
        return local color_treated `""0 114 178""'
        return local color_control `""230 159 0""'
        return local color_low `""0 114 178""'
        return local color_medium `""230 159 0""'
        return local color_high `""0 158 115""'
        return local color_period0 `""0 0 0""'
        return local color_period1 `""230 159 0""'
        return local color_period2 `""86 180 233""'
        return local color_period3 `""0 158 115""'
        return local color_period4 `""204 121 167""'
        
        return local description "Colorblind-safe style - accessible to all viewers"
    }
    
    // minimal: Minimal style
    else if "`preset'" == "minimal" {
        return local scheme "s1color"
        return local lw_mult "0.8"
        return local msize_mult "0.8"
        return local nogrid "nogrid"
        return local legend_region "region(lpattern(blank) fcolor(none))"
        
        return local description "Minimal style - clean, no grid, thin lines"
    }
    
    // Invalid preset
    else {
        di as error "pte_graph error: unknown preset '{bf:`preset'}'"
        di as error "valid presets: paper, presentation, grayscale, colorblind, minimal"
        exit 198
    }
    
end
