*! _pte_format_time.ado

version 14.0
capture program drop _pte_format_time
program define _pte_format_time, sclass
    version 14.0
    
    args seconds
    local total_tenths = round(`seconds' * 10, 1)
    local total_seconds = `total_tenths' / 10
    
    if `seconds' < 1 {
        sreturn local formatted "<1s"
    }
    else if `total_seconds' >= 3600 {
        local h = floor(`total_seconds' / 3600)
        local m = floor(mod(`total_seconds', 3600) / 60)
        sreturn local formatted "`h'h `m'm"
    }
    else if `total_seconds' >= 60 {
        local m = floor(`total_tenths' / 600)
        local s_tenths = mod(`total_tenths', 600)
        local s = `s_tenths' / 10
        if `s' >= 60 {
            local m = `m' + 1
            local s = 0
        }
        if `m' >= 60 {
            local h = floor(`m' / 60)
            local m = mod(`m', 60)
            sreturn local formatted "`h'h `m'm"
            exit
        }
        local seconds_str : display %9.1f `s'
        local seconds_str = strtrim("`seconds_str'")
        if strlen("`seconds_str'") >= 2 {
            if substr("`seconds_str'", strlen("`seconds_str'") - 1, 2) == ".0" {
                local seconds_str = substr("`seconds_str'", 1, strlen("`seconds_str'") - 2)
            }
        }
        sreturn local formatted "`m'm `seconds_str's"
    }
    else {
        local seconds_str : display %9.1f `total_seconds'
        local seconds_str = strtrim("`seconds_str'")
        if strlen("`seconds_str'") >= 2 {
            if substr("`seconds_str'", strlen("`seconds_str'") - 1, 2) == ".0" {
                local seconds_str = substr("`seconds_str'", 1, strlen("`seconds_str'") - 2)
            }
        }
        sreturn local formatted "`seconds_str's"
    }
end
