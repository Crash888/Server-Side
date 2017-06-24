import Kitura
import LoggerAPI
import HeliumLogger

import KituraStencil

//  Activates the Helium Logger
HeliumLogger.use()

let bios = [
    "kirk" : "My name is James Kirk and I love snakes.",
    "picard" : "My name is Jean-Luc Picard and I'm mad for cats.",
    "sisko" : "My name is Benjamin Sisko and I'm all about the budgies.", 
    "janeway" : "My name is Kathryn Janeway and I want to hug every hamster", 
    "archer" : "My name is Jonathan Archer and beagles are my thing."
]

func setContext() -> [String : Any] {
    //  Create context dictionary to pass to the template
    var context = [String : Any]()
    
    //  Sort the people in alphabetical order
    context["people"] = bios.keys.sorted()

    return context
}

let router = Router()

router.setDefault(templateEngine: StencilTemplateEngine())
router.all("/static", middleware: StaticFileServer())

router.get("/") {
    request, response, next in
    Log.info("Trying to render something")
    defer { next() }
    Log.info("After the next thing")
    do {
        try response.render("home.stencil", context: [:])
    } catch {
        print ("\(error.localizedDescription)")
        print ("Problem rendering")
    }    
Log.info("After the render line")
    //next()
}

router.get("/staff") {
    request, response, next in
    defer { next() }

    var context = setContext()

    do {
        try response.render("staff.stencil", context: context)
    } catch {
        print ("Cannot render /staff")
    }
}

router.get("/staff/:name") {
    request, response, next in
    defer { next() }

    //  Get the name from the parameter passed in
    guard let name = request.parameters["name"] else { return }

    var context = setContext()

    //  Find a staff member by the name
    if let bio = bios[name] {
        //  we found one
        context["name"] = name
        context["bio"] = bio
    }

    do {
        try response.render("staff.stencil", context: context)
    } catch {
        print("Error rendering staff")
        print("\(error.localizedDescription)")
    }
}

router.get("/contact") {
    request, response, next in
    defer { next() }
    try response.render("contact.stencil", context: [:])
}

Kitura.addHTTPServer(onPort: 8090, with: router)
Kitura.run()

