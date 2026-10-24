import { Controller } from "@hotwired/stimulus"

// The one place that knows Chart.js: draws the Reports::Chart spec that
// Components::Statistics::Chart puts on this canvas. Colours arrive as
// token names ("series-1", "good") and are read from the --stat-* custom
// properties, so the palette lives in the stylesheet only.
export default class extends Controller {
  static values = { spec: Object }

  // A canvas can be disconnected, or connected again by a morph, while
  // Chart.js is still loading: only a canvas still on the page and not yet
  // drawn gets its chart.
  async connect() {
    try {
      await loadChartJs()
    } catch (error) {
      console.warn("[chart] Chart.js not loaded", error)
      return
    }
    if (this.chart || !this.element.isConnected) return

    this.draw()
  }

  // Destroyed with the canvas: Turbo keeps a page's elements in its cache,
  // and a chart left on one would draw again on a canvas nobody sees.
  disconnect() {
    this.chart?.destroy()
    this.chart = null
  }

  specValueChanged() {
    if (!this.chart) return

    this.chart.destroy()
    this.draw()
  }

  draw() {
    this.chart = new Chart(this.element, this.config())
  }

  config() {
    const spec = this.specValue
    const kind = spec.kind
    const datasets = spec.series.map((series) => this.dataset(series, kind))
    if (spec.target != null) datasets.push(this.targetDataset(spec))

    return {
      type: kind === "line" || kind === "sparkline" ? "line" : "bar",
      data: { labels: spec.labels, datasets },
      options: this.options(spec, datasets)
    }
  }

  dataset(series, kind) {
    const color = this.color(series.color)
    const colors = series.colors?.map((token) => this.color(token))

    if (kind === "line" || kind === "sparkline") {
      return {
        label: series.label,
        data: series.values,
        borderColor: color,
        backgroundColor: color,
        borderWidth: 2,
        tension: 0.25,
        spanGaps: false,
        pointRadius: kind === "sparkline" ? 0 : 3,
        pointHoverRadius: 5,
        pointHitRadius: 12
      }
    }

    return {
      label: series.label,
      data: series.values,
      backgroundColor: colors ?? color,
      borderColor: this.color("surface"),
      borderWidth: kind === "stacked_bar" ? { top: 2 } : 0,
      borderRadius: 4,
      borderSkipped: "start",
      maxBarThickness: 36
    }
  }

  targetDataset(spec) {
    return {
      label: spec.target_label,
      data: spec.labels.map(() => spec.target),
      borderColor: this.color("ink-muted"),
      borderWidth: 1,
      borderDash: [6, 4],
      pointRadius: 0,
      pointHitRadius: 0,
      target: true
    }
  }

  options(spec, datasets) {
    const sparkline = spec.kind === "sparkline"
    const horizontal = spec.kind === "horizontal_bar"
    const stacked = spec.kind === "stacked_bar"
    const valueAxis = horizontal ? "x" : "y"
    const categoryAxis = horizontal ? "y" : "x"
    const seriesCount = datasets.filter((dataset) => !dataset.target).length

    return {
      responsive: true,
      maintainAspectRatio: false,
      animation: this.reducedMotion ? false : { duration: 400 },
      indexAxis: horizontal ? "y" : "x",
      interaction: { mode: sparkline ? undefined : "index", intersect: false },
      events: sparkline ? [] : undefined,
      plugins: {
        legend: {
          display: !sparkline && seriesCount >= 2,
          position: "bottom",
          labels: {
            color: this.color("ink-secondary"),
            boxWidth: 12,
            boxHeight: 12,
            useBorderRadius: true,
            borderRadius: 3
          }
        },
        tooltip: {
          enabled: !sparkline,
          filter: (item) => !item.dataset.target,
          callbacks: { label: (item) => `${item.dataset.label}: ${this.format(item.raw, spec)}` }
        }
      },
      scales: sparkline
        ? { x: { display: false }, y: { display: false } }
        : {
            [categoryAxis]: {
              stacked,
              grid: { display: false },
              border: { color: this.color("axis") },
              ticks: { color: this.color("ink-muted"), maxRotation: 0, autoSkip: true, autoSkipPadding: 12 }
            },
            [valueAxis]: {
              stacked,
              beginAtZero: true,
              max: spec.format === "percent" ? 100 : undefined,
              grid: { color: this.color("grid") },
              border: { display: false },
              ticks: {
                color: this.color("ink-muted"),
                maxTicksLimit: 5,
                precision: spec.format === "count" ? 0 : undefined,
                callback: (value) => this.format(value, spec)
              }
            }
          }
    }
  }

  format(value, spec) {
    if (value == null) return "—"

    const locale = spec.locale
    switch (spec.format) {
      case "percent":
        return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(value)}%`
      case "money":
        return new Intl.NumberFormat(locale, {
          style: "currency",
          currency: spec.currency,
          maximumFractionDigits: 0
        }).format(value)
      case "days":
        return new Intl.NumberFormat(locale, { style: "unit", unit: "day", unitDisplay: "long" }).format(value)
      default:
        return new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(value)
    }
  }

  color(token) {
    return getComputedStyle(this.element).getPropertyValue(`--stat-${token}`).trim()
  }

  get reducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}

// Chart.js is fetched the first time a chart connects rather than with
// every page, since only the statistics draw one. A failed fetch is
// forgotten, so the next chart tries again.
let Chart = null
let chartJsLoading = null

function loadChartJs() {
  chartJsLoading ??= import("chart.js").then(
    (chartJs) => {
      chartJs.Chart.register(
        chartJs.BarController,
        chartJs.BarElement,
        chartJs.CategoryScale,
        chartJs.Legend,
        chartJs.LinearScale,
        chartJs.LineController,
        chartJs.LineElement,
        chartJs.PointElement,
        chartJs.Tooltip
      )
      Chart = chartJs.Chart
    },
    (error) => {
      chartJsLoading = null
      throw error
    }
  )
  return chartJsLoading
}
