util = require("util")
async = require("async")
path = require("path")
_ = require("lodash")
cluster = require('cluster')
domain = require("domain")
oi = require("oibackoff")
logWrapper = require("./lib/log-wrapper")
moment = require('moment')
jobs = []

module.exports = (config, options)->
  if cluster.isMaster

    # a single process controls the creation of workers (one per configured job).
    if not config.jobs or config.jobs.length == 0
      throw new Error("Missing required configuration option 'jobs'")


    #the master should log into the api server and pass this information when the individual workers are forked
    restClient = require("icg-rest-client")(config.apiBaseUrl)

    callOpts =
      data:
        userId: config.credentials.user
        password: config.credentials.password

    restClient.post config.sessionPath, callOpts, (err, response)->
      if err
        config.log?.error(err)
        throw new Error("Unable to log in to the API")
      else

        # Here we are logged into the API, so let's go ahead and add the secToken to the config Object
        config.secToken = response.body.secToken

        # so now we are ready to fork our workers, one for each job, but if we want to pass

        if jobs and jobs.length > 0
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


    cluster.on "disconnect", (worker)->
      config.log.warn("A worker process disconnected form the cluster.")



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

    jobDomain = domain.create()

    jobDomain.on "error", (err)->
      config.log?.error(err)
      setTimeout ()->
        process.exit(1);
      , 5000
      cluster.worker.disconnect()


    jobDomain.run ()->
      if not config
        return config.log?.error("Invalid Config")

      if not config.apiBaseUrl
        return config.log?.error("Missing apiBaseUrl")

      cronJob = new CronJob options.cron, ->
        cb = (err)->
          if err
            config.log?.error(err, job)
          else
            config.log?.info("Job completed", job.job)

        config.log?.info("Job starting", job.job)
        workerFn(job.job, cb)
      cronJob.start()


###
