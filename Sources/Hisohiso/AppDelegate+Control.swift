import Foundation

@MainActor
extension AppDelegate {
    /// Start the local Unix-socket control server.
    func startControlServer() {
        guard controlServer == nil, let modelSelectionController else { return }

        let commandService = ControlCommandService(
            modelSelectionController: modelSelectionController,
            dictationController: { [weak self] in self?.dictationController }
        )

        let server = ControlServer { [weak self] request, reply in
            guard let self else {
                reply(ControlResponse.failure(id: request.id, error: "Hisohiso app is shutting down"))
                return
            }

            Task { @MainActor [weak self] in
                guard self != nil else {
                    reply(ControlResponse.failure(id: request.id, error: "Hisohiso app is shutting down"))
                    return
                }

                let response = await commandService.handle(request)
                reply(response)
            }
        }

        do {
            try server.start()
            controlServer = server
        } catch {
            logError("Failed to start control server: \(error.localizedDescription)")
        }
    }
}
