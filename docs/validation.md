# Validation guide

Validasi dibagi agar hasil static check tidak salah dianggap sebagai bukti
fitur bekerja di server.

## 1. Static audit

```bash
./scripts/audit.sh
```

Audit memeriksa sintaks empat entry point, whitespace Git, protocol marker,
dan pola credential berisiko. Hasil ini tidak menjalankan Roblox atau Delta.

## 2. Safe compatibility scan

Jalankan loader, buka tab `System`, lalu tekan `Run compatibility scan`.
Scan default tidak menggerakkan karakter dan tidak menjual inventory.

## 3. Active runtime test

Gunakan akun uji dan area yang aman:

```lua
local hub = loadstring(game:HttpGet("https://raw.githubusercontent.com/amarnazhan27-gif/IDHscrip/main/NazhanHub.lua", true))()
hub.runSelfTest({active = true, fishingWait = 25, miningWait = 10})
```

Untuk fishing, bukti minimum adalah: cast terjadi, GUI reel muncul, WhiteBar
bergerak mengikuti RedBar, GUI selesai, lalu inventory atau cash berubah sesuai
mekanisme game. Untuk mining, bukti minimum adalah target aman ditemukan,
karakter mencapai target, tool aktif, dan crystal/reward berubah.

## Status bukti

| Status | Arti |
|---|---|
| Static pass | Source dapat diparse dan marker protocol tersedia |
| Client pass | Path, GUI, tool, atau event terlihat di client |
| Server pass | Reward atau perubahan inventory benar-benar diterima |
| Unverified | Belum ada bukti segar pada versi game/executor saat ini |
