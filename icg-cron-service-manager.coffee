async = require("async")
path = require("path")
_ = require("lodash")
CronJob = require("cron").CronJob

jobs = []

module.exports = (config)->

  restClient = require("icg-rest-client")(config.apiBaseUrl)

  if not config.jobs or config.jobs.length == 0
    throw new Error("Missing required configuration option 'jobs'")

  ###

  Required configuraition

  config:
    jobs: [
      cron:"* 5 * * * * *"
      job: {
        name:"Do Something"
        script: "./job-assignment"
      }
    ]
  ###

  workerFn = ()->
    # Check funciton arity to allow optional...options.
    if arguments.length is 1
      options = {}
      workerCallback = arguments[0]
    else
      options = arguments[0]
      workerCallback = arguments[1]

    if not config
      workerCallback("Invalid Config")

    if not config.apiBaseUrl
      workerCallback("Missing apiBaseUrl")

    if not config.credentials
      workerCallback("Missing credentials")

    if not config.credentials.user
      workerCallback("Missing credentials.user")

    if not config.credentials.password
      workerCallback("Missing credentials.password")

    if not config.credentials
      workerCallback("Missing credentials")

    if not config.sessionPath
      workerCallback("Missing sessionPath")


    # Find items that have been locked for longer than the target duration

    if not config.credentials
      config.maxConcurrency or= 5
      config.maxLockMinutes or= 120
      try
        handler = require(options.script)
        handler.apply(this, [options, config, workerCallback])
      catch e
        workerCallback(e)

    else
      callOpts =
        data:
          userId: config.credentials.user
          password: config.credentials.password

      restClient.post config.sessionPath, callOpts, (err, response)->
        if err
          config.log?.error(err)
          workerCallback(err)
        else
          config.secToken = response.body.secToken

          config.maxConcurrency or= 5
          config.maxLockMinutes or= 120
          try
            handler = require(options.script)
            handler.apply(this, [options, config, workerCallback])
          catch e
            workerCallback(e)

  # Stop any existing jobs, in the case of an unhandled error
  if jobs and jobs.length > 0
    _.each jobs, (job)->
      job.stop()
    jobs = []
  _.each config.jobs, (job)->
    running = false
    try
      config.log?.debug("creating job", job.job)
      cronJob = new CronJob job.cron, ->
        cb = (err)->
          running = false
          if err
            config.log?.error(err, job)
          else
            config.log?.info("Job completed", job.job)
        if not running
          config.log?.info("Job starting", job.job)
          running  = true
          workerFn(job.job, cb)
        else
          config.log?.warn("Job skipped due to already running process.")
      jobs.push(cronJob)
      cronJob.start()

    catch e
      config.log?.error(e)
      throw e
