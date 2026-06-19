import Cocoa

struct StatusMenuSnapshot {
    let microphones: [AudioInputDevice]
    let currentMicrophone: AudioInputDevice
    let currentModel: TranscriptionModel
}

final class StatusMenuBuilder {
    private weak var target: AnyObject?
    private let selectMicrophone: Selector
    private let selectModel: Selector
    private let showPreferences: Selector

    init(target: AnyObject, selectMicrophone: Selector, selectModel: Selector, showPreferences: Selector) {
        self.target = target
        self.selectMicrophone = selectMicrophone
        self.selectModel = selectModel
        self.showPreferences = showPreferences
    }

    func build(snapshot: StatusMenuSnapshot) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(microphoneItem(snapshot: snapshot))
        menu.addItem(modelItem(currentModel: snapshot.currentModel))
        #if DEBUG
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Test UI", action: nil, keyEquivalent: ""))
        #endif
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: showPreferences, keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Hisohiso", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func microphoneItem(snapshot: StatusMenuSnapshot) -> NSMenuItem {
        let item = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for device in snapshot.microphones {
            let child = NSMenuItem(title: device.name, action: selectMicrophone, keyEquivalent: "")
            child.target = target
            child.representedObject = device
            child.state = device == snapshot.currentMicrophone ? .on : .off
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }

    private func modelItem(currentModel: TranscriptionModel) -> NSMenuItem {
        let item = NSMenuItem(title: "Transcription Model", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for model in TranscriptionModel.allCases {
            let child = NSMenuItem(title: model.displayName, action: selectModel, keyEquivalent: "")
            child.target = target
            child.representedObject = model.rawValue
            child.state = model == currentModel ? .on : .off
            submenu.addItem(child)
        }
        item.submenu = submenu
        return item
    }
}
