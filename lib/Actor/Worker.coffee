_ = require "underscore"
Promise = require "bluebird"
stream = require "readable-stream"
errors = require "../../core/helper/errors"
Match = require "mtr-match"
Actor = require "../Actor"

class Worker extends Actor
  constructor: (options, dependencies) ->
    Match.check options,
      domain: String
      taskList:
        name: String
      identity: String
      taskCls: Function # ActivityTask constructor
      maxLoops: Match.Optional(Match.Integer)
    super
  signature: -> ["domain", "taskList", "identity"]
  start: ->
    @info "Worker:starting", @details()
    @loop()
  loop: ->
    return if @isStopped
    process.nextTick =>
      Promise.bind(@)
      .then @poll
      .catch (error) ->
        @error "Worker:errored", @details(error)
        throw error # let it crash and restart
      .then @countdown
      .then @loop
  poll: ->
    @info "Worker:polling", @details()
    Promise.bind(@)
    .then ->
      @swf.pollForActivityTaskAsync
        domain: @domain
        taskList: @taskList
        identity: @identity
    .then (options) ->
      return false if not options.taskToken # "Call me later", said Amazon
      new Promise (resolve, reject) =>
        options.input = JSON.parse(options.input)
        @info "Worker:executing", @details({options: options}) # probability of exception on JSON.parse is quite low, while it's very convenient to have input in JSON
        inputChunks = options.input.chunks or []
        outputChunks = []
        input = new stream.Readable({objectMode: true})
        input.on "error", reject
        input._read = ->
          @push object for object in inputChunks
          @push null # end stream
        output = new stream.Writable({objectMode: true})
        output.on "error", reject
        output._write = (chunk, encoding, callback) ->
          outputChunks.push chunk
          callback()
        task = new @taskCls _.extend {}, options,
          input: input
          output: output
        task.execute()
        .then -> resolve _.extend {chunks: outputChunks}, task.result
        .catch reject
      .bind(@)
      .then (result) ->
        @info "Worker:completed", @details({result: result, options: options})
        @swf.respondActivityTaskCompletedAsync
          taskToken: options.taskToken
          result: JSON.stringify result
      .catch (error) ->
        errorInJSON = errors.errorToJSON error
        @info "Worker:failed", @details({error: errorInJSON, options: options})
        @swf.respondActivityTaskFailedAsync
          taskToken: options.taskToken
          reason: error.name
          details: JSON.stringify errorInJSON
        # don't rethrow the error, because Worker can fail

module.exports = Worker