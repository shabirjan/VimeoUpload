//
//  OldUploadDescriptor.swift
//  VimeoUpload
//
//  Created by Alfred Hanssen on 10/18/15.
//  Copyright © 2015 Vimeo. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import AFNetworking
import VimeoNetworking

open class OldUploadDescriptor: ProgressDescriptor, VideoDescriptor
{
    // MARK:
    
    let url: URL
    let videoSettings: VideoSettings?

    // MARK:
    
    fileprivate(set) var uploadTicket: VIMUploadTicket? // Create response
    open var videoUri: String? // Activate response
    fileprivate(set) var video: VIMVideo? // Settings response

    // MARK:
    
    fileprivate(set) var currentRequest = OldUploadRequest.Create
    {
        didSet
        {
            print("\(self.currentRequest.rawValue) \(self.identifier)")
        }
    }
    
    // MARK: VideoDescriptor
    
    open var type: VideoDescriptorType
    {
        return .upload
    }
    
    open var progressDescriptor: ProgressDescriptor
    {
        return self
    }

    // MARK: - Initialization
    
    required public init()
    {
        fatalError("init() has not been implemented")
    }

    public init(url: URL, videoSettings: VideoSettings? = nil)
    {
        self.url = url
        self.videoSettings = videoSettings
        
        super.init()
    }

    // MARK: Overrides
    
    override open func prepare(sessionManager: AFURLSessionManager) throws
    {
        let sessionManager = sessionManager as! VimeoSessionManager

        do
        {
            try self.transitionToState(request: .Create, sessionManager: sessionManager)
        }
        catch let error as NSError
        {
            self.currentTaskIdentifier = nil
            self.error = error
            self.state = .Finished
            
            throw error // Propagate this out so that DescriptorManager can remove the descriptor from the set
        }
    }
    
    override open func resume(sessionManager: AFURLSessionManager)
    {
        super.resume(sessionManager: sessionManager)
        
        if let identifier = self.currentTaskIdentifier,
            let task = sessionManager.uploadTaskForIdentifier(identifier),
            let progress = sessionManager.uploadProgress(for: task)
        {
            self.progress = progress
        }
    }

    override open func cancel(sessionManager: AFURLSessionManager)
    {
        super.cancel(sessionManager: sessionManager)
        
        FileManager.default.deleteFileAtURL(self.url)
    }
    
    // If necessary, resume the current task and re-connect progress objects

    override open func didLoadFromCache(sessionManager: AFURLSessionManager) throws
    {
        guard let identifier = self.currentTaskIdentifier,
            let task = sessionManager.uploadTaskForIdentifier(identifier),
            let progress = sessionManager.uploadProgress(for: task) else
        {
            // This error is thrown if you initiate an upload and then kill the app from the multitasking view in mid-upload
            // Upon reopening the app, the descriptor is loaded but no longer has a task
            
            FileManager.default.deleteFileAtURL(self.url)
            
            let error = NSError(domain: UploadErrorDomain.Upload.rawValue, code: 0, userInfo: [NSLocalizedDescriptionKey: "Loaded descriptor from cache that does not have a task associated with it."])
            self.error = error // TODO: Whenever we set error delete local file? Same for download?
            self.currentTaskIdentifier = nil
            self.state = .Finished
            
            throw error
        }

        self.progress = progress
    }
    
    override open func taskDidFinishDownloading(sessionManager: AFURLSessionManager, task: URLSessionDownloadTask, url: URL) -> URL?
    {
        let sessionManager = sessionManager as! VimeoSessionManager
        let responseSerializer = sessionManager.responseSerializer as! VimeoResponseSerializer
        
        do
        {
            switch self.currentRequest
            {
            case .Create:
                self.uploadTicket = try responseSerializer.processCreateVideoResponse(task.response, url: url as NSURL?, error: error)
                
            case .Upload:
                break
                
            case .Activate:
                self.videoUri = try responseSerializer.processActivateVideoResponse(task.response, url: url as NSURL?, error: error)
                
            case .Settings:
                self.video = try responseSerializer.processVideoSettingsResponse(task.response, url: url as NSURL?, error: error)
            }
        }
        catch let error as NSError
        {
            self.error = error
            self.currentTaskIdentifier = nil
            self.state = .Finished
        }

        return nil
    }
    
    override open func taskDidComplete(sessionManager: AFURLSessionManager, task: URLSessionTask, error: NSError?)
    {
        if self.currentRequest == .Upload
        {
            FileManager.default.deleteFileAtURL(self.url)
        }

        if self.error == nil
        {
            if let taskError = task.error // task.error is reserved for client-side errors, so check it first
            {
                let domain = self.errorDomainForRequest(self.currentRequest)
                self.error = (taskError as NSError).errorByAddingDomain(domain)
            }
            else if let error = error
            {
                let domain = self.errorDomainForRequest(self.currentRequest)
                self.error = error.errorByAddingDomain(domain)
            }
        }
        
        let nextRequest = OldUploadRequest.nextRequest(self.currentRequest)
        if self.error != nil || nextRequest == nil || (nextRequest == .Settings && self.videoSettings == nil)
        {
            self.currentTaskIdentifier = nil
            self.state = .Finished

            return
        }
        
        do
        {
            let sessionManager = sessionManager as! VimeoSessionManager
            try self.transitionToState(request: nextRequest!, sessionManager: sessionManager)
            self.resume(sessionManager: sessionManager)
        }
        catch let error as NSError
        {
            self.error = error
            self.currentTaskIdentifier = nil
            self.state = .Finished
        }
    }
    
    // MARK: Private API
    
    fileprivate func transitionToState(request: OldUploadRequest, sessionManager: VimeoSessionManager) throws
    {
        self.currentRequest = request
        let task = try self.taskForRequest(request, sessionManager: sessionManager)
        self.currentTaskIdentifier = task.taskIdentifier
    }
    
    fileprivate func taskForRequest(_ request: OldUploadRequest, sessionManager: VimeoSessionManager) throws -> URLSessionTask
    {
        switch request
        {
        case .Create:
            return try sessionManager.createVideoDownloadTask(url: self.url as NSURL)
            
        case .Upload:
            guard let uploadUri = self.uploadTicket?.uploadLinkSecure else
            {
                throw NSError(domain: UploadErrorDomain.Upload.rawValue, code: 0, userInfo: [NSLocalizedDescriptionKey: "Attempt to initiate upload but the uploadUri is nil."])
            }

            return try sessionManager.uploadVideoTask(source: self.url as NSURL, destination: uploadUri, completionHandler: nil)
            
        case .Activate:
            guard let activationUri = self.uploadTicket?.completeUri else
            {
                throw NSError(domain: UploadErrorDomain.Activate.rawValue, code: 0, userInfo: [NSLocalizedDescriptionKey: "Activate response did not contain the required values."])
            }
            
            return try sessionManager.activateVideoDownloadTask(uri: activationUri)

        case .Settings:
            guard let videoUri = self.videoUri, let videoSettings = self.videoSettings else
            {
                throw NSError(domain: UploadErrorDomain.VideoSettings.rawValue, code: 0, userInfo: [NSLocalizedDescriptionKey: "Video settings response did not contain the required values."])
            }
            
            return try sessionManager.videoSettingsDownloadTask(videoUri: videoUri, videoSettings: videoSettings)
        }
    }

    fileprivate func errorDomainForRequest(_ request: OldUploadRequest) -> String
    {
        switch request
        {
        case .Create:
            return UploadErrorDomain.Create.rawValue

        case .Upload:
            return UploadErrorDomain.Upload.rawValue

        case .Activate:
            return UploadErrorDomain.Activate.rawValue

        case .Settings:
            return UploadErrorDomain.VideoSettings.rawValue
        }
    }
    
    // MARK: NSCoding
    
    required public init(coder aDecoder: NSCoder)
    {
        self.url = aDecoder.decodeObject(forKey: "url") as! URL // If force unwrap fails we have a big problem
        self.videoSettings = aDecoder.decodeObject(forKey: "videoSettings") as? VideoSettings
        self.uploadTicket = aDecoder.decodeObject(forKey: "uploadTicket") as? VIMUploadTicket
        self.videoUri = aDecoder.decodeObject(forKey: "videoUri") as? String
        self.currentRequest = OldUploadRequest(rawValue: aDecoder.decodeObject(forKey: "currentRequest") as! String)!

        super.init(coder: aDecoder)
    }
    
    override open func encode(with aCoder: NSCoder)
    {
        aCoder.encode(self.url, forKey: "url")
        aCoder.encode(self.videoSettings, forKey: "videoSettings")
        aCoder.encode(self.uploadTicket, forKey: "uploadTicket")
        aCoder.encode(self.videoUri, forKey: "videoUri")
        aCoder.encode(self.currentRequest.rawValue, forKey: "currentRequest")
        
        super.encode(with: aCoder)
    }
}
