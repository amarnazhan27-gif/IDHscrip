# IDH Hub

Client helper untuk Indo Hangout. Fokus repo ini adalah automation yang kecil,
mudah diperiksa, dan tidak bergantung pada UI library pihak ketiga.

Referensi implementasi saat ini adalah dump client
`IDH_COMPLETE_CLIENT_DUMP.rbxlx` tanggal 17 Agustus 2026. Nama remote, struktur
GUI, dan folder crystal diambil dari dump tersebut—bukan hasil tebak nama
object.

## Fitur

- Auto fishing dengan dua metode:
  - `Input Assist` mengontrol `WhiteBar` terhadap `RedBar` dan membiarkan client
    bawaan menyelesaikan proses catch.
  - `Fast Catch` mengirim request catch langsung. Metode ini opsional karena
    validasi server dapat berubah.
- Auto mining dengan pathfinding menuju
  `Workspace.MapContent.Decoration.Crystals` dan interval hit 1,55 detik.
- Sell all fish dan crystal berdasarkan kategori yang dimuat oleh GUI game.
- Copy avatar melalui `HumanoidDescription` dan Bloxbiz apply remote.
- Anti-AFK dan low graphics lokal.
- GUI native yang mobile-friendly, draggable, dan tanpa asset eksternal.

## Menjalankan di Delta

1. Masuk ke Indo Hangout dan tunggu karakter selesai spawn.
2. Buka Delta Executor.
3. Tempel loader berikut.
4. Jalankan sekali. Menjalankan ulang akan membersihkan sesi hub sebelumnya.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/amarnazhan27-gif/IDHscrip/main/NazhanHub.lua"))()
```

Untuk hasil fishing yang paling aman terhadap server validation, mulai dengan
`Fast Catch` dalam keadaan mati. Nyalakan hanya jika `Input Assist` tidak dapat
mengirim tombol Space pada versi Delta/perangkat yang dipakai.

Auto mining membutuhkan pickaxe di Backpack. Auto fishing membutuhkan rod.
Fitur sell all membutuhkan menu SellFish atau SellCrystal pernah dibuka sekali
agar daftar kategori sudah tersedia di `PlayerGui`.

### Troubleshooting Delta Android

Build yang berhasil dimuat menampilkan notifikasi `IDH Hub 0.2.1` dan dua baris
console bertanda `[IDH Hub 0.2.1] starting` lalu `loaded`. Jika startup gagal,
pesan bertanda sama akan berisi stack trace pertama dan disimpan di
`getgenv().IDHBootError`.

Error seperti `UIStroke is not a valid member of TextButton` dari
`Script 'LocalScript', Line 2684` bukan berasal dari hub ini. Abaikan error game
tersebut dan cari prefix `[IDH Hub ...]` agar laporan bug tidak tercampur.

### Runtime self-test

Hub menyediakan `runSelfTest()` untuk memeriksa dependency, GUI lifecycle,
toggle lokal, fishing, dan mining. Hasil dicetak dengan prefix `[IDH Test]`.

```lua
local hub = loadstring(game:HttpGet("https://raw.githubusercontent.com/amarnazhan27-gif/IDHscrip/main/NazhanHub.lua", true))()
hub.runSelfTest()
```

Copy Avatar dan Sell sengaja tidak dijalankan oleh default karena mengubah
avatar atau inventory. Gunakan opsi berikut hanya jika perubahan tersebut
memang diinginkan:

```lua
hub.runSelfTest({avatar = true, inventory = true})
```

`PASS` berarti client path atau request berhasil dijalankan. Itu belum menjadi
bukti reward server sampai perubahan inventory/cash terlihat di game.

## Entry point terpisah

File berikut tetap tersedia untuk pemakaian sederhana:

- `autofish.lua` — membuka hub dan langsung menyalakan auto fishing.
- `automining.lua` — membuka hub dan langsung menyalakan auto mining.
- `copyavatar.lua` — mengembalikan fungsi copy avatar.

Contoh copy avatar dari script lain:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/amarnazhan27-gif/IDHscrip/main/NazhanHub.lua"))()

local hub = getgenv().IDHHub
local ok, message = hub.copyAvatar("NamaPlayer")
print(ok, message)
```

Nama boleh berupa username, display name, atau awal nama. Jika dikosongkan,
hub memilih pemain terdekat.

## Dasar teknis

| Fitur | Client path / protocol |
|---|---|
| Cast | `Events.RemoteEvent.Rod("Throw")` |
| Reeling | `PlayerGui.Reeling.MainFrame.Frame.WhiteBar/RedBar` |
| Catch | `Events.RemoteEvent.Rod("Catch", "Catch")` |
| Mining | `Events.RemoteEvent.Pickaxe("Hit")` |
| Crystal | `Workspace.MapContent.Decoration.Crystals` |
| Copy avatar | `BloxbizRemotes.CatalogOnApplyToRealHumanoid` |
| Sell fish | `SellFish("CheckFish"/"SellFish", category)` |
| Sell crystal | `SellCrystal("CheckCrystal"/"SellCrystal", category)` |

Dump client tidak menyimpan server script karena FilteringEnabled. Karena itu,
repo ini tidak mengklaim reward server atau kompatibilitas 100% hanya dari
static audit. Bukti final tetap membutuhkan runtime test pada versi game dan
Delta yang sedang digunakan.

## Kontribusi

1. Fork repo dan buat branch dengan nama yang menjelaskan perubahan.
2. Hindari menambah UI library atau loader tertutup tanpa alasan kuat.
3. Jika object game berubah, sertakan path lama, path baru, dan tanggal dump.
4. Pisahkan perubahan GUI dari perubahan protocol/remotes bila memungkinkan.
5. Buka pull request dan jelaskan cara pengujian yang sudah dilakukan.

Pull request untuk bug sebaiknya menyertakan:

- nama executor dan versinya;
- perangkat/OS;
- pesan error lengkap tanpa token atau data akun;
- fitur yang aktif saat error;
- apakah remote/folder terkait berstatus `OK` atau `MISS` pada tab System.

## Batasan

- Update game dapat mengganti nama object, payload remote, atau server
  validation tanpa pemberitahuan.
- Counter dan status GUI bukan bukti bahwa reward sudah diterima server.
- Gunakan akun uji. Automation dapat melanggar aturan game atau platform dan
  berisiko menyebabkan pembatasan akun.
- Repo tidak membutuhkan webhook, token, password, atau konfigurasi Discord.

## Lisensi

MIT. Lihat `LICENSE`.
