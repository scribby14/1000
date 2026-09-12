# Диагностика падений Claude Code (GPU-процесс) на Windows

Журнал расследования и скрипты для машины `scrib` (Intel iGPU, Windows 11).
Текущий эпизод: падение Claude Code во время установки Касперского, 24.08.2026.

| Файл | Назначение |
| --- | --- |
| `CLAUDE.md` | Правила работы в этом репозитории; потолок — восемь пунктов |
| `MISTAKES.md` | Журнал ошибок: причина, цена, механизм, критерий. Запись — командой `/mistake` |
| `docs/incident-2026-08-24-kaspersky.md` | Разбор инцидента 24.08.2026 и план действий |
| `docs/kaspersky-exclusions.md` | Как исключить Claude Code из контроля Касперского |
| `scripts/fix-intel-driver.ps1` | Откат Intel-драйвера 32.0.101.7088 → 32.0.101.5972 + блокировка доставки драйверов через Windows Update |
| `scripts/check-av-injection.ps1` | Проверка: внедряется ли Касперский в процессы Claude и перехватывает ли он TLS |

Скрипты рассчитаны на запуск из `C:\Users\scrib\claude-fix\` — рядом с уже
существующим `check-gpu-health.ps1`:

```powershell
# диагностика (обычный PowerShell)
powershell -ExecutionPolicy Bypass -File .\check-av-injection.ps1

# откат драйвера (PowerShell от администратора, Claude Code закрыть)
powershell -ExecutionPolicy Bypass -File .\fix-intel-driver.ps1
```
