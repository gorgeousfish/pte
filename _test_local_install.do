version 14.0
display "Stata version: " c(stata_version)
display "Testing local net install..."
capture net uninstall pte
net install pte, from("/Users/cxy/Desktop/2026project/pte/pte-stata") replace
if _rc == 0 {
    display "SUCCESS: local install works!"
    display "The issue is network/proxy, not file size."
}
else {
    display "FAILED with rc = " _rc
    display "Error is genuinely about pkg file size limit."
}
