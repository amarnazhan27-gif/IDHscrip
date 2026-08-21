# Client evidence manifest

Sumber analisis: `IDH_COMPLETE_CLIENT_DUMP.rbxlx`, 17 Agustus 2026. File dump
tidak disimpan di repo karena besar dan dapat memuat data yang tidak relevan.

Temuan yang dipakai oleh build 0.4.0:

- `ReelingLocalScript` mengubah arah WhiteBar berdasarkan state input.
- Input yang diterima: klik kiri, touch, Space, atau controller ButtonR2.
- Progress penuh memicu payload `Rod("Catch", "Catch")`.
- Screenshot runtime 22 Agustus 2026 memperlihatkan cast dan GUI reeling aktif,
  tetapi bar tidak dikendalikan oleh build yang hanya mengirim Space.
- Build 0.4.0 mengganti input assist menjadi pointer-first dengan fallback dan
  menambah deteksi GUI bila event `StartReeling` terlewat.

Screenshot mentah tidak disertakan karena memuat nama pemain. Bukti runtime
setelah perubahan masih diperlukan sebelum status server pass dapat diberikan.
