import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { interval: Number }

  connect() {
    const intervalMs = this.intervalValue || 10000
    this.timer = setInterval(() => {
      if (typeof Turbo !== "undefined") {
        Turbo.visit(window.location.href, { action: "replace" })
      }
    }, intervalMs)
  }

  disconnect() {
    if (this.timer) {
      clearInterval(this.timer)
    }
  }
}
