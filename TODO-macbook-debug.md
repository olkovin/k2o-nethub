# TODO: MacBook WireGuard Profile Debug

## Задача

Олександр хоче **2 конфіги для MacBook**:

1. **Full Tunnel (DGW)** — WireGuard як default gateway, весь трафік через тунель
2. **Roadwarrior (Selective)** — тільки маршрути до nethub мереж, решта трафіку — напряму

**Проблема:** профіль на MacBook не працює — треба з'ясувати чому.

---

## Як генеруються конфіги зараз

### Генератор

Скрипт `nethub-generate-client` створюється всередині `nethub_server_deploy.rsc` (рядки 126–378).

**Виклик:**
```routeros
:global nethubGenName "macbook"
:global nethubGenPlatform "mac"
:global nethubGenMode "dgw"         # або "selective"
:global nethubGenNetworks "..."     # тільки для selective
:global nethubGenAdmin "yes"        # опціонально
/system script run nethub-generate-client
```

### Режими для Non-ROS (Mac/Win/Linux/iOS/Android)

| Режим | Address | AllowedIPs | Файл |
|-------|---------|------------|------|
| **DGW** | `{ip}/32` | `0.0.0.0/0, ::/0` | `nethub_{name}_dgw.conf` |
| **DGW + Admin** | `{ip}/24` | `0.0.0.0/0, ::/0` | `nethub_{name}_admin.conf` |
| **Selective** | `{ip}/24` | `{serverIP}/32, {networks}` | `nethub_{name}.conf` |
| **Selective + Admin** | `{ip}/24` | `{serverIP}/32, {networks}, {hubNet}` | `nethub_{name}_admin.conf` |
| **Selective (minimal)** | `{ip}/24` | `{serverIP}/32` | `nethub_{name}_minimal.conf` |

### Шаблон .conf файлу

```ini
[Interface]
PrivateKey = {privKey}
Address = {clientAddr}       # /32 для DGW, /24 для selective
DNS = {nethubServerIP}       # завжди IP хаба (10.254.0.1)

[Peer]
PublicKey = {nethubServerPubKey}
Endpoint = {nethubFQDN}:{nethubWgPort}
AllowedIPs = {allowedIPs}
PersistentKeepalive = 25
```

---

## Що перевірити для дебагу MacBook

### 1. Перевірити існуючий конфіг на MacBook
- Який режим використовується (DGW чи Selective)?
- Які AllowedIPs прописані?
- Чи правильний Address (/32 vs /24)?
- Чи правильний Endpoint (FQDN + порт)?

### 2. Перевірити на стороні хаба
- Чи є peer зареєстрований в WireGuard інтерфейсі?
- Чи правильний `allowed-address` для цього peer?
- Чи є handshake (перевірити `latest-handshake`)?
- Firewall правила — чи не блокується трафік?

### 3. Можливі проблеми на macOS
- DNS resolution — macOS може ігнорувати DNS з WG конфігу
- `/32` адреса в DGW режимі — може бути проблема з маршрутизацією на macOS
- Конфлікт з іншими VPN або мережевими інтерфейсами
- Потрібно перевірити `scutil --dns` після підключення WG

### 4. Генерація двох конфігів
Для MacBook потрібно згенерувати:

**Конфіг 1 — Full Tunnel (DGW):**
```routeros
:global nethubGenName "macbook"
:global nethubGenPlatform "mac"
:global nethubGenMode "dgw"
:global nethubGenAdmin "yes"    # якщо потрібен доступ до hub network
/system script run nethub-generate-client
```

**Конфіг 2 — Roadwarrior (Selective):**
```routeros
:global nethubGenName "macbook-rw"
:global nethubGenPlatform "mac"
:global nethubGenMode "selective"
:global nethubGenNetworks "10.254.0.0/24,<інші_мережі>"
/system script run nethub-generate-client
```

> **Увага:** Генератор створює нового peer для кожного виклику. Для 2 конфігів з одним peer — треба вручну створити другий .conf з тим самим PrivateKey/Address, але іншими AllowedIPs.

---

## Мережеві деталі

- **Hub network:** `10.99.0.0/24` (не 10.254 як було в документації)
- **Hub server IP:** `10.99.0.1`
- **DNS:** через hub (`10.99.0.1`) або Cloudflare (`1.1.1.1`)
- **PersistentKeepalive:** 25 секунд
- **MacBook client IP:** `10.99.0.12`

---

## Статус

- [x] Отримати поточний .conf файл з MacBook
- [x] Перевірити peer на хабі
- [x] Визначити причину непрацюючого профілю
- [x] Згенерувати/створити 2 конфіги (DGW + Selective)
- [x] Перевірити обидва конфіги на MacBook

---

## Результат (2025-02-15)

### Проблема
Peer `mvsm-MacWG` мав `allowed-address=0.0.0.0/0` на хабі — WireGuard не знав на яку IP надсилати відповіді.

### Виправлення
```routeros
/interface wireguard peers set [find name="mvsm-MacWG"] allowed-address=10.99.0.12/32
```

### Конфіги

**DGW (Full Tunnel):** `/Users/olekovin/Downloads/mvsm_MacWG.conf`
- Address: `10.99.0.12/32`
- AllowedIPs: `0.0.0.0/0, ::/0`
- DNS: `1.1.1.1, 1.0.0.1`

**Selective (Roadwarrior):** `/Users/olekovin/Desktop/nethub_macbook_selective.conf`
- Address: `10.99.0.12/24`
- AllowedIPs: `10.99.0.0/24, 10.10.10.0/24, 10.15.15.0/24, 10.40.40.0/24, 192.168.100.0/24`
- DNS: `10.99.0.1`

### Тестування
| Конфіг | Hub ping | Інтернет | Статус |
|--------|----------|----------|--------|
| DGW | ✅ | Через тунель (145.239.91.106) | Працює |
| Selective | ✅ | Напряму (локальний IP) | Працює |

### Примітка
Omega infra (`192.168.100.0/24`) недоступна з хаба — VM вимкнені або проблема з omega-chr.
