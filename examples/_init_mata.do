version 14.0
clear all
set more off
args repo_root
local root "`repo_root'"
quietly adopath + "`root'/ado"
mata: mata mlib index
local func "GMM_CLK"
capture mata: mata which `func'()
display "rc = " _rc

