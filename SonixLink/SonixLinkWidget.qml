import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null

    readonly property string host: (pluginData.host || "").trim()
    readonly property int pollMs: Math.max(1, parseInt(pluginData.pollSeconds) || 3) * 1000
    readonly property string baseUrl: host !== "" ? "http://" + host + ":7800" : ""

    // mutable: re-read from pluginData on every refresh() so slider changes
    // apply within one poll cycle even if pluginData emits no change signal
    property int titleMaxWidth: 340

    readonly property bool online: alive
    property bool alive: false
    property string playerState: ""
    property string trackTitle: ""
    property string trackArtist: ""
    property string playMode: "normal"

    readonly property bool playing: playerState.toLowerCase() === "playing"
    readonly property string modeIcon: playMode === "repeat_all" ? "repeat"
                                     : playMode === "repeat_one" ? "repeat_one"
                                     : playMode.indexOf("shuffle") >= 0 ? "shuffle"
                                     : "arrow_forward"
    readonly property var modes: ["normal", "repeat_all", "repeat_one", "shuffle", "shuffle_repeat"]

    // the string shown in the horizontal pill
    readonly property string pillText: root.trackTitle !== ""
        ? (root.trackArtist !== "" ? root.trackTitle + " – " + root.trackArtist : root.trackTitle)
        : (root.host === "" ? "SonixLink: set player IP in settings"
         : (root.alive ? "Sonix Player" : "SonixLink: offline"))

    // measure the pill text OUTSIDE the visual tree: StyledText's implicitWidth
    // reflects elided painted width, so binding its width to Math.min(implicitWidth, cap)
    // creates a feedback loop that collapses the text. TextMetrics gives the stable
    // natural advance width, which the BarPill container reads via implicitWidth.
    TextMetrics {
        id: pillMetrics
        font.pixelSize: root.textSize || Theme.fontSizeMedium
        text: root.pillText
    }
    readonly property real pillTextWidth: Math.min(pillMetrics.advanceWidth, root.titleMaxWidth)

    function api(method, suffix, cb) {
        if (baseUrl === "") {
            alive = false
            return
        }
        var xhr = new XMLHttpRequest()
        xhr.open(method, baseUrl + suffix)
        xhr.timeout = 4000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status === 200) {
                alive = true
                if (cb) {
                    try { cb(JSON.parse(xhr.responseText)) } catch (e) {}
                }
            } else {
                alive = false
            }
        }
        xhr.ontimeout = function() { alive = false }
        xhr.onerror = function() { alive = false }
        try { xhr.send() } catch (e) { alive = false }
    }

    function refresh() {
        titleMaxWidth = Math.max(80, parseInt(pluginData.titleMaxWidth) || 340)
        api("GET", "/api/state", function(s) {
            playerState = (typeof s.state === "number") ? (s.state === 1 ? "playing" : "paused") : (s.state || "")
            trackTitle = s.title || ""
            trackArtist = s.artist || ""
            if (s.mode) playMode = s.mode
        })
    }

    function command(doSuffix) {
        api("POST", "/api/command?do=" + doSuffix, null)
        refreshLater.restart()
    }

    function cycleMode() {
        var i = modes.indexOf(playMode)
        if (i < 0) i = 0
        command("mode&value=" + modes[(i + 1) % modes.length])
    }

    function openPanel(x, y, width, section, screen) {
        popoutService?.toggleDankDash("plugin_" + pluginId, x, y, width, section, screen)
    }

    Timer {
        id: refreshLater
        interval: 400
        onTriggered: root.refresh()
    }

    Timer {
        interval: root.pollMs
        running: root.baseUrl !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    pillClickAction: (x, y, width, section, screen) => root.openPanel(x, y, width, section, screen)

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.online ? "music_note" : "music_off"
                size: root.iconSize || Theme.iconSize
                color: root.online ? Theme.primary : Theme.widgetIconColor
            }

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "skip_previous"
                size: root.iconSize || Theme.iconSize
                color: Theme.widgetIconColor

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.command("prev")
                }
            }

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.playing ? "pause" : "play_arrow"
                size: root.iconSize || Theme.iconSize
                color: root.online ? Theme.primary : Theme.widgetIconColor

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.command("toggle")
                }
            }

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "skip_next"
                size: root.iconSize || Theme.iconSize
                color: Theme.widgetIconColor

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.command("next")
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: root.pillTextWidth
                text: root.pillText
                font.pixelSize: root.textSize || Theme.fontSizeMedium
                color: Theme.widgetTextColor
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: root.modeIcon
                size: root.iconSize || Theme.iconSize
                visible: root.online
                color: Theme.widgetIconColor

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cycleMode()
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXXS

            DIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: root.playing ? "pause" : "play_arrow"
                size: root.iconSize || Theme.iconSize
                color: root.online ? Theme.primary : Theme.widgetIconColor

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.command("toggle")
                }
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.trackTitle !== "" ? root.trackTitle : "SonixLink"
                font.pixelSize: root.textSize || Theme.fontSizeSmall
                color: Theme.widgetTextColor
                elide: Text.ElideMiddle
                maximumLineCount: 1
                width: Math.min(paintedWidth, root.titleMaxWidth)
            }
        }
    }
}
