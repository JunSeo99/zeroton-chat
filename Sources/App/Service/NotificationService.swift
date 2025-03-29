//
//  NotificationService.swift
//  ZeroVapor
//
//  Created by jun on 3/27/25.
//

import Foundation
import Vapor
import APNSwift
import SwiftBSON

class NotificationService{
    static let defualt = NotificationService()
    private init(){}
    func sendAPNs(_ req: Request, notification: NotificationSender){
//        let uri = URI(stringLiteral: "http://ec2-15-164-125-91.ap-northeast-2.compute.amazonaws.com:8080/notification")
//        if notification.userIds.isEmpty{
//            return
//        }
//        req.client.post(uri, content: notification)
//            .whenComplete { result in
//                switch result{
//                case .success:
//                    break
//                case .failure(let error):
//                    print("Notification Error : \(error)")
//                }
//            }
    }
    func sendAPNs(_ req: Request, notification: BSONDocument){
//        let uri = URI(stringLiteral: "http://ec2-15-164-125-91.ap-northeast-2.compute.amazonaws.com:8080/notification")
//        if notification["userIds"]?.arrayValue?.isEmpty != false{
//            return
//        }
//        req.client.post(uri, content: notification)
//            .whenComplete { result in
//                switch result{
//                case .success:
//                    break
//                case .failure(let error):
//                    print("Notification Error : \(error)")
//                }
//            }
    }
    func sendAPNs(_ req: Request, fcmTokens: BSONDocument){
//        let uri = URI(stringLiteral: "http://ec2-15-164-125-91.ap-northeast-2.compute.amazonaws.com:8080/notification/tokens")
//        if fcmTokens["tokens"]?.arrayValue?.isEmpty != false{
//            return
//        }
//        req.client.post(uri, content: fcmTokens)
//            .whenComplete { result in
//                switch result{
//                case .success:
//                    break
//                case .failure(let error):
//                    print("Notification Error : \(error)")
//                }
//            }
    }
}
struct NotificationSender: Content{
    var userIds: [String]
    var content: String
    var title: String
    var body: String?
    var data: [String:String]? //chatType
}
struct NotificationWithTokens: Content{
    var tokens: [String]
    var content: String
    var title: String
    var body: String?
    var data: [String:String]?
}
