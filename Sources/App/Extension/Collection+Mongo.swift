//
//  Collection+Mongo.swift
//  ZeroVapor
//
//  Created by jun on 3/27/25.
//

import Foundation
import Vapor
import MongoSwift

extension Request {
    var roomCollection: MongoCollection<Room> {
        self.application.mongoDB.client.db("zeroton").collection("room", withType: Room.self)
    }
    var userCollection: MongoCollection<User> {
        self.application.mongoDB.client.db("zeroton").collection("users", withType: User.self)
    }
    var messageCollection: MongoCollection<Message> {
        self.application.mongoDB.client.db("zeroton").collection("messages", withType: Message.self)
    }

}
