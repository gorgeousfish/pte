*! pte_install.do - Complete installation helper for pte package
*! Usage: do pte_install.do
*! Or: net install pte, from("https://raw.githubusercontent.com/gorgeousfish/pte/main") replace

* Set proxy for users in China (modify port as needed)
* set httpproxy on
* set httpproxyhost "127.0.0.1"
* set httpproxyport 7897

local src "https://raw.githubusercontent.com/gorgeousfish/pte/main"

display as text ""
display as text "{hline 60}"
display as text "  Installing pte: Productivity Treatment Effects"
display as text "{hline 60}"
display as text ""

* Install core package (part 1)
display as text "  [1/3] Installing core commands..."
net install pte, from("`src'") replace
display as result "        Done."

* Install internal modules (part 2)
display as text "  [2/3] Installing internal modules (part 2)..."
net install pte_more, from("`src'") replace
display as result "        Done."

* Install internal modules (part 3)
display as text "  [3/3] Installing internal modules (part 3)..."
net install pte_more2, from("`src'") replace
display as result "        Done."

display as text ""
display as text "{hline 60}"
display as result "  pte installation complete!"
display as text "  Type {cmd:help pte} to get started."
display as text "{hline 60}"
display as text ""

* Optional: install examples
display as text "  To install example files, run:"
display as text "  {cmd:net install pte_examples, from(`src') replace}"
display as text ""
