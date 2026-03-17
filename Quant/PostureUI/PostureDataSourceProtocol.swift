import Combine

protocol PostureDataSourceProtocol: ObservableObject {
    var currentData: PostureDisplayData { get }
}
