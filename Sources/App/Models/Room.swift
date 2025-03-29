//
//  File.swift
//
//
//  Created by 송준서 on 2023/02/20.
//

import Vapor
@preconcurrency import MongoDBVapor

struct Room: Content {
    var _id: BSONObjectID?
    var participants: [Participant]
    var content: String
    var description: String
    var createdAt: Date
    var image: String?
    var type: String = "A" // A,Stest,D~~
    var imageURL:String?
    var brokenRoom: Bool?
    var postInformation: String?
    struct Participant: Content {
        var userId: BSONObjectID
        var recentMessageId: BSONObjectID?
        var name: String?
        var enteredDate: Date
        var notificationStatus: Bool
        var profileImage:String
        var profileImageURL:String?
        var activated:Bool
        var blockingUserIds: [BSONObjectID]?
        var forcedWithdrawal: Bool?
    }
    
    init(participants: [Participant],content: String,description:String, createdAt: Date,image: String?,imageURL: String?,applicantId: BSONObjectID? = nil,hostId: BSONObjectID? ,type:String = "A",announcementIds: [BSONObjectID]? = nil) {
        self.participants = participants
        self.createdAt = createdAt
        self.content = content
        self.description = description
        self.image = image
        self.type = type
        self.imageURL = imageURL
        self.postInformation = nil
    }
}

struct RoomSender{
    let id:String
    let participants: [User]
    let unreadCount: Int
    let lastMessage: LastMessage
    struct LastMessage:Content {
        let content: String
        let date: String
    }
    struct User:Content{
        let userId:String
        let name:String
    }
}
struct RoomReceive: Codable{
    let userId: String
//    var roomId: String?
    let type: String?
    let defaultImage: String
    let content: String
    let description: String
    let image: Data?
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.defaultImage = (try container.decodeIfPresent(String.self, forKey: .defaultImage)) ?? "4 - 3"
        self.content = try container.decode(String.self, forKey: .content)
        self.description = try container.decode(String.self, forKey: .description)
        self.image = try container.decodeIfPresent(Data.self, forKey: .image)
//        self.roomId = try container.decodeIfPresent(String.self, forKey: .roomId)
    }
}
struct RoomModifyReceive: Codable{
    let roomId: String
    let userId: String
    let content: String
    let description: String
    let image: Data?
    let imageURL: String?
    let defaultImage: String?
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.roomId = try container.decode(String.self, forKey: .roomId)
        self.content = try container.decode(String.self, forKey: .content)
        self.description = try container.decode(String.self, forKey: .description)
        self.image = try container.decodeIfPresent(Data.self, forKey: .image)
        self.imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        self.defaultImage = try container.decodeIfPresent(String.self, forKey: .defaultImage)
    }
}
