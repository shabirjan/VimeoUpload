//
//  VimeoResponseSerializer+Upload.swift
//  VimeoUpload
//
//  Created by Alfred Hanssen on 10/21/15.
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

extension VimeoResponseSerializer
{
    func processCreateVideoResponse(response: NSURLResponse?, url: NSURL?, error: NSError?) throws -> CreateVideoResponse
    {
        let dictionary: [String: AnyObject]
        do
        {
            dictionary = try self.dictionaryForDownloadTaskResponse(response, url: url, error: error)
        }
        catch let error as NSError
        {
            throw error.errorByAddingDomain(UploadErrorDomain.Create.rawValue)
        }
        
        guard let uploadUri = dictionary["upload_link_secure"] as? String, let activationUri = dictionary["complete_uri"] as? String else
        {
            throw NSError(domain: UploadErrorDomain.Create.rawValue, code: 0, userInfo: [NSLocalizedDescriptionKey: "Create response did not contain the required values."])
        }
        
        return CreateVideoResponse(uploadUri: uploadUri, activationUri: activationUri)
    }
    
    func processUploadVideoResponse(response: NSURLResponse?, responseObject: AnyObject?, error: NSError?) throws
    {
        if let error = error
        {
            throw error.errorByAddingDomain(UploadErrorDomain.Upload.rawValue)
        }
    }
    
    func processActivateVideoResponse(response: NSURLResponse?, url: NSURL?, error: NSError?) throws -> String
    {
        do
        {
            try self.dictionaryForDownloadTaskResponse(response, url: url, error: error)
        }
        catch let error as NSError
        {
            throw error.errorByAddingDomain(UploadErrorDomain.Activate.rawValue)
        }
        
        guard let HTTPResponse = response as? NSHTTPURLResponse, let location = HTTPResponse.allHeaderFields["Location"] as? String else
        {
            throw NSError(domain: UploadErrorDomain.Activate.rawValue, code: 0, userInfo: [NSLocalizedDescriptionKey: "Activate response did not contain the required value."])
        }
        
        return location
    }

    func processVideoSettingsResponse(response: NSURLResponse?, url: NSURL?, error: NSError?) throws -> VIMVideo
    {
        let dictionary: [String: AnyObject]
        do
        {
            dictionary = try self.dictionaryForDownloadTaskResponse(response, url: url, error: error)
        }
        catch let error as NSError
        {
            throw error.errorByAddingDomain(UploadErrorDomain.VideoSettings.rawValue)
        }
        
        let mapper = VIMObjectMapper()
        mapper.addMappingClass(VIMVideo.self, forKeypath: "")
        
        guard let video = mapper.applyMappingToJSON(dictionary) as? VIMVideo else
        {
            throw NSError(domain: UploadErrorDomain.VideoSettings.rawValue, code: 0, userInfo: [NSLocalizedDescriptionKey: "Video settings response did not contain a video."])
        }

        return video
    }
    
    // MARK: Private API
    
    // TODO: move this from extension into main class?
    
    private func dictionaryForDownloadTaskResponse(response: NSURLResponse?, url: NSURL?, error: NSError?) throws -> [String: AnyObject]
    {
        if let error = error
        {
            throw error
        }
        
        guard let url = url else
        {
            throw NSError(domain: VimeoResponseSerializer.ErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Url for completed download task is nil."])
        }
        
        guard let data = NSData(contentsOfURL: url) else
        {
            throw NSError(domain: VimeoResponseSerializer.ErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Data at url for completed download task is nil."])
        }
        
        var dictionary: [String: AnyObject]? = [:]
        if data.length > 0
        {
            do
            {
                dictionary = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.AllowFragments) as? [String: AnyObject]
            }
            catch let error as NSError
            {
                throw error
            }
        }
        
        if dictionary == nil
        {
            throw NSError(domain: VimeoResponseSerializer.ErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Download task response dictionary is nil."])
        }

        // TODO: add this check to taskDidComplete? So that we can catch upload errors too?
        
        if let httpResponse = response as? NSHTTPURLResponse where httpResponse.statusCode < 200 || httpResponse.statusCode > 299
        {
            // TODO: populate error object with dictionary contents
            // TODO: keep it in sync with localytics keys? Maybe not
            
            let userInfo = [NSLocalizedDescriptionKey: "Invalid http status code for download task"]
            
            throw NSError(domain: VimeoResponseSerializer.ErrorDomain, code: 0, userInfo: userInfo)
        }
        
        return dictionary!
    }
    
//        if (data)
//        {
//            userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] = data;
//        }
//
//        self.error = [NSError errorWithDomain:VIMCreateRecordTaskErrorDomain code:0 userInfo:userInfo];

}