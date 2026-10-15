# LifeofTetangga

Web operasional laundry berbahasa Indonesia, dengan antarmuka responsif dan database Supabase. Aplikasi menyimpan transaksi, pelanggan, progres membership, pesanan kiloan, katalog, stok, pengeluaran, hitungan pengunjung, dan tutup buku ke proyek Supabase.

## Konfigurasi yang sudah disiapkan

- Supabase project: `tekkutcwlbnpshbehonw` (`ap-southeast-1`)
- URL dan publishable key berada di `config.js`. Publishable key memang boleh dipakai di browser; jangan tambahkan `service_role` key atau password database ke file frontend.
- Data tabel dilindungi RLS dan hanya dapat dibaca pengguna terautentikasi dengan profil aktif di outlet yang sama.
- Akun pemilik pertama belum dibuat. Gunakan `supabase/owner_bootstrap.sql` setelah akun Auth dibuat di Dashboard Supabase.
- Harga katalog dan jumlah stok awal ditandai demo. Pemilik perlu menggantinya sebelum mencatat transaksi nyata.

## Menyiapkan akun pemilik pertama

1. Di Supabase Dashboard proyek LifeofTetangga, buat pengguna pertama di **Authentication → Users**.
2. Salin alamat email pengguna tersebut. Ubah `OWNER_EMAIL` di `supabase/owner_bootstrap.sql` lalu jalankan file itu lewat SQL Editor.
3. Buka situs, masuk dengan akun tersebut, lalu ubah tarif demo di **Layanan & Harga** dan stok demo di **Stok**.

Pemilik dapat mengaktifkan akun kasir setelah Auth user dibuat, dengan menambahkan baris profil berperan `cashier`. Pembuatan undangan belum otomatis dari aplikasi.

## Migrations

Urutan migration yang telah dipasang di database:

1. `schema.sql` — tabel usaha, pelanggan, transaksi, membership, pesanan, biaya, stok, tutup buku, RLS.
2. `20261015_reporting_membership.sql` — hitungan pengunjung, biaya layanan/barang, pencatatan QR saat tutup buku, auto-apply reward Self Service, reversal progres saat refund/batal.
3. `20261015_demo_catalog.sql` — katalog layanan dan stok awal bertanda demo.
4. `20261015_paid_price_guard.sql` — mencegah pembayaran dengan tarif demo atau nilai item yang tidak cocok dengan katalog.
5. `20261015_private_rls_helpers.sql` — memindahkan fungsi SECURITY DEFINER untuk RLS ke schema privat yang tidak diekspos sebagai API.

Semua migration tersimpan di folder `supabase/` untuk pelacakan perubahan selanjutnya.

## Aturan bisnis yang diterapkan

- Progres bertambah hanya setelah transaksi lunas untuk Self Service dan Kiloan Retail; B2B dikecualikan.
- Reward hanya saat penggunaan ke-5 dan ke-10, masing-masing 25% dan berlaku 30 hari.
- Database otomatis memakai reward aktif saat transaksi Self Service dilunasi. Potongan hanya dihitung dari jasa utama; add-on dan produk tidak ikut.
- Metode pembayaran: Tunai, QR Mesin, QR Tetangga.
- Status pesanan Kiloan: Masuk, Proses, Selesai, Diambil.
- Refund atau pembatalan transaksi lunas mengoreksi progres dan mencatat peristiwa audit. Bila reward belum dipakai, reward dari penggunaan yang dibatalkan dicabut.
- Laporan adalah ringkasan operasional dari data tersimpan. Laba sementara memakai perkiraan biaya yang diatur pada katalog dan pengeluaran tercatat; aplikasi tidak membuat jurnal akuntansi.

## Menjalankan / deploy

Aplikasi ini statis dan dapat di-host di Vercel tanpa langkah build. Impor repositori GitHub, pilih folder ini sebagai **Root Directory**, dan gunakan pengaturan build/output kosong/default. Setiap push ke branch produksi akan memicu deployment jika integrasi Git Vercel sudah terhubung.

WhatsApp hanya dicatat sebagai data kontak; aplikasi belum mengirim pesan. Penyimpanan berjalan lewat Supabase Auth, Postgres, dan RLS.
