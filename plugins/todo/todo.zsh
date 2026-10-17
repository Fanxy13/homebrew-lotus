# To-do – a plugin for Lotus (plugin.conf). The list is a text file in its own data folder, one to-do per line.
#   lotus todo                    the open to-dos
#   lotus todo add <text>         a new one
#   lotus todo done <number>      tick one off
#   lotus todo clear              tick off all of them
setopt extendedglob
list=${LOTUS_PLUGIN_DATA:?Lotus starts this}/todo.txt
k=$'\e['${LOTUS_COLOR_KEY:-38;5;150}m d=$'\e['${LOTUS_COLOR_DIM:-38;5;245}m x=$'\e[0m'
[[ -t 1 ]] || k= d= x=
[[ -e $list ]] || : >| $list
todos=("${(@f)$(<$list)}")
todos=(${todos:#[[:space:]]#})

word=${1:-list}
(( $# )) && shift
case $word in
  add)
    text=${*:-$LOTUS_ARG_TEXT}
    text=${${text//[[:cntrl:]]/ }## #}
    [[ -n $text ]] || { print -r -- "What is there to do? lotus todo add <text>"; exit 2 }
    print -r -- $text >> $list
    print -r -- "Added: $text ($(( ${#todos} + 1 )) open)" ;;
  list|ls|'')
    (( ${#todos} )) || { print -r -- "Nothing to do."; exit 0 }
    i=0
    for t in $todos; do (( i++ )); print -r -- "  $k$i$x  $t"; done
    [[ -t 1 ]] && print -r -- "  ${d}lotus todo done <number> ticks one off$x" ;;
  done|tick)
    n=${1:-$LOTUS_ARG_NUMBER}
    [[ $n == <1-> ]] && (( n <= ${#todos} )) || { print -r -- "There is no to-do $n – lotus todo lists them."; exit 2 }
    t=$todos[n]
    todos[n]=()
    print -rl -- $todos >| $list
    print -r -- "Done: $t (${#todos} open)" ;;
  clear)
    : >| $list
    print -r -- "All done." ;;
  count)
    (( ${#todos} )) && print -r -- "${#todos} open – lotus todo" ;;
  *)
    print -r -- "lotus todo [add <text> | done <number> | list | clear]"
    exit 2 ;;
esac
