# Nagios Core Modern Dashboard (Rails 7 & Clean Architecture)

Modern, reactive, and mobile-friendly monitoring dashboard for Nagios Core built with **Ruby on Rails 7**, **Hotwire (Turbo & Stimulus)**, and **Tailwind CSS**.

Berjalan berdampingan (*side-by-side*) dengan Nagios Core Engine klasik melalui Docker Compose, mengadopsi kontrol operasional, audit, dan analitik secara menyeluruh dengan antarmuka modern.

---

## 🚀 Fitur Utama & Adopsi dari Classic Nagios CGI/HTML

| Kategori | Fitur Modern Dashboard | Adopsi dari Antarmuka Klasik |
| :--- | :--- | :--- |
| **UX & Navigasi** | **Global Command Palette (`Cmd+K` / `Ctrl+K`)** | Form search di `side.php` |
| **UX & Navigasi** | **Auto-Refresh Interval & Live Countdown** (Dropdown Off, 10s, 15s, 30s, 60s di navbar) | CGI Meta-Refresh header |
| **Tema Tampilan** | **Sleek Dark Mode & Light Mode** (Auto-detect & toggle dengan `localStorage`) | Opsi tema di `side.php` |
| **Eksplanasi Status** | **Interactive Tooltips & Flapping Badges** (🔀 Flapping indicator, HARD vs SOFT State) | Direktori `html/contexthelp/` |
| **Kontrol Operasional** | **Host & Service Switches** (Mute/Unmute Notifications, Pause/Resume Checks) | Aksi `cmd.cgi` |
| **Kontrol Operasional** | **Host Problem Acknowledgment & Scheduled Downtimes** (Host & Service level) | `cmd.cgi` |
| **Kontrol Operasional** | **Manual Passive Check Injection** (0=OK, 1=WARN, 2=CRIT, 3=UNKNOWN) | `cmd.cgi?cmd_typ=30` |
| **Audit & Log** | **Live Event Log Stream (`/logs`)** dengan filter kategori (ALERT, NOTIFICATION, dsb) | `showlog.cgi` |
| **Audit & Log** | **Notification Audit Table & Export CSV (`/notifications.csv`)** riwayat alert kontak | `notifications.cgi` |
| **Audit & Log** | **Host Status Export CSV (`/hosts.csv`)** ekspor snapshot status untuk audit/reporting | `status.cgi` |
| **Analisis Insiden** | **Root Cause & Outages Report (`/outages`)** pemetaan blocking outage & availability | `outages.cgi` |
| **Visualisasi Tren** | **Alert Histogram (`/trends`)** distribusi alert 24-jam berbasis Chart.js | `histogram.cgi` |
| **Eksplorasi Konfigurasi** | **Objects Configuration Explorer (`/configuration`)** command lines, contacts, groups, timeperiods | `config.cgi` |
| **Event Architecture** | **In-App Domain Event Broker (`Statuses::Events::Broker`)** pub/sub & history | `base/broker.c` (NEB) |
| **Check Intelligence** | **Freshness & Stale Check Detector (`FreshnessDetector`)** deteksi check usang | `base/checks.c` (Freshness) |
| **Kontrol Operasional** | **Pencabutan Acknowledgment (`Disack`) & Cascade Cluster Downtime** | `base/commands.c` |
| **Integrasi 2 Arah** | **Bidirectional Bridge Navigation** (Akses cepat antar Dashboard & Classic UI) | Sidebar link di `side.php` & Navbar |

---

## 🏛️ Arsitektur Sistem (Clean Architecture)

Mengadopsi prinsip Clean Architecture & DDD:

```
dashboard/app/
├── domains/
│   ├── engines/
│   │   └── nagios_engine.rb       # Infrastructure Adapter (statusjson.cgi, archivejson.cgi, nagios.cmd)
│   └── statuses/
│       ├── entities/              # HostStatus, ServiceStatus, ProgramStatus, EventLog, OutageGroup
│       ├── repositories/          # Interface StatusRepository
│       ├── use_cases/             # ScheduleCheck, AcknowledgeProblem, ScheduleDowntime, FetchDashboardData
│       └── value_objects/         # StatusCode, PerformanceData
├── controllers/                   # Rails Controllers (Hotwire Turbo Stream & JSON/HTML responses)
├── javascript/controllers/        # Stimulus Controllers (quick_search, theme, filter)
└── views/                         # Tailwind CSS Views (100% Dark Mode & Turbo Frames)
```

---

## 🐳 Menjalankan dengan Docker Compose

Pastikan Docker & Docker Compose aktif di komputer Anda:

```bash
# Jalankan seluruh stack (Rails Modern Dashboard + Nagios Core)
docker compose up -d

# Periksa status container
docker compose ps
```

### Akses Antarmuka:
- **Modern Rails Dashboard**: [http://localhost:3000](http://localhost:3000)
- **Classic Nagios Core UI**: [http://localhost:8080/nagios/](http://localhost:8080/nagios/) (Login: `nagiosadmin` / `nagiosadmin`)

---

## 🧪 Menjalankan RSpec Test Suite

Seluruh pengujian unit dan request spec dapat dijalankan di dalam container:

```bash
docker compose exec web bundle exec rspec
```

Semua 95 test cases mencakup:
- Status API & Endpoints
- Request Specs untuk seluruh controller & view formats
- Remove Acknowledgment (Disack) & Cascade Cluster Downtime specs
- Freshness & Stale Check Detector specs (`Statuses::Services::FreshnessDetector`)
- Domain Event Broker pub/sub & history specs (`Statuses::Events::Broker`)
- CSV Export specs (`hosts.csv` & `notifications.csv`)
- Flapping detection pada entities Host & Service
- Turbo Stream responses untuk Host & Service operational toggles
- Audit log & passive check submissions
