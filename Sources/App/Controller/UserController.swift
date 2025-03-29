//
//  File.swift
//  
//
//  Created by 송준서 on 2023/02/25.
//

import Vapor
import MongoDBVapor

//class UserController: RouteCollection{
//    func boot(routes: RoutesBuilder) throws {
//        let user = routes.grouped("v1","user")
//        let userV2 = routes.grouped("v2","user")
//        userV2.post("register", use: registerV2)
//        userV2.post("company", use: registerCompany)
//        userV2.post("resign", use: resign)
//        
//        user.post("register", use: register)
//        user.put("block",":userId",":targetId",":roomId", use: block)
//        user.put("unblock",":userId",":targetId",":roomId", use: unblock)
//        
//        
//        
//    }
//    
//  
//
//    func unblock(_ req: Request) async throws -> BSONDocument{
//        guard let userIdStr = req.parameters.get("userId"),
//              let targetIdStr = req.parameters.get("targetId"),
//              let roomIdStr = req.parameters.get("roomId"),
//              let userId = try? BSONObjectID(userIdStr),
//              let targetId = try? BSONObjectID(targetIdStr),
//              let roomId = try? BSONObjectID(roomIdStr)
//        else {throw Abort(.badRequest)}
//        try await req.roomCollection.updateOne(filter: ["_id": .objectID(roomId)], update: ["$pull": ["participants.$[elem].blockingUserIds": .objectID(targetId)]],options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
//        guard let room = try await req.roomCollection.findOne(["_id": .objectID(roomId)]) else {throw Abort(.badRequest)}
//        guard let user = room.participants.first(where: {$0.userId == userId}) else {throw Abort(.badRequest)}
//        guard let newMessages = try await req.messageCollection.aggregate(MessagePipeline.getMessagesPipeline(roomId: roomId, user: user, isHR: room.announcementIds?.isEmpty == false)).next() else {throw Abort(.badRequest)}
//        return newMessages
//    }
//}
//
