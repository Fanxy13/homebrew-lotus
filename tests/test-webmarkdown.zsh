# The web chat's Markdown (lib/ai/web/app.js): HTML that models write into it – <br> in a table cell, <b>,
# &nbsp; – is shown the way it is meant; nothing that could run gets through, and code stays as it is.
# Needs Node.js to run the page's own code; without it the checks are skipped.
if ! (( $+commands[node] )); then
  print -r -- "  - needs Node.js – skipped"
  return 0
fi
md() {   # <markdown> → the HTML the page makes of it
  node -e '
    const src = require("fs").readFileSync(process.argv[1], "utf8");
    eval(src.slice(src.indexOf("const esc ="), src.indexOf("async function copyText")));
    process.stdout.write(md(process.argv[2]));' $LOTUS_ROOT/lib/ai/web/app.js "$1"
}
check_eq "<br> in a table cell is a line break" "$(md $'| A | B |\n|---|---|\n| 1 | x<br>y<br/>z |')" \
  '<table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>x<br>y<br>z</td></tr></tbody></table>'
check_eq "simple formatting is shown as such" "$(md 'H<sub>2</sub>O, x<sup>2</sup>, <b>bold</b>, <i>it</i>, <kbd>C</kbd>')" \
  '<p>H<sub>2</sub>O, x<sup>2</sup>, <b>bold</b>, <i>it</i>, <kbd>C</kbd></p>'
check_eq "entities become their characters" "$(md 'a&nbsp;b &amp; c &rarr; d')" '<p>a&nbsp;b &amp; c &rarr; d</p>'
check_eq "style wrappers disappear" "$(md 'a <span style="color:red">red</span> word')" '<p>a red word</p>'
check_eq "unknown tags stay as written" "$(md 'List<T> and Map<K, V>')" '<p>List&lt;T&gt; and Map&lt;K, V&gt;</p>'
check_has "code keeps its HTML" "$(md $'`<br>` and\n```html\n<p>a<br>b</p>\n```')" '<code>&lt;br&gt;</code>'
check_has "fenced code too" "$(md $'```html\n<p>a<br>b</p>\n```')" '&lt;p&gt;a&lt;br&gt;b&lt;/p&gt;'
out=$(md '<script>alert(1)</script> <img src=x onerror=alert(1)> <b onclick="x()">no</b> <a href="javascript:x">l</a>')
check "nothing that could run gets through" eval '[[ $out != *"<script"* && $out != *"<img"* && $out != *"onclick=\""* && $out != *"<a href=\"javascript"* ]]'
check_eq "<hr> on its own line is a rule" "$(md $'above\n<hr>\nbelow')" '<p>above</p><hr><p>below</p>'
