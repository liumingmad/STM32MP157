import QtQuick 2.12
import QtQuick.Window 2.12

Window {
    visible: true
    width: 800
    height: 480
    color: "#222"
    title: "STM32MP157 Qt-VNC demo aaa"

    // POST to the on-board led-daemon. Result lands in statusText.
    function ledPost(path) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 0)
                    statusText.text = "daemon unreachable (is led-daemon.service up?)"
                else
                    statusText.text = "→ " + path + "  [" + xhr.status + "]  " + xhr.responseText
            }
        }
        xhr.open("POST", "http://127.0.0.1:8081" + path)
        xhr.send()
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 16
        text: "Hello from STM32MP157 over VNC bbb"
        color: "#7CFC00"
        font.pixelSize: 24
    }

    // --- LED control buttons ---
    Row {
        spacing: 12
        anchors.horizontalCenter: parent.horizontalCenter
        y: 70
        Repeater {
            model: [
                { label: "ON",    path: "/led/on",                            tint: "#2a8" },
                { label: "OFF",   path: "/led/off",                           tint: "#844" },
                { label: "BLINK", path: "/led/blink?count=10&ms=150",         tint: "#86c" },
                { label: "TIMER", path: "/led/timer?on_ms=300&off_ms=300",    tint: "#48a" },
                { label: "STOP",  path: "/led/none",                          tint: "#666" }
            ]
            delegate: Rectangle {
                width: 120
                height: 56
                radius: 10
                color: tap.pressed ? Qt.lighter(modelData.tint, 1.3) : modelData.tint
                border.color: "#7CFC00"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                MouseArea {
                    id: tap
                    anchors.fill: parent
                    onClicked: ledPost(modelData.path)
                }
            }
        }
    }

    Text {
        id: statusText
        anchors.horizontalCenter: parent.horizontalCenter
        y: 150
        width: parent.width - 40
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: "#cccccc"
        font.pixelSize: 13
        text: "click a button to drive /sys/class/leds/user-led via led-daemon"
    }

    // --- the original animated rectangle, kept for sanity ---
    Rectangle {
        width: 100
        height: 100
        radius: 12
        color: "orange"
        y: parent.height - height - 60
        NumberAnimation on x {
            from: 0
            to: 700
            duration: 3000
            loops: Animation.Infinite
        }
    }

    Text {
        id: clock
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 12
        color: "#888"
        font.pixelSize: 16
        text: Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss")
        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: clock.text = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss")
        }
    }
}
