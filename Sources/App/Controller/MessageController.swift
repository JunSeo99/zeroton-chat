//
//  File.swift
//
//
//  Created by 송준서 on 2023/02/25.
//

import MongoDBVapor
import Vapor

class MessageController: RouteCollection{
    let decoder = JSONDecoder()
    let awsController:AwsController
    init(awsController: AwsController) {
        self.awsController = awsController
    }
    let socketService = SocketPoolService.defualt
    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("v1","message")
        group.post("notice", use: notice)
        group.get(":userId",":roomId", use: getMessages)
        group.delete(":roomId",":messageId", use: removeMessage)
        //        group.get("test", use: test)
        group.get("old",":userId",":roomId",":oldId", use: getOldMessages)
        //        group.get("recent",":roomId",":recentId", use: getRecentMessages)
        group.get("recent",":userId",":roomId",":recentId", use: getRecentMessagesV2)
        group.get("lastest",":userId",":roomId", use: index)
        group.get("show",":userId",":roomId", use: show)
        group.on(.POST, "image", body: .collect(maxSize: "30mb"), use: loadWithImage(_:))
        group.on(.POST, body: .collect(maxSize: "30mb"), use: loadWithLoadingMessages(_:))
        group.webSocket(":userId", onUpgrade: connectSocket)
        group.get("middle",":userId",":roomId",":messageId",use: getMiddleMesaage)
    }
    func notice(_ req: Request) async throws -> String {
        guard let content: String = try? req.query.get(at: "content"),
              let roomType: String = try? req.query.get(at: "roomType"),
              let roomId: BSONObjectID = (try await req.roomCollection.findOne(["type": .string(roomType)]))?._id else {throw Abort(.badRequest)}
        let message = Message(roomId: roomId, senderId: try BSONObjectID("624403bb28aeca21c990500c"), content: content, createdAt: Date(), type: "notice", image: nil, uid: UUID().uuidString, mention: nil)
        try await req.messageCollection.insertOne(message)
        return roomId.hex
    }
    func removeMessage(_ req: Request) async throws -> Response {
        guard let messageIdStr: String = req.parameters.get("messageId"),
              let roomIdStr: String = req.parameters.get("roomId")else {
            throw Abort(.badRequest)
        }
        let messageId = try BSONObjectID(messageIdStr)
        let roomId = try BSONObjectID(roomIdStr)
        guard let message = try await req.messageCollection.findOneAndUpdate(filter: ["_id": .objectID(messageId)], update: [
            "$set": [
                "deletedDate": BSON.datetime(Date())
            ]
        ]) else {throw Abort(.badRequest)}
        
        
        let room = try await req.roomCollection.findOne(["_id": .objectID(roomId)])
        let sender: BSONDocument = ["type": "remove",
                                    "roomId": .string(roomId.hex),
                                    "removedId": .string(messageId.hex),
                                    "uid": .string(UUID().uuidString)]
        
        if let notiIds = room?.participants.compactMap({
            if $0.userId != message.senderId && $0.forcedWithdrawal != true && $0.notificationStatus && $0.activated && ($0.blockingUserIds?.contains(message.senderId) != true){
                return $0.userId.hex
            }
            return nil
        }),
           let room,
           let user = try await req.userCollection.findOne(["userId": .objectID(message.senderId)]){
            let notification = NotificationSender(userIds: notiIds, content: room.content, title: user.name, body: "삭제된 메시지입니다.", data: ["roomId": roomId.hex ,"chatType": room.type,"messageId": messageId.hex])
            socketService.notificationService.sendAPNs(req, notification: notification)
        }
        
        
        room?.participants.forEach { participant in
            guard participant.activated && participant.forcedWithdrawal != true else {return}
            socketService.send(userId: participant.userId, document: sender)
        }
        return .init()
    }
    func show(_ req: Request) throws -> EventLoopFuture<BSONDocument> {
        let roomIdStr: String? = req.parameters.get("roomId")
        let userIdStr: String? = req.parameters.get("userId")
        guard let userIdStr ,let roomIdStr else {throw Abort(.badRequest)}
        let roomId = try BSONObjectID(roomIdStr)
        let userId = try BSONObjectID(userIdStr)
        let room = req.roomCollection.findOne(["_id": .objectID(roomId)])
            .unwrap(or: Abort(.badRequest))
        room.whenComplete {[weak self] room in
            guard let self, case let .success(room) = room,
                  let user = room.participants.first(where: {$0.userId == userId && $0.activated == true}),
                  !room.type.hasPrefix("S"),
                  !room.type.hasPrefix("D")
            else {
                return
            }
            if let oldId = user.recentMessageId {
                let sender: BSONDocument = ["type": "show",
                                            "roomId": .string(roomId.hex),
                                            "oldLastId": .string(oldId.hex),
                                            "uid": .string(UUID().uuidString)]
                room.participants.forEach { participant in
                    guard participant.userId != userId && participant.activated && participant.forcedWithdrawal != true else {return}
                    self.socketService.send(userId: participant.userId, document: sender)
                }
            }
            else{
                let sender:BSONDocument = ["type": "show",
                                           "roomId": .string(roomId.hex),
                                           "oldLastId": .string(roomId.hex),
                                           "uid": .string(UUID().uuidString)]
                room.participants.forEach { participant in
                    guard participant.userId != userId && participant.activated && participant.forcedWithdrawal != true else {return}
                    self.socketService.send(userId: participant.userId, document: sender)
                }
            }
        }
        return req.eventLoop.flatSubmit({ () -> EventLoopFuture<BSONDocument> in
            return room.tryFlatMap { room in
                return req.roomCollection
                    .updateOne(filter: ["_id":.objectID(roomId)],
                               update: ["$set" : ["participants.$[elem].recentMessageId": .objectID(BSONObjectID())]],
                               options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
                    .flatMap { result in
                        return req.messageCollection.aggregate(MessagePipeline.getRecentMessagePipeline(roomId: roomId)).flatMap({$0.next()})
                            .unwrap(or: Abort(.badRequest))
                    }
            }
        })
    }
    func connectSocket(_ req: Request,_ ws: WebSocket) async -> Void {
        guard let userIdStr = req.parameters.get("userId"),
              let userId = try? BSONObjectID(userIdStr) else {return}
        socketService.addUser(userId: userId, request: req, socket: ws)
    }
    func loadWithImage(_ req: Request) async throws -> BSONDocument{
        let messageSender = try req.content.decode(ImageMessage.self)
        let url = try await awsController.createBucketPutGetObject(data: messageSender.imageData)
        let roomId = try BSONObjectID(messageSender.roomId)
        let senderId = try BSONObjectID(messageSender.userId)
        guard let room = try await req.roomCollection.findOne(["_id":.objectID(roomId)]) else {throw Abort(.badRequest)}
        if room.brokenRoom == true || room.participants.first(where: {$0.userId == senderId})?.forcedWithdrawal == true { // 터지거나 강퇴 당한 방.
            throw Abort(.forbidden)
        }
        let message = Message(roomId: roomId, senderId: senderId, content: "(사진)", createdAt: Date(),type: "image",image: .init(url: url, height: messageSender.imageHeight, width: messageSender.imageWidth), uid: messageSender.uid,mention: nil)
        guard var newMessageId = try await req.messageCollection.insertOne(message)?.insertedID.objectIDValue else {throw Abort(.badRequest)}
        
        let newMessage = try await socketService.getMessage(req: req, messageId: newMessageId)
        var senderMessage = newMessage
        
        //        socketService.send(userId: senderId, document: newMessage)
        if case let .int32(unreadCount) = (senderMessage["unreadCount"]){
            senderMessage["unreadCount"] = .int32(unreadCount - 1)
        }
        var blockMessage = senderMessage
        blockMessage["block"] = .bool(true)
        senderMessage["block"] = .bool(false)
        
        let notiIds = room.participants.compactMap({
            if $0.userId != senderId && $0.notificationStatus && $0.activated && ($0.blockingUserIds?.contains(senderId) != true) && $0.forcedWithdrawal != true{
                return $0.userId.hex
            }
            return nil
        })
        
        let name = newMessage["name"]?.stringValue
        let notification = NotificationSender(userIds: notiIds, content: room.content, title: name ?? "", body: "(사진)", data: ["roomId": roomId.hex ,"chatType": room.type,"messageId": newMessageId.hex])
        socketService.notificationService.sendAPNs(req, notification: notification)
        
        try await req.roomCollection
            .updateOne(filter: ["_id":.objectID(roomId)],
                       update: ["$set" : ["participants.$[elem].recentMessageId": .objectID(newMessageId)]] ,options: .init(arrayFilters: [["elem.userId": .objectID(senderId)]]))
        
        room.participants.forEach { participant in
            guard participant.userId != senderId && participant.activated && participant.forcedWithdrawal != true else {return}
            if participant.blockingUserIds?.contains(senderId) == true{
                socketService.send(userId: participant.userId, document: blockMessage)
            }
            else{
                socketService.send(userId: participant.userId, document: senderMessage)
            }
        }
        return senderMessage
    }
    func loadWithLoadingMessages(_ req: Request) async throws -> [BSONDocument]{
        let messages = try req.content.decode(MessageReceive.self)
        let roomId = try BSONObjectID(messages.roomId)
        let userId = try BSONObjectID(messages.userId)
        guard let room = try await req.roomCollection.findOne(["_id": .objectID(roomId)]) else {throw Abort(.badRequest)}
        if room.brokenRoom == true || room.participants.first(where: {$0.userId == userId})?.forcedWithdrawal == true { // 터진 방.
            throw Abort(.forbidden)
        }
        var lastMessage: BSONDocument?
        var recentMessageId = BSONObjectID()
        for messageReceive in messages.contents.reversed(){
            let findResult = try await req.messageCollection.findOne(["uid": .string(messageReceive.uid)])
            if findResult == nil{
                let messages = Message(roomId: roomId, senderId: userId, content: messageReceive.content, createdAt: Date(),uid: messageReceive.uid, mention: nil)
                if let mention = messageReceive.mention,
                   let messageId = try? BSONObjectID(mention.messageId),
                   let targetUserId = try? BSONObjectID(mention.userId){
                    messages.mention = .init(messageId: messageId, userId: targetUserId, name: mention.name, content: mention.content)
                }
                guard let newMessageId = try await req.messageCollection.insertOne(messages)?.insertedID.objectIDValue else {throw Abort(.badRequest)}
                recentMessageId = newMessageId
                var newMessage = try await socketService.getMessage(req: req, messageId: newMessageId)
                if case let .int32(unreadCount) = (newMessage["unreadCount"]){
                    newMessage["unreadCount"] = .int32(unreadCount - 1)
                }
                var blockMessage = newMessage
                blockMessage["block"] = .bool(true)
                newMessage["block"] = .bool(false)
                lastMessage = newMessage
                room.participants.forEach({ participant in
                    guard participant.activated && !(participant.userId == userId) && participant.forcedWithdrawal != true else {return}
                    if participant.blockingUserIds?.contains(userId) == true{
                        socketService.send(userId: participant.userId, document: blockMessage)
                    }
                    else{
                        socketService.send(userId: participant.userId, document: newMessage)
                    }
                })
            }
        }
        if let first = messages.contents.first{
            
            let notiIds = room.participants.compactMap({
                if $0.userId != userId && $0.notificationStatus && $0.activated && ($0.blockingUserIds?.contains(userId) != true){
                    return $0.userId.hex
                }
                return nil
            })
            guard let user = try await req.userCollection.findOne(["userId":.objectID(userId)]) else {
                throw Abort(.badRequest)
            }
            let nickname = user.name
            let notification = NotificationSender(userIds: notiIds, content: room.content, title: nickname, body: "\(first.content)", data: ["roomId": roomId.hex, "chatType": room.type])
            socketService.notificationService.sendAPNs(req, notification: notification)
            //                messages.contents.first.
            
            
            try await req.roomCollection
                .updateOne(filter: ["_id":.objectID(roomId)],
                           update: ["$set" : ["participants.$[elem].recentMessageId": .objectID(recentMessageId)]] ,options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
        }
        guard let user = room.participants.first(where: {$0.userId == userId}) else {throw Abort(.badRequest) }
        return try await req.messageCollection.aggregate(MessagePipeline.getMessagesPipeline(roomId: roomId, user: user)).toArray()
    }
    
    func index(req: Request) throws -> EventLoopFuture<[BSONDocument]> {
        let roomIdStr: String? = req.parameters.get("roomId")
        let userIdStr: String? = req.parameters.get("userId")
        guard let roomIdStr,let userIdStr else {throw Abort(.badRequest)}
        let roomId = try BSONObjectID(roomIdStr)
        let userId = try BSONObjectID(userIdStr)
        let room = req.roomCollection.findOne(["_id": .objectID(roomId)])
            .unwrap(or: Abort(.badRequest))
        room.whenComplete {[weak self] room in
            guard let self, case let .success(room) = room,
                  !room.type.hasPrefix("S"),
                  !room.type.hasPrefix("D")
            else {
                return
            }
            if let oldId = room.participants.first(where: { participant in
                participant.userId == userId
            })?.recentMessageId {
                let sender: BSONDocument = ["type": "show",
                                            "roomId": .string(roomId.hex),
                                            "oldLastId": .string(oldId.hex),
                                            "uid": .string(UUID().uuidString)]
                room.participants.forEach { participant in
                    guard participant.userId != userId && participant.activated && participant.forcedWithdrawal != true else {return}
                    self.socketService.send(userId: participant.userId, document: sender)
                }
            }
            else{
                let sender:BSONDocument = ["type": "show",
                                           "roomId": .string(roomId.hex),
                                           "oldLastId": .string(roomId.hex),
                                           "uid": .string(UUID().uuidString)]
                room.participants.forEach { participant in
                    guard participant.userId != userId && participant.activated && participant.forcedWithdrawal != true else {return}
                    self.socketService.send(userId: participant.userId, document: sender)
                }
            }
        }
        return req.eventLoop.flatSubmit({ () -> EventLoopFuture<[BSONDocument]> in
            return room.tryFlatMap { room in
                guard let participant = room.participants.first(where: {$0.userId == userId}) else {throw Abort(.badRequest)}
                return req.roomCollection
                    .updateOne(filter: ["_id":.objectID(roomId)],
                               update: ["$set" : ["participants.$[elem].recentMessageId": .objectID(BSONObjectID())]],
                               options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
                    .flatMap { result in
                        return req.messageCollection.aggregate(MessagePipeline.getMessagesPipeline(roomId: roomId,user: participant)).flatMap({$0.toArray()})
                    }
            }
        })
        
    }
    
    func getOldMessages(_ req: Request) async throws -> [BSONDocument] {
        let userIdStr: String? = req.parameters.get("userId")
        let roomIdStr: String? = req.parameters.get("roomId")
        let oldIdStr: String? = req.parameters.get("oldId")
        guard let roomIdStr,let oldIdStr,let userIdStr else {throw Abort(.badRequest)}
        let roomId = try BSONObjectID(roomIdStr)
        let oldId = try BSONObjectID(oldIdStr)
        let userId = try BSONObjectID(userIdStr)
        guard let room = try await req.roomCollection.findOne(["_id": .objectID(roomId)]) else{
            throw Abort(.badRequest)
        }
        guard let user = room.participants.first(where: {$0.userId == userId}) else {throw Abort(.badRequest)}
        return try await req.messageCollection.aggregate(MessagePipeline.getOldMessagesPipeline(roomId: roomId, messageId: oldId, user: user)).toArray()
    }
    
    func getRecentMessagesV2(_ req: Request) async throws -> [BSONDocument] {
        let userIdStr: String? = req.parameters.get("userId")
        let roomIdStr: String? = req.parameters.get("roomId")
        let recentIdStr: String? = req.parameters.get("recentId")
        guard let roomIdStr,let recentIdStr,let userIdStr else {throw Abort(.badRequest)}
        let roomId = try BSONObjectID(roomIdStr)
        let recentId = try BSONObjectID(recentIdStr)
        let userId = try BSONObjectID(userIdStr)
        guard let room = try await req.roomCollection.findOne(["_id": .objectID(roomId)]) else{
            throw Abort(.badRequest)
        }
        guard let user = room.participants.first(where: {$0.userId == userId}) else {throw Abort(.badRequest)}
        return try await req.messageCollection.aggregate(MessagePipeline.getRecentMessagesPipeline(roomId: roomId, messageId: recentId,user: user)).toArray()
    }
    func getMiddleMesaage(_ req: Request) async throws -> BSONDocument {
        let roomIdStr: String? = req.parameters.get("roomId")
        let userIdStr: String? = req.parameters.get("userId")
        let messageIdStr: String? = req.parameters.get("messageId")
        guard let roomIdStr, let userIdStr, let messageIdStr else {throw Abort(.badRequest)}
        let roomId = try BSONObjectID(roomIdStr)
        let userId = try BSONObjectID(userIdStr)
        let messageId = try BSONObjectID(messageIdStr)
        let room = try await req.roomCollection.findOne(["_id": .objectID(roomId)])
        guard let user = room?.participants.first(where: {$0.userId == userId}) else {throw Abort(.badRequest)}
        guard let message = try await req.messageCollection.aggregate(MessagePipeline.getMiddleMessagesPipeline(roomId: roomId, userId: userId, recentMessageId: messageId, user: user)).next() else {throw Abort(.badRequest)}
        return message
    }
    func getMessages(_ req: Request) throws -> EventLoopFuture<BSONDocument> {
        let roomIdStr: String? = req.parameters.get("roomId")
        let userIdStr: String? = req.parameters.get("userId")
        guard let userIdStr ,let roomIdStr else {throw Abort(.badRequest)}
        let roomId = try BSONObjectID(roomIdStr)
        let userId = try BSONObjectID(userIdStr)
        //        let messageId = BSONObjectID()
        let room = req.roomCollection.findOne(["_id": .objectID(roomId)])
            .unwrap(or: Abort(.badRequest))
        room.whenComplete {[weak self] room in
            guard let self, case let .success(room) = room,
                  !room.type.hasPrefix("S"),
                  !room.type.hasPrefix("D")
            else {
                return
            }
            if let oldId = room.participants.first(where: { participant in
                participant.userId == userId
            })?.recentMessageId {
                let sender: BSONDocument = ["type": "show",
                                            "roomId": .string(roomId.hex),
                                            "oldLastId": .string(oldId.hex),
                                            "uid": .string(UUID().uuidString)]
                room.participants.forEach { participant in
                    guard participant.userId != userId && participant.activated && participant.forcedWithdrawal != true else {return}
                    self.socketService.send(userId: participant.userId, document: sender)
                }
            }
            else{
                let sender: BSONDocument = ["type": "show",
                                            "roomId": .string(roomId.hex),
                                            "oldLastId": .string(roomId.hex),
                                            "uid": .string(UUID().uuidString)]
                room.participants.forEach { participant in
                    guard participant.userId != userId && participant.activated && participant.forcedWithdrawal != true else {return}
                    self.socketService.send(userId: participant.userId, document: sender)
                }
            }
        }
        return req.eventLoop.flatSubmit({ () -> EventLoopFuture<BSONDocument> in
            return room.tryFlatMap { room in
                guard let participant = room.participants.first(where: {$0.userId == userId}) else {throw Abort(.badRequest)}
                var recentMessageId = participant.recentMessageId
                if participant.profileImage == "" {
                    recentMessageId = BSONObjectID()
                }
                if !participant.activated {
                    if (room.type.hasPrefix("S") || room.type.hasPrefix("D")){
                        return req.roomCollection.updateOne(filter: [
                            "_id": .objectID(roomId)
                        ], update: [
                            "$set": [
                                "participants.$[elem].activated": .bool(true),
                                "participants.$[elem].recentMessageId": .objectID(BSONObjectID())
                            ]
                        ],options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
                        .flatMap { result in
                            return req.messageCollection.aggregate(MessagePipeline.getRecentMessagePipeline(roomId: roomId)).flatMap({$0.next()})
                                .unwrap(or: Abort(.badRequest))
                        }
                    }
                    else{
                        throw Abort(.badRequest)
                    }
                }
                
                return req.roomCollection
                    .updateOne(filter: ["_id":.objectID(roomId)],
                               update: ["$set" : ["participants.$[elem].recentMessageId": .objectID(BSONObjectID())]],
                               options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
                    .flatMap { result in
                        return req.messageCollection.aggregate(MessagePipeline.getMiddleMessagesPipeline(roomId: roomId, userId: userId, recentMessageId: recentMessageId ?? .init(), user: participant))
                            .flatMap({
                                return $0.next()
                            })
                        //                            .map({
                        ////                                print($0)
                        //                                return $0
                        //                            })
                            .unwrap(orError: Abort(.badRequest))
                    }
            }
        })
    }
    
}
