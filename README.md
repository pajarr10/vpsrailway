# Railway VPS-like Environment (Debian 12 + SSH, akses dari Termux)

> ⚠️ **Yang perlu dipahami dulu:** ini adalah **container Docker Debian 12 biasa**
> yang menjalankan SSH server, dijalankan di atas platform Railway. Ini
> **BUKAN** VPS/KVM sungguhan: tidak ada kernel sendiri, tidak ada akses
> hardware, tidak ada systemd, dan container bisa di-restart/redeploy kapan
> saja oleh Railway. Cocok untuk dev environment ringan, scripting, testing,
> compile kecil-kecilan — bukan pengganti VPS untuk workload berat/production.

## Fitur

- Base image **Debian 12 (bookworm) slim**.
- **OpenSSH Server**, login **hanya dengan SSH key** (tanpa password, tanpa root login).
- User non-root **`pajar`** dengan `sudo` (NOPASSWD, karena satu-satunya akses masuk sudah dikunci via SSH key).
- Shell: **bash**.
- Runtime: **Python 3**, **Node.js 20 LTS**, **npm**, **PHP 8.2**, **Git**, `curl`, `wget`, `nano`, `htop`, `unzip`, `zip`.
- **Persistent storage** via Railway Volume (mount ke home directory user).
- Port SSH mengikuti `$PORT` dari Railway (kompatibel dengan **TCP Proxy**).
- Timezone **UTC** tetap.
- Startup script dengan log informatif.
- Tidak pakai systemd — `sshd` jalan di foreground sebagai proses utama container, jadi restart/crash-recovery ditangani dengan benar oleh Railway/Docker.

## Struktur folder

```
railway-vps-ssh/
├── Dockerfile
├── entrypoint.sh
├── sshd_config.template
├── railway.toml
├── .dockerignore
└── README.md
```

## Kenapa desainnya begini (ringkas)

| Persyaratan | Implementasi |
|---|---|
| Tidak ada systemd | `entrypoint.sh` jadi proses init sederhana, diakhiri `exec sshd -D` (foreground) |
| Tidak ada privileged Docker | `sshd` start sebagai root hanya untuk privilege separation bawaan OpenSSH — ini **normal**, bukan `--privileged`, bukan butuh capability tambahan |
| Tidak ada hardcoded credential | Tidak ada password sama sekali; public key **wajib** diisi lewat env var `SSH_PUBLIC_KEY`, container **menolak start** kalau kosong |
| Public key auth only | `PasswordAuthentication no`, `PermitEmptyPasswords no` di `sshd_config` |
| Tidak ada akses root SSH | `PermitRootLogin no` + `AllowUsers pajar` |

---

## 1. Panduan dari nol: bikin GitHub repo

1. Login ke [github.com](https://github.com) → klik **New repository**.
2. Nama repo misalnya `railway-vps-ssh`, set **Private** (karena ini akses SSH ke server kamu), lalu **Create repository**.
3. Di komputer/VPS/Termux kamu, masuk ke folder project ini lalu push:

   ```bash
   cd railway-vps-ssh
   git init
   git add .
   git commit -m "Initial commit: Railway VPS-like SSH environment"
   git branch -M main
   git remote add origin https://github.com/<username>/railway-vps-ssh.git
   git push -u origin main
   ```

   Ganti `<username>` dengan username GitHub kamu (`pajarr10`).

---

## 2. Deploy ke Railway

1. Login ke [railway.app](https://railway.app).
2. **New Project** → **Deploy from GitHub repo** → pilih repo `railway-vps-ssh` yang baru di-push.
3. Railway otomatis mendeteksi `Dockerfile` dan mulai build. Biarkan dulu, jangan tunggu sukses — kita harus set Variables & Volume dulu sebelum container bisa jalan dengan benar (karena tanpa `SSH_PUBLIC_KEY`, container akan exit/fatal — ini disengaja, bukan bug).

### 2.1 Generate SSH key di Termux (kalau belum punya)

Di HP Android, buka **Termux**:

```bash
pkg update && pkg install openssh
ssh-keygen -t ed25519 -C "termux-pajar"
# Enter 3x (pakai default path, boleh kosongkan passphrase atau isi untuk keamanan ekstra)
cat ~/.ssh/id_ed25519.pub
```

Copy **seluruh output** `cat` tadi (satu baris panjang diawali `ssh-ed25519 AAAA...`).

### 2.2 Set Environment Variables di Railway

Di project Railway → tab **Variables** → tambahkan:

| Key | Value |
|---|---|
| `SSH_PUBLIC_KEY` | isi dengan output `cat ~/.ssh/id_ed25519.pub` dari Termux tadi |

> Env var lain (`PORT`, `SSH_USERNAME`, `TZ`) sudah punya default yang aman dari Dockerfile; tidak wajib diisi manual. Kalau mau ganti username, set `SSH_USERNAME` — tapi ingat, user itu harus sudah dibuat di image (default: `pajar`).

### 2.3 Tambahkan Railway Volume (persistent storage)

1. Project Railway → tab **Volumes** (atau klik service → **Settings → Volumes**).
2. **New Volume**.
3. **Mount path**: `/home/pajar`
4. Simpan.

Dengan ini, home directory user (termasuk file yang kamu buat, dan `authorized_keys`) **tetap ada** walau container redeploy/restart.

### 2.4 Aktifkan TCP Proxy

Railway tidak expose SSH lewat domain HTTPS biasa (itu untuk web traffic). Untuk SSH, kamu butuh **TCP Proxy**:

1. Service kamu → tab **Settings** → scroll ke **Networking**.
2. Cari bagian **TCP Proxy** (biasanya di bawah/berdampingan dengan "Public Networking").
3. Klik **Add TCP Proxy** / aktifkan, pilih port internal container yang mau di-expose — isi **22** (port default SSH kita di dalam container, sesuai `EXPOSE 22` di Dockerfile).
4. Railway akan generate sebuah **hostname** + **port eksternal** unik, contoh:

   ```
   containers-us-west-123.railway.app:34567
   ```

   Itu hostname + port yang dipakai untuk connect, **bukan** port 22 langsung.

> Catatan: Railway TCP Proxy men-forward `host:port-eksternal` → container port **22** (port yang kamu daftarkan di step 3), apa pun nilai `$PORT`. Jadi di dalam container, biarkan `sshd` listen di port yang sama dengan yang kamu isi di TCP Proxy settings. Secara default Dockerfile ini pakai `PORT=22`, cocok dengan isian di atas. Kalau Railway di akun kamu mewajibkan pakai `$PORT` dinamis untuk TCP service, cek nilai `$PORT` di tab **Variables** (Railway biasa auto-inject), lalu masukkan angka yang sama persis di kolom "internal port" TCP Proxy.

5. Redeploy service (Railway → **Deploy** terbaru, atau trigger ulang lewat tombol **Redeploy**) supaya `SSH_PUBLIC_KEY` dan Volume terpasang saat container start.

### 2.5 Cek log startup

Tab **Deployments** → klik deployment aktif → **View Logs**. Kamu akan lihat output seperti:

```
[entrypoint] ... Railway VPS-like Environment — starting up
[entrypoint] ... User            : pajar
[entrypoint] ... Listen port     : 22 (from $PORT, Railway-managed)
[entrypoint] ... authorized_keys written for pajar (1 key line(s))
[entrypoint] ... sshd configuration OK, listening on 0.0.0.0:22
[entrypoint] ... Ready. Connect from Termux with:
[entrypoint] ...   ssh -p 22 pajar@<railway-tcp-proxy-host>
```

Kalau muncul `FATAL: SSH_PUBLIC_KEY environment variable is not set.` artinya step 2.2 belum tersimpan/redeploy belum jalan.

---

## 3. Connect dari Termux

```bash
ssh -p 34567 pajar@containers-us-west-123.railway.app
```

Ganti `34567` dan `containers-us-west-123.railway.app` dengan hostname:port asli dari TCP Proxy kamu (lihat step 2.4).

Kalau mau lebih praktis, tambahkan alias di `~/.ssh/config` (Termux):

```
Host railway-dev
    HostName containers-us-west-123.railway.app
    Port 34567
    User pajar
    IdentityFile ~/.ssh/id_ed25519
```

Lalu cukup:

```bash
ssh railway-dev
```

---

## 4. Update / redeploy

Setiap kali push commit baru ke `main` di GitHub, Railway otomatis build ulang image dan redeploy (kalau auto-deploy aktif, default-nya memang begitu untuk GitHub-connected service). Host SSH key container akan tetap sama antar-restart biasa (karena digenerate saat **build**, bukan saat start) — tapi akan berubah setiap kali image di-**rebuild** (misal setelah `git push`), jadi Termux mungkin menampilkan warning "host key berubah" setelah update — ini normal, konfirmasi saja (`yes`) atau hapus entry lama dari `~/.ssh/known_hosts`.

## 5. Mengganti / menambah public key

Tinggal update value `SSH_PUBLIC_KEY` di Railway → Variables, lalu **Redeploy**. Entrypoint menulis ulang `authorized_keys` setiap container start, jadi perubahan langsung berlaku restart berikutnya. Mau lebih dari satu key? Isi `SSH_PUBLIC_KEY` dengan beberapa baris sekaligus (satu key per baris), Railway mendukung env var multiline.

## 6. Troubleshooting singkat

- **Connection refused** → cek TCP Proxy sudah aktif dan port internal sesuai `PORT`/`sshd` (default 22).
- **Permission denied (publickey)** → pastikan `SSH_PUBLIC_KEY` di Railway persis sama dengan isi `id_ed25519.pub` kamu, dan kamu connect pakai private key yang pasangannya (`ssh -i ~/.ssh/id_ed25519 ...` kalau bukan default path).
- **Container langsung exit setelah deploy** → cek Logs, kemungkinan besar `SSH_PUBLIC_KEY` belum diisi.
- **Data hilang setelah redeploy** → pastikan Volume mount path persis `/home/pajar` (sesuai `SSH_USERNAME`).

---

## Batasan (disclaimer)

- Ini container Docker di platform Railway, **bukan VPS KVM**: tidak bisa ganti kernel, tidak ada akses device/hardware langsung, resource dibatasi plan Railway kamu.
- Cocok untuk: coding, scripting, testing Node/PHP/Python, git clone & build kecil, belajar Linux dari HP.
- Tidak cocok untuk: workload berat, perlu kernel custom, perlu root TRUE pada host, atau sebagai pengganti VPS produksi.
