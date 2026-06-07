*! _pte_detect_format.ado
*! Detect export format from file extension

version 14.0
program define _pte_detect_format, rclass
    version 14.0
    args filepath
    
    // Extract extension (handle .tiff, .jpeg 5-char extensions)
    local len = length("`filepath'")
    local ext5 = lower(substr("`filepath'", max(1, `len' - 4), .))
    local ext4 = lower(substr("`filepath'", max(1, `len' - 3), .))
    local ext3 = lower(substr("`filepath'", max(1, `len' - 2), .))
    
    // Format mapping
    local format "unknown"
    local type "unknown"
    
    // 5-char extensions first
    if "`ext5'" == ".tiff" {
        local format "tif"
        local type "bitmap"
    }
    else if "`ext5'" == ".jpeg" {
        local format "jpg"
        local type "bitmap"
    }
    // 4-char extensions
    else if "`ext4'" == ".eps" {
        local format "eps"
        local type "vector"
    }
    else if "`ext4'" == ".pdf" {
        local format "pdf"
        local type "vector"
    }
    else if "`ext4'" == ".png" {
        local format "png"
        local type "bitmap"
    }
    else if "`ext4'" == ".tif" {
        local format "tif"
        local type "bitmap"
    }
    else if "`ext4'" == ".svg" {
        local format "svg"
        local type "vector"
    }
    else if "`ext4'" == ".jpg" {
        local format "jpg"
        local type "bitmap"
    }
    else if "`ext4'" == ".gph" {
        local format "gph"
        local type "stata"
    }
    // 3-char extensions (e.g. .ps)
    else if "`ext3'" == ".ps" {
        local format "ps"
        local type "vector"
    }
    
    return local format "`format'"
    return local type "`type'"
end
