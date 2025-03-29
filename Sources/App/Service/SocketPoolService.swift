//
//  File.swift
//
//
//  Created by 송준서 on 2023/02/25.
//
import NIO
@preconcurrency import MongoDBVapor
import Vapor

class SocketPoolService {
    static let defualt = SocketPoolService()
    let decoder = JSONDecoder()
    let queue = DispatchQueue(label:"socket-pool-thread")
    let timer: DispatchSourceTimer
    var connect: [BSONObjectID: SocketMember] = [:]
    let notificationService = NotificationService.defualt
    private init(){
        timer = DispatchSource.makeTimerSource(flags: [], queue: queue)
        timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(10))
        timer.setEventHandler(handler: checkConnectIsAble)
        timer.resume()
    }
    func send(userId: BSONObjectID,string:String) {
        queue.async { [weak self] in
            self?.connect[userId]?.sockets.forEach({ user in
                user.socket?.send(string)
            })
        }
    }
    func send(userId: BSONObjectID,document:BSONDocument) {
        send(userId: userId, string: document.toExtendedJSONString())
    }
    
    func addUser(userId: BSONObjectID, request: Request, socket: WebSocket) {
        // WebSocket의 이벤트 루프에서 작업을 시작합니다.
        socket.eventLoop.execute { [weak self] in
            guard let self = self else { return }
            
            // 동기화 큐를 사용해 connect에 안전하게 접근
            self.queue.sync {
                if self.connect[userId] != nil {
                    self.connect[userId]?.sockets.append(.init(socket: socket, lastHeartbeat: Date().timeIntervalSince1970))
                } else {
                    self.connect[userId] = SocketMember(userId: userId, sockets: [
                        .init(socket: socket, lastHeartbeat: Date().timeIntervalSince1970)
                    ])
                }
            }
            
            // onClose 핸들러 등록
            socket.onClose.whenComplete { close in
                socket.eventLoop.execute {
                    self.queue.sync {
                        if case let .failure(error) = close {
                            print("<socket> close Fail", error)
                        } else {
                            print("<socket> close success")
                        }
                        
                        guard let member = self.connect[userId] else {
                            print("<socket> userId socket 이미 null 임.")
                            return
                        }
                        
                        // 소켓 배열에서 해당 소켓 제거 후, 빈 배열이면 키 제거
                        if member.sockets.count == 1, member.sockets.first?.socket === socket {
                            self.connect.removeValue(forKey: userId)
                        } else {
                            self.connect[userId]?.sockets.removeAll(where: { $0.socket === socket })
                            if self.connect[userId]?.sockets.isEmpty == true {
                                self.connect.removeValue(forKey: userId)
                            }
                        }
                    }
                }
            }
            
            // onPing 핸들러 등록
            socket.onPing { ws, buf in
                socket.eventLoop.execute {
                    self.queue.sync {
                        if let index = self.connect[userId]?.sockets.firstIndex(where: { $0.socket === socket }) {
                            self.connect[userId]?.sockets[index].lastHeartbeat = Date().timeIntervalSince1970
                        }
                    }
                }
            }
            
            // onText 핸들러 등록 (비동기 처리)
            socket.onText { ws, text in
                Task {
                    do {
                        try await self.onText(ws, request, text, userId: userId)
                    } catch {
                        print(error)
                    }
                }
            }
        }
    }
    func insertNewMessage(req:Request,message:Message) async throws -> BSONObjectID{
        let newId = try await req.messageCollection.insertOne(message)?.insertedID.objectIDValue
        guard let newId = newId else {throw Abort(.badRequest)}
        return newId
    }
    func updateRecentMessageId(req:Request, userId: BSONObjectID, roomId: BSONObjectID, messageId: BSONObjectID) async throws {
        try await req.roomCollection
            .updateOne(filter: ["_id":.objectID(roomId)],
                       update: ["$set" : ["participants.$[elem].recentMessageId": .objectID(messageId)]] ,options: .init(arrayFilters: [["elem.userId": .objectID(userId)]]))
        
    }
    func getMessage(req: Request,messageId: BSONObjectID) async throws -> BSONDocument {
        let jsonString = try await req.messageCollection.aggregate(MessagePipeline.getMessagePipeline(messageId: messageId)).next()
        guard let jsonString else { throw Abort(.badRequest) }
        return jsonString
    }
    func getMessageUnreadCount(req: Request, messageId: BSONObjectID) async throws -> Int32 {
        let bson = try await req.messageCollection.aggregate(MessagePipeline.getMessageUnreadCount(messageId: messageId)).next()
        guard let count = bson?["unreadCount"]?.int32Value else { throw Abort(.badRequest) }
        return count
    }
    func onText(_ ws: WebSocket,_ req: Request,_ text: String,userId: BSONObjectID) async throws -> Void{
        guard let data = text.data(using: .utf8) else {return}
        let json = try decoder.decode(JSONData.self, from: data)
        guard case let .object(object) = json,
              case let .string(type) = object["type"] else {return}
        switch type{
        case "chat":
            if case let .string(roomIdStr) = object["roomId"],
               case let .string(text) = object["content"],
               case let .string(uid) = object["uid"] {
                print(json)
                let roomId = try BSONObjectID(roomIdStr)
                guard let room = try await req.roomCollection.findOne(["_id":.objectID(roomId)]) else {return}
                let message = Message(roomId: roomId, senderId: userId, content: text, createdAt: Date(), uid: uid,mention: nil)
                //새 메세지 저장
                if case let .object(mention) = object["mention"],
                   case let .string(messageIdStr) = mention["messageId"],
                   let messageId = try? BSONObjectID(messageIdStr),
                   case let .string(name) = mention["name"],
                   case let .string(mentionContent) = mention["content"],
                   case let .string(targetUserIdStr) = mention["userId"],
                   let targetUserId = try? BSONObjectID(targetUserIdStr)
                {
                    if case let .string(mentionName) = mention["name"] {
                        message.mention = .init(messageId: messageId, userId: targetUserId, name: name, content: mentionContent)
                    }
                    else{
                        message.mention = .init(messageId: messageId, userId: targetUserId, name: name, content: mentionContent)
                    }
                    if case let .string(image) = mention["image"] {
                        message.mention?.image = image
                    }
                }
                
                let newMessageId = try await insertNewMessage(req: req, message: message)
                //룸에서 업데이트
                try await updateRecentMessageId(req: req, userId: userId, roomId: roomId, messageId: newMessageId)
                //메세지 구하기
                var newMessage = try await getMessage(req:req, messageId: newMessageId)
                
                // 메세지 보내기
                send(userId: userId, document: newMessage)
                
                
                newMessage["unreadCount"] = .int32(Int32(room.participants.filter({$0.activated}).count - 2))
                //room안에있는 사람들에게 알림 보내거나, 소켓으로 쏘기
                var blockMessage = newMessage
                blockMessage["block"] = .bool(true)
                newMessage["block"] = .bool(false)
                room.participants.forEach { participant in
                    guard participant.userId != userId && participant.activated else {return}
                    if participant.blockingUserIds?.contains(userId) == true {
                        send(userId: participant.userId, document: blockMessage)
                    }
                    else{
                        send(userId: participant.userId, document: newMessage)
                    }
                }
                let notificationIds = room.participants.compactMap { participant in
                    if participant.notificationStatus && participant.userId != userId && participant.activated && (participant.blockingUserIds?.contains(userId) != true){
                        return participant.userId.hex
                    }
                    return nil
                }
                
                
                let name = newMessage["name"]?.stringValue ?? ""
                let notification = NotificationSender(userIds: notificationIds, content: room.content, title: name, body: "\(text)", data: ["roomId": roomIdStr, "chatType": room.type,"messageId": newMessageId.hex])
                notificationService.sendAPNs(req, notification: notification)
                
            }
            else if case let .string(roomIdStr) = object["roomId"],
                    case let .string(text) = object["content"],
                    case let .string(uid) = object["uid"]{
                let roomId = try BSONObjectID(roomIdStr)
                let message = Message(roomId: roomId, senderId: userId, content: text, createdAt: Date(), uid: uid, mention: nil)
                
                if case let .object(mention) = object["mention"],
                   case let .string(messageIdStr) = mention["messageId"],
                   let messageId = try? BSONObjectID(messageIdStr),
                   case let .string(name) = mention["name"],
                   case let .string(mentionContent) = mention["content"],
                   case let .string(targetUserIdStr) = mention["userId"],
                   let targetUserId = try? BSONObjectID(targetUserIdStr)
                {
                    message.mention = .init(messageId: messageId, userId: targetUserId, name: name, content: mentionContent)
                    if case let .string(image) = mention["image"] {
                        message.mention?.image = image
                    }
                    if case let .string(mentionName) = mention["name"] {
                        message.mention?.name = mentionName
                    }
                }
                guard let room = try await req.roomCollection.findOne(["_id":.objectID(roomId)]) else {return}
                if room.brokenRoom == true || room.participants.first(where: {$0.userId == userId})?.forcedWithdrawal == true { // 방 터졌거나 강퇴당함.
                    return
                }
                //새 메세지 저장
                let newMessageId = try await insertNewMessage(req: req, message: message)
                //룸에서 업데이트
                try await updateRecentMessageId(req: req, userId: userId, roomId: roomId, messageId: newMessageId)
                //메세지 구하기
                var newMessage = try await getMessage(req:req, messageId: newMessageId)
                // 메세지 보내기
                send(userId: userId, document: newMessage)
                
                if case let .int32(unreadCount) = (newMessage["unreadCount"]){
                    newMessage["unreadCount"] = .int32(unreadCount - 1)
                }
                
                //room안에있는 사람들에게 알림 보내거나, 소켓으로 쏘기
                var blockMessage = newMessage
                blockMessage["block"] = .bool(true)
                newMessage["block"] = .bool(false)
                room.participants.forEach { participant in
                    guard participant.userId != userId && participant.activated && participant.forcedWithdrawal != true  else {return}
                    if participant.blockingUserIds?.contains(userId) == true {
                        send(userId: participant.userId, document: blockMessage)
                    }
                    else{
                        //                        for _ in 0...1{
                        send(userId: participant.userId, document: newMessage)
                        //                        }
                    }
                }
                let notificationIds = room.participants.compactMap { participant in
                    if participant.notificationStatus && participant.userId != userId && participant.activated && (participant.blockingUserIds?.contains(userId) != true) && participant.forcedWithdrawal != true {
                        return participant.userId.hex
                    }
                    return nil
                }
                let name = newMessage["name"]?.stringValue
                let notification = NotificationSender(userIds: notificationIds, content: room.content, title: name ?? "", body: "\(text)",
                                                      data: ["roomId": roomIdStr, "chatType": room.type,"messageId": newMessageId.hex])
                notificationService.sendAPNs(req, notification: notification)
            }
        case "show":
            if case let .string(roomIdStr) = object["roomId"],
               let roomId = try? BSONObjectID(roomIdStr),
               case let .string(messageIdStr) = object["messageId"],
               let messageId = try? BSONObjectID(messageIdStr){
                let room = try await req.roomCollection.findOne(["_id":.objectID(roomId)])
                try await updateRecentMessageId(req: req, userId: userId, roomId: roomId, messageId: BSONObjectID()) // ---- a
                if room?.type.hasPrefix("S") == true ||  room?.type.hasPrefix("D") == true {
                    return
                }
                let unreadCount = try await getMessageUnreadCount(req: req, messageId: messageId) // -- b
                let sender: BSONDocument = [
                    "type": "show",
                    "roomId": .string(roomId.hex),
                    "showedId": .string(messageId.hex),
                    "unreadCount": .int32(unreadCount),
                    "uid": .string(UUID().uuidString)
                ]
                room?.participants.forEach({ participant in
                    guard participant.userId != userId && participant.activated && participant.forcedWithdrawal != true else {return}
                    send(userId: participant.userId, document: sender)
                })
                
            }
        case "show2":
            if case let .string(roomIdStr) = object["roomId"],
               let roomId = try? BSONObjectID(roomIdStr),
               case let .string(messageIdStr) = object["messageId"],
               let messageId = try? BSONObjectID(messageIdStr){
                let room = try await req.roomCollection.findOne(["_id":.objectID(roomId)])
                try await updateRecentMessageId(req: req, userId: userId, roomId: roomId, messageId: BSONObjectID())
                if room?.type.hasPrefix("S") == true ||  room?.type.hasPrefix("D") == true {
                    return
                }
                let unreadCount = try await getMessageUnreadCount(req: req, messageId: messageId)
                let sender: BSONDocument = [
                    "type": "show",
                    "roomId": .string(roomId.hex),
                    "showedId": .string(messageId.hex),
                    "unreadCount": .int32(unreadCount),
                    "uid": .string(UUID().uuidString)
                ]
                room?.participants.forEach({ participant in
                    guard participant.activated && participant.forcedWithdrawal != true else {return}
                    send(userId: participant.userId, document: sender)
                })
            }
        default:
            break
        }
    }
    func checkConnectIsAble(){
        connect.forEach { (userId: BSONObjectID, socketMember: SocketMember) in
            socketMember.sockets.forEach { socket in
                if Date().timeIntervalSince1970 > socket.lastHeartbeat + 15{
                    if let ws = socket.socket,!ws.isClosed{
                        ws.close().whenComplete({ [weak self] result in
                            guard let self = self else {return}
                            self.queue.async {
                                switch result {
                                case .success(_):
                                    self.connect[userId]?.sockets.removeAll(where: {$0.socket === ws})
                                    print("Socket TimeOut: Close 성공 \(userId.hex)")
                                case .failure(let error):
                                    self.connect[userId]?.sockets.removeAll(where: {$0.socket === ws})
                                    print("Socket TimeOut: Close 실패 Error : \(error)\(userId.hex)")
                                }
                            }
                        })
                    }
                }
                else{
                    socket.socket?.sendPing()
                }
            }
            if socketMember.sockets.count == 0{
                connect.removeValue(forKey: userId)
            }
        }
    }
    
}
