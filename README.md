# IDHscrip

Script helper untuk Indo Hangout. Implementasi ini diperiksa terhadap
`IDH_COMPLETE_CLIENT_DUMP.rbxlx` tanggal 2026-08-17.

## File

- `autofish.lua` — mengontrol minigame `Reeling` lewat input. Catch hanya
  dihitung ketika `ProgressBar` benar-benar hampir penuh; timeout tidak lagi
  dianggap sukses.
- `automining.lua` — memakai remote resmi game
  `Events.RemoteEvent.Pickaxe` dengan action `"Hit"` dan interval 1.55 detik,
  sesuai debounce client bawaan.
- `copyavatar.lua` — menyalin `HumanoidDescription` pemain melalui
  `BloxbizRemotes.CatalogOnApplyToRealHumanoid`.
- `NazhanHub.lua` — UI gabungan lama. Masih perlu runtime test setelah setiap
  update game karena object/remote server dapat berubah.

## Penggunaan

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/amarnazhan27-gif/IDHscrip/main/autofish.lua"))()
```

Untuk copy avatar, jalankan `copyavatar.lua`, lalu:

```lua
local ok, result = shared.IDHCopyAvatar("NamaPlayer")
print(ok, result)
```

Catatan: audit dump dan syntax check bukan bukti runtime. Uji di server privat
atau akun uji. Jangan anggap counter UI sebagai bukti reward server.
