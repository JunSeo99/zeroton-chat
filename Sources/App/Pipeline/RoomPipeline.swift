//
//  RoomPipeline.swift
//  ZeroVapor
//
//  Created by jun on 3/27/25.
//
import MongoDBVapor
import Foundation

class RoomPipeline{
    static func getHRUserRooms(userId: BSONObjectID, lastId: BSONObjectID?) -> [BSONDocument] {
        var matchOperator: BSONDocument = [
            "$match": [
                "$and": [
                    ["participants.userId": .objectID(userId)],
                    ["type": "HR"],
                    ["applicantId": ["$ne": .null]]
                ]
            ],
        ]
        if let lastId {
            matchOperator = [
                "$match": [
                    "$and": [
                        ["participants.userId": .objectID(userId)],
                        ["type": "HR"],
                        ["applicantId": ["$ne": .null]],
                        ["_id": ["$lt": .objectID(lastId)]]
                    ]
                ]
            ]
        }
        let pipeline: [BSONDocument] = [
            matchOperator,
            [
                "$lookup": [
                    "from": "applicants",
                    "localField": "applicantId",
                    "foreignField": "_id",
                    "as": "applicant"
                ]
            ],
            ["$unwind": "$applicant"],
            ["$addFields": [
                "user": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$eq" : ["$$this.userId", .objectID(userId)]
                            ]
                        ]
                    ], 0]
                ],
                "manager": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$ne" : ["$$this.userId", .objectID(userId)]
                            ]
                        ]
                    ], 0]
                ],
            ]],
            [
                "$match" : ["user.activated": .bool(true)]
            ],
            ["$lookup": [
                "from": "messages",
                "let": ["roomId": "$_id","lastReadId": "$user.recentMessageId","enteredDate" : "$user.enteredDate","blockIds": "$user.blockingUserIds"],
                "pipeline": [
                    ["$match": ["$and": [
                        ["$or" : [
                            ["type": "chat"],
                            ["type": "image"]
                        ]],
                        ["$expr": ["$eq": ["$roomId", "$$roomId"]]],
                        ["$expr": ["$gt": ["$createdAt", "$$enteredDate"]]],
                        ["$expr": [
                            "$not" : [
                                "$in": [
                                    "$senderId",
                                    [
                                        "$ifNull": [
                                            "$$blockIds",
                                            .array([])]
                                    ]
                                ]
                            ]
                        ]]
                    ]]],
                    ["$sort": ["_id": 1]],
                    ["$group": [
                        "_id": "$roomId",
                        "content": ["$last": "$content"],
                        "date": ["$last" : "$createdAt"],
                        "deletedDate" : ["$last" : "$deletedDate"],
                        "messageId" : ["$last" : "$_id"],
                        "unreadCount": ["$sum": [
                            "$cond": [
                                ["$gt": ["$_id", "$$lastReadId"]],
                                1,
                                0
                            ]
                        ]],
                        "containMention": ["$max":[
                            "$cond": [
                                ["$and": [
                                    ["$ne": ["$mention", .undefined]],
                                    ["$gt": ["$_id", "$$lastReadId"]],
//                                    ["$eq": ["$mention.userId", .objectID(userId)]]
                                ]],
                                true,
                                false
                            ]
                        ]]
                    ]],
                ],
                "as": "lastMessage"
            ]],
            [
                "$unwind" : [
                    "path": "$lastMessage",
                    "preserveNullAndEmptyArrays": .bool(true)
                ]
            ],
            [
                "$match": ["lastMessage": ["$ne": .null]]
            ],
            [
                "$sort" : ["lastMessage.date" : -1]
            ],
            [
                "$limit" : .int32(50)
            ],
            [
                "$project": [
                    "_id": 0,
                    "id": ["$toString": "$_id"],
                    "names": [
                        ["$concat": ["$content"," 사장님"]],
                        "$description"
                    ],
                    "type": 1,
                    "lastMessage" : ["$cond" : [
                        ["$eq": ["$lastMessage",.undefined]],
                        .null,
                        [
                            "content" : ["$cond": [
                                ["$ne": ["$lastMessage.deletedDate", .null]],
                                "삭제된 메시지입니다.",
                                "$lastMessage.content"
                            ]],
                            "messageId": ["$toString": "$lastMessage.messageId"],
                            "date" : ["$dateToString": [
                                "date": "$lastMessage.date",
                                "format": "%Y-%m-%d %H:%M:%S",
                                "timezone":"Asia/Seoul"
                            ]],
                            "containMention": "$lastMessage.containMention"
                        ],
                    ]],
                    "notificationStatus": "$user.notificationStatus",
                    "unreadCount": ["$cond" : [
                        ["$eq": ["$lastMessage",.undefined]],
                        .int32(0),
                        "$lastMessage.unreadCount"
                    ]],
                    "isBlock": ["$in": ["$user.userId", ["$ifNull": ["$manager.blockingUserIds", .array([])]] ]],
                    "participantCount":  [
                        "$size": [
                            "$filter" : [
                                "input": "$participants",
                                "cond": [
                                    "$eq" : ["$$this.activated", .bool(true)]
                                ]
                            ]
                        ]
                    ],
                    "image": 1,
                    "applicantId": ["$toString": "$applicantId"]
                ]
            ]
        ]
        return pipeline
    }
    static func getHRUserRoom(userId: BSONObjectID, roomId: BSONObjectID) -> [BSONDocument] {
        let pipeline: [BSONDocument] = [
            [
                "$match": [
                    "_id": .objectID(roomId)
                ],
            ],
            [
                "$lookup": [
                    "from": "applicants",
                    "localField": "applicantId",
                    "foreignField": "_id",
                    "as": "applicant"
                ]
            ],
            ["$unwind": "$applicant"],
            ["$addFields": [
                "user": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$eq" : ["$$this.userId", .objectID(userId)]
                            ]
                        ]
                    ],0]
                ],
                "manager": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$ne" : ["$$this.userId", .objectID(userId)]
                            ]
                        ]
                    ],0]
                ],
            ]],
            [
                "$match" : ["user.activated": .bool(true)]
            ],
            ["$lookup": [
                "from": "messages",
                "let": ["roomId": "$_id","lastReadId": "$user.recentMessageId","enteredDate" : "$user.enteredDate","blockIds": "$user.blockingUserIds"],
                "pipeline": [
                    ["$match": ["$and": [
                        ["$or" : [
                            ["type": "chat"],
                            ["type": "image"]
                        ]],
                        ["$expr": ["$eq": ["$roomId", "$$roomId"]]],
                        ["$expr": ["$gt": ["$createdAt", "$$enteredDate"]]],
                        ["$expr": [
                            "$not" : [
                                "$in": [
                                    "$senderId",
                                    [
                                        "$ifNull": [
                                            "$$blockIds",
                                            .array([])]
                                    ]
                                ]
                            ]
                        ]]
                    ]]],
                    ["$sort": ["_id": 1]],
                    ["$group": [
                        "_id": "$roomId",
                        "content": ["$last": "$content"],
                        "date": ["$last" : "$createdAt"],
                        "deletedDate" : ["$last" : "$deletedDate"],
                        "messageId" : ["$last" : "$_id"],
                        "unreadCount": ["$sum": [
                            "$cond": [
                                ["$gt": ["$_id", "$$lastReadId"]],
                                1,
                                0
                            ]
                        ]],
                        "containMention": ["$max":[
                            "$cond": [
                                ["$and": [
                                    ["$ne": ["$mention", .undefined]],
                                    ["$gt": ["$_id", "$$lastReadId"]],
//                                    ["$eq": ["$mention.userId", .objectID(userId)]]
                                ]],
                                true,
                                false
                            ]
                        ]]
                    ]],
                ],
                "as": "lastMessage"
            ]],
            [
                "$unwind" : [
                    "path": "$lastMessage",
                    "preserveNullAndEmptyArrays": .bool(true)
                ]
            ],
            [
                "$addFields" : [ "lastMessage" : ["$ifNull": ["$lastMessage",
                                                              [
                                                                "content": "",
                                                                "date": "$user.enteredDate",
                                                                "unreadCount": .int32(0),
                                                                "containMention": .bool(false),
                                                                "deletedDate": .null
                                                              ]
                                                             ]]]
            ],
            [
                "$sort" : ["lastMessage.date" : -1]
            ],
            [
                "$limit" : .int32(50)
            ],
            [
                "$project": [
                    "_id": 0,
                    "id": ["$toString": "$_id"],
                    "names": [
                        ["$concat": ["$content"," 사장님"]],
                        "$description"
                    ],
                    "image": "$users.profileImage",
                    "type": 1,
                    "lastMessage" : ["$cond" : [
                        ["$eq": ["$lastMessage",.undefined]],
                        .null,
                        [
                            "content" : ["$cond": [
                                ["$ne": ["$lastMessage.deletedDate", .null]],
                                "삭제된 메시지입니다.",
                                "$lastMessage.content"
                            ]],
                            "messageId": ["$toString": "$lastMessage.messageId"],
                            "date" : ["$dateToString": [
                                "date": "$lastMessage.date",
                                "format": "%Y-%m-%d %H:%M:%S",
                                "timezone":"Asia/Seoul"
                            ]],
                            "containMention": "$lastMessage.containMention"
                        ],
                    ]],
                    "notificationStatus": "$user.notificationStatus",
                    "unreadCount": ["$cond" : [
                        ["$eq": ["$lastMessage",.undefined]],
                        .int32(0),
                        "$lastMessage.unreadCount"
                    ]],
                    "isBlock": ["$in": ["$user.userId", ["$ifNull": ["$manager.blockingUserIds", .array([])]] ]],
                    "applicantId": ["$toString": "$applicantId"],
                    "participantCount":  [
                        "$size": [
                            "$filter" : [
                                "input": "$participants",
                                "cond": [
                                    "$eq" : ["$$this.activated", .bool(true)]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
            
            
        ]
        return pipeline
    }
    static func getManagerRoom(managerId: BSONObjectID, roomId: BSONObjectID) -> [BSONDocument] {
        let pipeline: [BSONDocument] = [
            [
                "$match": [
                    "_id": .objectID(roomId)
                ],
            ],
            [
                "$lookup": [
                    "from": "applicants",
                    "localField": "applicantId",
                    "foreignField": "_id",
                    "as": "applicant"
                ]
            ],
            ["$unwind": "$applicant"],
            ["$addFields": [
                "user": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$eq" : ["$$this.userId", .objectID(managerId)]
                            ]
                        ]
                    ],0]
                ],
            ]],
            [
                "$match" : ["user.activated": .bool(true)]
            ],
            ["$lookup": [
                "from": "messages",
                "let": ["roomId": "$_id","lastReadId": "$user.recentMessageId","enteredDate" : "$user.enteredDate","blockIds": "$user.blockingUserIds"],
                "pipeline": [
                    ["$match": ["$and": [
                        ["$or" : [
                            ["type": "chat"],
                            ["type": "image"]
                        ]],
                        ["$expr": ["$eq": ["$roomId", "$$roomId"]]],
                        ["$expr": ["$gt": ["$createdAt", "$$enteredDate"]]],
                        ["$expr": [
                            "$not" : [
                                "$in": [
                                    "$senderId",
                                    [
                                        "$ifNull": [
                                            "$$blockIds",
                                            .array([])]
                                    ]
                                ]
                            ]
                        ]]
                    ]]],
                    ["$sort": ["_id": 1]],
                    ["$group": [
                        "_id": "$roomId",
                        "content": ["$last": "$content"],
                        "date": ["$last" : "$createdAt"],
                        "deletedDate" : ["$last" : "$deletedDate"],
                        "messageId" : ["$last" : "$_id"],
                        "unreadCount": ["$sum": [
                            "$cond": [
                                ["$gt": ["$_id", "$$lastReadId"]],
                                1,
                                0
                            ]
                        ]],
                        "containMention": ["$max":[
                            "$cond": [
                                ["$and": [
                                    ["$ne": ["$mention", .undefined]],
                                    ["$gt": ["$_id", "$$lastReadId"]],
//                                    ["$eq": ["$mention.userId", .objectID(managerId)]]
                                ]],
                                true,
                                false
                            ]
                        ]]
                    ]],
                ],
                "as": "lastMessage"
            ]],
            [
                "$unwind" : [
                    "path": "$lastMessage",
                    "preserveNullAndEmptyArrays": .bool(true)
                ]
            ],
            [
                "$addFields" : [ "lastMessage" : ["$ifNull": ["$lastMessage",
                                                              [
                                                                "content": "",
                                                                "date": "$user.enteredDate",
                                                                "unreadCount": .int32(0),
                                                                "containMention": .bool(false),
                                                                "deletedDate": .null
                                                              ]
                                                             ]]]
            ],
            [
                "$lookup": [
                    "from": "users",
                    "localField": "applicant.userId",
                    "foreignField": "_id",
                    "as": "users"
                ]
            ],
            ["$unwind": "$users"],
            [
                "$project": [
                    "_id": 0,
                    "id": ["$toString": "$_id"],
                    "names": [
                        ["$concat": [
                            ["$substrCP": ["$users.info.name", 0, 1]],
                            "OO"
                        ]],
                        ["$concat": [
                            ["$toString": ["$sum": [
                                [
                                    "$subtract": [
                                        ["$year": .datetime(.init())],
                                        ["$year": ["$toDate":
                                                    ["$concat": [
                                                        ["$toString": "$users.info.birth"],
                                                        "-01-01"
                                                    ]]
                                                  ]]
                                    ]
                                ],
                                1
                            ]]
                            ],
                            "세"
                        ]],
                        ["$cond": [
                            "if": ["$eq": ["$users.info.gender", 0]],
                            "then": "남",
                            "else": "여"
                        ]]
                    ],
                    "image": ["$ifNull": ["$users.info.image", "defaultImage"]],
                    "type": 1,
                    "isBlock": ["$in": ["$applicant.managerId", ["$ifNull": ["$users.blockingUsers",.array([])]]]],
                    "lastMessage" : ["$cond" : [
                        ["$eq": ["$lastMessage",.undefined]],
                        .null,
                        [
                            "content" : ["$cond": [
                                ["$ne": ["$lastMessage.deletedDate", .null]],
                                "삭제된 메시지입니다.",
                                "$lastMessage.content"
                            ]],
                            "messageId": ["$toString": "$lastMessage.messageId"],
                            "date" : ["$dateToString": [
                                "date": "$lastMessage.date",
                                "format": "%Y-%m-%d %H:%M:%S",
                                "timezone":"Asia/Seoul"
                            ]],
                            "containMention": "$lastMessage.containMention"
                        ],
                    ]],
                    "applicantId": ["$toString": "$applicantId"],
                    "notificationStatus": "$user.notificationStatus",
                    "unreadCount": ["$cond" : [
                        ["$eq": ["$lastMessage",.undefined]],
                        .int32(0),
                        "$lastMessage.unreadCount"
                    ]],
                    "participantCount":  [
                        "$size": [
                            "$filter" : [
                                "input": "$participants",
                                "cond": [
                                    "$eq" : ["$$this.activated", .bool(true)]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        return pipeline
    }
    static func getManagerRooms(managerId: BSONObjectID, lastId: BSONObjectID?) -> [BSONDocument] {
        var matchOperator: BSONDocument = [
            "$match": [
                "$and": [
                    ["participants.userId": .objectID(managerId)],
                    ["type": "HR"],
                    ["applicantId": ["$ne": .null]]
                ]
            ],
        ]
        if let lastId {
            matchOperator = [
                "$match": [
                    "$and": [
                        ["participants.userId": .objectID(managerId)],
                        ["type": "HR"],
                        ["applicantId": ["$ne": .null]],
                        ["_id": ["$lt": .objectID(lastId)]]
                    ]
                ],
            ]
        }
        let pipeline: [BSONDocument] = [
            matchOperator,
            [
                "$lookup": [
                    "from": "applicants",
                    "localField": "applicantId",
                    "foreignField": "_id",
                    "as": "applicant"
                ]
            ],
            ["$unwind": "$applicant"],
            ["$addFields": [
                "user": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$eq" : ["$$this.userId", .objectID(managerId)]
                            ]
                        ]
                    ],0]
                ],
            ]],
            [
                "$match" : ["$and": [
                    ["user.activated": .bool(true)],
                    ["$or": [
                        ["applicant.state": .int32(1)],
                        ["applicant.state": .int32(2)]
                    ]]
                ]]
            ],
            ["$lookup": [
                "from": "messages",
                "let": ["roomId": "$_id","lastReadId": "$user.recentMessageId","enteredDate" : "$user.enteredDate","blockIds": "$user.blockingUserIds"],
                "pipeline": [
                    ["$match": ["$and": [
                        ["$or" : [
                            ["type": "chat"],
                            ["type": "image"]
                        ]],
                        ["$expr": ["$eq": ["$roomId", "$$roomId"]]],
                        ["$expr": ["$gt": ["$createdAt", "$$enteredDate"]]],
                        ["$expr": [
                            "$not" : [
                                "$in": [
                                    "$senderId",
                                    [
                                        "$ifNull": [
                                            "$$blockIds",
                                            .array([])]
                                    ]
                                ]
                            ]
                        ]]
                    ]]],
                    ["$sort": ["_id": 1]],
                    ["$group": [
                        "_id": "$roomId",
                        "content": ["$last": "$content"],
                        "date": ["$last" : "$createdAt"],
                        "deletedDate": ["$last" : "$deletedDate"],
                        "messageId" : ["$last" : "$_id"],
                        "unreadCount": ["$sum": [
                            "$cond": [
                                ["$gt": ["$_id", "$$lastReadId"]],
                                1,
                                0
                            ]
                        ]],
                        "containMention": ["$max":[
                            "$cond": [
                                ["$and": [
                                    ["$ne": ["$mention", .undefined]],
                                    ["$gt": ["$_id", "$$lastReadId"]],
//                                    ["$eq": ["$mention.userId", .objectID(managerId)]]
                                ]],
                                true,
                                false
                            ]
                        ]]
                    ]],
                ],
                "as": "lastMessage"
            ]],
            [
                "$unwind" : [
                    "path": "$lastMessage",
                    "preserveNullAndEmptyArrays": .bool(true)
                ]
            ],
            [
                "$addFields" : [ "lastMessage" : ["$ifNull": ["$lastMessage",
                                                              [
                                                                "content": "",
                                                                "date": "$user.enteredDate",
                                                                "unreadCount": .int32(0),
                                                                "containMention": .bool(false),
                                                                "deletedDate": .null
                                                              ]
                                                             ]]]
            ],
            [
                "$sort" : ["lastMessage.date" : -1]
            ],
            [
                "$limit" : .int32(50)
            ],
            [
                "$lookup": [
                    "from": "users",
                    "localField": "applicant.userId",
                    "foreignField": "_id",
                    "as": "users"
                ]
            ],
            ["$unwind": "$users"],
            [
                "$project": [
                    "_id": 0,
                    "id": ["$toString": "$_id"],
                    "applicantId": ["$toString": "$applicantId"],
                    "names": [
                        ["$cond": [
                            ["$eq": ["$applicant.isChatInProgress", .bool(true)]],
                            "$users.info.name",
                            ["$concat": [
                                ["$substrCP": ["$users.info.name", 0, 1]],
                                "OO"
                            ]]
                        ]],
                        ["$concat": [
                            ["$toString": ["$sum": [
                                [
                                    "$subtract": [
                                        ["$year": .datetime(.init())],
                                        ["$year": ["$toDate":
                                                    ["$concat": [
                                                        ["$toString": "$users.info.birth"],
                                                        "-01-01"
                                                    ]]
                                                  ]]
                                    ]
                                ],
                                1
                            ]]
                            ],
                            "세"
                        ]],
                        ["$cond": [
                            "if": ["$eq": ["$users.info.gender", 0]],
                            "then": "남",
                            "else": "여"
                        ]]
                    ],
                    "type": 1,
                    "isBlock": ["$in": ["$applicant.managerId", ["$ifNull": ["$users.blockingUsers",.array([])]]]],
                    "lastMessage" : ["$cond" : [
                        ["$eq": ["$lastMessage",.undefined]],
                        .null,
                        [
                            "content" : ["$cond": [
                                ["$ne": ["$lastMessage.deletedDate", .null]],
                                "삭제된 메시지입니다.",
                                "$lastMessage.content"
                            ]],
                            "messageId": ["$toString": "$lastMessage.messageId"],
                            "date" : ["$dateToString": [
                                "date": "$lastMessage.date",
                                "format": "%Y-%m-%d %H:%M:%S",
                                "timezone":"Asia/Seoul"
                            ]],
                            "containMention": "$lastMessage.containMention"
                        ],
                    ]],
                    "notificationStatus": "$user.notificationStatus",
                    "unreadCount": ["$cond" : [
                        ["$eq": ["$lastMessage",.undefined]],
                        .int32(0),
                        "$lastMessage.unreadCount"
                    ]],
                    "image": "$users.info.image",
                    "participantCount":  [
                        "$size": [
                            "$filter" : [
                                "input": "$participants",
                                "cond": [
                                    "$eq" : ["$$this.activated", .bool(true)]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
            
            
        ]
        return pipeline
    }
    static func getUserBadgeCount(userId: BSONObjectID) -> [BSONDocument] {
        let pipeline: [BSONDocument] = [
            [
                "$match":
                    ["$and": [
                        ["participants.userId": .objectID(userId)],
                        ["brokenRoom": ["$ne": .bool(true)]],
                        ["type": ["$ne": "HR"]]
                    ]]
            ],
            ["$addFields": [
                "user": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$eq" : ["$$this.userId", .objectID(userId)]
                            ]
                        ]
                    ],0]
                ],
            ]],
            [
                "$match": ["$and": [
                        ["user.activated": .bool(true)],
                        ["user.profileImage": ["$ne": ""]],
                        ["user.forcedWithdrawal": ["$ne": .bool(true)]]
                    ]]
            ],
            ["$lookup": [
                "from": "messages",
                "let": ["roomId": "$_id","lastReadId": "$user.recentMessageId","enteredDate" : "$user.enteredDate","blockIds": "$user.blockingUserIds"],
                "pipeline": [
                    ["$match": ["$and": [
                        ["$or" : [
                            ["type": "chat"],
                            ["type": "image"]
                        ]],
                        ["$expr": ["$eq": ["$roomId", "$$roomId"]]],
                        ["$expr": ["$gt": ["$createdAt", "$$enteredDate"]]],
                        ["$expr": [
                            "$not" : [
                                "$in": [
                                    "$senderId",
                                    [
                                        "$ifNull": [
                                            "$$blockIds",
                                            .array([])]
                                    ]
                                ]
                            ]
                        ]]
                    ]]],
                    ["$group": [
                        "_id" : "$roomId",
                        "unreadCount": ["$sum": [
                            "$cond": [
                                ["$gt": ["$_id", "$$lastReadId"]],
                                1,
                                0
                            ]
                        ]]
                    ]],
                ],
                "as": "lastMessage"
            ]],
            [
                "$unwind" : "$lastMessage"
            ],
            [
                "$group": [
                    "_id" : 0,
                    "badgeCount": ["$sum": "$lastMessage.unreadCount"]
                ]
            ]
        ]
        return pipeline
    }
    
    static func getAlbaBadgeCount(userId: BSONObjectID) -> [BSONDocument] {
        let pipeline: [BSONDocument] = [
            [
                "$match":
                    ["$and": [
                        ["participants.userId": .objectID(userId)],
                        ["brokenRoom": ["$ne": .bool(true)]],
                        ["type": "alba"]
                    ]]
            ],
            ["$addFields": [
                "user": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$eq" : ["$$this.userId", .objectID(userId)]
                            ]
                        ]
                    ],0]
                ],
            ]],
            ["$addFields": [
                "isNewRoom": ["$eq": ["$user.recentMessageId", .null]]
            ]],
            [
                "$match": ["$and": [
                        ["user.activated": .bool(true)],
                        ["user.profileImage": ["$ne": ""]],
                        ["user.forcedWithdrawal": ["$ne": .bool(true)]]
                    ]]
            ],
            ["$lookup": [
                "from": "messages",
                "let": ["roomId": "$_id", "lastReadId": "$user.recentMessageId", "enteredDate": "$user.enteredDate", "blockIds": "$user.blockingUserIds"],
                "pipeline": [
                    ["$match": ["$and": [
                        ["$or" : [
                            ["type": "chat"],
                            ["type": "image"]
                        ]],
                        ["$expr": ["$eq": ["$roomId", "$$roomId"]]],
                        ["$expr": ["$gt": ["$createdAt", "$$enteredDate"]]],
                        ["$expr": [
                            "$not" : [
                                "$in": [
                                    "$senderId",
                                    [
                                        "$ifNull": [
                                            "$$blockIds",
                                            .array([])]
                                    ]
                                ]
                            ]
                        ]]
                    ]]],
                    ["$group": [
                        "_id" : "$roomId",
                        "unreadCount": ["$sum": [
                            "$cond": [
                                ["$gt": ["$_id", "$$lastReadId"]],
                                1,
                                0
                            ]
                        ]]
                    ]],
                ],
                "as": "lastMessage"
            ]],
            [
                "$unwind" : [
                    "path": "$lastMessage",
                    "preserveNullAndEmptyArrays": .bool(true)
                ]
            ],
            [
                "$group": [
                    "_id" : 0,
                    "badgeCount": ["$sum": ["$ifNull": ["$lastMessage.unreadCount", 0]]]
                ]
            ]
        ]
        return pipeline
    }
    

    
    
    static func getParticipants(roomId: BSONObjectID) -> [BSONDocument]{
        let pipeline:[BSONDocument] = [
            [
                "$match" : ["_id" : .objectID(roomId)],
            ],
            [
                "$unwind" : [
                    "path": "$participants",
                    "includeArrayIndex": "index"
                ]
            ],
            [
                "$lookup": [
                    "from": "users",
                    "localField": "participants.userId",
                    "foreignField": "_id",
                    "as": "users"
                ]
            ],
            [
                "$unwind" : "$users"
            ],
            [
                "$project": [
                    "_id": 0,
                    "name": "$users.name",
                    "userId": ["$toString": "$users.userId"],
                    "schoolName" : "$users.schoolName",
                    "isHost": ["$and": [
                        ["$eq": ["$index", .int32(0)]],
                        ["$or": [
                            ["$eq": ["type": "A"]],
                            ["$eq": ["type": "test"]]
                        ]]
                    ]]
                ]
            ]
        ]
        return pipeline
        
    }
    static func getRoomInformationV2(userId: BSONObjectID,roomId: BSONObjectID) -> [BSONDocument] {
        let pipeline: [BSONDocument] = [
            [
                "$match": [
                    "_id": .objectID(roomId)
                ]
            ],
            ["$addFields": [
                "user": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$eq" : ["$$this.userId", .objectID(userId)]
                            ]
                        ]
                    ],0]
                ],
                "hostId": ["$toString": "$hostId"]
            ]],
            [
                "$unwind" : [
                    "path": "$participants"
                ]
            ],
            [
                "$match": [
                    "$and": [
                        ["participants.activated": .bool(true)],
                        ["participants.forcedWithdrawal": ["$ne": .bool(true)]]
                    ]
                ]
            ],
            
            [
                "$lookup": [
                    "from": "users",
                    "localField": "participants.userId",
                    "foreignField": "_id",
                    "as": "users"
                ]
            ],
            [
                "$unwind" : [
                    "path": "$users",
                    "preserveNullAndEmptyArrays": true
                ]
            ],
            ["$addFields":[
                "isMe": [
                    "$eq": [
                        "$users.userId", .objectID(userId)
                    ]
                ],
//                "hostId": ["$and": [
//                    ["$eq": ["$index", .int32(0)]],
//                    ["$or": [
//                        ["$eq": ["$type", "A"]],
//                        ["$eq": ["$type", "test"]]
//                    ]]
//                ]],
                 "hasProfileImage": ["$cond": [
                    ["$eq": ["$$ROOT.participants.profileImage", ""]],
                    false,
                    true
                ]]
                ]
            ],
            ["$sort": ["isMe": -1,"hasProfileImage": -1, "users.name": 1]],
            ["$group": [
                "_id": ["$ifNull": ["$$ROOT.users.schoolName","$$ROOT.participants.schoolName"]],
                "roomId": ["$last": "$_id"],
                "content" : ["$last": "$content"],
                "image" : ["$last": "$image"],
                "imageURL" : ["$last": "$imageURL"],
                "description" : ["$last": "$description"],
                "notificationStatus" : ["$last": "$user.notificationStatus"],
                "type" : ["$last": "$$ROOT.type"],
                "hostId": ["$last": "$hostId"],
                "participants" : ["$addToSet": [
                    "userId": ["$toString": "$$ROOT.participants.userId"],
                    "schoolName": ["$ifNull": ["$$ROOT.users.schoolName","$$ROOT.participants.schoolName"]],
                    "name": ["$ifNull": ["$$ROOT.users.name", "$$ROOT.participants.name"]],
                    "profileImage":  "$$ROOT.users.profileImage",
                    "block": ["$in": ["$$ROOT.participants.userId", ["$ifNull" : ["$$ROOT.user.blockingUserIds", .array([])]]]]
                ]],
            ]],
            ["$sort": ["_id": 1]],
            ["$group": [
                "_id" : "$roomId",
                "content" : ["$last": "$content"],
                "hostId": ["$last": "$hostId"],
                "image" : ["$last": "$image"],
                "imageURL" : ["$last": "$imageURL"],
                "description" : ["$last": "$description"],
                "notificationStatus" : ["$last": "$notificationStatus"],
                "type" : ["$last": "$$ROOT.type"],
                "participants" : ["$push": [
                    "schoolName": "$$ROOT._id",
                    "users": "$$ROOT.participants"
                ]],
            ]],
            ["$addFields": ["id": ["$toString": "$_id"]]],
            ["$unset":"_id"]
        ]
        return pipeline
    }
    static func getRoomInformation(userId: BSONObjectID,roomId: BSONObjectID) -> [BSONDocument] {
        let pipeline: [BSONDocument] = [
            [
                "$match": [
                    "_id": .objectID(roomId)
                ]
            ],
            ["$addFields": [
                "user": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$eq" : ["$$this.userId", .objectID(userId)]
                            ]
                        ]
                    ],0]
                ]
            ]],
            [
                "$unwind" : [
                    "path": "$participants"
                ]
            ],
            [
                "$match": [
                    "participants.activated": .bool(true)
                ]
            ],
            [
                "$lookup": [
                    "from": "users",
                    "localField": "participants.userId",
                    "foreignField": "_id",
                    "as": "users"
                ]
            ],
            [
                "$unwind" : [
                    "path": "$users",
                    "preserveNullAndEmptyArrays": true
                ]
            ],
            ["$addFields":
                ["isMe": [
                    "$eq": [
                        "$users.userId", .objectID(userId)
                    ]
                ],
                 "isProfileImage": ["$cond": [
                    ["$eq": ["$$ROOT.participants.profileImage", ""]],
                    false,
                    true
                ]]
                ]
            ],
            ["$sort": ["isMe": -1, "users.schoolName": 1, "users.profileImage": 1]],
            ["$group": [
                "_id" : "$_id",
                "content" : ["$last": "$content"],
                "image" : ["$last": "$image"],
                "imageURL" : ["$last": "$imageURL"],
                "description" : ["$last": "$description"],
                "notificationStatus" : ["$last": "$user.notificationStatus"],
                "type" : ["$last": "$$ROOT.type"],
                "participants" : ["$push": [
                    "userId": ["$toString": "$$ROOT.participants.userId"],
                    "schoolName": ["$ifNull": ["$$ROOT.users.schoolName","$$ROOT.participants.schoolName"]],
                    "name": ["$ifNull": ["$$ROOT.users.name", "$$ROOT.participants.name"]],
                    "profileImage": ["$cond": [
                        ["$eq": ["$$ROOT.participants.profileImage", ""]],
                        "defaultImage",
                        "$$ROOT.users.profileImage"
                    ]],
                    "block": ["$in": ["$$ROOT.participants.userId", ["$ifNull" : ["$$ROOT.user.blockingUserIds", .array([])]]]]
                ]],
            ]],
            ["$addFields": ["id": ["$toString": "$_id"]]],
            ["$unset":"_id"]
        ]
        return pipeline
    }
    static func getRoom(userId: BSONObjectID,roomId: BSONObjectID?, targetId: BSONObjectID? = nil) -> [BSONDocument]{
        var match: BSONDocument =  [
            "$match": [
                "participants.userId": .objectID(userId)
            ]
        ]
        if let targetId = targetId {
            match =  [
                "$match": [
                    "$and": [
                        ["participants.userId": .objectID(targetId)],
                        ["participants.userId": .objectID(userId)]
                    ]
                ]
            ]
        }
        else if let roomId = roomId {
            match = [
                "$match": [
                    "_id": .objectID(roomId)
                ]
            ]
        }
        
        let pipeline: [BSONDocument] = [
            match,
            ["$addFields": [
                "user": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$eq" : ["$$this.userId", .objectID(userId)]
                            ]
                        ]
                    ],0]
                ]
            ]],
            [
                "$match": [
                    "user.activated": .bool(true)
                ]
            ],
            ["$lookup": [
                "from": "messages",
                "let": ["roomId": "$_id","lastReadId": "$user.recentMessageId","enteredDate": "$user.enteredDate","blockIds": "$user.blockingUserIds"],
                "pipeline": [
                    ["$match": ["$and": [
                        ["$or" : [
                            ["type": "chat"],
                            ["type": "image"]
                        ]],
                        ["$expr": ["$eq": ["$roomId", "$$roomId"]]],
                        ["$expr": ["$gt": ["$createdAt", "$$enteredDate"]]],
                        ["$expr": [
                            "$not" : [
                                "$in": [
                                    "$senderId",
                                    [
                                        "$ifNull": [
                                            "$$blockIds",
                                            .array([])]
                                    ]
                                ]
                            ]
                        ]]
                    ]]],
                    ["$sort": ["_id": 1]],
                    ["$group": [
                        "_id" : "$roomId",
                        "content" : ["$last": "$content"],
                        "date" : ["$last" : "$createdAt"],
                        "deletedDate" : ["$last" : "$deletedDate"],
                        "messageId" : ["$last" : "$_id"],
                        "unreadCount": ["$sum": [
                            "$cond": [
                                ["$gt": ["$_id", "$$lastReadId"]],
                                1,
                                0
                            ]
                        ]],
                        "containMention": ["$max":[
                            "$cond": [
                                ["$and": [
                                    ["$ne": ["$mention", .undefined]],
                                    ["$gt": ["$_id", "$$lastReadId"]],
                                    ["$eq": ["$mention.userId", .objectID(userId)]]
                                ]],
                                true,
                                false
                            ]
                        ]]
                    ]],
                ],
                "as": "lastMessage"
            ]],
            [
                "$unwind" : [
                    "path": "$lastMessage",
                    "preserveNullAndEmptyArrays": .bool(true)
                ]
            ],
            [
                "$addFields" : [ "lastMessage" : ["$ifNull": ["$lastMessage",
                                                              [
                                                                "content": "",
                                                                "date": "$user.enteredDate",
                                                                "unreadCount": .int32(0),
                                                                "containMention": .bool(false),
                                                                "deletedDate": .null
                                                              ]
                                                             ]]]
            ],
            [
                "$lookup": [
                    "from": "users",
                    "localField": "participants.userId",
                    "foreignField": "_id",
                    "as": "users"
                ]
            ],
            [
                "$unwind": "$users"
            ],
            [
                "$project": [
                    "_id": 0,
                    "id": ["$toString": "$_id"],
                    "content": 1,
                    "description": 1,
                    "type": 1,
                    "hostId": ["$toString": "$hostId"],
                    "forcedWithdrawal": "$user.forcedWithdrawal",
                    "brokenRoom": 1,
                    "postInformation": 1,
                    "lastMessage" : ["$cond" : [
                        ["$eq": ["$lastMessage", .undefined]],
                        .null,
                        [
                            "content" : ["$cond": [
                                ["$ne": ["$lastMessage.deletedDate", .null]],
                                "삭제된 메시지입니다.",
                                "$lastMessage.content"
                            ]],
                            "messageId": ["$toString": "$lastMessage.messageId"],
                            "date" : ["$dateToString": [
                                "date": "$lastMessage.date",
                                "format": "%Y-%m-%d %H:%M:%S",
                                "timezone":"Asia/Seoul"
                            ]],
                            "containMention": "$lastMessage.containMention"
                        ],
                        
                    ]],
                    "notificationStatus": "$user.notificationStatus",
                    "unreadCount": ["$cond" : [
                        ["$eq": ["$lastMessage", .undefined]],
                        .int32(0),
                        "$lastMessage.unreadCount"
                    ]],
                    "image" : 1,
                    "imageURL" : 1,
                    "profileImage": "$users.profileImage",
                    "participantCount": [
                        "$size": [
                            "$filter" : [
                                "input": "$participants",
                                "cond": [
                                    "$and": [
                                        ["$ne": ["$$this.forcedWithdrawal", .bool(true)]],
                                        ["$eq" : ["$$this.activated", .bool(true)]]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        return pipeline
    }
    static func getRoomsPipelineWithPaging(userId: BSONObjectID,lastMessageDate: String?,type: String = "A") -> [BSONDocument] {
        //yyyy-MM-dd HH:mm:ss -> UTC
        guard let lastMessageDate else {
            return RoomPipeline.getRoomsPipeline(userId: userId, type: type, schoolId: nil, districtId: nil)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(abbreviation: "KST")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let koreanDate = formatter.date(from: lastMessageDate) else {
            let pipeline:[BSONDocument] = [[
                "$match": [
                    "_id" : .objectID(userId)
                ]
            ]]
            return pipeline
        }
        let date = koreanDate.addingTimeInterval(TimeInterval(TimeZone.current.secondsFromGMT(for: koreanDate)))
        let pipeline: [BSONDocument] = [
            [
                "$match": ["$and" : [
                    [
                        "participants.userId": .objectID(userId)
                    ],
                    [ "$or": [
                        [
                            "type" : .string("A")
                        ],
                        [
                            "type": .string(type)
                        ]
                    ]]
                ]]
            ],
            ["$addFields": [
                "user": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$eq" : ["$$this.userId", .objectID(userId)]
                            ]
                        ]
                    ],0]
                ],
            ]],
            [
                "$match": [
                    "user.activated": .bool(true)
                ]
            ],
            ["$lookup": [
                "from": "messages",
                "let": ["roomId": "$_id","lastReadId": "$user.recentMessageId","enteredDate" : "$user.enteredDate","blockIds": "$user.blockingUserIds"],
                "pipeline": [
                    ["$match": ["$and": [
                        ["$or" : [
                            ["type": "chat"],
                            ["type": "image"]
                        ]],
                        ["$expr": ["$eq": ["$roomId", "$$roomId"]]],
                        ["$expr": ["$gt": ["$createdAt", "$$enteredDate"]]],
                        ["$expr": [
                            "$not" : [
                                "$in": [
                                    "$senderId",
                                    [
                                        "$ifNull": [
                                            "$$blockIds",
                                            .array([])]
                                    ]
                                ]
                            ]
                        ]]
                    ]]],
                    ["$sort": ["_id": 1]],
                    ["$group": [
                        "_id": "$roomId",
                        "content": ["$last": "$content"],
                        "date": ["$last" : "$createdAt"],
                        "deletedDate" : ["$last" : "$deletedDate"],
                        "messageId" : ["$last" : "$_id"],
                        "unreadCount": ["$sum": [
                            "$cond": [
                                ["$gt": ["$_id", "$$lastReadId"]],
                                1,
                                0
                            ]
                        ]],
                        "containMention": ["$max":[
                            "$cond": [
                                ["$and": [
                                    ["$ne": ["$mention", .undefined]],
                                    ["$gt": ["$_id", "$$lastReadId"]],
                                    ["$eq": ["$mention.userId", .objectID(userId)]]
                                ]],
                                true,
                                false
                            ]
                        ]]
                    ]],
                ],
                "as": "lastMessage"
            ]],
            [
                "$unwind" : [
                    "path": "$lastMessage",
                    "preserveNullAndEmptyArrays": .bool(true)
                ]
            ],
            [
                "$addFields" : [ "lastMessage" : ["$ifNull": ["$lastMessage",
                                                              [
                                                                "content": "",
                                                                "date": "$user.enteredDate",
                                                                "unreadCount": .int32(0),
                                                                "containMention": .bool(false),
                                                                "deletedDate": .null
                                                              ]
                                                             ]]]
            ],
            [
                "$match": [
                    "lastMessage.date": ["$lt": .datetime(date)]
                ]
            ],
            [
                "$sort" : ["lastMessage.date" : -1]
            ],
            [
                "$limit" : .int32(50)
            ],
            //            [
            //                "$lookup": [
            //                    "from": "users",
            //                    "localField": "participants.userId",
            //                    "foreignField": "userId",
            //                    "as": "users"
            //                ]
            //            ],
            [
                "$project": [
                    "_id": 0,
                    "id": ["$toString": "$_id"],
                    "image" : 1,
                    "imageURL" : 1,
                    "content": 1,
                    "type": 1,
                    "hostId": ["$toString": "$hostId"],
                    "forcedWithdrawal": "$user.forcedWithdrawal",
                    "brokenRoom": 1,
                    "description": 1,
                    "lastMessage" : ["$cond" : [
                        ["$eq": ["$lastMessage",.undefined]],
                        .null,
                        [
                            "content" : ["$cond": [
                                ["$ne": ["$lastMessage.deletedDate", .null]],
                                "삭제된 메시지입니다.",
                                "$lastMessage.content"
                            ]],
                            "messageId": ["$toString": "$lastMessage.messageId"],
                            "date" : ["$dateToString": [
                                "date": "$lastMessage.date",
                                "format": "%Y-%m-%d %H:%M:%S",
                                "timezone":"Asia/Seoul"
                            ]],
                            "containMention": "$lastMessage.containMention"
                        ],
                    ]],
                    "notificationStatus": "$user.notificationStatus",
                    "unreadCount": ["$cond" : [
                        ["$eq": ["$lastMessage",.undefined]],
                        .int32(0),
                        "$lastMessage.unreadCount"
                    ]],
                    "profileImage": "$user.profileImage",
                    "participantCount": [
                        "$size": [
                            "$filter" : [
                                "input": "$participants",
                                "cond": [
                                    "$and": [
                                        ["$ne": ["$$this.forcedWithdrawal", .bool(true)]],
                                        ["$eq" : ["$$this.activated", .bool(true)]]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        return pipeline
    }
    static func getRoomsPipeline(userId: BSONObjectID, type: String = "A", schoolId: String?, districtId: String?) -> [BSONDocument] {
       
        let pipeline: [BSONDocument] = [
            [
                "$match": ["$and" : [
                    [
                        "participants.userId": .objectID(userId)
                    ],
                    [ "$or": [
                        [
                            "type": .string("A")
                        ],
                        [
                            "type": .string(type)
                        ]
                    ]]
                ]]
            ],
            ["$addFields": [
                "user": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$eq" : ["$$this.userId", .objectID(userId)]
                            ]
                        ]
                    ],0]
                ],
                "otherUser": [
                    "$arrayElemAt": [[
                        "$filter" : [
                            "input": "$participants",
                            "cond": [
                                "$ne" : ["$$this.userId", .objectID(userId)]
                            ]
                        ]
                    ],0]
                ],
            ]],
            [
                "$match": [
                    "user.activated": .bool(true)
                ]
            ],
            [
                "$lookup": [
                    "from": "users" ,
                    "localField": "otherUser.userId",
                    "foreignField": "_id",
                    "as": "otherUsers"
                ]
            ],
            ["$unwind": "$otherUsers"],
            ["$lookup": [
                "from": "messages",
                "let": [
                    "roomId": "$_id",
                    "lastReadId": "$user.recentMessageId",
                    "blockIds": "$user.blockingUserIds"
                ],
                "pipeline": [
                    ["$match": ["$and": [
                        ["$or" : [
                            ["type": "chat"],
                            ["type": "image"]
                        ]],
                        ["$expr": ["$eq": ["$roomId", "$$roomId"]]],
//                        ["$expr": ["$gt": ["$createdAt", "$$enteredDate"]]],
                        ["$expr": [
                            "$not" : [
                                "$in": [
                                    "$senderId",
                                    [
                                        "$ifNull": [
                                            "$$blockIds",
                                            .array([])]
                                    ]
                                ]
                            ]
                        ]],
                    ]]],
                    ["$sort": ["_id": 1]],
                    ["$group": [
                        "_id" : "$roomId",
                        "content" : ["$last": "$content"],
                        "date" : ["$last" : "$createdAt"],
                        "deletedDate" : ["$last" : "$deletedDate"],
                        "messageId" : ["$last" : "$_id"],
                        "unreadCount": ["$sum": [
                            "$cond": [
                                ["$gt": ["$_id", "$$lastReadId"]],
                                1,
                                0
                            ]
                        ]],
                        "containMention": ["$max": [
                            "$cond": [
                                ["$and": [
                                    ["$ne": ["$mention", .undefined]],
                                    ["$gt": ["$_id", "$$lastReadId"]],
                                    ["$eq": ["$mention.userId", .objectID(userId)]]
                                ]],
                                true,
                                false
                            ]
                        ]],
                    ]],
                ],
                "as": "lastMessage"
            ]],
            [
                "$unwind" : [
                    "path": "$lastMessage",
                    "preserveNullAndEmptyArrays": .bool(true)
                ]
            ],
            [
                "$addFields" : [ "lastMessage" : ["$ifNull": ["$lastMessage",
                                                              [
                                                                "content": "",
                                                                "date": "$user.enteredDate",
                                                                "unreadCount": .int32(0),
                                                                "containMention": .bool(false),
                                                                "deletedDate": .null
                                                              ]
                                                             ]]]
            ],
            [
                "$sort" : ["lastMessage.date" : -1]
            ],
            [
                "$limit" : .int32(50)
            ],
            [
                "$project": [
                    "_id": 0,
                    "id": ["$toString": "$_id"],
                    "image": "$otherUsers.profileImage",
                    "imageURL": "$otherUsers.profileImage",
                    "content": "$otherUser.name",
                    "description": 1,
                    "type": 1,
                    "hostId": ["$toString": "$hostId"],
                    "forcedWithdrawal": "$user.forcedWithdrawal",
                    "brokenRoom": 1,
                    "postInformation": 1,
                    "lastMessage" : ["$cond" : [
                        ["$eq": ["$lastMessage", .undefined]],
                        .null,
                        [
                            "content" : ["$cond": [
                                ["$ne": ["$lastMessage.deletedDate", .null]],
                                "삭제된 메시지입니다.",
                                "$lastMessage.content"
                            ]],
                            "messageId": ["$toString": "$lastMessage.messageId"],
                            "date" : ["$dateToString": [
                                "date": "$lastMessage.date",
                                "format": "%Y-%m-%d %H:%M:%S",
                                "timezone":"Asia/Seoul"
                            ]],
                            "containMention": "$lastMessage.containMention"
                        ],
                    ]],
                    "notificationStatus": "$user.notificationStatus",
                    "unreadCount": ["$cond" : [
                        ["$eq": ["$lastMessage",.undefined]],
                        .int32(0),
                        "$lastMessage.unreadCount"
                    ]],
                    "profileImage": "",
                    "profileImageURL": "",
                    "participantCount": [
                        "$size": [
                            "$filter" : [
                                "input": "$participants",
                                "cond": [
                                    "$and": [
                                        ["$ne": ["$$this.forcedWithdrawal", .bool(true)]],
                                        ["$eq" : ["$$this.activated", .bool(true)]]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
       
        return pipeline
    }
    static func getLocalRooms(userId: BSONObjectID, schoolId: String, districtId: String) -> [BSONDocument] {
        let pipeline: [BSONDocument] = [
            ["$match": ["$or": [
                ["type": .string("S\(schoolId)")],
                ["type": .string("D\(districtId)")]
            ]]],
            [
                "$addFields": [
                    "user": [
                        "$arrayElemAt": [[
                            "$filter" : [
                                "input": "$participants",
                                "cond": [
                                    "$eq" : ["$$this.userId", .objectID(userId)]
                                ]
                            ]
                        ],0]
                    ],
                    "sortValue": ["$cond": [
                        ["$eq": ["$type", .string("S\(schoolId)")]],
                        0,
                        1
                    ]]
                ]
            ],
            [
                "$lookup": [
                    "from": "messages",
                    "let": ["roomId": "$_id",
                            "lastReadId": "$user.recentMessageId",
                            "enteredDate" : "$user.enteredDate",
                            "blockIds": "$user.blockingUserIds"],
                    "pipeline": [
                        ["$match": ["$and": [
                            ["$expr": ["$eq": ["$roomId", "$$roomId"]]],
                            ["$or" : [
                                ["type": "chat"],
                                ["type": "image"]
                            ]],
                            ["$expr": ["$gt": ["$createdAt", "$$enteredDate"]]],
                            ["$expr": [
                                "$not" : [
                                    "$in": [
                                        "$senderId",
                                        [
                                            "$ifNull": [
                                                "$$blockIds",
                                                .array([])]
                                        ]
                                    ]
                                ]
                            ]],
                        ]]],
                        ["$group": [
                            "_id" : "$roomId",
                            "content" : ["$last": "$content"],
                            "date" : ["$last" : "$createdAt"],
                            "deletedDate" : ["$last" : "$deletedDate"],
                            "messageId" : ["$last" : "$_id"],
                            "unreadCount": ["$sum": [
                                "$cond": [
                                    ["$gt": ["$_id", "$$lastReadId"]],
                                    1,
                                    0
                                ]
                            ]],
                            "containMention": ["$max": [
                                "$cond": [
                                    ["$and": [
                                        ["$ne": ["$mention", .undefined]],
                                        ["$gt": ["$_id", "$$lastReadId"]],
                                        ["$eq": ["$mention.userId", .objectID(userId)]]
                                    ]],
                                    true,
                                    false
                                ]
                            ]]
                        ]],
                    ],
                    "as": "lastMessage"
                ]
            ],
            [
                "$unwind" : [
                    "path": "$lastMessage",
                    "preserveNullAndEmptyArrays": .bool(true)
                ]
            ],
            [
                "$addFields" : [
                    "unreadCount" : [
                        "$ifNull": [
                            "$lastMessage.unreadCount",
                            .int32(0)
                        ]
                    ]
                ]
            ],
            [
                "$sort" : ["sortValue": -1]
            ],
            [
                "$project": [
                    "_id": 0,
                    "id": ["$toString": "$_id"],
                    "content": 1,
                    "type": 1,
                    "unreadCount": 1,
                    "containMention": ["$ifNull": ["$lastMessage.containMention", .bool(false)]],
                    "notificationStatus": "$user.notificationStatus",
                    "profileImage": "$user.profileImage",
                    "isParticipated": "$user.activated",
                    "participantCount": [
                        "$size": [
                            "$filter" : [
                                "input": "$participants",
                                "cond": [
                                    "$eq" : ["$$this.activated", .bool(true)]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        return pipeline
    }
    static func getCategoryRoom(categoryId: BSONObjectID,userId: BSONObjectID) -> [BSONDocument] {
        let pipeline: [BSONDocument] = [
            [
                "$facet": [
                    "categories": [
                        ["$sort": ["priority": -1]],
                        ["$project": [
                            "_id": 0,
                            "title": 1,
                            "id": ["$toString": "$_id"],
                            "isSelected": ["$eq": ["$_id", .objectID(categoryId)]]
                        ]]
                    ],
                    "selectedRooms": [
                        ["$match": [
                            "_id": .objectID(categoryId)
                        ]],
                        ["$unwind": "$subCategories"],
                        ["$unwind": "$subCategories.roomIds"],
                        ["$lookup": [
                            "from": "room",
                            "let": ["roomId": "$subCategories.roomIds.roomId"],
                            "pipeline": [
                                ["$match": ["$expr": ["$eq": ["$_id", "$$roomId"]]]],
                                ["$addFields": [
                                    "participants": [
                                        "$filter": [
                                            "input": "$participants",
                                            "cond": ["$eq": ["$$participant.activated", .bool(true)]],
                                            "as": "participant"
                                        ]
                                    ]
                                ]],
                                ["$project": [
                                    "_id": 0,
                                    "id": ["$toString": "$_id"],
                                    "content": 1,
                                    "description": 1,
                                    "image": 1,
                                    "imageURL": 1,
                                    "type": 1,
                                    "brokenRoom": 1,
                                    "isParticipated": ["$anyElementTrue":
                                                        [
                                                            "$map": [
                                                                "input": "$participants",
                                                                "as": "participate",
                                                                "in": ["$and": [
                                                                    ["$eq": ["$$participate.activated", .bool(true)]],
                                                                    ["$eq": ["$$participate.userId", .objectID(userId)]]
                                                                ]]
                                                            ]
                                                        ]
                                                      ],
                                    "participantCount": [
                                        "$size": "$participants"
                                    ],
                                ]]
                            ],
                            "as": "room"
                        ]],
                        ["$unwind": "$room"],
                        ["$match": [
                            "room.brokenRoom": ["$ne": .bool(true)]
                        ]],
                        ["$group": [
                            "_id": "$subCategories.subCategoryTitle",
                            "priority": ["$first": "$subCategories.priority"],
                            "rooms": ["$push": "$$ROOT.room"]
                        ]],
                        ["$addFields": ["isEmptyTitle": ["$eq": ["$_id", ""]]]],
                        ["$sort": ["isEmptyTitle": 1, "priority": -1]],
                        ["$project": [
                            "_id": 0,
                            "subCategoryTitle": "$_id",
                            "rooms": 1
                        ]]
                    ]
                ]
            ]
        ]
        
        return pipeline
        
    }
    static func findRooms(userId: BSONObjectID,type: String = "A",schoolId: String?, districtId: String?) -> [BSONDocument] {
        let pipeline: [BSONDocument] =
        [
            ["$match":[
                "$and": [
                    ["$or" : [
                        ["type": .string("A")],
                        ["type": .string(type)]
                    ]],
                    ["brokenRoom": ["$ne": .bool(true)]]
                ]
            ]],
            ["$lookup": [
                "from": "messages",
                "let": ["roomId": "$_id"],
                "pipeline": [
                    ["$match": ["$and": [
                        ["$expr": ["$eq": ["$roomId", "$$roomId"]]],
                        ["$or" : [
                            ["type": "chat"],
                            ["type": "image"]
                        ]],
                    ]]],
//                    ["$sort": ["_id": 1]],
                    ["$group": [
                        "_id" : "$roomId",
                        "date" : ["$last" : "$createdAt"]
                    ]],
                ],
                "as": "lastMessage"
            ]],
            [
                "$unwind" : [
                    "path": "$lastMessage",
                    "preserveNullAndEmptyArrays": .bool(true)
                ]
            ],
            [
                "$sort" : ["lastMessage.date" : -1]
            ],
            [
                "$limit" : .int32(150)
            ],
            [
                "$project": [
                    "_id": 0,
                    "id": ["$toString": "$_id"],
                    "content": 1,
                    "description": 1,
                    "image" : 1,
                    "imageURL" : 1,
                    "type": 1,
                    "lastMessageDate" :  ["$dateToString": [
                        "date": "$lastMessage.date",
                        "format": "%Y-%m-%d %H:%M:%S",
                        "timezone":"Asia/Seoul"
                    ]],
                    "isParticipated": ["$anyElementTrue":
                                        [
                                            "$map": [
                                                "input": "$participants",
                                                "as": "participate",
                                                "in": ["$and": [
                                                    ["$eq": ["$$participate.activated",.bool(true)]],
                                                    ["$eq": ["$$participate.userId",.objectID(userId)]]
                                                ]]
                                            ]
                                        ]
                                      ],
                    "participantCount": [
                        "$size": [
                            "$filter" : [
                                "input": "$participants",
                                "cond": [
                                    "$eq" : ["$$this.activated", .bool(true)]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        
        if let schoolId, let districtId {
            let pipeline2: [BSONDocument] = [
                [
                    "$facet": [
                        "localRooms": [
                            [
                                "$match": [
                                    "$and": [
                                        [
                                            "participants.userId": .objectID(userId)
                                        ],
                                        ["$or": [
                                            ["type": .string("S\(schoolId)")],
                                            ["type": .string("D\(districtId)")]
                                        ]]
                                    ]
                                ],
                            ],
                            [
                                "$addFields": [
                                    "user": [
                                        "$arrayElemAt": [[
                                            "$filter" : [
                                                "input": "$participants",
                                                "cond": [
                                                    "$eq" : ["$$this.userId", .objectID(userId)]
                                                ]
                                            ]
                                        ],0]
                                    ],
                                    "sortValue": ["$cond": [
                                        ["$eq": ["$type", .string("S\(schoolId)")]],
                                        0,
                                        1
                                    ]]
                                ]
                            ],
                            [
                                "$lookup": [
                                    "from": "messages",
                                    "let": ["roomId": "$_id","lastReadId": "$user.recentMessageId","enteredDate" : "$user.enteredDate","blockIds": "$user.blockingUserIds"],
                                    "pipeline": [
                                        ["$match": ["$and": [
                                            ["$or" : [
                                                ["type": "chat"],
                                                ["type": "image"]
                                            ]],
                                            ["$expr": ["$eq": ["$roomId", "$$roomId"]]],
                                            ["$expr": ["$gt": ["$createdAt", "$$enteredDate"]]],
                                            ["$expr": [
                                                "$not" : [
                                                    "$in": [
                                                        "$senderId",
                                                        [
                                                            "$ifNull": [
                                                                "$$blockIds",
                                                                .array([])]
                                                        ]
                                                    ]
                                                ]
                                            ]],
                                        ]]],
                                        
                                        ["$group": [
                                            "_id" : "$roomId",
                                            "content" : ["$last": "$content"],
                                            "date" : ["$last" : "$createdAt"],
                                            "deletedDate" : ["$last" : "$deletedDate"],
                                            "messageId" : ["$last" : "$_id"],
                                            "unreadCount": ["$sum": [
                                                "$cond": [
                                                    ["$gt": ["$_id", "$$lastReadId"]],
                                                    1,
                                                    0
                                                ]
                                            ]],
                                            "containMention": ["$max": [
                                                "$cond": [
                                                    ["$and": [
                                                        ["$ne": ["$mention", .undefined]],
                                                        ["$gt": ["$_id", "$$lastReadId"]],
                                                        ["$eq": ["$mention.userId", .objectID(userId)]]
                                                    ]],
                                                    true,
                                                    false
                                                ]
                                            ]]
                                        ]],
                                    ],
                                    "as": "lastMessage"
                                ]],
                            [
                                "$unwind" : [
                                    "path": "$lastMessage",
                                    "preserveNullAndEmptyArrays": .bool(true)
                                ]
                            ],
                            [
                                "$addFields" : [
                                    "unreadCount" : [
                                        "$ifNull": [
                                            "$lastMessage.unreadCount",
                                            .int32(0)
                                        ]
                                    ]
                                ]
                            ],
                            [
                                "$sort" : ["sortValue": -1]
                            ],
                            [
                                "$project": [
                                    "_id": 0,
                                    "id": ["$toString": "$_id"],
                                    "content": 1,
                                    "type": 1,
                                    "unreadCount": 1,
                                    "containMention": ["$ifNull": ["$lastMessage.containMention", .bool(false)]],
                                    "notificationStatus": "$user.notificationStatus",
                                    "profileImage": "$user.profileImage",
                                    "isParticipated": "$user.activated",
                                    "participantCount": [
                                        "$size": [
                                            "$filter" : [
                                                "input": "$participants",
                                                "cond": [
                                                    "$eq" : ["$$this.activated", .bool(true)]
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ],
                        "rooms": .array(pipeline.map({BSON.document($0)}))
                    ]
                ]
            ]
            return pipeline2
        }
        return pipeline
        
    }
    static func findRooms(query: String?,userId: BSONObjectID,type: String = "A",schoolId: String?, districtId: String?) -> [BSONDocument] {
        guard let query else {return RoomPipeline.findRooms(userId: userId, type: type,schoolId: schoolId,districtId: districtId)}
        guard !query.isEmpty else {return RoomPipeline.findRooms(userId: userId, type: type,schoolId: schoolId,districtId: districtId)}
        let pipeline: [BSONDocument] =
        [
            ["$search": [
                "index" : "searchRoom",
                "text" : [
                    "query" : .string(query),
                    "path" : ["content","description"]
                ]
            ]],
            [
                "$addFields" : [
                    "searchScore" : ["$meta": "searchScore"],
                    "searchHighlights" : ["$meta": "searchHighlights"]
                ]
            ],
            ["$match":[
                "$and": [
                    ["$or" : [
                        ["type": .string("A")],
                        ["type": .string(type)]
                    ]],
                    ["brokenRoom": ["$ne": .bool(true)]]
                ]
            ]],
            //            [
            //                "$match": [
            //                    "$or" : [
            //                        ["participants.userId" : ["$ne": .objectID(userId) ]],
            //                        ["participants": [
            //                            "$elemMatch": [
            //                                "userId": .objectID(userId),
            //                                "activated": false
            //                            ]
            //                        ]]
            //                    ]
            //                ]
            //            ],
            ["$sort" : ["searchScore": -1]],
            [
                "$limit" : .int32(50)
            ],
            ["$lookup": [
                "from": "messages",
                "let": ["roomId": "$_id"],
                "pipeline": [
                    ["$match": ["$and": [
                        ["$expr": ["$eq": ["$roomId", "$$roomId"]]],
                        ["$or" : [
                            ["type": "chat"],
                            ["type": "image"]
                        ]],
                    ]]],
                    ["$group": [
                        "_id" : "$roomId",
                        "date" : ["$last" : "$createdAt"]
                    ]],
                ],
                "as": "lastMessage"
            ]],
            [
                "$unwind" : [
                    "path": "$lastMessage",
                    "preserveNullAndEmptyArrays": .bool(true)
                ]
            ],
            [
                "$project": [
                    "_id": 0,
                    "id": ["$toString": "$_id"],
                    "content": 1,
                    "description": 1,
                    "searchHighlights": 1,
                    "image" : 1,
                    "imageURL" : 1,
                    "searchScore" : 1,
                    "type": 1,
                    "lastMessageDate" :  ["$dateToString": [
                        "date": "$lastMessage.date",
                        "format": "%Y-%m-%d %H:%M:%S",
                        "timezone":"Asia/Seoul"
                    ]],
                    "isParticipated": ["$anyElementTrue":
                                        [
                                            "$map": [
                                                "input": "$participants",
                                                "as": "participate",
                                                "in": ["$and": [
                                                    ["$eq": ["$$participate.activated",.bool(true)]],
                                                    ["$eq": ["$$participate.userId",.objectID(userId)]]
                                                ]]
                                            ]
                                        ]
                                      ],
                    "participantCount": [
                        "$size": [
                            "$filter" : [
                                "input": "$participants",
                                "cond": [
                                    "$eq" : ["$$this.activated", .bool(true)]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        return pipeline
    }
}
