set -u
TARGETS=(
 "0x100089108:__viewDidLoad_body"
 "0x10008b470:numberOfRowsInTableView"
 "0x10008b564:viewForTableColumn_row"
 "0x10008b78c:rowActionsForRow_edge"
 "0x10008b8b0:shouldSelectRow"
 "0x1000aab90:PasteStackTableView_initWithFrame"
 "0x100057fc8:PasteStackSnippetCell_initWithFrame"
 "0x1000137a0:PasteStackWindowController_windowDidLoad"
 "0x100013b14:PasteStackWindow_init"
 "0x10008aa1c:toggleStackDirection"
)
for t in "${TARGETS[@]}"; do
  addr="${t%%:*}"; name="${t##*:}"
  node scripts/rea.mjs function /tmp/paste-arm64 --procedure "$addr" --provider ghidra \
    --snapshot /tmp/paste.ghidra.snapshot --format json > "/tmp/pasteRE/$name.json" 2>/dev/null
  echo "done $name ($addr) exit=$?"
done
