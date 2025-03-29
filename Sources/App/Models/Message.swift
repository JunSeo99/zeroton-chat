//
//  File.swift
//  
//
//  Created by 송준서 on 2023/02/20.
//

import Vapor
@preconcurrency import MongoDBVapor

final class Message: Content {
    var _id: BSONObjectID?
    var roomId: BSONObjectID
    var senderId: BSONObjectID
    var content: String
    var createdAt: Date
    var type: String
    var image: Image?
    var uid: String
    var mention: Mention?
    var deletedDate: Date?
    struct Image: Content{
        let url: String
        let height: Double
        let width: Double
    }
    struct Mention: Content{
        var messageId: BSONObjectID
        var userId: BSONObjectID
        var name: String
        var content: String
        var image: String?
    }
    init(roomId: BSONObjectID, senderId: BSONObjectID, content: String, createdAt: Date,type: String = "chat",image: Message.Image? = nil,uid: String,mention: Mention?) {
        self.roomId = roomId
        self.senderId = senderId
        self.content = content
        self.createdAt = createdAt
        self.type = type
        self.image = image
        self.uid = uid
        self.mention = mention
    }
}

struct MessageSender: Content {
    let id: String?
    var sender: User
    let content: String
    let createdAt: Date
    struct User:Content{
        let userId:String
        let name:String
    }
}

struct NoticeReceive: Content {
    let content: String
    let roomType: String
}
struct ChatSender: Codable{
    let userId: String
    let name: String
    let date: String
    let content: String
    let type: String
}
