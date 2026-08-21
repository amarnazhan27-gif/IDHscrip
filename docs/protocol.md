# Client protocol map

Peta ini diturunkan dari `IDH_COMPLETE_CLIENT_DUMP.rbxlx` tanggal 17 Agustus
2026. Dump client tidak berisi server script. Nama remote dan payload di bawah
tetap dapat berubah setelah game diperbarui.

| Fitur | Client path atau payload |
|---|---|
| Equip rod | `Events.RemoteEvent.Rod("Equipped")` dari stock tool script |
| Cast | `Tool:Activate()` lalu stock script mengirim `Rod("Throw")` |
| Mulai reel | `Rod.OnClientEvent("StartReeling", tool)` |
| Reeling GUI | `PlayerGui.Reeling.MainFrame.Frame.WhiteBar/RedBar` |
| Progress | `PlayerGui.Reeling.MainFrame.ProgressBg.ProgressBar` |
| Catch | stock client mengirim `Rod("Catch", "Catch")` |
| Mining | `Tool:Activate()` lalu stock script mengirim `Pickaxe("Hit")` |
| Crystal | `Workspace.MapContent.Decoration.Crystals` |
| Copy avatar | `BloxbizRemotes.CatalogOnApplyToRealHumanoid` |

## Reeling input

Stock `ReelingLocalScript` menerima `MouseButton1`, `Touch`, `Space`, atau
`ButtonR2`. Build 0.4.0 mengirim pointer input untuk Delta Android dan Space
sebagai fallback. Jika event `StartReeling` tidak sampai ke hub tetapi GUI
reeling terlihat, visibilitas GUI akan mengaktifkan assist secara otomatis.

`Fast Catch` melewati input mini-game dan langsung mengirim payload catch.
Mode itu opsional karena server dapat menolak request yang tidak sesuai state.
