import Testing
@testable import ModelScope

@Test func example() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    
    var downloadManager: ModelScope.DownloadManager = ModelScope.DownloadManager("/whisperkit-coreml")
    Task {
        await downloadManager.downloadModel(downFolder: "", modelId: "", completion: { _ in
            
        } )
    }
    
}
