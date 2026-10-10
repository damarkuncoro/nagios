import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["badge", "select"]
  static values = {
    interval: { type: Number, default: 30 },
    autoStart: { type: Boolean, default: true }
  }

  connect() {
    const saved = localStorage.getItem("nagios_auto_refresh_sec")
    if (saved !== null) {
      this.currentInterval = parseInt(saved, 10)
    } else {
      this.currentInterval = this.intervalValue
    }

    this.remainingSec = this.currentInterval

    if (this.hasSelectTarget) {
      this.selectTarget.value = this.currentInterval.toString()
    }

    if (this.autoStartValue && this.currentInterval > 0) {
      this.startTimer()
    } else {
      this.updateDisplay()
    }
  }

  disconnect() {
    this.stopTimer()
  }

  changeInterval(event) {
    const val = parseInt(event.target.value, 10)
    this.currentInterval = isNaN(val) ? 0 : val
    this.remainingSec = this.currentInterval
    localStorage.setItem("nagios_auto_refresh_sec", this.currentInterval.toString())

    this.stopTimer()
    if (this.currentInterval > 0) {
      this.startTimer()
    } else {
      this.updateDisplay()
    }
  }

  toggle() {
    if (this.currentInterval > 0) {
      this.prevInterval = this.currentInterval
      this.setNewInterval(0)
    } else {
      this.setNewInterval(this.prevInterval || 30)
    }
  }

  setNewInterval(val) {
    this.currentInterval = val
    this.remainingSec = val
    localStorage.setItem("nagios_auto_refresh_sec", val.toString())
    if (this.hasSelectTarget) {
      this.selectTarget.value = val.toString()
    }
    this.stopTimer()
    if (val > 0) {
      this.startTimer()
    } else {
      this.updateDisplay()
    }
  }

  startTimer() {
    this.stopTimer()
    this.updateDisplay()

    this.timer = setInterval(() => {
      this.remainingSec -= 1
      if (this.remainingSec <= 0) {
        this.remainingSec = this.currentInterval
        if (typeof Turbo !== "undefined") {
          Turbo.visit(window.location.href, { action: "replace" })
        } else {
          window.location.reload()
        }
      } else {
        this.updateDisplay()
      }
    }, 1000)
  }

  stopTimer() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  updateDisplay() {
    if (!this.hasBadgeTarget) return

    if (this.currentInterval <= 0) {
      this.badgeTarget.textContent = "Paused"
      this.badgeTarget.className = "text-[11px] font-mono font-medium text-slate-400 dark:text-slate-500"
    } else {
      this.badgeTarget.textContent = `${this.remainingSec}s`
      this.badgeTarget.className = "text-[11px] font-mono font-bold text-indigo-600 dark:text-indigo-400"
    }
  }
}
