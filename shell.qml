// Spotify player overlay. Resident and hidden; the keybind toggles it. Design: "Spotify Player Design" in Figma, no-glass variant.
//   qs -c music                         start (autostart.lua does this)
//   qs -c music ipc call music toggle   open/close (Alt+S)
//   qs -c music ipc call music search "text"   open with the search already filled in (testing)
// Keys: Enter search, Space pause, Left/Right prev/next, Escape close. In search: Up/Down + Enter plays, Escape goes back.
// Closing keeps the music playing (the hidden official Spotify app plays it; it starts on first open, quits after 10 idle minutes).
// Spotify and LRCLIB calls go through ./spot. assets/ holds the pre-rendered mesh, grain, vignette and record.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

ShellRoot {
    id: root
    readonly property string dir: Quickshell.env("HOME") + "/.config/quickshell/music"
    readonly property string spot: dir + "/spot"
    readonly property string fontName: "Euclid Circular A"
    readonly property int lyricOffset: 0   // ms; raise if lyrics lag the audio, lower if they run ahead

    property bool shown: false
    property bool searching: false
    property var results: []
    property string resultsFor: ""
    property int selected: 0
    property string error: ""
    property var now: ({})          // {uri,name,artist,album,art,ms,playing,pos,volume}
    property var queue: []
    property real position: 0
    property var lyrics: []
    property bool synced: false
    property string lyricsFor: ""
    property string lyricsNote: ""
    property var bars: []
    property int volume: now.volume === undefined ? 0 : now.volume

    readonly property bool playing: now.playing === true
    readonly property int activeLine: {
        if (!synced) return -1;
        let i = 0;
        while (i + 1 < lyrics.length && lyrics[i + 1].t <= position + lyricOffset) i++;
        return i;
    }

    // Same order as GENRE_RULES in ./spot: base, three streak colours
    readonly property var genres: [
        ["#100a1a", "#a8406f", "#d79a92", "#4c3580"],   // pop
        ["#0b0a18", "#8e2a1c", "#c27a24", "#3a2a6a"],   // hip-hop / rap
        ["#0f0814", "#7a2a58", "#b98742", "#351a50"],   // r&b / soul
        ["#0c0a0c", "#8c2228", "#a84f2a", "#2e2a30"],   // rock
        ["#06070a", "#4c1214", "#67747e", "#1a1e26"],   // metal
        ["#060a18", "#1f8fa0", "#7fa63a", "#3a2a96"],   // electronic / dance
        ["#070d18", "#234a86", "#a9853e", "#155560"],   // jazz / blues
        ["#0d1216", "#5f7f98", "#bfb48f", "#4a6660"]    // classical / ambient
    ]
    property int genre: 1
    property string genreFor: ""
    property color c0: genres[genre][0]
    property color c1: genres[genre][1]
    property color c2: genres[genre][2]
    property color c3: genres[genre][3]
    Behavior on c0 { ColorAnimation { duration: 1200 } }
    Behavior on c1 { ColorAnimation { duration: 1200 } }
    Behavior on c2 { ColorAnimation { duration: 1200 } }
    Behavior on c3 { ColorAnimation { duration: 1200 } }
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    Component {
        id: job
        Process {
            id: p
            property var done: null
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    let v = null;
                    try { v = JSON.parse(text); } catch (e) { /* killed or empty */ }
                    if (v && v.error) root.error = v.error;
                    else if (v && p.done) { root.error = ""; p.done(v); }
                    p.destroy();
                }
            }
        }
    }
    function run(args, done) { job.createObject(root, { command: [spot].concat(args), done: done || null }); }

    function open() { idleMinutes = 0; run(["ensure"]); refresh(); shown = true; }
    function refresh() {
        run(["status"], s => {
            now = s; position = s.pos || 0; lastTick = Date.now();
            if (s.uri && s.uri !== lyricsFor) { loadLyrics(s); run(["queue"], q => queue = q.items); }
            const artist = (s.artist || "").split(",")[0];
            if (artist && artist !== genreFor) {
                genreFor = artist;
                run(["genre", artist], g => { if (g.artist === genreFor) genre = g.genre; });
            }
        });
    }
    function loadLyrics(s) {
        lyricsFor = s.uri; lyrics = []; synced = false; lyricsNote = "Finding lyrics…";
        run(["lyrics", s.uri, s.artist, s.name, s.album, String(Math.round(s.ms / 1000))], l => {
            if (l.uri !== lyricsFor) return;
            lyrics = l.synced ? l.lines.filter(x => x.l.trim() !== "") : l.lines;
            synced = l.synced;
            lyricsNote = l.lines.length ? "" : "No lyrics found for this song";
        });
    }
    function control(args) { run(args, () => settle.restart()); }
    function search(q) {
        if (!q.trim()) { results = []; resultsFor = ""; return; }
        run(["search", q], r => { if (r.q === input.text) { results = r.items; resultsFor = r.q; selected = 0; } });
    }
    function openSearch() { searching = true; input.text = ""; results = []; resultsFor = ""; input.forceActiveFocus(); }
    function closeSearch() { searching = false; keys.forceActiveFocus(); }
    function play(i) {
        if (!results[i]) return;
        run(["play", results[i].uri], () => settle.restart());
        closeSearch();
    }
    function seek(ms) { position = ms; lastTick = Date.now(); control(["seek", String(Math.round(ms))]); }
    function setVolume(v) { volume = v; control(["volume", String(v)]); }
    function clock(ms) {
        const s = Math.floor((ms || 0) / 1000);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    IpcHandler {
        target: "music"
        function toggle(): void { root.shown ? root.shown = false : root.open() }
        function open(): void { root.open() }
        function close(): void { root.shown = false }
        function search(q: string): void { root.open(); root.openSearch(); input.text = q }
    }

    property real lastTick: 0
    Timer {     // smooth position between polls
        running: root.shown && root.playing
        interval: 100; repeat: true
        onTriggered: { const t = Date.now(); root.position += t - root.lastTick; root.lastTick = t; }
    }
    Timer { running: root.shown; interval: 3000; repeat: true; onTriggered: root.refresh() }
    Timer { id: settle; interval: 500; onTriggered: root.refresh() }   // Spotify's state lags a command slightly
    Timer { id: debounce; interval: 280; onTriggered: root.search(input.text) }

    // The Spotify app only runs on demand: quit it after this long closed + not playing.
    readonly property int quitAfterMinutes: 10
    property int idleMinutes: 0
    Timer {
        running: !root.shown
        interval: 60000; repeat: true
        onTriggered: root.run(["idle"], r => {
            if (!r.running || r.playing) { root.idleMinutes = 0; return; }
            if (++root.idleMinutes >= root.quitAfterMinutes) { root.idleMinutes = 0; root.run(["quit"]); }
        })
    }

    Process {
        running: root.shown && root.playing
        command: ["cava", "-p", root.dir + "/cava.conf"]
        stdout: SplitParser { onRead: data => root.bars = data.split(";").filter(v => v !== "").map(Number) }
        onRunningChanged: if (!running) root.bars = []
    }

    component Streak: Rectangle {
        id: st
        required property real cx
        required property real halfW
        required property color tone
        required property real strength
        required property real drift
        required property int period
        property real sway: 0
        x: cx - halfW + sway
        y: -160; width: halfW * 2; height: 1400
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.alpha(st.tone, 0) }
            GradientStop { position: 0.25; color: root.alpha(st.tone, st.strength * 0.35) }
            GradientStop { position: 0.5; color: root.alpha(st.tone, st.strength) }
            GradientStop { position: 0.75; color: root.alpha(st.tone, st.strength * 0.35) }
            GradientStop { position: 1; color: root.alpha(st.tone, 0) }
        }
        SequentialAnimation on sway {
            running: root.shown; loops: Animation.Infinite
            NumberAnimation { from: -st.drift; to: st.drift; duration: st.period * 1000; easing.type: Easing.InOutSine }
            NumberAnimation { from: st.drift; to: -st.drift; duration: st.period * 1000; easing.type: Easing.InOutSine }
        }
    }

    component Hair: Rectangle {
        id: h
        required property real baseX
        required property real strength
        required property int period
        property real sway: 0
        x: baseX + sway
        y: -160; width: 1.5; height: 1400
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.35; color: "white" }
            GradientStop { position: 0.65; color: "white" }
            GradientStop { position: 1; color: "transparent" }
        }
        opacity: strength
        SequentialAnimation on sway {
            running: root.shown; loops: Animation.Infinite
            NumberAnimation { from: -40; to: 40; duration: h.period * 1000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 40; to: -40; duration: h.period * 1000; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on opacity {
            running: root.shown; loops: Animation.Infinite
            NumberAnimation { from: h.strength; to: h.strength * 0.25; duration: h.period * 330; easing.type: Easing.InOutSine }
            NumberAnimation { from: h.strength * 0.25; to: h.strength; duration: h.period * 330; easing.type: Easing.InOutSine }
        }
    }

    component Label: Text {
        font.family: root.fontName
        font.weight: Font.Medium
        color: "white"
        renderType: Text.NativeRendering
    }

    component IconButton: Item {
        id: btn
        required property string icon
        property int size: 24
        signal clicked()
        width: 40; height: 40
        Image { anchors.centerIn: parent; width: btn.size; height: btn.size; sourceSize: Qt.size(48, 48); source: "file://" + root.dir + "/assets/" + btn.icon + ".svg" }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { btn.clicked(); keys.forceActiveFocus(); } }
    }

    component Rail: Item {
        id: rail
        property real fraction: 0
        signal picked(real f)
        height: 20
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 3; color: Qt.rgba(1, 1, 1, 0.26) }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * Math.max(0, Math.min(1, rail.fraction)); height: 3; color: "white" }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: m => rail.picked(m.x / width) }
    }

    component SongRow: Item {
        id: sr
        required property var song
        property bool selected: false
        signal clicked()
        height: 72
        Rectangle { anchors.fill: parent; radius: 8; visible: sr.selected; color: Qt.tint("#08070c", root.alpha(root.c1, 0.7)) }
        ClippingRectangle {
            id: thumb
            x: 10; anchors.verticalCenter: parent.verticalCenter
            width: 52; height: 52; radius: 10; color: "#222"
            Image { anchors.fill: parent; source: sr.song.thumb || ""; asynchronous: true; fillMode: Image.PreserveAspectCrop }
        }
        Column {
            anchors { left: thumb.right; leftMargin: 14; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            Label { width: parent.width; text: sr.song.name; font.pixelSize: 18; elide: Text.ElideRight }
            Label { width: parent.width; text: sr.song.artist; font.pixelSize: 14; opacity: 0.72; elide: Text.ElideRight }
        }
        MouseArea { anchors.fill: parent; onClicked: sr.clicked() }
    }

    PanelWindow {
        id: win
        visible: root.shown
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "music"
        color: root.c0
        onVisibleChanged: if (visible) { root.searching = false; keys.forceActiveFocus(); }

        // ---- background: streaks, fade, lines, then the filmed-monitor texture ----
        Item {
            width: 1920; height: 1080
            transform: Scale { xScale: win.width / 1920; yScale: win.height / 1080 }
            Streak { cx: 600; halfW: 150; tone: root.c3; strength: 0.3; drift: 40; period: 23 }
            Streak { cx: 880; halfW: 200; tone: root.c1; strength: 0.6; drift: 55; period: 19 }
            Streak { cx: 1135; halfW: 130; tone: root.c2; strength: 0.58; drift: 60; period: 17 }
            Streak { cx: 1010; halfW: 44; tone: root.c2; strength: 0.34; drift: 75; period: 13 }
            Streak { cx: 1250; halfW: 26; tone: root.c1; strength: 0.26; drift: 70; period: 11 }
            Streak { cx: 1400; halfW: 120; tone: root.c3; strength: 0.24; drift: 50; period: 29 }
            Streak { cx: 770; halfW: 34; tone: root.c1; strength: 0.3; drift: 65; period: 16 }
            Streak { cx: 1195; halfW: 30; tone: root.c2; strength: 0.3; drift: 80; period: 14 }
            Streak { cx: 950; halfW: 18; tone: root.c2; strength: 0.24; drift: 90; period: 12 }
            Rectangle {
                width: 1920; height: 324
                gradient: Gradient { GradientStop { position: 0; color: root.c0 } GradientStop { position: 1; color: root.alpha(root.c0, 0) } }
            }
            Rectangle {
                y: 778; width: 1920; height: 302
                gradient: Gradient { GradientStop { position: 0; color: root.alpha(root.c0, 0) } GradientStop { position: 1; color: root.c0 } }
            }
            Hair { baseX: 690; strength: 0.1; period: 14 }
            Hair { baseX: 842; strength: 0.16; period: 17 }
            Hair { baseX: 905; strength: 0.12; period: 20 }
            Hair { baseX: 1012; strength: 0.2; period: 23 }
            Hair { baseX: 1128; strength: 0.18; period: 26 }
            Hair { baseX: 1186; strength: 0.12; period: 29 }
            Hair { baseX: 1322; strength: 0.1; period: 32 }
            Hair { baseX: 1470; strength: 0.07; period: 35 }
        }
        Image { anchors.fill: parent; source: "file://" + root.dir + "/assets/mesh.png"; fillMode: Image.Tile; smooth: false; horizontalAlignment: Image.AlignLeft; verticalAlignment: Image.AlignTop }
        Image { anchors.fill: parent; source: "file://" + root.dir + "/assets/grain.png"; fillMode: Image.Tile; opacity: 0.5; horizontalAlignment: Image.AlignLeft; verticalAlignment: Image.AlignTop }
        Image { anchors.fill: parent; source: "file://" + root.dir + "/assets/vignette.png" }

        // ---- everything else is laid out at 1920x1080 and scaled to the screen ----
        Item {
            width: 1920; height: 1080
            anchors.centerIn: parent
            scale: Math.min(win.width / 1920, win.height / 1080)

            Item { id: keys; focus: true
                Keys.onReturnPressed: root.openSearch()
                Keys.onEnterPressed: root.openSearch()
                Keys.onEscapePressed: root.shown = false
                Keys.onSpacePressed: root.control(["toggle"])
                Keys.onLeftPressed: root.control(["prev"])
                Keys.onRightPressed: root.control(["next"])
            }

            // left column: title, record, queue
            Column {
                x: 110; y: 136; width: 440
                Label { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.now.name || "Nothing playing"; font.pixelSize: 44; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Label { width: parent.width; topPadding: 6; horizontalAlignment: Text.AlignHCenter; text: root.now.artist || "Press Enter to search"; font.pixelSize: 22; opacity: 0.75; elide: Text.ElideRight }
                Item { width: 1; height: 36 }
                Item {
                    id: disc
                    width: 400; height: 400
                    anchors.horizontalCenter: parent.horizontalCenter
                    RotationAnimator on rotation { from: 0; to: 360; duration: 8000; loops: Animation.Infinite; running: root.shown; paused: root.shown && !root.playing }
                    Image { anchors.fill: parent; source: "file://" + root.dir + "/assets/disc.png"; sourceSize: Qt.size(800, 800); smooth: true; mipmap: true }
                    ClippingRectangle {
                        anchors.centerIn: parent
                        width: 206; height: 206; radius: 103; color: "#141216"
                        Image { anchors.fill: parent; source: root.now.art || ""; sourceSize: Qt.size(412, 412); asynchronous: true; fillMode: Image.PreserveAspectCrop }
                    }
                    Rectangle { anchors.centerIn: parent; width: 12; height: 12; radius: 6; color: "#0b0a0c"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35) }
                }
                Item { width: 1; height: 34 }
                Label { visible: root.queue.length > 0; text: "Up next"; font.pixelSize: 16; font.weight: Font.DemiBold; opacity: 0.75; bottomPadding: 6 }
                Repeater {
                    model: root.queue
                    Item {
                        id: q
                        required property var modelData
                        width: 440; height: 60
                        ClippingRectangle {
                            id: qt
                            anchors.verticalCenter: parent.verticalCenter
                            width: 52; height: 52; radius: 10; color: "#222"
                            Image { anchors.fill: parent; source: q.modelData.thumb || ""; asynchronous: true; fillMode: Image.PreserveAspectCrop }
                        }
                        Column {
                            anchors { left: qt.right; leftMargin: 14; right: parent.right; verticalCenter: parent.verticalCenter }
                            Label { width: parent.width; text: q.modelData.name; font.pixelSize: 18; elide: Text.ElideRight }
                            Label { width: parent.width; text: q.modelData.artist; font.pixelSize: 14; opacity: 0.72; elide: Text.ElideRight }
                        }
                    }
                }
            }

            // vertical visualizer: bass in the middle, mirrored up and down
            Column {
                x: 760; y: 190; width: 400; spacing: 21
                Repeater {
                    model: 23
                    Rectangle {
                        id: bar
                        required property int index
                        readonly property real env: Math.pow(Math.sin(Math.PI * index / 22), 0.9)
                        readonly property real level: (root.bars[Math.abs(index - 11)] || 0) / 100
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(10, 400 * env * (root.playing ? 0.14 + 0.86 * level : 0))
                        height: 10; radius: 5; opacity: 0.82
                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutSine } }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: root.alpha(Qt.lighter(root.c1, 1.5), 0.5) }
                            GradientStop { position: 0.5; color: root.alpha(Qt.lighter(root.c2, 1.45), 0.95) }
                            GradientStop { position: 1; color: root.alpha(Qt.lighter(root.c2, 1.2), 0.5) }
                        }
                    }
                }
            }

            // lyrics: the centre line is the focused one and the list scrolls up under it
            ListView {
                id: lyricView
                x: 1240; y: 240; width: 641; height: 600
                clip: true
                interactive: !root.synced
                model: root.lyrics
                currentIndex: root.synced ? root.activeLine : -1
                highlightRangeMode: root.synced ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
                preferredHighlightBegin: height / 2 - (currentItem ? currentItem.height / 2 : 61)
                preferredHighlightEnd: height / 2 + (currentItem ? currentItem.height / 2 : 61)
                highlightMoveDuration: 700
                highlightMoveVelocity: -1
                delegate: Item {
                    id: line
                    required property var modelData
                    required property int index
                    readonly property int distance: Math.abs(index - root.activeLine)
                    width: ListView.view.width
                    height: words.height + 30
                    Label {
                        id: words
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: line.modelData.l || "♪"
                        font.pixelSize: root.synced ? 48 : 30
                        font.weight: Font.DemiBold
                        lineHeight: 61; lineHeightMode: Text.FixedHeight
                        opacity: !root.synced || line.distance === 0 ? 1 : line.distance === 1 ? 0.62 : 0
                        scale: !root.synced || line.distance === 0 ? 1 : 0.83
                        Behavior on opacity { NumberAnimation { duration: 500 } }
                        Behavior on scale { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                        layer.enabled: root.synced && line.distance === 1
                        layer.effect: MultiEffect { blurEnabled: true; blur: 0.5; blurMax: 16 }
                    }
                    MouseArea { anchors.fill: parent; enabled: root.synced; onClicked: root.seek(line.modelData.t) }
                }
                Label { anchors.centerIn: parent; visible: root.lyrics.length === 0; text: root.lyricsNote; font.pixelSize: 22; opacity: 0.7 }
            }

            // flat media controls
            Row {
                anchors { bottom: parent.bottom; bottomMargin: 38; horizontalCenter: parent.horizontalCenter }
                spacing: 20
                IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "back"; onClicked: root.control(["prev"]) }
                IconButton { anchors.verticalCenter: parent.verticalCenter; icon: root.playing ? "pause" : "play"; onClicked: root.control(["toggle"]) }
                IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "next"; onClicked: root.control(["next"]) }
                Label { anchors.verticalCenter: parent.verticalCenter; text: root.clock(root.position); font.pixelSize: 14; opacity: 0.72; font.features: ({ "tnum": 1 }) }
                Rail { anchors.verticalCenter: parent.verticalCenter; width: 300; fraction: root.now.ms ? root.position / root.now.ms : 0; onPicked: f => { if (root.now.ms) root.seek(f * root.now.ms); } }
                Label { anchors.verticalCenter: parent.verticalCenter; text: root.clock(root.now.ms); font.pixelSize: 14; opacity: 0.72; font.features: ({ "tnum": 1 }) }
                Image { anchors.verticalCenter: parent.verticalCenter; width: 24; height: 24; sourceSize: Qt.size(48, 48); source: "file://" + root.dir + "/assets/volume.svg" }
                Rail { anchors.verticalCenter: parent.verticalCenter; width: 90; fraction: root.volume / 100; onPicked: f => root.setVolume(Math.round(f * 100)) }
            }
            Label { anchors { bottom: parent.bottom; bottomMargin: 12; horizontalCenter: parent.horizontalCenter }
                visible: root.error !== ""; text: root.error; font.pixelSize: 14; color: "#ffb4a8" }

            // search: solid screen, no blur
            Rectangle {
                id: sheet
                anchors.fill: parent
                color: "#08070c"
                opacity: root.searching ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }
                Column {
                    x: 580; y: 300; width: 760; spacing: 20
                    Item {
                        width: parent.width; height: 86
                        TextInput {
                            id: input
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            color: "white"; selectionColor: root.c1
                            font.family: root.fontName; font.pixelSize: 56; font.weight: Font.Medium
                            clip: true
                            onTextChanged: debounce.restart()
                            Keys.onUpPressed: root.selected = Math.max(0, root.selected - 1)
                            Keys.onDownPressed: root.selected = Math.min(root.results.length - 1, root.selected + 1)
                            Keys.onReturnPressed: root.play(root.selected)
                            Keys.onEnterPressed: root.play(root.selected)
                            Keys.onEscapePressed: root.closeSearch()
                            Label { anchors.fill: parent; visible: !input.text; text: "Search Spotify"; font: input.font; opacity: 0.45 }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: input.activeFocus ? "white" : Qt.rgba(1, 1, 1, 0.3) }
                    }
                    ListView {
                        width: parent.width; height: 600
                        clip: true; spacing: 2
                        model: root.results
                        currentIndex: root.selected
                        delegate: SongRow {
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            song: modelData
                            selected: index === root.selected
                            onClicked: { root.selected = index; root.play(index); }
                        }
                        Label { visible: root.results.length === 0 && root.resultsFor !== "" && root.resultsFor === input.text; text: "No songs match that search."; font.pixelSize: 18; opacity: 0.7 }
                    }
                }
            }
        }
    }
}
