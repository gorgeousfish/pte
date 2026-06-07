* Test: Install pte package via GitHub mirror
* Date: 2026-06-07

clear all
set more off

display _dup(70) "="
display "Test: Install pte package via GitHub"
display _dup(70) "="

* First uninstall any existing pte installation
capture net uninstall pte

* ============================================================
* Method A: Direct access (no proxy)
* ============================================================
display ""
display _dup(70) "-"
display "Method A: Direct access to raw.githubusercontent.com"
display _dup(70) "-"

set httpproxy off
capture noisily net install pte, from("https://raw.githubusercontent.com/gorgeousfish/pte/main") replace

if _rc == 0 {
    display ""
    display ">>> SUCCESS: Direct install worked!"
    display ""
    which pte
    exit
}
else {
    display ""
    display ">>> FAILED with rc = " _rc
    display ">>> Trying Method B..."
    display ""
}

* ============================================================
* Method B: Via ghfast.top mirror (no proxy needed)
* ============================================================
display _dup(70) "-"
display "Method B: ghfast.top mirror"
display _dup(70) "-"

set httpproxy off
capture noisily net install pte, from("https://ghfast.top/https://raw.githubusercontent.com/gorgeousfish/pte/main") replace

if _rc == 0 {
    display ""
    display ">>> SUCCESS: ghfast.top mirror install worked!"
    display ""
    which pte
    exit
}
else {
    display ""
    display ">>> FAILED with rc = " _rc
    display ">>> Trying Method C..."
    display ""
}

* ============================================================
* Method C: Via gh-proxy.com mirror (no proxy needed)
* ============================================================
display _dup(70) "-"
display "Method C: gh-proxy.com mirror"
display _dup(70) "-"

set httpproxy off
capture noisily net install pte, from("https://gh-proxy.com/https://raw.githubusercontent.com/gorgeousfish/pte/main") replace

if _rc == 0 {
    display ""
    display ">>> SUCCESS: gh-proxy.com mirror install worked!"
    display ""
    which pte
    exit
}
else {
    display ""
    display ">>> FAILED with rc = " _rc
    display ">>> Trying Method D..."
    display ""
}

* ============================================================
* Method D: Via Stata HTTP proxy to raw.githubusercontent.com
* ============================================================
display _dup(70) "-"
display "Method D: Stata HTTP proxy (127.0.0.1:7897)"
display _dup(70) "-"

set httpproxy on
set httpproxyhost "127.0.0.1"
set httpproxyport 7897
set httpproxyauth off
capture noisily net install pte, from("https://raw.githubusercontent.com/gorgeousfish/pte/main") replace

if _rc == 0 {
    display ""
    display ">>> SUCCESS: Proxy install worked!"
    display ""
    which pte
    exit
}
else {
    display ""
    display ">>> FAILED with rc = " _rc
    display ""
    display "ALL METHODS FAILED"
}

display _dup(70) "="
display "Test complete"
display _dup(70) "="
