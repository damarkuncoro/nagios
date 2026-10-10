import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "input", "resultsContainer", "emptyState"]

  connect() {
    this.boundKeyDown = this.handleKeyDown.bind(this)
    window.addEventListener("keydown", this.boundKeyDown)
    this.items = []
    this.selectedIndex = -1
    this.loadData()
  }

  disconnect() {
    window.removeEventListener("keydown", this.boundKeyDown)
  }

  handleKeyDown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "k") {
      event.preventDefault()
      this.toggle()
    } else if (event.key === "Escape" && !this.modalTarget.classList.contains("hidden")) {
      event.preventDefault()
      this.close()
    } else if (!this.modalTarget.classList.contains("hidden")) {
      if (event.key === "ArrowDown") {
        event.preventDefault()
        this.navigateResults(1)
      } else if (event.key === "ArrowUp") {
        event.preventDefault()
        this.navigateResults(-1)
      } else if (event.key === "Enter") {
        event.preventDefault()
        this.selectCurrent()
      }
    }
  }

  open() {
    this.modalTarget.classList.remove("hidden")
    this.inputTarget.value = ""
    this.selectedIndex = -1
    this.filter()
    setTimeout(() => this.inputTarget.focus(), 50)
  }

  close() {
    this.modalTarget.classList.add("hidden")
  }

  toggle() {
    if (this.modalTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  closeOnBackdrop(event) {
    if (event.target === this.modalTarget) {
      this.close()
    }
  }

  async loadData() {
    // Static navigation items
    const staticPages = [
      { type: "Page", title: "Tactical Overview", subtitle: "Monitoring health overview", url: "/tactical", icon: "📊" },
      { type: "Page", title: "Network Map", subtitle: "Topology graph and relationships", url: "/statusmap", icon: "🗺️" },
      { type: "Page", title: "Unhandled Problems", subtitle: "Unacknowledged host & service alerts", url: "/problems", icon: "⚠️" },
      { type: "Page", title: "Network Outages", subtitle: "Root cause failure and impacted downstream services", url: "/outages", icon: "🌐" },
      { type: "Page", title: "Host Groups", subtitle: "Groupings of host machines", url: "/hostgroups", icon: "🖥️" },
      { type: "Page", title: "Service Groups", subtitle: "Groupings of services", url: "/servicegroups", icon: "📦" },
      { type: "Page", title: "Availability SLA", subtitle: "Uptime and SLA reports", url: "/availability", icon: "⏱️" },
      { type: "Page", title: "Trends & Daily Health", subtitle: "State histories and metrics", url: "/trends", icon: "📈" },
      { type: "Page", title: "Alert Totals Summary", subtitle: "Historic alert counts", url: "/summary", icon: "📑" },
      { type: "Page", title: "Alert History", subtitle: "Log of state changes and notifications", url: "/alerts", icon: "🔔" },
      { type: "Page", title: "Notifications History", subtitle: "Audit trail of sent notification alerts", url: "/notifications", icon: "📬" },
      { type: "Page", title: "Live Event Log", subtitle: "Real-time daemon log stream from nagios.log", url: "/logs", icon: "📜" },
      { type: "Page", title: "Scheduling Queue", subtitle: "Upcoming active checks", url: "/queue", icon: "⏳" },
      { type: "Page", title: "Comments Manager", subtitle: "User and downtime comments", url: "/comments", icon: "💬" },
      { type: "Page", title: "Downtimes Manager", subtitle: "Scheduled maintenance windows", url: "/downtimes", icon: "🛑" },
      { type: "Page", title: "Process Info", subtitle: "Nagios daemon statistics and options", url: "/process_info", icon: "⚙️" },
      { type: "Page", title: "Performance Info", subtitle: "Check execution latency metrics", url: "/perf_info", icon: "⚡" },
      { type: "Page", title: "Configuration Viewer", subtitle: "Parsed commands and contacts", url: "/configuration", icon: "🔧" },
      { type: "API", title: "Prometheus Metrics (/metrics)", subtitle: "OpenMetrics scrape stream", url: "/metrics", icon: "⚡" },
      { type: "API", title: "Objects JSON API", subtitle: "objectjson.cgi configuration endpoints", url: "/api/v1/objects", icon: "🔌" },
      { type: "API", title: "Archives JSON API", subtitle: "archivejson.cgi audit & log endpoints", url: "/api/v1/archives", icon: "📁" }
    ]

    try {
      const response = await fetch("/api/v1/status")
      if (response.ok) {
        const data = await response.json()
        const dynamicItems = []

        if (data.hosts) {
          data.hosts.forEach(h => {
            dynamicItems.push({
              type: "Host",
              title: h.name,
              subtitle: `Status: ${h.status} | Output: ${h.plugin_output || '-'}`,
              url: `/hosts/${encodeURIComponent(h.name)}`,
              icon: "🖥️",
              badge: h.status
            })
          })
        }

        if (data.services) {
          data.services.forEach(s => {
            dynamicItems.push({
              type: "Service",
              title: `${s.host_name} / ${s.description}`,
              subtitle: `Status: ${s.status} | ${s.plugin_output || '-'}`,
              url: `/hosts/${encodeURIComponent(s.host_name)}`,
              icon: "⚙️",
              badge: s.status
            })
          })
        }

        this.items = [...staticPages, ...dynamicItems]
      } else {
        this.items = staticPages
      }
    } catch (e) {
      this.items = staticPages
    }
  }

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()
    let filtered = []

    if (query === "") {
      filtered = this.items.slice(0, 8)
    } else {
      filtered = this.items.filter(item => {
        return (
          item.title.toLowerCase().includes(query) ||
          item.subtitle.toLowerCase().includes(query) ||
          item.type.toLowerCase().includes(query)
        )
      }).slice(0, 15)
    }

    this.renderResults(filtered)
  }

  renderResults(results) {
    this.resultsContainerTarget.innerHTML = ""
    this.selectedIndex = results.length > 0 ? 0 : -1

    if (results.length === 0) {
      this.emptyStateTarget.classList.remove("hidden")
      return
    }

    this.emptyStateTarget.classList.add("hidden")

    results.forEach((item, index) => {
      const el = document.createElement("a")
      el.href = item.url
      el.className = `flex items-center justify-between p-3 rounded-lg text-sm transition cursor-pointer ${
        index === this.selectedIndex
          ? "bg-indigo-50 dark:bg-indigo-900/40 text-indigo-700 dark:text-indigo-300"
          : "hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-200"
      }`
      el.dataset.index = index

      const badgeHtml = item.badge
        ? `<span class="px-2 py-0.5 rounded text-[10px] font-bold ${
            item.badge === "OK" || item.badge === "UP"
              ? "bg-emerald-100 text-emerald-800 dark:bg-emerald-950 dark:text-emerald-300"
              : item.badge === "WARNING"
              ? "bg-amber-100 text-amber-800 dark:bg-amber-950 dark:text-amber-300"
              : "bg-rose-100 text-rose-800 dark:bg-rose-950 dark:text-rose-300"
          }">${item.badge}</span>`
        : `<span class="text-[11px] font-medium text-slate-400 dark:text-slate-500">${item.type}</span>`

      el.innerHTML = `
        <div class="flex items-center gap-3 min-w-0">
          <span class="text-base">${item.icon}</span>
          <div class="truncate">
            <p class="font-medium truncate">${this.highlightMatch(item.title, this.inputTarget.value)}</p>
            <p class="text-xs text-slate-500 dark:text-slate-400 truncate">${item.subtitle}</p>
          </div>
        </div>
        <div class="shrink-0 ml-3">
          ${badgeHtml}
        </div>
      `

      el.addEventListener("mouseenter", () => {
        this.selectedIndex = index
        this.updateSelectionStyles()
      })

      this.resultsContainerTarget.appendChild(el)
    })
  }

  highlightMatch(text, query) {
    if (!query) return text
    const regex = new RegExp(`(${query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")})`, "gi")
    return text.replace(regex, `<mark class="bg-amber-200 dark:bg-amber-800/80 text-inherit rounded px-0.5">$1</mark>`)
  }

  navigateResults(direction) {
    const items = this.resultsContainerTarget.querySelectorAll("a")
    if (items.length === 0) return

    this.selectedIndex = (this.selectedIndex + direction + items.length) % items.length
    this.updateSelectionStyles()
    items[this.selectedIndex].scrollIntoView({ block: "nearest" })
  }

  updateSelectionStyles() {
    const items = this.resultsContainerTarget.querySelectorAll("a")
    items.forEach((item, idx) => {
      if (idx === this.selectedIndex) {
        item.className = "flex items-center justify-between p-3 rounded-lg text-sm transition cursor-pointer bg-indigo-50 dark:bg-indigo-900/40 text-indigo-700 dark:text-indigo-300"
      } else {
        item.className = "flex items-center justify-between p-3 rounded-lg text-sm transition cursor-pointer hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-700 dark:text-slate-200"
      }
    })
  }

  selectCurrent() {
    const items = this.resultsContainerTarget.querySelectorAll("a")
    if (this.selectedIndex >= 0 && items[this.selectedIndex]) {
      items[this.selectedIndex].click()
    }
  }
}
