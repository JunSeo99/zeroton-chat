import MongoDBVapor
import Vapor
import APNS

//struct UserReceive: Codable{
//    var userId: String
//    var nickname: String
//    var schoolName: String
//    var schoolId: String?
//    var districtId: String?
//    var reason: Int?
//    var profileImage: ProfileImage?
//    struct ProfileImage: Codable {
//        var image: String
//        /// default ,urlDefault, url
//        var type: String
//    }
//}
//
//struct UserReceive2: Codable{
//    var userId: String
//    var nickname: String
//    
//    
//    //MARK: - 학교 정보
//    var schoolName: String?
//    var schoolId: String?
//    var districtId: String?
//    var reason: Int?
//    //MARK: - 개인정보
//    var birthdate: String
//    var userType: String // -> "adult", "student", "manager"
//    var gender: Int32
//    var name: String
//    
//    var albaProfileImage: ProfileImage?
//    var communityProfileImage: ProfileImage?
//    var companyName: String?
//    
//    struct ProfileImage: Codable {
//        var image: String
//        var type: String
//    }
//}
//
//struct UserId: Codable{
//    var id: BSONObjectID
//    var nickname: String
//    var schoolName: String
//    var reason: Int
//}
func routes(_ app: Application) throws {

    app.get("state", use: { req async throws -> Int32 in
//
//        let rooms = try await req.roomCollection.find([
//            "$and": [
//               ["type": "A"],
//               ["hostId": .null]
//            ]
//        ]).toArray()
//        for room in rooms{
//            guard let id = room._id, room.hostId == nil else {throw Abort(.badRequest)}
//            if let firstActivated = room.participants.first(where: { $0.activated == true }){
//                let userId = firstActivated.userId
//                // 해당 조건에 맞는 문서의 hostId를 업데이트합니다.
//                let filter: BSONDocument = ["_id": .objectID(id)]
//                let update: BSONDocument = ["$set": ["hostId": .objectID(userId)]]
//                let update2 = try await req.roomCollection.updateOne(filter: filter, update: update)
//                print(update2)
//            }
//            else{
//                print("없음", id.hex)
//            }
//        }
//
//
//        try await req.mess
//        let d = try await req.messageCollection.deleteMany(["mention": ["$ne": .null]])?.deletedCount
////        guard let messageIdStr = try? req.query.get(String.self, at: "id") else {throw Abort(.badRequest)}
////        let bson = try await req.messageCollection.aggregate(MessagePipeline.getMessageUnreadCount(messageId: try BSONObjectID(messageIdStr))).next()
////        guard let count = bson?["unreadCount"]?.int32Value else {throw Abort(.badRequest)}
//        return Int32(d!)
        return 3
    })
    app.get("alive", use: { req async throws -> Int32 in
//        fatalError("testError")
        return 5
    })
}




