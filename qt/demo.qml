import QtQuick 2.12
import QtQuick.Window 2.12

Window {
    visible: true
    width: 800
    height: 480
    color: "#222"
    title: "STM32MP157 Qt-VNC demo"

    Text {
        anchors.centerIn: parent
        text: "Hello from STM32MP157 over VNC"
        color: "#7CFC00"
        font.pixelSize: 28
    }

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
