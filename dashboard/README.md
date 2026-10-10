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
| **Flap Intelligence** | **Flap Detection & Hysteresis Calculation (`FlapDetector`)** curved state change & threshold hysteresis | `base/flapping.c` |
| **Alert Viability** | **Notification Viability Engine (`NotificationViability`)** filter downtime, throttle interval, ACK, flapping & dependencies | `base/notifications.c` |
| **State Persistence** | **State Retention Parser & Dumper (`StateRetention`)** parsing & serialization `retention.dat` roundtrip | `base/sretention.c` & `xdata/xrddefault.c` |
| **Automation** | **Event Handlers Dispatcher (`EventHandlerDispatcher`)** auto-remediation macro expansion & state change dispatch | `base/sehandlers.c` |
| **Metric Telemetry** | **Performance Data & Output Parser (`PerfdataParser`)** UOM, thresholds, percentages & check output split | `base/perfdata.c` & `base/checks.c` |
| **Topology & Outages** | **Host Reachability Engine (`HostReachabilityDetector`)** DOWN vs UNREACHABLE parent topology analyzer | `base/checks.c` |
| **Engine Analytics** | **Operational Metrics Aggregator (`OperationalMetricsAggregator`)** latency min/max/avg & cluster health score | `base/nagiostats.c` |
| **Event Scheduling** | **Timed Event Queue & Loop (`TimedEventQueue`)** priority queue, interleave check distribution & recurrence | `base/events.c` |
| **Radio Streaming** | **Nagios Event Radio Dispatcher (`EventRadioDispatcher`)** NERD channel pub/sub broadcast streaming hub | `base/nerd.c` |
| **Socket Querying** | **Query Handler Socket Client (`QueryHandlerClient`)** runtime daemon IPC socket protocol (`@echo`, `@core`, `@wproc`) | `base/query-handler.c` |
| **Network Probing** | **Network Connection Utilities (`NetUtils`)** non-blocking TCP socket connect probe & IP resolution | `base/netutils.c` |
| **Logging & Audit** | **Daemon Structured Logger (`DaemonLogger`)** formatting standard Nagios alerts & atomic log rotation | `base/logging.c` |
| **Worker Process Pool** | **Worker Process Pool (`WorkerProcessPool`)** multi-slot job execution, timeout watchdog & status codes | `base/workers.c` |
| **Time Windows** | **Timeperiod Evaluator (`TimeperiodEvaluator`)** check active time window, day ranges & exclusions | `base/utils.c` |
| **Plugin Extensions** | **NEB Module Registry (`NebModuleRegistry`)** event broker dynamic module loader & callback hooks | `base/nebmods.c` |
| **Daemon Orchestrator** | **Daemon Lifecycle Coordinator (`DaemonLifecycleCoordinator`)** master loop, start/stop/pause & subsystem glue | `base/nagios.c` |
| **Command Processing** | **External Command Processor (`ExternalCommandHandler`)** parser & dispatcher 37 opcode external command (FIFO `nagios.cmd`) | `base/commands.c` |
| **Configuration Engine** | **Main Configuration Parser (`MainConfigParser`)** parser, validator direktif, array multi-value & serializer `nagios.cfg` | `base/config.c` |
| **Macro Resolution** | **Macro Expansion Engine (`MacroResolver`)** ekspansi standard host/service state, dates, $USERx$, & notifikasi | `common/macros.c` |
| **Maintenance Windows** | **Downtime Coordinator (`DowntimeCoordinator`)** fixed vs flexible downtime, triggered cascades & depth tracking | `common/downtime.c` |
| **Status File Persistence** | **Status Data Engine (`StatusDataParser`)** parser & serializer runtime `status.dat` (host/service status, comments, downtimes) | `common/statusdata.c` & `xdata/xsddefault.c` |
| **Comments & Annotations** | **Comments Manager (`CommentsManager`)** pelacakan catatan user, downtime, flapping, & ACK persistent | `common/comments.c` |
| **SLA & Uptime Intelligence** | **Availability Calculator (`AvailabilityCalculator`)** komputasi SLA % presisi, diskon jendela maintenance, & batas kepatuhan | `cgi/avail.c` |
| **Alert Histogram & Analytics** | **Alert Histogram Calculator (`AlertHistogramCalculator`)** distribusi alert 24-jam, deteksi jam puncak, & pemetaan sumber insiden | `cgi/histogram.c` & `cgi/summary.c` |
| **Object Definitions Engine** | **Object Configuration Parser (`ObjectConfigParser`)** parser `define` blocks (.cfg), resolusi pewarisan template (`use`), & serialisasi | `common/objects.c` & `xdata/xodtemplate.c` |
| **Access Control & RBAC** | **CGI Auth & Permissions Manager (`CgiAuthManager`)** otorisasi contact-level, hak eksekusi perintah, & profil read-only | `cgi/cgiauth.c` |
| **Archive Log & Event History** | **Archive Log Parser (`ArchiveLogParser`)** parser log historis terotasi, ekstraksi alert, notifikasi, downtime & flapping | `cgi/archiveutils.c` & `cgi/showlog.c` |
| **Network Topology & Layout** | **Network Topology Engine (`NetworkTopologyBuilder`)** relasi hierarki parent-child, kalkulasi kedalaman tier & graf DAG | `cgi/statusmap.c` |
| **Tactical Overview & Health** | **Tactical Overview Aggregator (`TacticalOverviewAggregator`)** bird's-eye unhandled vs acknowledged problems, downtime suppression, & gauge health scores | `cgi/tac.c` |
| **Network Outages & RCA** | **Blocking Outage Analyzer (`BlockingOutageAnalyzer`)** penelusuran graf dependensi hierarkis, pemisahan root blocker vs kegagalan turunan, & skor keparahan | `cgi/outages.c` |
| **Historical State Trends** | **State Trends Calculator (`TrendsCalculator`)** kalkulasi durasi kumulatif status (OK/WARN/CRIT), MTTR, bucket harian & availability % | `cgi/trends.c` |
| **Check Scheduling Queue** | **Check Scheduling Queue (`CheckSchedulingQueue`)** antrean eksekusi host/service check, sorting multi-kriteria, metrik sebaran waktu & deteksi check storm | `cgi/extinfo.c` & `base/events.c` |
| **Alert Summary & Producers** | **Alert Summary Aggregator (`AlertSummaryAggregator`)** top incident producers, agregasi HARD vs SOFT, rasio share insiden & ringkasan 24 jam | `cgi/summary.c` |
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
