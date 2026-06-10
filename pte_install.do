*! pte_install.do — One-command installer for pte package
*! Usage: do "https://raw.githubusercontent.com/gorgeousfish/pte/main/pte_install.do"
*!
*! For users in China, set proxy first:
*!   set httpproxy on
*!   set httpproxyhost "127.0.0.1"
*!   set httpproxyport YOUR_PORT
*!   do "https://raw.githubusercontent.com/gorgeousfish/pte/main/pte_install.do"

version 14.0

local src "https://raw.githubusercontent.com/gorgeousfish/pte/main"

display ""
display as text "{hline 60}"
display as text "  Installing pte: Productivity Treatment Effects"
display as text "  Source: `src'"
display as text "{hline 60}"
display ""

* Uninstall previous versions
capture net uninstall pte
capture net uninstall pte_more
capture net uninstall pte_more2

* --- Helper: install with retry (GitHub CDN may rate-limit) ---
capture program drop _pte_net_install
program define _pte_net_install
    args pkgname src maxretry
    if "`maxretry'" == "" local maxretry 3
    local attempt 1
    local success 0
    while `attempt' <= `maxretry' & `success' == 0 {
        capture net install `pkgname', from("`src'") replace
        if _rc == 0 {
            local success 1
        }
        else {
            if `attempt' < `maxretry' {
                display as text "        Retry `attempt'/`maxretry' (waiting 10s)..."
                sleep 10000
            }
            local attempt = `attempt' + 1
        }
    }
    if `success' == 0 {
        display as error "  FAILED: Could not install `pkgname' after `maxretry' attempts (rc=" _rc ")"
        display as error "  Check your internet connection or proxy settings."
        exit _rc
    }
end

* Install core package (part 1/3)
display as text "  [1/3] Installing pte (core commands)..."
_pte_net_install pte `src' 3
display as result "        Done."

* Pause to avoid GitHub rate limiting
sleep 10000

* Install internal modules (part 2/3)
display as text "  [2/3] Installing pte_more (internal modules)..."
_pte_net_install pte_more `src' 3
display as result "        Done."

* Pause to avoid GitHub rate limiting
sleep 10000

* Install internal modules (part 3/3)
display as text "  [3/3] Installing pte_more2 (internal modules)..."
_pte_net_install pte_more2 `src' 3
display as result "        Done."

* Index Mata library
display as text "  [*] Indexing Mata library..."
mata: mata mlib index
display as result "        Done."

* Clean up helper
capture program drop _pte_net_install

display ""
display as text "{hline 60}"
display as result "  pte installation complete!"
display as text ""
display as text "  Quick start:"
display as text "    {cmd:pte_example, clear}"
display as text "    {cmd:xtset firm year}"
display as text `"    {cmd:pte lny, free(lnl) state(lnk) proxy(lnm) treatment(D) pfunc(cd)}"'
display as text ""
display as text "  Help:  {cmd:help pte}"
display as text "{hline 60}"
display ""
