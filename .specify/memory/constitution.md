# K2O-NETHUB - Constitution

> WireGuard Hub Manager for MikroTik RouterOS

## Article I: Simplicity First

RFC 1925 #12: *"Perfection is when there's nothing left to take away"*

Мінімум коду, максимум функціоналу. Кожна фіча повинна виправдовувати свою складність.

## Article II: Single-File Deployment

RouterOS deployment = один `.rsc` файл.
- Без зовнішніх залежностей на роутері
- Без web-сервісів для базової роботи
- Import → працює

## Article III: Multi-Platform Support

Клієнтські конфіги для всіх платформ:
- RouterOS (`.rsc` з management scripts)
- Windows / macOS (`.conf`)
- iOS / Android (`.conf`)
- Linux (`.conf` + `.sh` scripts)

## Article IV: Self-Contained Configs

Згенеровані конфіги повинні бути самодостатніми:
- Всі ключі включені
- Endpoint та порт вказані
- Готові до імпорту без редагування

## Article V: Safe Uninstall

Видалення захищене від випадкового виконання:
- `nethub-uninstall` на hub блокується якщо є активні клієнти
- Client uninstall потребує 3x підтвердження

## Article VI: Routing Modes

Три режими маршрутизації для різних платформ:

**RouterOS (єдиний режим):**
- `pbr` — Policy Based Routing з address-lists (SRCviaWG, DSTviaWG, SRCtoAVOIDviaWG, DSTtoAVOIDviaWG)

**Non-RouterOS (Win/Mac/Linux/iOS/Android):**
- `dgw` — весь трафік через тунель, тільки інтернет, ізоляція від інших клієнтів
- `selective` — вибіркові мережі через тунель

## Article VII: No External Dependencies

RouterOS скрипти працюють автономно:
- Без телеметрії
- Без зовнішніх API
- Без реєстрації

## Article VIII: Masquerade Only What Goes Through Tunnel

NAT правила застосовуються тільки до трафіку що йде через WG:
- Hub: masquerade src=nethub-network out=WAN
- Client (PBR): masquerade out=wg_nethub

---

*Слава Україні!*
