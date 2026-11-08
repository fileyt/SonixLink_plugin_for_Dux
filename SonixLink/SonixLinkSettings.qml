import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "sonixlink"

    StyledText {
        width: parent.width
        text: "SonixLink"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Remotes Sonix Player on a HiBy R1 / R3 Pro II over Wi-Fi. Enable Wireless → SonixLink on the player, then enter its IP address below (it serves its API on port 7800). Tip: the IP is also shown if you briefly enable the file-transfer server on the player."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "host"
        label: "Player address"
        description: "IP address or hostname of the player on your Wi-Fi network"
        placeholder: "192.168.1.42"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "pollSeconds"
        label: "Poll interval (seconds)"
        description: "How often the bar pill and panel refresh player state"
        placeholder: "3"
        defaultValue: "3"
    }

	SliderSetting {
	        settingKey: "titleMaxWidth"
	        label: "Pill title width"
	        description: "Maximum width of the track title in the bar pill, in pixels"
	        defaultValue: 340
	        minimum: 120
	        maximum: 600
	        unit: "px"
	    }
}
