_ = require "underscore"
Promise = require "bluebird"
stream = require "readable-stream"
input = require "../../core/test-helper/input"
createDependencies = require "../../core/helper/dependencies"
settings = (require "../../core/helper/settings")("#{process.env.ROOT_DIR}/settings/test.json")

domains = require "../definitions/domains.json"
workflowTypes = require "../definitions/workflowTypes.json"
activityTypes = require "../definitions/activityTypes.json"
helpers = require "../helpers"
cleanup = require "../../helper/cleanup"

Registrar = require "../../lib/Actor/Registrar"
Decider = require "../../lib/Actor/Decider"
Worker = require "../../lib/Actor/Worker"
Cron = require "../../lib/Actor/Cron"
ListenToYourHeart = require "../ListenToYourHeart"
Echo = require "../Echo"

describe "Cron", ->
  @timeout(60000) if process.env.NOCK_BACK_MODE is "record"
  @slow(500) # relevant for tests using fixtures

  dependencies = createDependencies(settings, "Cron")
  mongodb = dependencies.mongodb

  Commands = mongodb.collection("Commands")
  Issues = mongodb.collection("Issues")
  Steps = mongodb.collection("Steps")

  registrar = null; decider = null; worker = null; cron = null;

  commandIds = ["zhk6CpJ75FB2GmNCe", "vLZmn6aCwekJ7HvxX"]
  steps =
    manualMode:
      _id: "CCykeZzwd3ZTurM3i"
      userId: "DenisGorbachev"
      cls: "ListenToYourHeart"
      isAutorun: false
    refreshPlannedAtPast:
      _id: "wwzkZTu4qvSBdqJBX"
      userId: "DenisGorbachev"
      cls: "ListenToYourHeart"
      isAutorun: true
      refreshPlannedAt: new Date("2015-05-15T17:52:00.000Z")
    refreshPlannedAtPastWithExplicitRefreshInterval:
      _id: "hSjHoH2drFcayvDSB"
      userId: "DenisGorbachev"
      cls: "ListenToYourHeart"
      isAutorun: true
      refreshPlannedAt: new Date("2015-05-15T17:56:00.000Z")
      refreshInterval: 30 * 60000
    refreshPlannedAtFuture:
      _id: "Kvw3vj8XFHHZ3emSx"
      userId: "DenisGorbachev"
      cls: "ListenToYourHeart"
      isAutorun: true
      refreshPlannedAt: new Date("2015-05-15T18:08:00.000Z")

  beforeEach ->
    registrar = new Registrar(
      {}
    ,
      dependencies
    )
    decider = new Decider(
      domain: "Test"
      taskList:
        name: "ListenToYourHeart"
      taskCls: ListenToYourHeart
      identity: "ListenToYourHeart-test-decider"
    ,
      dependencies
    )
    worker = new Worker(
      domain: "Test"
      taskList:
        name: "Echo"
      taskCls: Echo
      identity: "Echo-test-worker"
      env: "test"
    ,
      dependencies
    )
    cron = new Cron(
      domain: "Test"
      identity: "Cron-test-worker"
      token: "TBN871ukMn14Hyb0437tt5B1EGmX01u9xzF96nFCDQZI4Yh3xraCVCekoxOm6C2A"
      url: "http://localhost:3000"
    ,
      dependencies
    )
    sinon.stub(cron, "getCurrentDate").returns(new Date("2015-05-15T18:00:00.000Z"))
    Promise.bind(@)
    .then ->
      Promise.all [
        Commands.remove()
        Issues.remove()
        Steps.remove()
      ]
    .then ->
      Promise.all(Steps.insert(step) for mode, step of steps)

  it "should run once each step with multiple instances @fast", ->
    new Promise (resolve, reject) ->
      nock.back "test/fixtures/cron/NormalRun.json", (recordingDone) ->
        Promise.bind(@)
        .then -> registrar.registerDomains(domains)
        .then -> registrar.registerWorkflowTypesForDomain(workflowTypes, "Test")
        .then -> registrar.registerActivityTypesForDomain(activityTypes, "Test")
        .then -> cleanup(
          domain: "Test"
          startTimeFilter:
            oldestDate: 0
          typeFilter:
            name: "ListenToYourHeart"
            version: "1.0.0"
        ,
          dependencies
        )
        .then -> sinon.stub(cron, "getInput").returns(new Promise.resolve([{}, {
          Echo:
            messages: ["Hello Cron"]
        }]))
        .then ->
          Promise.all [# let it burn!
            cron.schedule(commandIds)
            cron.schedule(commandIds)
            cron.schedule(commandIds)
            cron.schedule(commandIds)
            cron.schedule(commandIds)
          ]
        .then -> decider.poll()
        .then -> decider.poll()
        .then ->
          Steps.findOne({_id: steps.refreshPlannedAtPast._id}).then (step) ->
            step.refreshPlannedAt.getTime().should.equal(new Date("2015-05-15T18:05:00.000Z").getTime())
        .then ->
          Steps.findOne({_id: steps.refreshPlannedAtPastWithExplicitRefreshInterval._id}).then (step) ->
            step.refreshPlannedAt.getTime().should.equal(new Date("2015-05-15T18:30:00.000Z").getTime())
        .then ->
          Commands.count().should.eventually.equal(2)
        .then ->
          Commands.findOne({stepId: steps.refreshPlannedAtPast._id}).then (command) ->
            command.isStarted.should.be.true
            command.isCompleted.should.be.false
            command.isFailed.should.be.false
        .then -> worker.poll()
        .then -> worker.poll()
        .then -> decider.poll()# CompleteWorkflowExecution
        .then -> decider.poll()# CompleteWorkflowExecution
        .then ->
          Commands.findOne({stepId: steps.refreshPlannedAtPast._id}).then (command) ->
            command.isStarted.should.be.true
            command.isCompleted.should.be.true
            command.isFailed.should.be.false
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it "shouldn't start workflow execution in dry-run mode @fast", ->
    cron.isDryRun = true
    new Promise (resolve, reject) ->
      nock.back "test/fixtures/cron/isDryRun.json", (recordingDone) ->
        Promise.bind(@)
        .then -> sinon.stub(cron, "getInput").returns(new Promise.resolve([{}, {
          Echo:
            messages: ["Hello Cron"]
        }]))
        .then -> cron.schedule(commandIds)
        .then ->
          Commands.count().should.eventually.equal(2)
        .then -> dependencies.swf.listOpenWorkflowExecutionsAsync(
          domain: "Test"
          startTimeFilter:
            oldestDate: 0
          typeFilter:
            name: "ListenToYourHeart"
            version: "1.0.0"
        )
        .then (data) -> data.executionInfos.length.should.be.equal(0)
        .then @assertScopesFinished
        .then resolve
        .catch reject
        .finally recordingDone

  it "shouldn't error when there are no steps @fast", ->
    cron.isDryRun = true
    Promise.bind(@)
    .then -> Steps.remove()
    .then -> sinon.stub(cron, "getInput").returns(new Promise.resolve([{}, {
      Echo:
        messages: ["Hello Cron"]
    }]))
    .then -> cron.schedule(commandIds)
