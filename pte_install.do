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

* Install core package (part 1/3)
display as text "  [1/3] Installing pte (core commands)..."
capture net install pte, from("`src'") replace
if _rc {
    display as error "  FAILED: Could not install pte (rc=" _rc ")"
    display as error "  Check your internet connection or proxy settings."
    exit _rc
}
display as result "        Done."

* Install internal modules (part 2/3)
display as text "  [2/3] Installing pte_more (internal modules)..."
capture net install pte_more, from("`src'") replace
if _rc {
    display as error "  FAILED: Could not install pte_more (rc=" _rc ")"
    exit _rc
}
display as result "        Done."

* Install internal modules (part 3/3)
display as text "  [3/3] Installing pte_more2 (internal modules)..."
capture net install pte_more2, from("`src'") replace
if _rc {
    display as error "  FAILED: Could not install pte_more2 (rc=" _rc ")"
    exit _rc
}
display as result "        Done."

* Index Mata library
display as text "  [*] Indexing Mata library..."
mata: mata mlib index
display as result "        Done."

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
