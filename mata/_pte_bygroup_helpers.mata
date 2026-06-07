*! version 1.0.0  13mar2026
*! Mata helper functions for _pte_bygroup
*! Extracted from inline mata: { } blocks that trigger r(3000) in ado execution.

capture mata: mata drop _pte_bygroup_boot_se()
mata:
void _pte_bygroup_boot_se(string scalar boot_name, string scalar se_name)
{
    real matrix boot_mat, se_out
    real scalar nc, j
    real colvector col_data, valid

    boot_mat = st_matrix(boot_name)
    nc = cols(boot_mat)
    se_out = J(1, nc, .)

    for (j = 1; j <= nc; j++) {
        col_data = boot_mat[., j]
        valid = select(col_data, col_data :!= .)
        if (rows(valid) > 1) {
            se_out[1, j] = sqrt(variance(valid))
        }
    }

    st_matrix(se_name, se_out)
}
end
