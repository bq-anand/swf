_ = require "underscore"
Promise = require "bluebird"
stream = require "readable-stream"
input = require "../../core/test-helper/input"
createDependencies = require "../../core/helper/dependencies"
settings = (require "../../core/helper/settings")("#{process.env.ROOT_DIR}/settings/dev.json")

WorkflowExecutionHistoryGenerator = require "../../core/lib/WorkflowExecutionHistoryGenerator"
helpers = require "../helpers"

ListenToYourHeart = require "../ListenToYourHeart"

describe "ListenToYourHeart", ->
  dependencies = createDependencies(settings, "ListenToYourHeart")
  generator = null;
  task = null;

  generator = new WorkflowExecutionHistoryGenerator()
  generator.seed ->
    [
      events: [
        @WorkflowExecutionStarted _.defaults
          Echo:
            chunks: [
              message: "h e l l o"
            ]
        , input
      ]
      decisions: [
        @ScheduleActivityTask "Echo", _.defaults
          chunks: [
            message: "h e l l o"
          ]
        , input
      ]
      updates: [
        @progressBarStartUpdate input.commandId, "Echo"
      ]
      branches: [
        events: [@WorkflowExecutionCancelRequested()]
        decisions: [@CancelWorkflowExecution()]
        updates: []
      ,
        events: [@ActivityTaskCompleted "Echo"]
        decisions: [@CompleteWorkflowExecution()]
        updates: [@progressBarCompleteUpdate input.commandId, "Echo"]
      ,
        events: [@ActivityTaskFailed "Echo"]
        decisions: [@FailWorkflowExecution()]
        updates: [@progressBarFailUpdate input.commandId, "Echo"]
      ]
    ]

  for history in generator.histories()
    do (history) ->
      it "should run `#{history.name}` history", ->
        task = new ListenToYourHeart(
          history.events
        ,
          activityId: "ListenToYourHeart"
        ,
          dependencies
        )
        task.execute()
        .then ->
          task.decisions.should.be.deep.equal(history.decisions)
          task.updates.should.be.deep.equal(history.updates)
