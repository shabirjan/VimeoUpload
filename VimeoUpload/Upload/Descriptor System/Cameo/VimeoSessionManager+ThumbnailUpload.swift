//
//  VimeoSessionManager+ThumbnailUpload.swift
//  Cameo
//
//  Created by Westendorf, Michael on 6/23/16.
//  Copyright © 2016 Vimeo. All rights reserved.
//

import Foundation
import VimeoNetworking

extension VimeoSessionManager
{
    func createThumbnailDownloadTask(uri: VideoUri) throws -> Task?
    {
        let request = try self.jsonRequestSerializer.createThumbnailRequest(with: uri) as URLRequest
        return self.download(request, then: { _ in })
    }
    
    func uploadThumbnailTask(source: URL, destination: String, completionHandler: ErrorBlock?) throws -> Task?
    {
        let request = try self.jsonRequestSerializer.uploadThumbnailRequest(with: source, destination: destination) as URLRequest
        return self.upload(request, sourceFile: source) { [jsonResponseSerializer] sessionManagingResult in
            switch sessionManagingResult.result {
            case .failure(let error as NSError):
                completionHandler?(error)
            case .success(let json):
                do {
                    try jsonResponseSerializer.process(
                        uploadThumbnailResponse: sessionManagingResult.response,
                        responseObject: json as AnyObject,
                        error: nil
                    )
                    completionHandler?(nil)
                } catch let error as NSError {
                    completionHandler?(error)
                }
            }
        }
    }
    
    func activateThumbnailTask(activationUri: String) throws -> Task?
    {
        let request = try self.jsonRequestSerializer.activateThumbnailRequest(with: activationUri) as URLRequest
        return self.download(request) { _ in }
    }
}
