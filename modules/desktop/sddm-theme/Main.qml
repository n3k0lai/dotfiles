import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtGraphicalEffects 1.15

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#0A0E14"

    // Animated wave layers
    Item {
        id: waveContainer
        anchors.fill: parent

        // Back wave
        Canvas {
            id: wave1
            anchors.fill: parent
            property real offset: 0

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var gradient = ctx.createLinearGradient(0, height * 0.7, 0, height)
                gradient.addColorStop(0, "#4ba69c33")
                gradient.addColorStop(1, "#4ba69c66")

                ctx.fillStyle = gradient
                ctx.beginPath()
                ctx.moveTo(0, height)

                for (var x = 0; x <= width; x += 5) {
                    var y = height * 0.75 + Math.sin((x + offset) * 0.01) * 40
                    ctx.lineTo(x, y)
                }

                ctx.lineTo(width, height)
                ctx.closePath()
                ctx.fill()
            }

            Timer {
                running: true
                repeat: true
                interval: 50
                onTriggered: {
                    wave1.offset += 2
                    wave1.requestPaint()
                }
            }
        }

        // Middle wave
        Canvas {
            id: wave2
            anchors.fill: parent
            property real offset: 100

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var gradient = ctx.createLinearGradient(0, height * 0.8, 0, height)
                gradient.addColorStop(0, "#6f95fc44")
                gradient.addColorStop(1, "#6f95fc88")

                ctx.fillStyle = gradient
                ctx.beginPath()
                ctx.moveTo(0, height)

                for (var x = 0; x <= width; x += 5) {
                    var y = height * 0.82 + Math.sin((x + offset) * 0.015) * 35
                    ctx.lineTo(x, y)
                }

                ctx.lineTo(width, height)
                ctx.closePath()
                ctx.fill()
            }

            Timer {
                running: true
                repeat: true
                interval: 50
                onTriggered: {
                    wave2.offset -= 1.5
                    wave2.requestPaint()
                }
            }
        }

        // Front wave
        Canvas {
            id: wave3
            anchors.fill: parent
            property real offset: 200

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var gradient = ctx.createLinearGradient(0, height * 0.85, 0, height)
                gradient.addColorStop(0, "#83d9f766")
                gradient.addColorStop(1, "#83d9f7aa")

                ctx.fillStyle = gradient
                ctx.beginPath()
                ctx.moveTo(0, height)

                for (var x = 0; x <= width; x += 5) {
                    var y = height * 0.87 + Math.sin((x + offset) * 0.02) * 30
                    ctx.lineTo(x, y)
                }

                ctx.lineTo(width, height)
                ctx.closePath()
                ctx.fill()
            }

            Timer {
                running: true
                repeat: true
                interval: 50
                onTriggered: {
                    wave3.offset += 3
                    wave3.requestPaint()
                }
            }
        }
    }

    // Login box
    Rectangle {
        id: loginBox
        width: 450
        height: 520
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -50
        color: "#1F1E1E"
        opacity: 0.95
        radius: 12
        border.color: "#4ba69c"
        border.width: 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 40
            spacing: 20

            // Title
            Text {
                text: "Welcome"
                font.family: "Hurmit Nerd Font"
                font.pixelSize: 36
                font.bold: true
                color: "#83d9f7"
                Layout.alignment: Qt.AlignHCenter
            }

            Item { Layout.fillHeight: true; Layout.preferredHeight: 10 }

            // Username
            Column {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Username"
                    font.family: "Martian Mono"
                    font.pixelSize: 14
                    color: "#9da09e"
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1
                }

                Rectangle {
                    width: parent.width
                    height: 45
                    color: "#0A0E14"
                    radius: 6
                    border.color: userField.focus ? "#4ba69c" : "#9da09e33"
                    border.width: 2

                    TextField {
                        id: userField
                        anchors.fill: parent
                        anchors.margins: 4
                        font.family: "Martian Mono"
                        font.pixelSize: 16
                        color: "#bfbab0"
                        text: userModel.lastUser
                        background: Item {}

                        KeyNavigation.backtab: loginButton
                        KeyNavigation.tab: passwordField
                    }
                }
            }

            // Password
            Column {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Password"
                    font.family: "Martian Mono"
                    font.pixelSize: 14
                    color: "#9da09e"
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1
                }

                Rectangle {
                    width: parent.width
                    height: 45
                    color: "#0A0E14"
                    radius: 6
                    border.color: passwordField.focus ? "#4ba69c" : "#9da09e33"
                    border.width: 2

                    TextField {
                        id: passwordField
                        anchors.fill: parent
                        anchors.margins: 4
                        font.family: "Martian Mono"
                        font.pixelSize: 16
                        color: "#bfbab0"
                        echoMode: TextInput.Password
                        focus: true
                        background: Item {}

                        KeyNavigation.backtab: userField
                        KeyNavigation.tab: sessionSelect

                        Keys.onPressed: {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                sddm.login(userField.text, passwordField.text, sessionSelect.currentIndex)
                                event.accepted = true
                            }
                        }
                    }
                }
            }

            // Session selector
            Column {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Session"
                    font.family: "Martian Mono"
                    font.pixelSize: 14
                    color: "#9da09e"
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1
                }

                Rectangle {
                    width: parent.width
                    height: 45
                    color: "#0A0E14"
                    radius: 6
                    border.color: "#9da09e33"
                    border.width: 2

                    ComboBox {
                        id: sessionSelect
                        anchors.fill: parent
                        anchors.margins: 8
                        font.family: "Martian Mono"
                        font.pixelSize: 14
                        model: sessionModel
                        currentIndex: sessionModel.lastIndex
                        textRole: "name"

                        KeyNavigation.backtab: passwordField
                        KeyNavigation.tab: loginButton

                        delegate: ItemDelegate {
                            width: sessionSelect.width
                            contentItem: Text {
                                text: model.name
                                color: "#bfbab0"
                                font: sessionSelect.font
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }
                            highlighted: sessionSelect.highlightedIndex === index
                            background: Rectangle {
                                color: highlighted ? "#4ba69c" : "#1F1E1E"
                            }
                        }

                        background: Rectangle {
                            color: "transparent"
                        }

                        contentItem: Text {
                            leftPadding: 8
                            rightPadding: sessionSelect.indicator.width + sessionSelect.spacing
                            text: sessionSelect.displayText
                            font: sessionSelect.font
                            color: "#bfbab0"
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true; Layout.preferredHeight: 10 }

            // Login button
            Button {
                id: loginButton
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                text: "Login"

                KeyNavigation.backtab: sessionSelect
                KeyNavigation.tab: userField

                background: Rectangle {
                    color: loginButton.pressed ? "#6f95fc" : (loginButton.hovered ? "#83d9f7" : "#4ba69c")
                    radius: 6

                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                }

                contentItem: Text {
                    text: loginButton.text
                    font.family: "Martian Mono"
                    font.pixelSize: 16
                    font.bold: true
                    color: "#0A0E14"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: sddm.login(userField.text, passwordField.text, sessionSelect.currentIndex)
            }
        }
    }

    DropShadow {
        anchors.fill: loginBox
        horizontalOffset: 0
        verticalOffset: 8
        radius: 16
        samples: 32
        color: "#000000"
        source: loginBox
    }

    // Clock
    Column {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 80
        spacing: 10

        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(new Date(), "hh:mm")
            font.family: "Hurmit Nerd Font"
            font.pixelSize: 72
            font.bold: true
            color: "#83d9f7"
        }

        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(new Date(), "dddd, MMMM d, yyyy")
            font.family: "Hurmit Nerd Font"
            font.pixelSize: 18
            color: "#9da09e"
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            timeText.text = Qt.formatTime(new Date(), "hh:mm")
            dateText.text = Qt.formatDate(new Date(), "dddd, MMMM d, yyyy")
        }
    }

    // Power menu
    Row {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 40
        spacing: 20

        // Reboot
        Rectangle {
            width: 50
            height: 50
            radius: 25
            color: rebootMouse.containsMouse ? "#4ba69c44" : "#1F1E1E"
            border.color: "#4ba69c"
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: "⟳"
                font.pixelSize: 24
                color: "#bfbab0"
            }

            MouseArea {
                id: rebootMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: sddm.reboot()
            }
        }

        // Shutdown
        Rectangle {
            width: 50
            height: 50
            radius: 25
            color: shutdownMouse.containsMouse ? "#ff333344" : "#1F1E1E"
            border.color: "#ff3333"
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: "⏻"
                font.pixelSize: 24
                color: "#bfbab0"
            }

            MouseArea {
                id: shutdownMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: sddm.powerOff()
            }
        }
    }

    Component.onCompleted: {
        passwordField.forceActiveFocus()
    }
}
