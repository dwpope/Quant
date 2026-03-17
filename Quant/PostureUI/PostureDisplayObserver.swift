import SwiftUI
import Combine

@MainActor
class PostureDisplayObserver: ObservableObject {
    @Published var data: PostureDisplayData
    private var cancellable: AnyCancellable?

    init(source: any PostureDataSourceProtocol) {
        self.data = source.currentData
        subscribe(to: source)
    }

    func switchSource(to newSource: any PostureDataSourceProtocol) {
        self.data = newSource.currentData
        subscribe(to: newSource)
    }

    private func subscribe(to source: any PostureDataSourceProtocol) {
        _subscribe(to: source)
    }

    private func _subscribe<S: PostureDataSourceProtocol>(to source: S) {
        cancellable = source.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.data = source.currentData
            }
    }
}
