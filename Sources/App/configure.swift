import MongoDBVapor
import Vapor

/// Configures the application.
public func configure(_ app: Application) throws {
    // Uncomment to serve files from the /Public folder.
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    // Configure the app to connect to a MongoDB deployment. If a connection string is provided via the `MONGODB_URI`
    // environment variable it will be used; otherwise, use the default connection string for a local MongoDB server.
    try app.mongoDB.configure(Environment.get("MONGODB_URI") ?? "")


    app.http.server.configuration.hostname = "0.0.0.0"
    app.http.server.configuration.port = 8080
    let awsController = AwsController()
    ContentConfiguration.global.use(encoder: ExtendedJSONEncoder(), for: .json)
    ContentConfiguration.global.use(decoder: ExtendedJSONDecoder(), for: .json)
    // Register routes.
//    try app.register(collection: UserController())
    try app.register(collection: RoomContoller(awsController: awsController))
    try app.register(collection: MessageController(awsController: awsController))
//    try app.register(collection: ReportController())
//    try app.register(collection: RelationController())
//    try app.register(collection: HRServerController())
    try routes(app)
}
