import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Retro Diffusion usage in the bar: plan usage left (or balance) next to a
// palette glyph, with a popup laid out as a Plan section and a Balance
// section, then the jobs running right now.
Panel {
  id: root
  moduleName: "io.github.lviit.retro-diffusion"
  ipcTarget: "io.github.lviit.retro-diffusion"
  manageIpc: false

  readonly property string siteUrl: "https://www.retrodiffusion.ai/"
  // Where the web app's own "Manage plan" button goes.
  readonly property string planUrl: "https://retrodiffusion.ai/app/balance#plans"
  readonly property string iconGlyph: "󰏘"      // nf-md-palette
  readonly property string refreshGlyph: "󰑐"   // nf-md-refresh
  readonly property string openGlyph: "󰏌"      // nf-md-open_in_new
  readonly property string manageGlyph: "󰘮"    // nf-md-tune

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var info: service.info
  readonly property var plan: info ? info.plan : null
  readonly property bool hasPlan: Model.planActive(info)
  readonly property bool low: Model.isLow(info, service.intSetting("lowPlanPct", 10, 0, 100))
  readonly property string barMode: String(setting("barValue", "plan"))
  readonly property bool showLabel: setting("showLabel", true) !== false && !vertical
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property string labelText: showLabel ? Model.barText(info, barMode, fmt) : ""

  function fmt(value, decimals) { return Commons.I18n.formatNumber(value, decimals) }

  function formatDate(ms) {
    if (!ms) return "—"
    return new Date(ms).toLocaleDateString(Qt.locale(Commons.I18n.formatLocale), "MMM d, yyyy")
  }

  function formatTime(ms) {
    if (!ms) return "—"
    return new Date(ms).toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), "HH:mm")
  }

  function slotsText(s) {
    if (!s) return "—"
    return strings.t("slots", "%1 of %2").arg(fmt(s.inUse, 0)).arg(fmt(s.limit, 0))
  }

  function openSite() {
    Qt.openUrlExternally(siteUrl)
  }

  // Refresh this bar's copy. fetch.sh caches for a few seconds, so when every
  // monitor's bar does this at once only the first one hits the API.
  function refreshLocal() {
    service.refresh(5)
  }

  // A manual refresh updates the widget on every monitor, not just this one.
  function refreshAll() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    if (!items || items.length === 0) items = [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i].refreshLocal === "function") items[i].refreshLocal()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    service.refresh()
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  Service {
    id: service
    settings: root.settings
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshAll(); return "ok" }
    // English on purpose: IPC output is for scripts and logs.
    function status(): string {
      if (!root.info) return service.errorKey !== "" ? service.errorKey : "loading"  // i18n: ignore
      var parts = []
      if (root.hasPlan) parts.push(root.plan.name + " " + root.plan.usageLeftPct + "% left")  // i18n: ignore
      parts.push("balance $" + Number(root.info.balance).toFixed(2))  // i18n: ignore
      return parts.join(", ")
    }
  }

  TextMetrics {
    id: labelMetrics
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    text: root.labelText
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconGlyph
    labelText: root.labelText
    foreground: root.low ? root.urgent : root.barForeground
    dimmed: !root.info
    fixedWidth: root.vertical
      ? -1
      : (root.labelText !== ""
          ? Math.ceil(canvasSize + labelMetrics.advanceWidth + Style.space(4) + scaledHorizontalMargin * 2)
          : slotSize)
    tooltipText: ""

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openSite()
      else if (buttonCode === Qt.MiddleButton) root.refreshAll()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(520))

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshAll()
        else if (t === "o" || t === "O") root.openSite()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: strings.t("title", "Retro Diffusion")
          meta: service.busy
            ? strings.t("updating", "Updating…")
            : (service.updatedAt ? strings.t("updated", "Updated %1").arg(root.formatTime(service.updatedAt)) : "")
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: root.iconGlyph
              color: root.low ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
          // The plan badge sits here, beside the refresh button, rather than
          // in PanelHero's `detail` slot: that slot rides the title line,
          // while the trailing control is centred on the whole hero, so the
          // two never lined up.
          trailingControl: Component {
            Row {
              spacing: Style.space(8)

              BorderSurface {
                visible: root.hasPlan
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: planBadge.implicitWidth + Style.space(10)
                implicitHeight: planBadge.implicitHeight + Style.space(4)
                color: "transparent"
                borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)
                radius: Style.cornerRadius

                Text {
                  id: planBadge
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.hasPlan ? root.plan.name : ""
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }

              PanelActionButton {
                anchors.verticalCenter: parent.verticalCenter
                iconText: root.refreshGlyph
                tooltipText: strings.t("action.refresh", "Refresh (R)")
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !service.busy
                onClicked: root.refreshAll()
              }
            }
          }
        }

        Body {
          visible: service.errorKey !== ""
          text: strings.t(service.errorKey, "")
          color: root.info ? root.dim : root.urgent
        }

        Body {
          visible: !root.info && service.errorKey === ""
          text: strings.t("loading", "Loading…")
        }

        // ── Plan ──────────────────────────────────────────────
        Column {
          visible: root.hasPlan
          width: parent.width
          spacing: Style.space(6)

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Heading {
              Layout.fillWidth: true
              text: root.hasPlan ? strings.t("plan.title", "%1 plan").arg(root.plan.name) : ""
            }

            Text {
              textFormat: Text.PlainText
              text: root.hasPlan
                ? strings.t("plan.left", "%1 left").arg(Model.percent(root.plan.usageLeftPct, root.fmt))
                : ""
              color: root.low ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }

          Item {
            width: parent.width
            height: Style.space(6)

            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            }

            Rectangle {
              height: parent.height
              radius: height / 2
              width: root.hasPlan ? parent.width * root.plan.usageLeftPct / 100 : 0
              color: root.low ? root.urgent : root.foreground
              // Keeps a refresh from making the fill jump.
              Behavior on width {
                NumberAnimation { duration: Style.duration(200); easing.type: Easing.OutCubic }
              }
            }
          }

          Note {
            text: root.hasPlan
              ? (root.plan.cancelAtPeriodEnd
                  ? strings.t("plan.ends", "Ends %1")
                  : strings.t("plan.resets", "Resets %1")).arg(root.formatDate(root.plan.periodEndMs))
              : ""
          }

          Item { width: 1; height: Style.space(2) }

          Button {
            text: strings.t("action.managePlan", "Manage plan")
            iconText: root.manageGlyph
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: Qt.openUrlExternally(root.planUrl)
          }
        }

        PanelSeparator {
          visible: root.hasPlan
          foreground: root.foreground
        }

        // ── Balance ───────────────────────────────────────────
        Column {
          visible: !!root.info
          width: parent.width
          spacing: Style.space(6)

          Heading { text: strings.t("balance.title", "Balance") }

          Text {
            textFormat: Text.PlainText
            text: root.info ? Model.money(root.info.balance, root.fmt) : "—"
            color: !root.hasPlan && root.low ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Note {
            visible: !!root.info && root.info.spend30 !== null
            text: !root.info || root.info.spend30 === null ? ""
              : (root.hasPlan && root.plan.priceUsd !== null
                  ? strings.t("balance.spendPlan", "Your last 30 days would have cost %1 from balance. Your plan covered it for %2.")
                      .arg(Model.money(root.info.spend30, root.fmt))
                      .arg(Model.money(root.plan.priceUsd, root.fmt))
                  : strings.t("balance.spend", "Last 30 days at balance rates: %1.")
                      .arg(Model.money(root.info.spend30, root.fmt)))
          }

          Note {
            visible: root.hasPlan
            text: strings.t("balance.order", "Jobs use your plan usage first, then your balance.")
          }

          Item { visible: !root.hasPlan; width: 1; height: Style.space(2) }

          Button {
            visible: !root.hasPlan
            text: strings.t("action.open", "Open Retro Diffusion")
            iconText: root.openGlyph
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.openSite()
          }
        }

        PanelSeparator {
          visible: !!root.info
          foreground: root.foreground
        }

        // ── Running now ───────────────────────────────────────
        Note {
          visible: !!root.info
          text: root.info
            ? strings.t("running", "Running now: website %1 · API %2")
                .arg(root.slotsText(root.info.webSlots))
                .arg(root.slotsText(root.info.apiSlots))
            : ""
        }
      }
    }
  }

  component Heading: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
    elide: Text.ElideRight
  }

  component Body: Text {
    textFormat: Text.PlainText
    width: parent ? parent.width : implicitWidth
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  component Note: Text {
    textFormat: Text.PlainText
    width: parent ? parent.width : implicitWidth
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}
