//
//  MessagePipeline.swift
//  ZeroVapor
//
//  Created by jun on 3/27/25.
//

import MongoDBVapor
import Vapor

class MessagePipeline{
    static func messageProjectPipeline() -> BSONDocument {
        let pipeline: BSONDocument = ["$project": [
            "_id": 0,
            "id": ["$toString" : "$_id"],
            "image": 1,
            "uid": 1,
            "deletedDate": 1,
            "userId": ["$toString": "$user._id"],
            "name": "$user.name",
            "content": 1,
            "createdAt": ["$dateToString": [
                "date": "$createdAt",
                "format": "%Y-%m-%d %H:%M:%S",
                "timezone":"Asia/Seoul"
            ]],
            "roomId": ["$toString": "$roomId"],
            "type": 1,
            "removed": ["$ne": ["$deletedDate", .undefined]],
            "profileImage": "$user.profileImage",
            "mention": [
                "$cond": [
                    "if": ["$ne": ["$mention", .undefined]],
                    "then": [
                        "content": "$mention.content",
                        "image": "$mention.image",
                        "name": "$mention.name",
                        "messageId": ["$toString": "$mention.messageId"],
                        "userId": ["$toString": "$mention.userId"]
                    ],
                    "else": .null
                ]
            ],
            "unreadCount": ["$size": [
                "$filter": [
                    "input": "$room.participants",
                    "cond": [
                        "$and" : [
                            ["$lt": ["$$this.recentMessageId", "$_id"]],
                            ["$eq" : ["$$this.activated", .bool(true)]],
                            ["$ne" : ["$$this.forcedWithdrawal", .bool(true)]]
                        ]
                    ]
                ]]]
        ]]
        return pipeline
    }
    
    /// 위에 있는 Messages 페이징
    /// - Parameters:
    ///   - roomId: 포함되어 있는 room 의 Id
    ///   - messageId: 맨 위에있는 message의 Id
    /// - Returns: Aggreagation Pipeline
    static func getOldMessagesPipeline(roomId:BSONObjectID, messageId:BSONObjectID, user:Room.Participant) -> [BSONDocument] {
        let pipeline: [BSONDocument] = [
            [ "$match" :
                ["$and" : [
                    ["roomId": .objectID(roomId) ],
                    ["_id" : ["$lt": .objectID(messageId)]],
                ]]
            ],
            ["$sort": ["_id" : -1]],
            ["$limit": 50],
            //            ["$sort": ["_id" : 1]],
            [
                "$lookup": [
                    "from": "room" ,
                    "localField": "roomId",
                    "foreignField": "_id",
                    "as": "room"
                ]
            ],
            ["$unwind": "$room"],
            [
                "$lookup": [
                    "from": "users" ,
                    "localField": "senderId",
                    "foreignField": "_id",
                    "as": "user"
                ]
            ],
            ["$unwind": "$user"],
            messageProjectPipeline()
        ]
        return pipeline
    }
    
    /// 아래에 있는 Messages 페이징
    /// - Parameters:
    ///   - roomId: 포함되어 있는 room 의 Id
    ///   - messageId: 맨 아래 에있는 message의 Id
    /// - Returns: Aggreagation Pipeline
    static func getRecentMessagesPipeline(roomId:BSONObjectID,messageId:BSONObjectID,user:Room.Participant? = nil) -> [BSONDocument] {
        let pipeline: [BSONDocument] = [
            [ "$match" :
                ["$and" : [
                    ["roomId": .objectID(roomId) ],
                    ["_id" : ["$gt": .objectID(messageId)]],
                ]]
            ],
            ["$limit": 50],
            ["$sort": ["_id" : -1]],
            [
                "$lookup": [
                    "from": "room" ,
                    "localField": "roomId",
                    "foreignField": "_id",
                    "as": "room"
                ]
            ],
            ["$unwind": "$room"],
            [
                "$lookup": [
                    "from": "users" ,
                    "localField": "senderId",
                    "foreignField": "_id",
                    "as": "user"
                ]
            ],
            ["$unwind": "$user"],
            messageProjectPipeline()
        ]
        return pipeline
    }
    
    ///내가 본 메세지 부터 주기
    static func getMiddleMessagesPipeline(roomId: BSONObjectID,
                                          userId: BSONObjectID,
                                          recentMessageId: BSONObjectID,
                                          user: Room.Participant) -> [BSONDocument]{
        let pipeline2: [BSONDocument] = [
            [
                "$match": ["$and": [
                    ["roomId": .objectID(roomId)]
                ]],
            ],
            [
                "$facet": [
                    "old": [
                        ["$match" :
                            ["_id" : ["$lte" : .objectID(recentMessageId)]]
                        ],
                        ["$sort": ["_id" : -1]],
                        ["$limit": 50],
                        [
                            "$lookup": [
                                "from": "room" ,
                                "localField": "roomId",
                                "foreignField": "_id",
                                "as": "room"
                            ]
                        ],
                        ["$unwind": "$room"],
                        [
                            "$lookup": [
                                "from": "users" ,
                                "localField": "senderId",
                                "foreignField": "_id",
                                "as": "user"
                            ]
                        ],
                        ["$unwind": "$user"],
                        .document(messageProjectPipeline()),
                    ],
                    "new": [
                        ["$match" :
                            ["_id" : ["$gt" : .objectID(recentMessageId)]]
                        ],
                        ["$limit": 50],
                        ["$sort": ["_id" : -1]],
                        [
                            "$lookup": [
                                "from": "room" ,
                                "localField": "roomId",
                                "foreignField": "_id",
                                "as": "room"
                            ]
                        ],
                        ["$unwind": "$room"],
                        [
                            "$lookup": [
                                "from": "users" ,
                                "localField": "senderId",
                                "foreignField": "_id",
                                "as": "user"
                            ]
                        ],
                        ["$unwind": "$user"],
                        .document(messageProjectPipeline()),
                    ]
                ]
            ]
        ]
        return pipeline2
    }
    
    static func getMessagesPipeline(roomId: BSONObjectID,user:Room.Participant) -> [BSONDocument]{
        let pipeline: [BSONDocument] = [
            [ "$match" :
                ["$and": [
                    ["roomId": .objectID(roomId)],
                ]]
            ],
            ["$sort": ["_id" : -1]],
            ["$limit": 50],
            [
                "$lookup": [
                    "from": "room" ,
                    "localField": "roomId",
                    "foreignField": "_id",
                    "as": "room"
                ]
            ],
            ["$unwind": "$room"],
            [
                "$lookup": [
                    "from": "users" ,
                    "localField": "senderId",
                    "foreignField": "_id",
                    "as": "user"
                ]
            ],
            ["$unwind": "$user"],
            messageProjectPipeline(),
        ]
        return pipeline
    }
    
    static func getMessageUnreadCount(messageId: BSONObjectID) -> [BSONDocument] {
        let pipeline: [BSONDocument] = [
            ["$match":
                ["_id": .objectID(messageId)]
            ],
            [
                "$lookup": [
                    "from": "room",
                    "localField": "roomId",
                    "foreignField": "_id",
                    "as": "room"
                ]
            ],
            ["$unwind": "$room"],
            ["$project":[
                "unreadCount": ["$size": [
                    "$filter" : [
                        "input": "$room.participants",
                        "cond": [
                            "$and" : [
                                ["$lt" : ["$$this.recentMessageId", "$_id"]],
                                ["$eq" : ["$$this.activated", .bool(true)]],
                                ["$ne" : ["$$this.forcedWithdrawal", .bool(true)]]
                            ]
                            
                        ]
                    ]]]
            ]]
        ]
        return pipeline
    }
    
    static func getMessagePipeline(messageId: BSONObjectID) -> [BSONDocument]{
        let pipeline: [BSONDocument] = [
            ["$match":
                ["_id": .objectID(messageId)]
            ],
            [
                "$lookup": [
                    "from": "room",
                    "localField": "roomId",
                    "foreignField": "_id",
                    "as": "room"
                ]
            ],
            ["$unwind" : "$room"],
            [
                "$lookup": [
                    "from": "users",
                    "localField": "senderId",
                    "foreignField": "_id",
                    "as": "user"
                ]
            ],
            ["$unwind" : "$user"],
            messageProjectPipeline(),
        ]
        return pipeline
    }
    
    static func getRecentMessagePipeline(roomId: BSONObjectID) -> [BSONDocument]{
        let pipeline: [BSONDocument] = [
            [ "$match" :
                ["roomId": .objectID(roomId) ]
            ],
            ["$sort": ["_id" : -1]],
            ["$limit": 1],
            [
                "$lookup": [
                    "from": "room" ,
                    "localField": "roomId",
                    "foreignField": "_id",
                    "as": "room"
                ]
            ],
            ["$unwind": "$room"],
            [
                "$lookup": [
                    "from": "users" ,
                    "localField": "senderId",
                    "foreignField": "_id",
                    "as": "user"
                ]
            ],
            ["$unwind": "$user"],
            messageProjectPipeline(),
        ]
        return pipeline
    }
}

