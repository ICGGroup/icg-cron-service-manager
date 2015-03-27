util = require("util")
async = require("async")
path = require("path")
_ = require("lodash")
cluster = require('cluster')
domain = require("domain")
logWrapper = require("./lib/log-wrapper")
moment = require('moment')
CronJob = require('cron').CronJob
jobs = []

module.exports = (config, options)->

  serviceLogin = (cb)->
    restClient = require("icg-rest-client")(config.apiBaseUrl)

    callOpts =
      data:
        userId: config.credentials.user
        password: config.credentials.password

    restClient.post config.sessionPath, callOpts, (err, response)->
      if err
        config.log?.error(err)
        throw new Error("Unable to log in to the API")
        cb(err)
      else
        # Here we are logged into the API, so let's go ahead and add the secToken to the config Object
        config.secToken = response.body.secToken

        if cb
          cb(null, config.secToken)


  if cluster.isMaster

    # a single process controls the creation of workers (one per configured job).
    if not config.jobs or config.jobs.length == 0
      throw new Error("Missing required configuration option 'jobs'")


    launchServiceWorkers = ()->
      _.each cluster.workers, (w)->
          w.kill()
      _.each config.jobs, (jobOptions)->
        jobOptions.secToken = config.secToken
        try
          config.log?.debug("forking task job onto worker", jobOptions.job)
          lastHeartbeat = null

          initJobWorker = ()->
            # since the values to be passed can only be pass in key-value pairs, we will stringify the important parts and parse them in the worker
            worker = cluster.fork(jobOptions:JSON.stringify(jobOptions))

            lastHeartbeat = new Date()
            worker.on "message", (msg)->
              # we will expect to get notified from the worker periodically
              lastHeartbeat = new Date()

            return worker

          jobWorker = initJobWorker()
          setInterval ()->
            # once every 10 sconds we will check to see if we heard from the worker.  if we haven't, we will recycle the worker
            timeSinceHeartbeat = new Date() - lastHeartbeat

            # Allow for the timeout in the config, but assume six minutes, since this is longer than the default max backoff delay
            timeout = moment.duration(config.deadWorkerProcessTimeout || 360000).asMilliseconds();
            if timeout > 0
              if timeSinceHeartbeat > timeout
                config.log.error("Dead worker detected from job #{jobOptions.job.name} after timeout of #{timeout}ms")
                jobWorker.kill()
                jobWorker = initJobWorker()
            else
              config.log.warn "Invalid deadWorkerProcessTimeout (#{config.deadWorkerProcessTimeout}) in config"
          , 10000

        catch e
          config.log?.error(e)
          throw e


    if not config.apiBaseUrl or not config.credentials
      config.log?.warn("API login information not present, launching workers without logging in.  To login to the API, provide an apiBaseUrl and credentials.")
      launchServiceWorkers()
    else
      #the master should log into the api server and pass this information when the individual workers are forked
      serviceLogin ()->
        # so now we are ready to fork our workers, one for each job
        launchServiceWorkers()


    cluster.on "disconnect", (worker)->
      config.log.warn("A worker process disconnected from the cluster.")



  else
    # this is our worker process for each worker.  By using clusters, we can increase the rocervability of the application

    # Job info is passed as a env param, so is serialized by the cluster master.  Parse it
    options = JSON.parse(process.env.jobOptions)
    job = options.job
    config.log = logWrapper(options.job.name, config.log, (text, meta)->
      # The log wrapper allows us to be able to add the job name to the log output which helps us untangle the log later.  We will also us this to make sure that we are still getting feedback from the worker.
      process.send({heartbeat:true})
      return true
    )

    restClient = require("icg-rest-client")(config.apiBaseUrl, options.secToken)

    config.log?.info("Loading handler: #{job.script}")
    try
      handler = require(job.script)
    catch e
      config.log?.error("unable to load:", job.script)

    config.log?.info("Creating Job Domain for :#{job.script}")

    setTimeout ()->
      serviceLogin (err, secToken)->
        if not err and secToken
          options.secToken = secToken
          config?.log.info("Sec Token Refreshed")
    , config.loginExpirationMs || 3600000


    jobDomain = domain.create()

    jobDomain.on "error", (err)->
      config.log?.error(err.stack)
      setTimeout ()->
        process.exit(1);
      , config.errorRestartDelay || 120000
      cluster.worker.disconnect()


    jobDomain.run ()->
      if not config
        return config.log?.error("Invalid Config")

      running = false

      cronJob = new CronJob options.cron, ->
        cb = (err)->
          if err
            config.log?.error(err, job)
          else
            config.log?.info("Job completed", options.job.name)
          running = false

        if not running
          config.log?.info("Job starting", options.job)
          running = true
          handler(options, config, cb)

      cronJob.start()


###
