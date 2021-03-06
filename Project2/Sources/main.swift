import Kitura
import HeliumLogger
import LoggerAPI

import SwiftyJSON

import CouchDB

import KituraStencil

HeliumLogger.use()

//  Connecting to CouchDB
let connectionProperties = ConnectionProperties(host: "localhost", port: 5984, secured: false)
let client = CouchDBClient(connectionProperties: connectionProperties)
let database = client.database("polls")

let router = Router()

router.get("/polls/list") {
    request, response, next in
    
    //  Has a closure which makes this look asynchronous
    //  but it is actually synchronous.
    database.retrieveAll(includeDocuments: true) {
        docs, error in

        //  Ensure this is only run after the documents are fetched
        defer { next() }
        
        if let error = error {
            let errorMessage = error.localizedDescription
            let status = ["status": "error", 
                          "message": errorMessage]
            let result = ["result": status]
            let json = JSON(result)

            response.status(.OK).send(json: json)
        } else {

            //  Success!!!
            let status = ["status": "ok"]
            var polls = [[String: Any]]()

            if let docs = docs {
                for document in docs["rows"].arrayValue {
                    
                    var poll = [String: Any]()
 
                    poll["id"] = document["id"].stringValue
                    poll["title"] = document["doc"]["title"].stringValue
                    poll["option1"] = document["doc"]["option1"].stringValue
                    poll["option2"] = document["doc"]["option2"].stringValue
                    poll["votes1"] = document["doc"]["votes1"].intValue
                    poll["votes2"] = document["doc"]["votes2"].intValue
          
                    polls.append(poll)
                }
            }

            let result: [String: Any] = ["result": status, "polls": polls]
            let json = JSON(result)

            response.status(.OK).send(json: json)
        } 
    }
}

//  Putting this before the second /polls/create loop will cause
//  Kitura to parse the submitted data for us
router.post("/polls/create", middleware: BodyParser())

router.post("/polls/create") {
    request, response, next in
    // defer { next() }

    //  First check to see if any data was submitted
    guard let values = request.body else {
        try response.status(.badRequest).end()
        return
    }

    //  Now try to get all the URL encoded values
    guard case .urlEncoded(let body) = values else {
        try response.status(.badRequest).end()
        return
    }

    //  Now check for fields that we expect to be in the request
    //  and populated with a value
    let fields = ["title", "option1", "option2"]

   //  var to store the values of the above fields
   var poll = [String: Any]()

    for field in fields {
        //  Check that the field exists and remove any whitespace
        if let value = body[field]?.trimmingCharacters(in: .whitespacesAndNewlines) {
            //  Make sure it has something in it
            if value.characters.count > 0 {
                //  Add it to our list of values
                poll[field] = value

                //  Continue to next loop iteration
                continue
            }
        }

        //  If we are here then the value does not exist
        //  or exists but is blank
        try response.status(.badRequest).end()
        return
    }

    //  Validation is complete.  Time to update the db
    
    //  Set a couple of default values
    poll["votes1"] = 0
    poll["votes2"] = 0

    let json = JSON(poll)

    database.create(json) { id, revision, doc, error in
        defer { next() }

        if let id = id {
            //  document was successfully created so send back to
            //  the user
            let status = ["status": "ok", "id": id]
            let result = ["result": status]
            let json = JSON(result)

            response.status(.OK).send(json: json)
        } else {
            let errorMessage = error?.localizedDescription ?? "Unknown Error"
            let status = ["status": "error", "message": errorMessage]
            let result = ["result": status]
            let json = JSON(result)

            response.status(.internalServerError).send(json: json)
        }
    }
}

router.post("/polls/vote/:pollid", middleware: BodyParser())

router.post("/polls/vote/:pollid") {
    request, response, next in

    //  Make sure we have valid values
    guard let poll = request.parameters["pollid"] else {
        try response.status(.badRequest).end()
        return
    }

    //  Works with BodyParser above or else get nil value
    guard let values = request.body else {
        try response.status(.badRequest).end()
        return
    }

    //  Get the URL Encoded fields
    guard case .urlEncoded(let body) = values else {
        try response.status(.badRequest).end()
        return
    }

    //  Get the poll that the user requested
    database.retrieve(poll) { doc, error in
        defer { next() }

        if let error = error {
            let errorMessage = error.localizedDescription
            let status = ["status": "error", "message": errorMessage]
            let result = ["result": status]
            let json = JSON(result)

            response.status(.notFound).send(json: json)
        } else if let doc = doc {

            var newDocument = doc

            let id = doc["_id"].stringValue
            let rev = doc["_rev"].stringValue
            
            if let vote = body["vote"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
            
                switch (vote) {
                case "1":
                    newDocument["votes1"].intValue += 1
                case "2":
                    newDocument["votes2"].intValue += 1
                default:
                    let status = ["status": "error", "message": "Bad vote option"]
                    let result = ["result": status]
                    let json = JSON(result)

                    response.status(.badRequest).send(json: json)
                    return
                }
            } else {
                let status = ["status": "error", "message": "Bad vote option"]
                let result = ["result": status]
                let json = JSON(result)

                response.status(.badRequest).send(json: json)
                return
            }

            database.update(id, rev: rev, document: newDocument) { rev, doc, error in
                defer { next() }

                if let error = error {
                    let status = ["status": "error"]
                    let result = ["result": status]
                    let json = JSON(result)

                    response.status(.conflict).send(json: json)

                } else {
                    let status = ["status": "ok"]
                    let result = ["result": status]
                    let json = JSON(result)

                    response.status(.OK).send(json: json)
                }
            }
        }
    }
}

router.post("/polls/delete/:pollid") {
    request, response, next in

    guard let poll = request.parameters["pollid"] else {
        try response.status(.badRequest).end()
        return
    }

    database.retrieve(poll) { doc, error in
        if let error = error {
            let errorMessage = error.localizedDescription
            let status = ["status": "error", "message": errorMessage]
            let result = ["result": status]
            let json = JSON(result)

            response.status(.notFound).send(json: json)
            next()
        } else if let doc = doc {
            
            let id = doc["_id"].stringValue
            let rev = doc["_rev"].stringValue

            database.delete(id, rev: rev, failOnNotFound: true) { error in
                defer { next() }

                if let error = error {
                    let errorMessage = error.localizedDescription
                    let status = ["status": "error", "message": errorMessage]
                    let result = ["result": status]
                    let json = JSON(result)

                    response.status(.conflict).send(json: json)

                } else {
                    let status = ["status": "ok"]
                    let result = ["result": status]
                    let json = JSON(result)

                    response.status(.OK).send(json: json)
                }
            }
        }
    }
}

Kitura.addHTTPServer(onPort: 8090, with: router)
Kitura.run()

