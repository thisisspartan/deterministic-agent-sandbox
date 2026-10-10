/^[[:space:]]*mount[[:space:]]/ {
   if ($0 !~ /->/) { print "BAD (no ->, path would be SOURCE): " $0; bad=1 }
   if (!match($0, /options=\([^)]*\)/)) { print "BAD (no options= — conditionals would match ANY flags): " $0; bad=1; next }
   opts = substr($0, RSTART + 9, RLENGTH - 10)
   n = split(opts, toks, "[, ]")
   for (i = 1; i <= n; i++)
     if (toks[i] == "bind") { print "BAD (bare bind token — kernel audits recursive binds as rbind): " $0; bad=1 }
} END { exit (bad ? 1 : 0) }
