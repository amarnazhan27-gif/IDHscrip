# Contributing

IDH Hub sengaja dipertahankan sebagai single-file runtime agar mudah diaudit
dan mudah dimuat di perangkat mobile. Perubahan sebaiknya kecil, dapat dilacak
ke bukti client, dan tidak menambah dependency tertutup.

## Alur perubahan

1. Buat branch dengan nama yang menjelaskan masalah.
2. Jelaskan path atau protocol lama dan baru bila game berubah.
3. Jalankan `./scripts/audit.sh`.
4. Uji pada akun uji dan catat build, executor, perangkat, serta hasil nyata.
5. Buka pull request. Pisahkan perubahan protocol dari perubahan tampilan.

## Laporan bug

Sertakan nomor build dari notifikasi IDH Hub, langkah reproduksi, fitur yang
aktif, dan baris console dengan prefix `[IDH Hub]` atau `[IDH Test]`. Hapus
username, token, data akun, dan identitas pemain lain sebelum mengunggah bukti.

Status `PASS` pada compatibility scan hanya membuktikan path client tersedia.
Reward, inventory, dan cash harus diverifikasi terpisah di dalam game.

## Batas kontribusi

- Jangan menambahkan webhook, token, password, logger pemain, atau telemetry.
- Jangan meng-obfuscate source.
- Jangan memasukkan dump `.rbxlx`, arsip besar, atau screenshot mentah.
- Jangan mengklaim kompatibilitas penuh tanpa runtime test yang dapat diulang.
