//
//  File.swift
//
//
//  Created by 송준서 on 2023/02/20.
//

import Vapor
import MongoDBVapor
final class ImageMessage: Content {
    var roomId: String
    var userId: String
    var imageData:Data
    var imageHeight: Double
    var imageWidth: Double
    var uid: String
    var hrOption: String?
}


final class MessageReceive: Content {
    var roomId: String
    var userId: String
    var contents: [MessageReceive.Message]
    struct Message: Content{
        var content: String
        var uid: String
        var hrOption: String?
        var mention: Message.Mention?
        struct Mention: Content {
            var messageId: String
            var userId: String
            var name: String
            var content: String
            var image: String?
        }
    }
}
