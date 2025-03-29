//
//  SocketMember.swift
//  ZeroVapor
//
//  Created by jun on 3/27/25.
//
import Vapor
import SwiftBSON

struct SocketMember{
    let userId:BSONObjectID
    var sockets: [Socket]
    struct Socket{
        weak var socket: WebSocket?
        var lastHeartbeat: Double
    }
}
