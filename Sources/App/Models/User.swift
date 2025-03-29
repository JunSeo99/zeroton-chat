//
//  File.swift
//  
//
//  Created by 송준서 on 2023/02/20.
//

import Vapor
@preconcurrency import MongoDBVapor

struct User: Content {
    var _id: BSONObjectID?
    var name: String
    var schoolCode: String
    var age: Int
    var mannerValue: Int
    
    var profileImage: String
    
    init(_id: BSONObjectID? = nil, name: String, schoolCode: String, age: Int, mannerValue: Int, profileImage: String) {
        self._id = _id
        self.name = name
        self.schoolCode = schoolCode
        self.age = age
        self.mannerValue = mannerValue
        self.profileImage = profileImage
    }
}


//struct UserProfile: Content {
//    var _id: BSONObjectID?
//    var userId: BSONObjectID
//    var name: String
//    var profileImage: ProfileImage
//    init(userId: BSONObjectID, name: String, profileImage: ProfileImage) {
//        self.userId = userId
//        self.name = name
//        self.profileImage = profileImage
//    }
//    struct ProfileImage: Content {
//        var type: String
//        var image: String
//    }
//}

