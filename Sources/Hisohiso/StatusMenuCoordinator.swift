import Cocoa

final class StatusMenuCoordinator {
    private let builder: StatusMenuBuilder

    init(builder: StatusMenuBuilder) {
        self.builder = builder
    }

    func menu(snapshot: StatusMenuSnapshot) -> NSMenu {
        builder.build(snapshot: snapshot)
    }
}
