//
//  File.swift
//  
//
//  Created by 송준서 on 2023/02/25.
//
import MongoDBVapor
import Vapor


class RoomContoller: RouteCollection{
    let socketService: SocketPoolService = SocketPoolService.defualt
    let awsController:AwsController
    init(awsController: AwsController) {
        self.awsController = awsController
    }
    func boot(routes: RoutesBuilder) throws {
//        let alba = routes.grouped("v1","alba",)
        let room = routes.grouped("v1","room")
        let room2 = routes.grouped("v2","room")
        room.get(":userId", use: index)
        room.get(":userId",":roomId", use: show)
        
        room.get("item",":userId",":roomId", use: getRoomItem)
        room.get("badgeCount",":userId",use: getUserBadgeCount)
        
        room.on(.POST, body: .collect(maxSize: "30mb"), use: add)
        room.on(.PUT, body: .collect(maxSize: "30mb"), use: modify)
        room.put(":userId",":roomId", use: participateRoom)
        room.put("local",":userId",":roomId", use: participateLocalRoom)
        room.get("participants",":roomId",use: findParicipants)
        room.get("search",":userId",use: findRooms)
        room.get("profileImage",":roomId",use: profileRandomImage)
        
        room.put("readAll",":userId",":roomId", use: readAll)
        room.put("notification",":userId",":roomId",":isOn", use: changeNotificationStatus)
        room.delete("withdrawal",":userId",":roomId", use: withdrawal)
       
        
//        hrRoom.post(use: makeHRRoom)
        room2.get("target", ":userId",":targetId", use: makeOrGetAlbaRoom)
        room2.get(":userId", use: indexV2)
        room2.get(":userId",":roomId", use: show2)
        room2.delete("withdrawal",":userId",":roomId", use: withdrawalV2)
    }
    
    
    func makeOrGetAlbaRoom(_ req: Request) async throws -> BSONDocument {
        guard let userIdStr: String = req.parameters.get("userId"),
              let targetIdStr: String = req.parameters.get("targetId") else {throw Abort(.badRequest)}
        guard let userId = try? BSONObjectID(userIdStr), let targetId = try? BSONObjectID(targetIdStr) else { throw Abort(.badRequest) }
        
        guard let room = try await req.roomCollection.aggregate(RoomPipeline.getRoom(userId: userId, roomId: nil, targetId: targetId)).next() else { throw Abort(.badRequest) }
        return room

    }

    func getUserBadgeCount(_ req: Request) async throws -> Int{
        guard let userIdStr = req.parameters.get("userId"),
              let userId = try? BSONObjectID(userIdStr) else {throw Abort(.badRequest)}
        if let doc = try await req.roomCollection.aggregate(RoomPipeline.getUserBadgeCount(userId: userId)).next()?["badgeCount"]  {
            return Int(doc.int64Value ?? 0)
        }
        else{
           return 0
        }
    }
    
    func getAlbaBadgeCount(_ req: Request) async throws -> BSONDocument {
        guard let userIdStr = req.parameters.get("userId"),
              let userId = try? BSONObjectID(userIdStr) else {throw Abort(.badRequest)}
        
        if let doc = try await req.roomCollection.aggregate(RoomPipeline.getAlbaBadgeCount(userId: userId)).next() {
            
            return doc
        }
        else{
            return ["badgeCount": .int32(0)]
        }
            
    }
    
    
    func readAll(_ req: Request) throws -> EventLoopFuture<Response>{
        guard let roomIdStr = req.parameters.get("roomId"),
              let userIdStr = req.parameters.get("userId"),
              let roomId = try? BSONObjectID(roomIdStr),
              let userId = try? BSONObjectID(userIdStr) else {throw Abort(.badRequest)}
        return req.roomCollection
            .updateOne(filter: ["_id":.objectID(roomId)],
                       update: ["$set" : ["participants.$[elem].recentMessageId": .objectID(BSONObjectID())]],
                       options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
            .map { value in
                Response(status: .ok)
            }
    }
    func changeNotificationStatus(_ req: Request) throws -> EventLoopFuture<Response> {
        guard let roomIdStr = req.parameters.get("roomId"),
              let userIdStr = req.parameters.get("userId"),
              let isOn = req.parameters.get("isOn", as: Bool.self),
              let roomId = try? BSONObjectID(roomIdStr),
              let userId = try? BSONObjectID(userIdStr) else {throw Abort(.badRequest)}
        return req.roomCollection
            .updateOne(filter: ["_id":.objectID(roomId)],
                       update: ["$set" : ["participants.$[elem].notificationStatus": .bool(isOn)]],
                       options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
            .map { value in
                Response(status: .ok)
            }
    }
    func withdrawal(_ req: Request) async throws -> Response {
        guard let roomIdStr = req.parameters.get("roomId"),
              let userIdStr = req.parameters.get("userId"),
              let roomId = try? BSONObjectID(roomIdStr),
              let userId = try? BSONObjectID(userIdStr) else {throw Abort(.badRequest)}
//        let force = req.parameters.get("force") ?? false
        guard let room = try await req.roomCollection.findOne(["_id": .objectID(roomId)]) else {throw Abort(.badRequest)}
      
        var update: BSONDocument = ["$set" : ["participants.$[elem].activated": .bool(false)]]
        
        try await req.roomCollection
            .updateOne(filter: ["_id":.objectID(roomId)],
                       update: update,
                       options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
        //        guard update?.modifiedCount == 1 else {throw Abort(.badRequest)}
        guard let user = try await req.userCollection.findOne(["userId": .objectID(userId)]) else {throw Abort(.badRequest)}
        let content = ""
        let message = Message(roomId: roomId, senderId: userId, content: content, createdAt: Date(), type: "withdrawal", uid: UUID().uuidString, mention: nil)
        guard let insertId = try await req.messageCollection.insertOne(message)?.insertedID.objectIDValue?.hex else {throw Abort(.badRequest)}
        // chat - notice
        let participant = room.participants.first(where: {$0.userId == userId})
        if participant?.activated == false{
            return Response(status: .ok)
        }
        if room.type != "alba" {
            let filteredCount = room.participants.filter({$0.activated}).count
            if filteredCount <= 1{
                try await req.roomCollection.deleteOne(["_id": .objectID(roomId)])
                try await req.messageCollection.deleteMany(["roomId": .objectID(roomId)])
            }
        }
        let oldId = participant?.recentMessageId ?? BSONObjectID()
        let sender: BSONDocument = [ "id" : .string(insertId),
                                     "userId": .string(userId.hex),
                                     "name": .string(user.name),
                                     "createdAt": .string(""),
                                     "uid": .string(UUID().uuidString),
                                     "unreadCount": 0,
                                     "type": "withdrawal",
                                     "roomId": .string(roomId.hex),
                                     "content": .string(content),
                                    ]
        var block = sender
        block["block"] = .bool(true)
        let show: BSONDocument = ["type": "show",
                                  "roomId": .string(roomId.hex),
                                  "oldLastId": .string(oldId.hex),
                                  "uid": .string(UUID().uuidString)]
        
        room.participants.forEach({ participant in
            guard (participant.activated && participant.forcedWithdrawal != true) || participant.userId == userId else {return}
            if participant.userId != userId {
                socketService.send(userId: participant.userId, document: show)
            }
            if participant.blockingUserIds?.contains(userId) == true{
//                socketService.send(userId: participant.userId, document: block)
            }
            else{
                socketService.send(userId: participant.userId, document: sender)
            }
        })
        return Response(status: .ok)
    }

   
    func withdrawalV2(_ req: Request) async throws -> Response {
        guard let roomIdStr = req.parameters.get("roomId"),
              let userIdStr = req.parameters.get("userId"),
              let roomId = try? BSONObjectID(roomIdStr),
              let userId = try? BSONObjectID(userIdStr) else {throw Abort(.badRequest)}
        guard let room = try await req.roomCollection.findOne(["_id": .objectID(roomId)]) else {throw Abort(.badRequest)}
        let participant = room.participants.first(where: {$0.userId == userId})
        if participant?.activated == false{ // 이미 나간 방이라면 업데이트 하지 않고 응답.
            return Response(status: .ok)
        }
        
        
        try await req.roomCollection
            .updateOne(filter: ["_id":.objectID(roomId)],
                       update: ["$set" : ["participants.$[elem].activated": .bool(false)]],
                       options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
        
        guard let user = try await req.userCollection.findOne(["userId": .objectID(userId)]) else {throw Abort(.badRequest)}
        
        let message = Message(roomId: roomId, senderId: userId, content: "", createdAt: Date(), type: "withdrawal", uid: UUID().uuidString, mention: nil)
        guard let insertId = try await req.messageCollection.insertOne(message)?.insertedID.objectIDValue?.hex else {throw Abort(.badRequest)}
        
        let filteredCount = room.participants.filter({$0.activated}).count
        if filteredCount <= 1 && room.type != "alba" {
            try await req.roomCollection.deleteOne(["_id": .objectID(roomId)])
            try await req.messageCollection.deleteMany(["roomId": .objectID(roomId)])
        }
        let oldId = participant?.recentMessageId ?? BSONObjectID()
        var sender: BSONDocument = [ "id" : .string(insertId),
                                     "userId": .string(userId.hex),
                                     "name": .string(user.name),
                                     "createdAt": .string(""),
                                     "uid": .string(UUID().uuidString),
                                     "unreadCount": 0,
                                     "type": "withdrawal",
                                     "roomId": .string(roomId.hex),
                                     "content": .string(""),
        ]
        sender["name"] = .string(user.name)
        var block = sender
        block["block"] = .bool(true)
        let show: BSONDocument = ["type": "show",
                                  "roomId": .string(roomId.hex),
                                  "oldLastId": .string(oldId.hex),
                                  "uid": .string(UUID().uuidString)]
        
        room.participants.forEach({ participant in
            guard participant.activated || participant.userId == userId else {return}
            if participant.userId != userId {
                socketService.send(userId: participant.userId, document: show)
            }
            if participant.blockingUserIds?.contains(userId) == true{
                //                socketService.send(userId: participant.userId, document: block)
            }
            else{
                socketService.send(userId: participant.userId, document: sender)
            }
        })
        return Response(status: .ok)
    }
    
    
    func profileRandomImage(_ req: Request) async throws -> String {
        guard let roomIdStr = req.parameters.get("roomId") else {throw Abort(.badRequest)}
        guard let roomId = try? BSONObjectID(roomIdStr) else {throw Abort(.badRequest)}
        guard let room = try await req.roomCollection.findOne(["_id":.objectID(roomId)]) else {throw Abort(.badRequest)}
        let profileImages = Set<String>(room.participants.flatMap({ participant in
            if !participant.activated {
                return Array<String>()
            }
            if let url = participant.profileImageURL{
                return [url]
            }
            else {
                return [participant.profileImage]
            }
        }))
        var availableProfileImages:Set<String> = []
        for i in 0...11{
            availableProfileImages.insert("https://chat-indexfinger-storage.s3.ap-northeast-2.amazonaws.com/profileImage\(i).png")
        }
        for i in 1...12 {
            for j in 1...4 {
                availableProfileImages.insert("\(i) - \(j)")
            }
        }
        if !room.type.hasPrefix("S") && !room.type.hasPrefix("D") && room._id?.hex != "642e6dabff4cc09ccd7a6767"{
            availableProfileImages = availableProfileImages.subtracting(profileImages)
        }
        if availableProfileImages.isEmpty{
            throw Abort(.forbidden)
        }
        return availableProfileImages.randomElement() ?? ""
    }
    func participateLocalRoom(_ req: Request) async throws -> String {
        let roomIdStr: String? = req.parameters.get("roomId")
        let userIdStr: String? = req.parameters.get("userId")
        let profileImage: String = try req.content.get(at: "image")
        let notificationStatus: Bool = try req.content.get(at: "notificationStatus")
        guard let roomIdStr,let userIdStr,
              let roomId = try? BSONObjectID(roomIdStr),
              let userId = try? BSONObjectID(userIdStr)
        else {throw Abort(.badGateway)}
        if profileImage.hasSuffix("png") || profileImage.hasSuffix("jpeg"){
            try await req.roomCollection
                .updateOne(filter: ["_id":.objectID(roomId)],
                           update: ["$set" : [
                            "participants.$[elem].profileImage": .string("defaultImage"),
                            "participants.$[elem].profileImageURL": .string(profileImage),
                            "participants.$[elem].notificationStatus": .bool(notificationStatus)
                           ]],
                           options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
        }
        else{
            try await req.roomCollection
                .updateOne(filter: ["_id":.objectID(roomId)],
                           update: ["$set" : [
                            "participants.$[elem].profileImage": .string(profileImage),
                            "participants.$[elem].notificationStatus": .bool(notificationStatus)
                           ]],
                           options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
        }
        
        return "\(profileImage)"
    }
    func participateRoom(_ req: Request) async throws -> BSONDocument {
        let roomIdStr: String? = req.parameters.get("roomId")
        let userIdStr: String? = req.parameters.get("userId")
        let profileImage: String? = try? req.content.get(at: "image")
//        let profileImage: String? = try? req..get(at: "image")
        guard let roomIdStr,let userIdStr,
              let roomId = try? BSONObjectID(roomIdStr),
              let userId = try? BSONObjectID(userIdStr)
        else {throw Abort(.badGateway)}
        guard var room = try await req.roomCollection.findOne(["_id": .objectID(roomId)]),
              room.brokenRoom != true else {throw Abort(.badRequest)}
        let oldParticipate = room.participants.first(where: { $0.userId == userId })
        if oldParticipate?.forcedWithdrawal == true {
            throw Abort(.notAcceptable)
        }
        if oldParticipate?.activated == true {
            let pipeline = RoomPipeline.getRoom(userId: userId, roomId: roomId)
            guard let room = try await req.roomCollection.aggregate(pipeline, withOutputType: BSONDocument.self).next() else { throw Abort(.badRequest)}
            return room
        }
        else{
            room.participants = room.participants.filter({$0.activated})
            if room.participants.count >= 100 && room._id?.hex != "642e6dabff4cc09ccd7a6767" {
                throw Abort(.forbidden)
            }
//            var availableProfileImageURLs: Set<String> = []
//            for i in 0...11{
//                availableProfileImageURLs.insert("https://chat-indexfinger-storage.s3.ap-northeast-2.amazonaws.com/profileImage\(i).png")
//            }
            var availableProfileImages: Set<String> = ["4 - 5","4 - 6"]
            //                    for i in 0...11 {
            //                        availableProfileImages.insert("0 - \(i)")
            //                    }
            for i in 1...12 {
                for j in 1...4 {
                    availableProfileImages.insert("\(i) - \(j)")
                }
            }
//            let images = Set(room.participants.flatMap { participant in
//                return [participant.profileImage,participant.profileImageURL].compactMap({$0})
//            })
//            if room._id?.hex != "642e6dabff4cc09ccd7a6767" {
//                availableProfileImages = availableProfileImages.subtracting(images)
//                availableProfileImageURLs = availableProfileImageURLs.subtracting(images)
//            }
            let image = availableProfileImages.randomElement() ?? "3 - 5"
            let participate = Room.Participant.init(userId: userId, recentMessageId: BSONObjectID(), enteredDate: Date(), notificationStatus: true, profileImage: (profileImage?.hasSuffix("png") == true || profileImage?.hasSuffix("jpeg") == true) ? image : (profileImage ?? image),profileImageURL: URL(string: profileImage ?? "")?.absoluteString, activated: true,blockingUserIds: oldParticipate?.blockingUserIds)
            guard let bson = try BSONEncoder().encode(participate) else {throw Abort(.badRequest)}
            try await req.roomCollection.updateOne(filter: ["_id":.objectID(roomId)], update: [
                "$pull": ["participants": ["userId": .objectID(userId)]]])
            try await req.roomCollection.updateOne(filter: ["_id":.objectID(roomId)], update: ["$push": ["participants": .document(bson)]])
            guard let user = try await req.userCollection.findOne(["userId":.objectID(userId)]) else {throw Abort(.badRequest)}
            let content = ""
            let message = Message(roomId: roomId, senderId: userId, content: content, createdAt: Date(), type: "participate", uid: UUID().uuidString, mention: nil)
            let result = try await req.messageCollection.insertOne(message)
            if let resultId = result?.insertedID.objectIDValue?.hex {
                let sender: BSONDocument = [ "id" : .string(resultId),
                                             "userId": .string(userId.hex),
                                             "name": .string(user.name),
                                             "createdAt": .string(""),
                                             "uid": .string(UUID().uuidString),
                                             "unreadCount": 0,
                                             "type": "participate",
                                             "roomId": .string(roomId.hex),
                                             "content": .string(content),
                                             "block": .bool(false)]
                var block = sender
                block["block"] = .bool(true)
                room.participants.forEach({ participant in
                    guard participant.userId != userId && participant.activated && participant.forcedWithdrawal != true else {return}
                    if participant.blockingUserIds?.contains(userId) == true{
                        socketService.send(userId: participant.userId, document: block)
                    }
                    else{
                        socketService.send(userId: participant.userId, document: sender)
                    }
                })
                
            }
            let pipeline = RoomPipeline.getRoom(userId: userId, roomId: roomId)
            guard let room = try await req.roomCollection.aggregate(pipeline, withOutputType: BSONDocument.self).next() else {throw Abort(.badRequest)}
            return room
        }
    }
    func findParicipants(_ req: Request) throws -> EventLoopFuture<[BSONDocument]> {
        let roomIdStr: String? = req.parameters.get("roomId")
        guard let roomIdStr else {throw CustomError.nullExeption}
        let roomId = try BSONObjectID(roomIdStr)
        let response = req.roomCollection.aggregate(RoomPipeline.getParticipants(roomId: roomId))
            .flatMap { b in
                b.toArray()
            }
        return response
    }
    func index(_ req: Request) throws -> EventLoopFuture<[BSONDocument]>{
        let userIdStr: String? = req.parameters.get("userId")
        let pagingKey: String? = try? req.query.get(at: "date")
        let type: String? = try? req.query.get(at: "type")  // 이거 임시
        guard let userIdStr else {throw CustomError.nullExeption}
        let userId = try BSONObjectID(userIdStr)
        let pipeline = RoomPipeline.getRoomsPipelineWithPaging(userId: userId, lastMessageDate: pagingKey,type: type ?? "A")
        return  req.roomCollection.aggregate(pipeline)
            .flatMap({$0.toArray()})
    }
    
    func indexV2(_ req: Request) throws -> EventLoopFuture<BSONResponse>{
        let userIdStr: String? = req.parameters.get("userId")
        let pagingKey: String? = try? req.query.get(at: "date")
        guard let userIdStr else {throw CustomError.nullExeption}
        let userId = try BSONObjectID(userIdStr)
        let pipeline = RoomPipeline.getRoomsPipelineWithPaging(userId: userId, lastMessageDate: pagingKey,type: "A")
        return  req.roomCollection.aggregate(pipeline)
            .flatMap({$0.toArray()})
            .map({ doc in
                return .array(doc)
            })
    }
    func show(_ req: Request) throws -> EventLoopFuture<BSONDocument>{
        let userIdStr: String? = req.parameters.get("userId")
        let roomIdStr: String? = req.parameters.get("roomId")
        guard let userIdStr ,let roomIdStr else {throw Abort(.badRequest)}
        let userId = try BSONObjectID(userIdStr)
        let roomId = try BSONObjectID(roomIdStr)
        let pipeline = RoomPipeline.getRoomInformation(userId: userId, roomId: roomId)
        let response = req.roomCollection.aggregate(pipeline, withOutputType: BSONDocument.self).flatMap({ cursor in
            cursor.next()
        }).unwrap(orError: CustomError.nullExeption)
        return response
    }
    func show2(_ req: Request) throws -> EventLoopFuture<BSONDocument>{
        let userIdStr: String? = req.parameters.get("userId")
        let roomIdStr: String? = req.parameters.get("roomId")
        guard let userIdStr ,let roomIdStr else {throw Abort(.badRequest)}
        let userId = try BSONObjectID(userIdStr)
        let roomId = try BSONObjectID(roomIdStr)
        let pipeline = RoomPipeline.getRoomInformationV2(userId: userId, roomId: roomId)
        let response = req.roomCollection.aggregate(pipeline, withOutputType: BSONDocument.self).flatMap({ cursor in
            cursor.next()
        }).unwrap(orError: CustomError.nullExeption)
        return response
    }
    func add(_ req: Request) async throws -> BSONDocument {
        let receive = try req.content.decode(RoomReceive.self)
        let url = receive.image != nil ? try? await awsController.createBucketPutGetObject(data: receive.image!) : nil
        let date = Date()
        let participants = [receive.userId].compactMap { userId -> Room.Participant? in
            guard let userId = try? BSONObjectID(userId) else {return nil}
            var availableProfileImages:Set<String> = ["4 - 5","4 - 6"]
            var availableProfileImageURLs: Set<String> = []
            for i in 1...12 {
                for j in 1...4 {
                    availableProfileImages.insert("\(i) - \(j)")
                }
            }
            for i in 0...11{
                availableProfileImageURLs.insert("https://chat-indexfinger-storage.s3.ap-northeast-2.amazonaws.com/profileImage\(i).png")
            }
            if availableProfileImages.contains(receive.defaultImage) {
                return Room.Participant(userId: userId, recentMessageId: nil, enteredDate: date, notificationStatus: true, profileImage: receive.defaultImage,activated: true)
            }
            guard let profileImage = availableProfileImages.randomElement() else {return nil}
            if availableProfileImageURLs.contains(receive.defaultImage) {
                return Room.Participant(userId: userId, recentMessageId: nil, enteredDate: date, notificationStatus: true, profileImage: profileImage,profileImageURL: receive.defaultImage, activated: true)
            }
            return Room.Participant(userId: userId, recentMessageId: nil, enteredDate: date, notificationStatus: true, profileImage: profileImage, activated: true)
        }
        let userId = try BSONObjectID(receive.userId)
        let newRoom = Room(participants: participants, content: receive.content, description: receive.description, createdAt: date,image: participants.first?.profileImage ?? "1 - 1", imageURL: url, hostId: userId, type: receive.type ?? "A")
        let insert = try await req.roomCollection.insertOne(newRoom)
        guard let insertId = insert?.insertedID.objectIDValue else {throw Abort(.badRequest)}
        let chat = Message(roomId: insertId, senderId: userId, content: "\(receive.content) 방이 생성 되었어요.", createdAt: Date(), type: "notice", uid: UUID().uuidString, mention: nil)
        try await req.messageCollection.insertOne(chat)
        try await req.roomCollection
            .updateOne(filter: ["_id":.objectID(insertId)],
                       update: ["$set" : ["participants.$[elem].recentMessageId": .objectID(.init())]],
                       options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
        guard let room = try await req.roomCollection.aggregate(RoomPipeline.getRoom(userId: userId, roomId: insertId)).next() else {throw Abort(.badRequest)
        }
        
        return room
    }
    
    func modify(_ req: Request) async throws -> BSONDocument {
        let receive = try req.content.decode(RoomModifyReceive.self)
        let roomId = try BSONObjectID(receive.roomId)
        let userId = try BSONObjectID(receive.userId)
        if let image = receive.image,
           let imageURL = try? await awsController.createBucketPutGetObject(data: image){
            try await req.roomCollection.updateOne(filter: ["_id": .objectID(roomId)], update: [
                "$set": [
                    "content": .string(receive.content),
                    "description": .string(receive.description),
                    "imageURL": .string(imageURL)
                ]
            ])
        }
        else if let imageURL = receive.imageURL {
            try await req.roomCollection.updateOne(filter: ["_id": .objectID(roomId)], update: [
                "$set": [
                    "content": .string(receive.content),
                    "description": .string(receive.description),
                    "imageURL": .string(imageURL)
                ]
            ])
        }
        else if let image = receive.defaultImage {
            try await req.roomCollection.updateOne(filter: ["_id": .objectID(roomId)], update: [
                "$set": [
                    "content": .string(receive.content),
                    "description": .string(receive.description),
                    "image": .string(image),
                    "imageURL": .null
                ]
            ])
        }
        else{
            try await req.roomCollection.updateOne(filter: ["_id": .objectID(roomId)], update: [
                "$set": [
                    "content": .string(receive.content),
                    "description": .string(receive.description),
                ]
            ])
        }
        if let room = try await req.roomCollection.findOne(["_id": .objectID(roomId)]) {
            room.participants.forEach({ participant in
                guard participant.activated && participant.userId != userId && participant.forcedWithdrawal != true else {return}
                socketService.send(userId: participant.userId, document: ["type": "modifiedRoom",
                                                                          "roomId": .string(roomId.hex),
                                                                          "content": .string(room.content),
                                                                          "description": .string(room.description),
                                                                          "image": room.image == nil ? .null : .string(room.image!),
                                                                          "imageURL": room.imageURL == nil ? .null : .string(room.imageURL!)
                                                                         ])
            })
        }
        guard let room = try await req.roomCollection.aggregate(RoomPipeline.getRoom(userId: userId, roomId: roomId)).next() else {throw Abort(.badRequest)
        }
        return room
    }
    
    
    func findRooms(_ req: Request) throws -> EventLoopFuture<BSONResponse> {
        let query: String? = try req.query.get(at: "query")
        let type: String? = try? req.query.get(at: "type")
        let schoolId: String? = try? req.query.get(at: "schoolId")
        let districtId: String? = try? req.query.get(at: "districtId")
        guard let userIdStr = req.parameters.get("userId") else {throw Abort(.badRequest)}
        let userId = try BSONObjectID(userIdStr)
        let pipeline = RoomPipeline.findRooms(query: query, userId: userId,type: type ?? "A",schoolId: schoolId,districtId: districtId)
        if (query == nil || query?.isEmpty == true), schoolId != nil, districtId != nil {
            let response = req.roomCollection.aggregate(pipeline)
                .flatMap { b in
                    b.next()
                }.map({ doc in
                    return BSONResponse.single(doc ?? BSONDocument())
                })
            return response
        }
        let response = req.roomCollection.aggregate(pipeline)
            .flatMap { b in
                return b.toArray()
            }.map({ doc in
                return BSONResponse.array(doc)
            })
        return response
    }
    func getRoomItem(_ req: Request) throws -> EventLoopFuture<BSONDocument>{
        let userIdStr: String? = req.parameters.get("userId")
        let roomIdStr: String? = req.parameters.get("roomId")
        guard let userIdStr ,let roomIdStr else {throw Abort(.badRequest)}
        let userId = try BSONObjectID(userIdStr)
        let roomId = try BSONObjectID(roomIdStr)
        let pipeline = RoomPipeline.getRoom(userId: userId, roomId: roomId)
        let response = req.roomCollection.aggregate(pipeline, withOutputType: BSONDocument.self).flatMap({ cursor in
            cursor.next()
        }).unwrap(orError: CustomError.nullExeption)
        return response
    }
}
enum CustomError: Error{
    case nullExeption
}
enum BSONResponse: ResponseEncodable {
    func encodeResponse(for request: Vapor.Request) -> NIOCore.EventLoopFuture<Vapor.Response> {
        switch self{
        case .array(let doc):
            let data = (try? ExtendedJSONEncoder().encode(doc)) ?? Data()
            return request.eventLoop.future(Response(body: .init(data: data)))
        case .single(let doc):
            let data = (try? ExtendedJSONEncoder().encode(doc)) ?? Data()
            return request.eventLoop.future(Response(body: .init(data: data)))
        }
    }
    
    case single(BSONDocument)
    case array([BSONDocument])
}
