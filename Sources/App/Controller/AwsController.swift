//
//  AwsController.swift
//  ZeroVapor
//
//  Created by jun on 3/27/25.
//

import MongoDBVapor
import Vapor
import SotoS3

final class AwsController {
    let client: AWSClient
    init(){
        let client = AWSClient(
            credentialProvider: .static(accessKeyId: Environment.get("S3_ACCESS_KEY_ID") ?? "", secretAccessKey: Environment.get("S3_SECRET_ACCESS_KEY") ?? ""),
            httpClientProvider: .createNew
        )
        self.client = client
        self.s3 = S3(client: client, region: .apnortheast2)
    }
    let bucket = "chat-indexfinger-storage"
    let s3:S3
    func createBucketPutGetObject(data: Data) async throws -> String {
        // Create Bucket, Put an Object, Get the Object
//        let createBucketRequest = S3.CreateBucketRequest(bucket: bucket)
//        _ = try await s3.createBucket(createBucketRequest)
        // Upload text file to the s3
        let key = UUID().uuidString + ".jpeg"
        let putObjectRequest = S3.PutObjectRequest(
            acl: .publicRead,
            body: .data(data),
            bucket: bucket,
            key: key
        )
        _ = try await s3.putObject(putObjectRequest)
        return "https://d2mflm5u6xw6b8.cloudfront.net/\(key)"
    }
    deinit{
        do{
            try client.syncShutdown()
        }
        catch(let e){
            print(e.localizedDescription)
        }
    }
}
