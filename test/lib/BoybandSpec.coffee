_ = require "underscore"
Promise = require "bluebird"
stream = require "readable-stream"
createLogger = require "../../core/helper/logger"
#createKnex = require "../../core/helper/knex"
#createBookshelf = require "../../core/helper/bookshelf"
createMongoDB = require "../../core/helper/mongodb"
settings = (require "../../core/helper/settings")("#{process.env.ROOT_DIR}/settings/dev.json")

domains = require "../definitions/domains.json"
workflowTypes = require "../definitions/workflowTypes.json"
activityTypes = require "../definitions/activityTypes.json"
createSWF = require "../../core/helper/swf"
helpers = require "../helpers"

Registrar = require "../../lib/Actor/Registrar"
Decider = require "../../lib/Actor/Decider"
Worker = require "../../lib/Actor/Worker"
ListenToYourHeart = require "../ListenToYourHeart"
Echo = require "../Echo"

describe "Boyband: Decider & Worker", ->
  @timeout(30000) if process.env.NOCK_BACK_MODE is "record"
  @slow(500) # relevant for tests using fixtures

  registrar = null; decider = null; worker = null;

  beforeEach ->
    registrar = new Registrar(
      {}
    ,
      logger: createLogger(settings.logger)
      swf: createSWF(settings.swf)
    )
    decider = new Decider(
      domain: "TestDomain"
      taskList:
        name: "ListenToYourHeart"
      taskCls: ListenToYourHeart
      identity: "ListenToYourHeart-test-decider"
    ,
      logger: createLogger(settings.logger)
      swf: createSWF(settings.swf)
      mongodb: createMongoDB(settings.mongodb)
    )
    worker = new Worker(
      domain: "TestDomain"
      taskList:
        name: "Echo"
      taskCls: Echo
      identity: "Echo-test-worker"
    ,
      logger: createLogger(settings.logger)
      swf: createSWF(settings.swf)
    )



  describe "domains", ->

    it "should run through `ListenToYourHeart` workflow multiple times", ->
      new Promise (resolve, reject) ->
        worker.details = _.wrap worker.details, (parent, args...) ->
          args[0]?.error?.stack = "~ stripped for tests ~"
          parent.apply(@, args)
        nock.back "test/fixtures/decider/ListenToYourHeartMultiple.json", (recordingDone) ->
          Promise.resolve()
          .then -> registrar.registerDomains(domains)
          .then -> registrar.registerWorkflowTypesForDomain(workflowTypes, "TestDomain")
          .then -> registrar.registerActivityTypesForDomain(activityTypes, "TestDomain")
          .then -> helpers.clean(registrar.swf)
          # Normally, workflow execution should be started by frontend code
          .then -> registrar.swf.startWorkflowExecutionAsync(
            helpers.generateWorkflowExecutionParams("ListenToYourHeart-test-workflow-1", "h e l l o")
          )
          .then -> registrar.swf.startWorkflowExecutionAsync(
            helpers.generateWorkflowExecutionParams("ListenToYourHeart-test-workflow-2", "Schmetterling!")
          )
          .then -> decider.poll() # ScheduleActivityTask 1
          .then -> decider.poll() # ScheduleActivityTask 2
          .then -> worker.poll() # Echo 1 Completed
          .then -> decider.poll() # CompleteWorkflowExecution
          .then -> worker.poll() # Echo 2 Failed
          .then -> decider.poll() # FailWorkflowExecution
          .then -> registrar.swf.startWorkflowExecutionAsync(
            helpers.generateWorkflowExecutionParams("ListenToYourHeart-test-workflow-3", "Knock, knock, Neo")
          )
          .then -> decider.poll() # ScheduleActivityTask 3
          .then -> worker.poll() # Echo 3 Completed
          .then -> decider.poll() # CompleteWorkflowExecution
          .then resolve
          .catch reject
          .finally recordingDone


  describe "error handling", ->

#
#      client.on "error", (msg) -> testDone(new Error(msg))
#      client.start()
#
#      worker = WorkerFactory.create(addr, "EchoApi", {}, {}, ->)
#      worker.on "error", (msg) -> testDone(new Error(msg))
#      worker.start()
#
#      client.request("EchoApi", "hello")
#      .on "error", (msg) ->
#        msg.should.be.equal("Error: Expected object, got string")
#        testDone()
#
