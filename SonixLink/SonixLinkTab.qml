import QtQuick
import QtQuick.Controls as QC
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

DashTabComponent {
    id: root

    readonly property string host: (pluginData.host || "").trim()
    readonly property int pollMs: Math.max(1, parseInt(pluginData.pollSeconds) || 3) * 1000
    readonly property string baseUrl: host !== "" ? "http://" + host + ":7800" : ""

    readonly property bool online: alive
    property bool alive: false
    property int view: 0
    property string playerState: ""
    property string trackPath: ""
    property string trackTitle: ""
    property string trackArtist: ""
    property string trackAlbum: ""
    property real position: 0
    property real duration: 0
    property real volume: 0
    property string playMode: "normal"
    property var queueModel: []
    property int queuePos: -1
    property bool fav: false
    property int artRetries: 0

    // paths whose /api/art 404'd — never request them again (until reload)
    property var artDead: ({})

    property string browsePath: ""
    property var browseModel: []
    property var crumbs: []
    property var favModel: []
    property var favPaths: []

    readonly property bool playing: playerState.toLowerCase() === "playing"
    readonly property var modes: ["normal", "repeat_all", "repeat_one", "shuffle", "shuffle_repeat"]
    readonly property string modeIconName: playMode === "repeat_all" ? "repeat"
                                          : playMode === "repeat_one" ? "repeat_one"
                                          : playMode.indexOf("shuffle") >= 0 ? "shuffle"
                                          : "arrow_forward"
    readonly property string artUrl: (baseUrl !== "" && trackPath !== "")
        ? baseUrl + "/api/art?path=" + encodeURIComponent(trackPath) + "&max=400"
        : ""
    readonly property string queueLen: queueModel.length > 0 ? String(queueModel.length) : ""

    readonly property var navItems: [
        { label: "Play", icon: "play_circle" },
        { label: "Browse", icon: "folder_open" },
        { label: "Favourites", icon: "favorite" }
    ]

    function fmtTime(sec) {
        sec = Math.max(0, Math.floor(sec || 0))
        return Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0")
    }

    function baseName(p) {
        var i = p.lastIndexOf("/")
        return i >= 0 ? p.substring(i + 1) : p
    }

    function toList(v) {
        if (Array.isArray(v)) return v
        if (v && typeof v === "object") {
            if (Array.isArray(v.favourites)) return v.favourites
            if (Array.isArray(v.paths)) return v.paths
            if (Array.isArray(v.items)) return v.items
            if (Array.isArray(v.tracks)) return v.tracks
            if (Array.isArray(v.entries)) return v.entries
        }
        return []
    }

    // returns an art URL, or "" if this path already failed once
    function artFor(path, max) {
        if (baseUrl === "" || path === "")
            return ""
        return root.artDead[path] ? "" : baseUrl + "/api/art?path=" + encodeURIComponent(path) + "&max=" + max
    }

    function markArtDead(url) {
        if (url !== "")
            root.artDead[url] = true
    }

    function api(method, suffix, cb) {
        if (baseUrl === "") {
            alive = false
            return
        }
        var xhr = new XMLHttpRequest()
        xhr.open(method, baseUrl + suffix)
        xhr.timeout = 5000
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status === 200) {
                alive = true
                if (cb) {
                    try { cb(xhr.responseText) } catch (e) {}
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
        api("GET", "/api/state", function(txt) {
            var s = JSON.parse(txt)
            playerState = (typeof s.state === "number") ? (s.state === 1 ? "playing" : "paused") : (s.state || "")
            trackPath = s.path || ""
            trackTitle = s.title || ""
            trackArtist = s.artist || ""
            trackAlbum = s.album || ""
            position = s.position || 0
            duration = s.duration || 0
            volume = s.volume || 0
            if (s.mode) playMode = s.mode
            fav = trackPath !== "" && favPaths.indexOf(trackPath) >= 0
        })
        api("GET", "/api/queue?from=0", function(txt) {
            queueModel = toList(JSON.parse(txt)).map(function(q) {
                if (typeof q === "string") return q
                return q.path || q.file || q.name || ""
            }).filter(function(p) { return p !== "" })
        })
        api("GET", "/api/favourites", function(txt) {
            var nm = toList(JSON.parse(txt)).map(function(f) {
                if (typeof f === "string")
                    return { path: f, name: "", artist: "" }
                return {
                    path: f.path || f.file || "",
                    name: f.name || "",
                    artist: f.artist || ""
                }
            }).filter(function(f) { return f.path !== "" })
            var np = nm.map(function(f) { return f.path })
            // only swap the model when it actually changed — reassigning
            // rebuilds every ListView delegate and re-requests all art
            if (np.join("\n") !== favPaths.join("\n")) {
                favModel = nm
                favPaths = np
            }
            fav = trackPath !== "" && favPaths.indexOf(trackPath) >= 0
        })
    }

    function browse(path) {
        var url = "/api/browse" + (path !== "" ? "?path=" + encodeURIComponent(path) : "")
        api("GET", url, function(txt) {
            var r = JSON.parse(txt)
            browsePath = r.path || ""
            browseModel = toList(r.entries || r.items).map(function(e) {
                if (typeof e === "string")
                    return { name: baseName(e), path: e, dir: e.lastIndexOf("/") === e.length - 1 }
                return { name: e.name || baseName(e.path || ""), path: e.path || "", dir: !!e.dir }
            })
            var c = []
            var acc = ""
            var parts = browsePath.split("/")
            for (var i = 0; i < parts.length; i++) {
                if (parts[i] === "") continue
                acc += "/" + parts[i]
                c.push({ name: parts[i], path: acc })
            }
            crumbs = c
        })
    }

    function playTrack(path) {
        command("play_path&path=" + encodeURIComponent(path))
    }

    function enqueueTrack(path) {
        if (baseUrl === "") return
        var xhr = new XMLHttpRequest()
        xhr.open("POST", baseUrl + "/api/command?do=queue_next")
        xhr.setRequestHeader("Content-Type", "text/plain")
        xhr.send(path + "\n")
        refreshLater.restart()
    }

    function command(doSuffix) {
        api("POST", "/api/command?do=" + doSuffix, null)
        refreshLater.restart()
    }

    function seekTo(sec) {
        command("seek&value=" + Math.round(sec))
    }

    function setVolume(v) {
        command("volume&value=" + Math.round(v))
    }

    Timer {
        id: refreshLater
        interval: 400
        onTriggered: root.refresh()
    }

    Timer {
        interval: root.pollMs
        running: root.baseUrl !== "" && root.live
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Column {
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingM

        // ================= shell-style tab nav (compact) =================
        Item {
            id: navBar
            width: parent.width
            height: 52

            Row {
                anchors.fill: parent
                spacing: 0

                Repeater {
                    model: root.navItems

                    Item {
                        width: navBar.width / 3
                        height: navBar.height

                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 36
                                height: 28
                                radius: Theme.fullRadius(width, height)
                                color: root.view === index ? Theme.primaryContainer : "transparent"

                                DIcon {
                                    anchors.centerIn: parent
                                    name: modelData.icon
                                    size: Theme.iconSizeSmall
                                    color: root.view === index ? Theme.primary : Theme.onSurfaceVariant
                                }
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.view === index ? Theme.surfaceText : Theme.onSurfaceVariant
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.view !== index) {
                                    root.view = index
                                    if (index === 1 && root.browseModel.length === 0) root.browse("")
                                    if (index === 2) root.refresh()
                                }
                            }
                        }
                    }
                }
            }
        }

        // offline notice
        DCard {
            width: parent.width
            height: offlineText.implicitHeight + Theme.spacingXL * 2
            visible: root.baseUrl !== "" && !root.alive

            Column {
                anchors.centerIn: parent
                spacing: Theme.spacingM

                DIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "cloud_off"
                    size: 40
                    color: Theme.outline
                }

                StyledText {
                    id: offlineText
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - Theme.spacingXL * 4
                    text: "Player unreachable at " + root.host + ":7800. Check the R1 is awake, on Wi-Fi, with Wireless → SonixLink enabled."
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.onSurfaceVariant
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // =============== VIEW 0: PLAY (compact) ===============
        Column {
            width: parent.width
            height: parent.height - navBar.height - Theme.spacingM
            spacing: Theme.spacingM
            visible: root.alive && root.view === 0

            // ---- compact player card ----
            DCard {
                id: playerCard
                width: parent.width
                height: playerColumn.height + Theme.spacingM * 2

                Column {
                    id: playerColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    // top row: small art | title/artist
                    Row {
                        width: parent.width
                        spacing: Theme.spacingM

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64
                            height: 64
                            radius: Theme.fullRadius(width, height)
                            color: Theme.surfaceContainerHigh
                            clip: true

                            Image {
                                id: art
                                anchors.fill: parent
                                anchors.margins: 2
                                fillMode: Image.PreserveAspectCrop
                                source: root.artUrl
                                asynchronous: true
                                visible: status === Image.Ready
                                onStatusChanged: {
                                    if (status === Image.Error && root.artRetries < 4) {
                                        root.artRetries++
                                        artRetryTimer.restart()
                                    } else if (status === Image.Ready) {
                                        root.artRetries = 0
                                    }
                                }
                            }

                            Timer {
                                id: artRetryTimer
                                interval: 2000
                                onTriggered: art.source = root.artUrl
                            }

                            DIcon {
                                anchors.centerIn: parent
                                name: "album"
                                size: 24
                                visible: art.status !== Image.Ready
                                color: Theme.outline
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 64 - Theme.spacingM * 2 - 40
                            spacing: 0

                            StyledText {
                                width: parent.width
                                text: root.trackTitle || "Nothing playing"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            StyledText {
                                width: parent.width
                                text: root.trackArtist || ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.onSurfaceVariant
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        // favourite heart
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32

                            DIcon {
                                anchors.centerIn: parent
                                name: root.fav ? "favorite" : "favorite_border"
                                size: Theme.iconSizeSmall
                                color: root.fav ? Theme.primary : Theme.outline
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.trackPath !== "")
                                        root.command("favourite&path=" + encodeURIComponent(root.trackPath) + "&value=" + (root.fav ? 0 : 1))
                                }
                            }
                        }
                    }

                    // seek slider
                    Column {
                        width: parent.width
                        spacing: 0

                        QC.Slider {
                            id: seekSlider
                            width: parent.width
                            from: 0
                            to: Math.max(1, root.duration)
                            value: root.position
                            live: true
                            onMoved: root.seekTo(value)

                            background: Rectangle {
                                x: seekSlider.handle.width / 2
                                y: parent.height / 2 - height / 2
                                width: parent.availableWidth
                                height: 6
                                radius: Theme.fullRadius(width, height)
                                color: Theme.surfaceContainerHigh

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: seekSlider.visualPosition * parent.width
                                    radius: parent.radius
                                    color: Theme.primary
                                }
                            }

                            handle: Rectangle {
                                id: seekHandle
                                x: parent.visualPosition * (parent.availableWidth - width)
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14
                                radius: Theme.fullRadius(width, height)
                                color: Theme.primary
                                visible: seekSlider.hovered || seekSlider.pressed
                            }
                        }

                        Item {
                            width: parent.width
                            height: posText.implicitHeight

                            StyledText {
                                id: posText
                                anchors.left: parent.left
                                text: root.fmtTime(root.position)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.onSurfaceVariant
                            }

                            StyledText {
                                anchors.right: parent.right
                                text: root.fmtTime(root.duration)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.onSurfaceVariant
                            }
                        }
                    }

                    // transport + volume (single tight row)
                    Row {
                        spacing: Theme.spacingM
                        anchors.horizontalCenter: parent.horizontalCenter

                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            DIcon { anchors.centerIn: parent; name: root.modeIconName; size: Theme.iconSizeSmall; color: Theme.primary }
                            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                onClicked: { var i = root.modes.indexOf(root.playMode); if (i < 0) i = 0
                                    root.command("mode&value=" + root.modes[(i + 1) % root.modes.length]) } }
                        }

                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            DIcon { anchors.centerIn: parent; name: "shuffle"; size: Theme.iconSizeSmall;
                                color: root.playMode.indexOf("shuffle") >= 0 ? Theme.primary : Theme.outline }
                            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                onClicked: root.command("play_all&list=all&how=" + (root.playMode === "shuffle" ? "sequence" : "shuffle")) }
                        }

                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            DIcon { anchors.centerIn: parent; name: "skip_previous"; size: Theme.iconSizeSmall; color: Theme.surfaceText }
                            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.command("prev") }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 40
                            height: 40
                            radius: Theme.fullRadius(width, height)
                            color: Theme.primary

                            DIcon {
                                anchors.centerIn: parent
                                name: root.playing ? "pause" : "play_arrow"
                                size: Theme.iconSizeSmall
                                color: Theme.onPrimary
                            }

                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.command("toggle") }
                        }

                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            DIcon { anchors.centerIn: parent; name: "skip_next"; size: Theme.iconSizeSmall; color: Theme.surfaceText }
                            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.command("next") }
                        }

                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 28
                            height: 28
                            DIcon { anchors.centerIn: parent; name: "replay"; size: Theme.iconSizeSmall; color: Theme.outline }
                            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: root.command("scan") }
                        }

                        DIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.volume >= 50 ? "volume_up" : (root.volume > 0 ? "volume_down" : "volume_off")
                            size: Theme.iconSizeSmall
                            color: Theme.onSurfaceVariant

                            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                onClicked: root.setVolume(root.volume > 0 ? 0 : 40) }
                        }

                        QC.Slider {
                            id: volumeSlider
                            anchors.verticalCenter: parent.verticalCenter
                            width: 140
                            from: 0
                            to: 100
                            value: root.volume
                            live: true
                            onMoved: root.setVolume(value)

                            background: Rectangle {
                                x: volumeSlider.handle.width / 2
                                y: parent.height / 2 - height / 2
                                width: parent.availableWidth
                                height: 6
                                radius: Theme.fullRadius(width, height)
                                color: Theme.surfaceContainerHigh

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: volumeSlider.visualPosition * parent.width
                                    radius: parent.radius
                                    color: Theme.primary
                                }
                            }

                            handle: Rectangle {
                                id: volumeHandle
                                x: parent.visualPosition * (parent.availableWidth - width)
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14
                                radius: Theme.fullRadius(width, height)
                                color: Theme.primary
                                visible: volumeSlider.hovered || volumeSlider.pressed
                            }
                        }
                    }
                }
            }

            // ---- queue card (fills all remaining space) ----
            DCard {
                width: parent.width
                height: Math.max(110, parent.height - playerCard.height - Theme.spacingM)

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    Item {
                        id: queueHeader
                        width: parent.width
                        height: Math.max(queueIcon.height, queueTitle.height)

                        DIcon {
                            id: queueIcon
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            name: "queue_music"
                            size: Theme.iconSizeSmall
                            color: Theme.primary
                        }

                        StyledText {
                            id: queueTitle
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.iconSizeSmall + Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Queue"
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            text: root.queueLen !== "" ? root.queueLen + " tracks" : "empty"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.onSurfaceVariant
                        }
                    }

                    DListView {
                        width: parent.width
                        height: parent.height - queueHeader.height - Theme.spacingS
                        clip: true
                        spacing: Theme.spacingXXS
                        model: root.queueModel

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 28
                            radius: Theme.fullRadius(width, height)
                            color: index === root.queuePos ? Theme.primaryContainer : "transparent"

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingM
                                spacing: Theme.spacingM

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String(index + 1)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.onSurfaceVariant
                                    width: 26
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 54
                                    text: root.baseName(modelData)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: index === root.queuePos ? Theme.primary : Theme.surfaceText
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.command("queue_index&value=" + index)
                            }
                        }
                    }
                }
            }
        }

        // =============== VIEW 1: BROWSE ===============
        Item {
            width: parent.width
            height: parent.height - navBar.height - Theme.spacingM
            visible: root.alive && root.view === 1

            Column {
                anchors.fill: parent
                spacing: Theme.spacingM

                DCard {
                    width: parent.width
                    height: crumbRow.implicitHeight + Theme.spacingM
                    visible: root.baseUrl !== "" && root.alive

                    Row {
                        id: crumbRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "folder_open"
                            size: Theme.iconSizeSmall
                            color: Theme.primary
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Card"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.primary

                            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.browse("") }
                        }

                        Repeater {
                            model: root.crumbs

                            Row {
                                spacing: Theme.spacingXXS

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: " / "
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.outline
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.name
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: index === root.crumbs.length - 1 ? Font.Bold : Font.Normal
                                    color: index === root.crumbs.length - 1 ? Theme.surfaceText : Theme.primary
                                    elide: Text.ElideRight

                                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: root.browse(modelData.path) }
                                }
                            }
                        }
                    }
                }

                DListView {
                    width: parent.width
                    height: parent.height - (crumbRow.implicitHeight + Theme.spacingM + Theme.spacingM)
                    clip: true
                    spacing: Theme.spacingS
                    model: root.browseModel

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 56
                        radius: Theme.fullRadius(width, height)
                        color: Theme.surfaceContainer

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            spacing: Theme.spacingM

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44
                                height: 44
                                radius: Theme.fullRadius(width, height)
                                color: Theme.surfaceContainerHigh
                                clip: true

                                Image {
                                    id: browseArt
                                    anchors.fill: parent
                                    visible: !modelData.dir && status === Image.Ready
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    // empty source for dirs and for paths that
                                    // already 404'd — never request them twice
                                    source: modelData.dir ? "" : root.artFor(modelData.path, 100)
                                    onStatusChanged: if (status === Image.Error) root.markArtDead(source)
                                }

                                DIcon {
                                    anchors.centerIn: parent
                                    name: modelData.dir ? "folder" : "music_note"
                                    size: 22
                                    color: Theme.primary
                                    opacity: modelData.dir ? 1 : 0.4
                                    visible: modelData.dir || browseArt.status !== Image.Ready
                                }
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 210
                                text: modelData.name
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: modelData.dir ? Font.Medium : Font.Normal
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        Rectangle {
                            anchors.right: favAction.left
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36
                            height: 36
                            radius: Theme.fullRadius(width, height)
                            visible: !modelData.dir
                            color: Theme.surfaceContainerHigh

                            DIcon {
                                anchors.centerIn: parent
                                name: "playlist_add"
                                size: 18
                                color: Theme.surfaceText
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.enqueueTrack(modelData.path)
                            }
                        }

                        Rectangle {
                            id: favAction
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingM
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36
                            height: 36
                            radius: Theme.fullRadius(width, height)
                            visible: !modelData.dir
                            color: Theme.surfaceContainerHigh

                            DIcon {
                                anchors.centerIn: parent
                                name: root.favPaths.indexOf(modelData.path) >= 0 ? "favorite" : "favorite_border"
                                size: 18
                                color: root.favPaths.indexOf(modelData.path) >= 0 ? Theme.primary : Theme.surfaceText
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.command("favourite&path=" + encodeURIComponent(modelData.path) + "&value=" + (root.favPaths.indexOf(modelData.path) >= 0 ? 0 : 1))
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.rightMargin: !modelData.dir ? 92 : 0
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.dir) root.browse(modelData.path)
                                else root.playTrack(modelData.path)
                            }
                        }
                    }
                }
            }
        }

        // =============== VIEW 2: FAVOURITES ===============
        Item {
            width: parent.width
            height: parent.height - navBar.height - Theme.spacingM
            visible: root.alive && root.view === 2

            Column {
                anchors.fill: parent
                spacing: Theme.spacingM

                DCard {
                    width: parent.width
                    height: favCountText.implicitHeight + Theme.spacingL
                    visible: root.baseUrl !== "" && root.alive

                    StyledText {
                        id: favCountText
                        anchors.centerIn: parent
                        width: parent.width - Theme.spacingXL * 2
                        text: root.favModel.length > 0
                              ? root.favModel.length + " favourite" + (root.favModel.length === 1 ? "" : "s")
                              : "No favourites yet — tap the heart on a track in Browse."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onSurfaceVariant
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                DListView {
                    width: parent.width
                    height: parent.height - (favCountText.implicitHeight + Theme.spacingL + Theme.spacingM)
                    clip: true
                    spacing: Theme.spacingS
                    model: root.favModel

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 52
                        radius: Theme.fullRadius(width, height)
                        color: modelData.path === root.trackPath ? Theme.primaryContainer : Theme.surfaceContainer

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingM
                            spacing: Theme.spacingM

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40
                                height: 40
                                radius: Theme.fullRadius(width, height)
                                color: Theme.surfaceContainerHigh
                                clip: true

                                Image {
                                    id: favArt
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: status === Image.Ready
                                    source: root.artFor(modelData.path, 80)
                                    onStatusChanged: if (status === Image.Error) root.markArtDead(source)
                                }

                                DIcon {
                                    anchors.centerIn: parent
                                    name: "music_note"
                                    size: 18
                                    visible: favArt.status !== Image.Ready
                                    color: Theme.outline
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 72
                                spacing: 1

                                StyledText {
                                    width: parent.width
                                    text: modelData.name !== "" ? modelData.name : root.baseName(modelData.path)
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    color: modelData.path === root.trackPath ? Theme.primary : Theme.surfaceText
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }

                                StyledText {
                                    width: parent.width
                                    visible: modelData.artist !== ""
                                    text: modelData.artist
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.onSurfaceVariant
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.playTrack(modelData.path)
                        }
                    }
                }
            }
        }
    }
}
