*! _pte_export.ado
*! High-resolution export functionality

version 14.0
program define _pte_export, rclass
    version 14.0
    
    // DPI/WIDTH/HEIGHT use string type to distinguish "not specified" from explicit
    syntax , [EXPORT(string) SAVE(string) ///
              FORMAT(string) DPI(string) ///
              WIDTH(string) HEIGHT(string) ///
              PRESET(string)]
    
    // =========================================================
    // 1. Check graph existence (IC-E6-010.1)
    // =========================================================
    
    capture graph describe
    if _rc {
        di as error "[pte] no graph to export"
        di as error "[pte] generate a graph first using pte_graph, <type>"
        exit 198
    }
    
    // =========================================================
    // 2. Apply preset if specified (IMP-010-10)
    // =========================================================
    
    local preset_format ""
    local preset_dpi ""
    local preset_width ""
    local preset_height ""
    
    if "`preset'" != "" {
        _pte_get_preset "`preset'"
        local preset_format "`r(format)'"
        local preset_dpi "`r(dpi)'"
        local preset_width "`r(width)'"
        local preset_height "`r(height)'"
    }
    
    // =========================================================
    // 3. Resolve parameters: user > preset > default
    // =========================================================
    
    // Format resolution
    local exp_format ""
    if "`format'" != "" {
        local exp_format "`format'"
    }
    else if "`preset_format'" != "" {
        local exp_format "`preset_format'"
    }
    
    // Auto-detect format from export path extension
    if "`exp_format'" == "" & "`export'" != "" {
        _pte_detect_format "`export'"
        if "`r(format)'" != "unknown" {
            local exp_format "`r(format)'"
        }
    }
    
    // Default format: png
    if "`exp_format'" == "" {
        local exp_format "png"
    }
    
    // Determine format type (vector vs bitmap)
    local exp_type "bitmap"
    if inlist("`exp_format'", "eps", "pdf", "svg", "ps") {
        local exp_type "vector"
    }
    
    // DPI resolution: user > preset > default (300)
    local exp_dpi "300"
    if "`dpi'" != "" {
        local exp_dpi "`dpi'"
    }
    else if "`preset_dpi'" != "" {
        local exp_dpi "`preset_dpi'"
    }
    
    // Validate DPI range (72-1200)
    if "`exp_type'" == "bitmap" {
        capture confirm integer number `exp_dpi'
        if _rc {
            di as error "[pte] invalid DPI value: `exp_dpi'"
            di as error "[pte] DPI must be an integer between 72 and 1200"
            exit 198
        }
        if `exp_dpi' < 72 | `exp_dpi' > 1200 {
            di as error "[pte] DPI out of range: `exp_dpi'"
            di as error "[pte] DPI must be between 72 and 1200"
            exit 198
        }
    }
    
    // Warn if DPI specified for vector format
    if "`exp_type'" == "vector" & "`dpi'" != "" {
        di as text "[pte] note: DPI is ignored for vector format (`exp_format')"
    }
    
    // =========================================================
    // 4. Size resolution (IMP-010-09)
    // =========================================================
    
    // Width resolution: user > preset > default (1200)
    local exp_width "1200"
    if "`width'" != "" {
        local exp_width "`width'"
    }
    else if "`preset_width'" != "" {
        local exp_width "`preset_width'"
    }
    
    // Height resolution: user > preset > default (900)
    local exp_height "900"
    if "`height'" != "" {
        local exp_height "`height'"
    }
    else if "`preset_height'" != "" {
        local exp_height "`preset_height'"
    }
    
    // Aspect ratio 4:3 when only one dimension specified
    if "`width'" != "" & "`height'" == "" & "`preset_height'" == "" {
        local exp_height = round(`exp_width' * 3 / 4)
    }
    else if "`height'" != "" & "`width'" == "" & "`preset_width'" == "" {
        local exp_width = round(`exp_height' * 4 / 3)
    }
    
    // Validate size range (100-10000)
    if "`exp_type'" == "bitmap" {
        foreach dim in exp_width exp_height {
            capture confirm integer number ``dim''
            if _rc {
                di as error "[pte] invalid size value: ``dim''"
                exit 198
            }
            if ``dim'' < 100 | ``dim'' > 10000 {
                di as error "[pte] size out of range: ``dim''"
                di as error "[pte] size must be between 100 and 10000 pixels"
                exit 198
            }
        }
    }
    
    // =========================================================
    // 5. Path handling (IMP-010-11)
    // =========================================================
    
    // Process export path
    if "`export'" != "" {
        // Add extension if missing
        _pte_detect_format "`export'"
        if "`r(format)'" == "unknown" {
            local export "`export'.`exp_format'"
        }
        
        // Extract directory and create if needed
        // Handle both / and \ separators
        local dir ""
        local has_sep = 0
        
        // Check for last separator
        local flen = length("`export'")
        forvalues i = `flen'(-1)1 {
            local ch = substr("`export'", `i', 1)
            if "`ch'" == "/" | "`ch'" == "\" {
                local dir = substr("`export'", 1, `i')
                local has_sep = 1
                continue, break
            }
        }
        
        // Create directory if it doesn't exist
        if `has_sep' & "`dir'" != "" {
            capture mkdir "`dir'"
            // Ignore error if directory already exists
        }
    }
    
    // Process save path (.gph)
    if "`save'" != "" {
        // Add .gph extension if missing
        _pte_detect_format "`save'"
        if "`r(format)'" != "gph" {
            local save "`save'.gph"
        }
    }
    
    // =========================================================
    // 6. Execute export (IMP-010-05, IMP-010-06)
    // =========================================================
    
    // Save .gph file (IMP-010-07)
    if "`save'" != "" {
        graph save "`save'", replace
        di as text "[pte] graph saved: `save'"
        return local save_path "`save'"
    }
    
    // Export to image format
    if "`export'" != "" {
        
        if "`exp_type'" == "vector" {
            // Vector format export (EPS/PDF/SVG) - no size params
            graph export "`export'", as(`exp_format') replace
            di as text "[pte] exported (`exp_format', vector): `export'"
        }
        else {
            // Bitmap format export (PNG/TIFF) - with size params
            graph export "`export'", as(`exp_format') ///
                width(`exp_width') height(`exp_height') replace
            di as text "[pte] exported (`exp_format', `exp_width'x`exp_height', `exp_dpi'dpi): `export'"
        }
        
        // Return values (IMP-010-12)
        return local export_path "`export'"
        return local export_format "`exp_format'"
        return local export_type "`exp_type'"
        
        if "`exp_type'" == "bitmap" {
            return local width "`exp_width'"
            return local height "`exp_height'"
            return local dpi "`exp_dpi'"
        }
    }
    
    // Nothing to do
    if "`export'" == "" & "`save'" == "" {
        di as text "[pte] note: no export or save path specified"
    }
    
end
