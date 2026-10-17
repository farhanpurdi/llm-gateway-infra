# LLM Gateway Infrastructure

LiteLLM, PostgreSQL, dan Redis memakai Docker existing pada port 4000. Runtime
config ada di repository saudara `llm-gateway-config`; E2E ada di `llm-gateway-e2e`.

[Dokumentasi dan handover project](../llm-gateway-docs/README.md) ·
[Master context](../llm-gateway-docs/MASTER_CONTEXT.md).

## Checkpoint H10: gunakan environment existing

Tidak perlu init environment, compose staging, atau container baru. Compose staging
beserta scriptnya sudah dihapus. Data staging lama yang diabaikan Git boleh tetap
tersimpan sebagai arsip; tidak dipakai oleh prosedur ini.

```bash
export PATH="$PWD/../.venv/bin:$PATH"
./scripts/health/check-all.sh
./scripts/ci/validate.sh
```

Base Compose memublikasikan gateway port 4000; PostgreSQL/Redis tidak memublikasikan
port host. Override development membuka DB/Redis di loopback saja. Server harus
memiliki pembatasan jaringan dan TLS sebelum menerima pengguna.

## Operasional

- [Release dan rollback config](../llm-gateway-docs/operations/deployment.md)
- [Backup dan restore](../llm-gateway-docs/operations/backup.md)
- [Onboarding, offboarding, incident](../llm-gateway-docs/operations/incident.md)
- [Checklist pilot Phase 1](../llm-gateway-docs/operations/phase1-checklist.md)

```bash
./scripts/release/release.sh capture sebelum-perubahan
./scripts/backup/drill.sh --quiesce
../llm-gateway-e2e/scripts/run-all.sh
```

Drill menghentikan gateway sebentar, membuat database `<POSTGRES_DB>_restore_test`
di PostgreSQL existing untuk membandingkan seluruh tabel, lalu menghidupkan gateway.
Database aplikasi utama tidak ditimpa. Backup berisi data sensitif dan salinan `.env`;
simpan ketiga file backup di penyimpanan terbatas/enkripsi, bukan di Git.

Validator memiliki 7 tahap: syntax Bash, ShellCheck, template environment, base
Compose, development override, regresi operasional offline, dan Git safety.

Scanner lokal dapat memakai `GITLEAKS_BIN`, `TRIVY_BIN`, `PIP_AUDIT_BIN` untuk
binary native. Default CI tetap mengikuti scanner versi project. Pemindaian secret
mencakup riwayat Git dan file tracked/untracked yang tidak di-ignore.
