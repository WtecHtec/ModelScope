// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation
import Alamofire

extension String {
   var decodedPath: String {
       removingPercentEncoding ?? self
   }
   
   var sanitizedPath: String {
       self.replacingOccurrences(of: "%20", with: " ")
           .replacingOccurrences(of: "%25", with: "%")
           .decodedPath
   }
}

public struct ModelScope {
    // file 类型
    public struct ModelFile: Codable, Sendable {
       public let type: String
       public let name: String
       public let path: String
       public let size: Int
       public let revision: String
       
       enum CodingKeys: String, CodingKey {
           case type = "Type"
           case name = "Name"
           case path = "Path"
           case size = "Size"
           case revision = "Revision"
       }
    }
    
    // 接口返回格式
    public struct ModelResponse: Codable, Sendable {
        public let code: Int
        public let data: ModelData
          
        enum CodingKeys: String, CodingKey {
            case code = "Code"
            case data = "Data"
        }
    }

    public struct ModelData: Codable, Sendable {
        let files: [ModelFile]
        
        enum CodingKeys: String, CodingKey {
            case files = "Files"
        }
    }
    
    // 文件下载状态结构
    public struct FileStatus: Codable {
           let path: String
           let size: Int
           let revision: String
           let lastModified: Date
       }
    
    @available(iOS 13.0, macOS 10.15, *)
    public actor DownloadManager: Sendable {
        
        private var repoPath = ""
        private let baseURL = "https://modelscope.cn/api/v1/models"
       
        private var totalFiles = 0
        private var downloadedFiles = 0
        
        private let userDefaults = UserDefaults.standard
        private let downloadedFilesKey = "ModelDownloadManager.downloadedFiles"
        
        public init(_ repoPath: String) {
            self.repoPath = repoPath
        }
        
        public func downloadModel(
                  downFolder: String = "",
                  modelId: String,
                  progress:  ((Float) -> Void)? = nil,
                  completion: @escaping (Result<Void, Error>) -> Void = { _ in }
              ) async {
                  let progressHandler: (Float) -> Void = progress ?? { _ in }
                  do {
                      var destinationPath = downFolder
                      if destinationPath.isEmpty {
                          let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
                          destinationPath = documentsPath
                      }
                      try createDirectory(at: destinationPath)
                      
                      let files = try await fetchFileList(root: "", revision: "")
                      self.totalFiles = files.count
                      
                      let filteredFiles = files.filter { modelFile in
                          modelFile.name == modelId && modelFile.type == "tree"
                      }
                      
                      try await downloadFiles(
                          files: filteredFiles,
                          revision: "",
                          destinationPath: destinationPath,
                          progress: progressHandler
                      )
                      
                      completion(.success(()))
                  } catch {
                      completion(.failure(error))
                  }
              }
        
        // 创建文件夹
        private func createDirectory(at path: String) throws {
             let sanitizedPath = path.sanitizedPath
             if !FileManager.default.fileExists(atPath: sanitizedPath) {
                 try FileManager.default.createDirectory(
                     atPath: sanitizedPath,
                     withIntermediateDirectories: true,
                     attributes: nil
                 )
             }
        }
        
        // 查找文件列表
        private func fetchFileList(
                   root: String,
                   revision: String
               ) async throws -> [ModelFile] {
               let url = "\(baseURL)/\(repoPath)/repo/files"
               let parameters: Parameters = [
                   "Root": root,
                   "Revision": revision
               ]
               return try await withCheckedThrowingContinuation { continuation in
                   AF.request(url, parameters: parameters)
                       .validate()
                       .responseDecodable(of: ModelResponse.self) { response in
                           switch response.result {
                           case .success(let modelResponse):
                               continuation.resume(returning: modelResponse.data.files)
                           case .failure(let error):
                               continuation.resume(throwing: error)
                           }
                       }
               }
        }
        
        private func downloadFiles(
                    files: [ModelFile],
                    revision: String,
                    destinationPath: String,
                    progress: @escaping (Float) -> Void
        ) async throws {
            for file in files {
                if file.type == "tree" {
                    let sanitizedPath = destinationPath.sanitizedPath
                    let dirName = file.name.sanitizedPath
                    let newPath = (sanitizedPath as NSString).appendingPathComponent(dirName)
                    
                    try createDirectory(at: newPath)
                    
                    let subFiles = try await fetchFileList(root: file.path, revision: revision)
                    try await downloadFiles(
                        files: subFiles,
                        revision: revision,
                        destinationPath: newPath,
                        progress: progress
                    )
                } else if file.type == "blob" {
                    if  isFileDownloaded(file, at: destinationPath) {
                        print("文件已存在，跳过下载: \(file.path)")
                        downloadedFiles += 1
                        progress(Float(downloadedFiles) / Float(totalFiles))
                    } else {
                        try await downloadFile(
                            file: file,
                            destinationPath: destinationPath
                        )
                        downloadedFiles += 1
                        saveFileStatus(file, at: destinationPath)
                        progress(Float(downloadedFiles) / Float(totalFiles))
                    }
                }
            }
        }
        
        private func downloadFile(
                 file: ModelFile,
                 destinationPath: String
             ) async throws {
                 return try await withCheckedThrowingContinuation { continuation in
                     let url = "https://modelscope.cn/api/v1/models/\(repoPath)/repo?Revision=master&FilePath=\(file.path)"
                     let destination: DownloadRequest.Destination = { _, _ in
                         let fileURL = URL(fileURLWithPath: destinationPath)
                             .appendingPathComponent(file.name)
                         return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
                     }
                     
                     AF.download(url, parameters: nil, to: destination)
                         .validate()
                         .response { response in
                             switch response.result {
                             case .success:
                                 continuation.resume()
                             case .failure(let error):
                                 continuation.resume(throwing: error)
                             }
                         }
                 }
             }
        
        
        // 检查文件是否已下载
           private func isFileDownloaded(_ file: ModelFile, at path: String) -> Bool {
               let filePath = (path.sanitizedPath as NSString).appendingPathComponent(file.name.sanitizedPath)
               
               // 检查文件是否存在
               guard FileManager.default.fileExists(atPath: filePath) else {
                   return false
               }
               
               // 获取已下载文件的信息
               guard let downloadedFiles = getDownloadedFiles(),
                     let fileStatus = downloadedFiles[filePath] else {
                   return false
               }
               
               // 检查文件大小和版本是否匹配
               return fileStatus.size == file.size && fileStatus.revision == file.revision
           }
        
        // 获取已下载文件信息
          private func getDownloadedFiles() -> [String: FileStatus]? {
              guard let data = userDefaults.data(forKey: downloadedFilesKey),
                    let downloadedFiles = try? JSONDecoder().decode([String: FileStatus].self, from: data) else {
                  return nil
              }
              return downloadedFiles
          }
        
        
        // 保存下载文件信息
           private  func saveFileStatus(_ file: ModelFile, at path: String) {
               let filePath = (path.sanitizedPath as NSString).appendingPathComponent(file.name.sanitizedPath)
               let fileStatus = FileStatus(
                   path: filePath,
                   size: file.size,
                   revision: file.revision,
                   lastModified: Date()
               )
               
               var downloadedFiles = getDownloadedFiles() ?? [:]
               downloadedFiles[filePath] = fileStatus
               
               if let encoded = try? JSONEncoder().encode(downloadedFiles) {
                   userDefaults.set(encoded, forKey: downloadedFilesKey)
               }
           }
        
    }
}
