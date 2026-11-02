# Prints one section of docs/curseforge.md: the text under its "## <section>" heading (the heading itself and the
# blank lines around the text left out), so each part can be pasted into its own field on CurseForge.
#   awk -v section=Description -f .github/scripts/curseforge-section.awk docs/curseforge.md
# A heading may carry a note in brackets ("## Summary (max 250 characters)"). The Description runs to the end of the
# file, because the description has ## headings of its own: it has to stay the last section. Exit status 1 when the
# section is not there.
$0 == "## " section || index($0, "## " section " (") == 1 { found = 1; on = 1; next }
on && section != "Description" && /^## / { on = 0 }
on { lines[++n] = $0 }
END {
    first = 1
    while (first <= n && lines[first] ~ /^[ \t]*$/) first++
    last = n
    while (last >= first && lines[last] ~ /^[ \t]*$/) last--
    for (i = first; i <= last; i++) print lines[i]
    if (!found) exit 1
}
