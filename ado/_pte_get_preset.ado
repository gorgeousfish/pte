*! _pte_get_preset.ado
*! Journal/general export preset configurations

version 14.0
program define _pte_get_preset, rclass
    version 14.0
    args preset
    
    local preset = lower("`preset'")
    
    // =========================================
    // Academic journal presets - vector formats
    // =========================================
    
    if inlist("`preset'", "joe", "aer", "qje", "ecma", "econometrica") {
        local format "eps"
        local dpi ""
        local width ""
        local height ""
    }
    else if inlist("`preset'", "restud", "res") {
        local format "eps"
        local dpi ""
        local width ""
        local height ""
    }
    
    // =========================================
    // Academic journal presets - high resolution
    // =========================================
    
    else if "`preset'" == "jasa" {
        local format "pdf"
        local dpi "600"
        local width "2400"
        local height "1800"
    }
    else if "`preset'" == "jss" {
        local format "pdf"
        local dpi "300"
        local width "1200"
        local height "900"
    }
    
    // =========================================
    // General presets
    // =========================================
    
    else if "`preset'" == "print" {
        local format "tif"
        local dpi "300"
        local width "2100"
        local height "1575"
    }
    else if "`preset'" == "print_high" | "`preset'" == "printhigh" {
        local format "tif"
        local dpi "600"
        local width "4200"
        local height "3150"
    }
    else if "`preset'" == "web" {
        local format "png"
        local dpi "150"
        local width "800"
        local height "600"
    }
    else if "`preset'" == "presentation" | "`preset'" == "ppt" {
        local format "png"
        local dpi "150"
        local width "1920"
        local height "1080"
    }
    else if "`preset'" == "retina" {
        local format "png"
        local dpi "300"
        local width "2400"
        local height "1800"
    }
    
    // =========================================
    // Unknown preset
    // =========================================
    
    else {
        di as error "[pte] unknown preset: `preset'"
        di as error "[pte] available presets:"
        di as error "[pte]   journals: joe, aer, qje, jasa, jss, ecma, restud"
        di as error "[pte]   general:  print, print_high, web, presentation, retina"
        exit 198
    }
    
    // Return results
    return local format "`format'"
    return local dpi "`dpi'"
    return local width "`width'"
    return local height "`height'"
end
